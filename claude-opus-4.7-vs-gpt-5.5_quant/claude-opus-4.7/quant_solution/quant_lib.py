"""Equity option pricing and risk analytics.

Pure numpy + standard library. Provides:
    - black_scholes_price        closed-form European pricer
    - monte_carlo_option_price   GBM Monte Carlo (European / arithmetic Asian)
    - calculate_greeks           analytical first-order Greeks
    - implied_volatility         Newton-Raphson with bisection fallback
    - parametric_var             variance-covariance VaR
"""

from __future__ import annotations

import math
import time
from typing import Optional, Union

import numpy as np


_SQRT_2: float = math.sqrt(2.0)
_SQRT_2PI: float = math.sqrt(2.0 * math.pi)

ArrayLike = Union[float, np.ndarray]


_erf_ufunc = np.frompyfunc(math.erf, 1, 1)


def _norm_cdf(x: ArrayLike) -> np.ndarray:
    arr = np.asarray(x, dtype=float)

    if arr.ndim == 0:
        return np.asarray(0.5 * (1.0 + math.erf(float(arr) / _SQRT_2)))

    return 0.5 * (1.0 + _erf_ufunc(arr / _SQRT_2).astype(float))


def _norm_pdf(x: ArrayLike) -> np.ndarray:
    arr = np.asarray(x, dtype=float)

    return np.exp(-0.5 * arr * arr) / _SQRT_2PI


def _norm_ppf(p: float) -> float:
    """Inverse standard-normal CDF via Acklam's algorithm (~1.15e-9 max error)."""
    if not 0.0 < p < 1.0:
        raise ValueError("p must be in (0, 1)")

    a = (-3.969683028665376e+01,  2.209460984245205e+02,
         -2.759285104469687e+02,  1.383577518672690e+02,
         -3.066479806614716e+01,  2.506628277459239e+00)
    b = (-5.447609879822406e+01,  1.615858368580409e+02,
         -1.556989798598866e+02,  6.680131188771972e+01,
         -1.328068155288572e+01)
    c = (-7.784894002430293e-03, -3.223964580411365e-01,
         -2.400758277161838e+00, -2.549732539343734e+00,
          4.374664141464968e+00,  2.938163982698783e+00)
    d = ( 7.784695709041462e-03,  3.224671290700398e-01,
          2.445134137142996e+00,  3.754408661907416e+00)

    plow = 0.02425
    phigh = 1.0 - plow

    if p < plow:
        q = math.sqrt(-2.0 * math.log(p))
        num = ((((c[0]*q + c[1])*q + c[2])*q + c[3])*q + c[4])*q + c[5]
        den = (((d[0]*q + d[1])*q + d[2])*q + d[3])*q + 1.0

        return num / den

    if p > phigh:
        q = math.sqrt(-2.0 * math.log(1.0 - p))
        num = ((((c[0]*q + c[1])*q + c[2])*q + c[3])*q + c[4])*q + c[5]
        den = (((d[0]*q + d[1])*q + d[2])*q + d[3])*q + 1.0

        return -num / den

    q = p - 0.5
    r = q * q
    num = (((((a[0]*r + a[1])*r + a[2])*r + a[3])*r + a[4])*r + a[5]) * q
    den = ((((b[0]*r + b[1])*r + b[2])*r + b[3])*r + b[4])*r + 1.0

    return num / den


def _validate_market_inputs(S: ArrayLike, K: ArrayLike, T: ArrayLike,
                            r: ArrayLike, sigma: ArrayLike) -> None:
    if np.any(np.asarray(S) < 0) or np.any(np.asarray(K) < 0):
        raise ValueError("S and K must be non-negative")

    if np.any(np.asarray(T) < 0):
        raise ValueError("T must be non-negative")

    if np.any(np.asarray(r) < 0):
        raise ValueError("r must be non-negative")

    if np.any(np.asarray(sigma) < 0):
        raise ValueError("sigma must be non-negative")


def black_scholes_price(
    S: ArrayLike,
    K: ArrayLike,
    T: ArrayLike,
    r: ArrayLike,
    sigma: ArrayLike,
    option_type: str,
) -> ArrayLike:
    """Closed-form Black-Scholes price for a European option.

    Args:
        S: spot price.
        K: strike price.
        T: time to maturity in years.
        r: continuously compounded risk-free rate.
        sigma: volatility (annualised).
        option_type: ``"call"`` or ``"put"``.

    Returns:
        Option price. Float for scalar inputs; ``np.ndarray`` if any input is
        an array (broadcast over inputs).

    Raises:
        ValueError: on negative S/K/T/r/sigma or unknown option_type.

    Complexity: O(N) time and space in total elements, fully vectorised.
    """
    _validate_market_inputs(S, K, T, r, sigma)

    if option_type not in ("call", "put"):
        raise ValueError(f"option_type must be 'call' or 'put', got {option_type!r}")

    S_arr = np.asarray(S, dtype=float)
    K_arr = np.asarray(K, dtype=float)
    T_arr = np.asarray(T, dtype=float)
    r_arr = np.asarray(r, dtype=float)
    sigma_arr = np.asarray(sigma, dtype=float)

    discount = np.exp(-r_arr * T_arr)

    with np.errstate(divide="ignore", invalid="ignore"):
        sqrt_T = np.sqrt(T_arr)
        denom = sigma_arr * sqrt_T
        d1 = (np.log(S_arr / K_arr) + (r_arr + 0.5 * sigma_arr * sigma_arr) * T_arr) / denom
        d2 = d1 - denom

        if option_type == "call":
            price = S_arr * _norm_cdf(d1) - K_arr * discount * _norm_cdf(d2)
            intrinsic = np.maximum(S_arr - K_arr * discount, 0.0)
        else:
            price = K_arr * discount * _norm_cdf(-d2) - S_arr * _norm_cdf(-d1)
            intrinsic = np.maximum(K_arr * discount - S_arr, 0.0)

    degenerate = (T_arr <= 0) | (sigma_arr <= 0) | (S_arr <= 0) | (K_arr <= 0)
    price = np.where(degenerate, intrinsic, price)

    if price.ndim == 0:
        return float(price)

    return price


def monte_carlo_option_price(
    S: float,
    K: float,
    T: float,
    r: float,
    sigma: float,
    option_type: str,
    n_simulations: int = 100_000,
    n_steps: int = 252,
    seed: Optional[int] = None,
) -> tuple[float, float]:
    """Monte Carlo price (call payoff) for a European or arithmetic-average Asian option.

    GBM is integrated with the log-Euler scheme
    ``S_{t+dt} = S_t * exp((r - sigma^2/2) dt + sigma sqrt(dt) Z)``,
    which is the exact transition for constant-coefficient GBM and the
    standard discretisation of the Euler-Maruyama family for log-prices.
    Simulations are processed in chunks to bound peak memory.

    Args:
        S, K, T, r, sigma: standard model parameters (call payoff assumed).
        option_type: ``"european"`` (terminal payoff) or ``"asian"``
            (arithmetic mean over the ``n_steps`` simulated dates after t=0).
        n_simulations: number of Monte Carlo paths.
        n_steps: number of discretisation steps per path.
        seed: optional RNG seed for reproducibility.

    Returns:
        ``(price, standard_error)`` — discounted sample mean and the
        sample-mean standard error (sample stdev / sqrt(n_simulations)).

    Raises:
        ValueError: on negative inputs, unknown option_type, or
            non-positive ``n_simulations`` / ``n_steps``.

    Complexity: O(n_simulations * n_steps) time;
        O(chunk_size * n_steps) auxiliary space.
    """
    _validate_market_inputs(S, K, T, r, sigma)

    if option_type not in ("european", "asian"):
        raise ValueError(f"option_type must be 'european' or 'asian', got {option_type!r}")

    if n_simulations <= 0 or n_steps <= 0:
        raise ValueError("n_simulations and n_steps must be positive")

    rng = np.random.default_rng(seed)

    dt = T / n_steps
    drift = (r - 0.5 * sigma * sigma) * dt
    diffusion = sigma * math.sqrt(dt)
    discount = math.exp(-r * T)

    chunk_size = min(10_000, n_simulations)
    payoffs = np.empty(n_simulations, dtype=float)

    for start in range(0, n_simulations, chunk_size):
        end = min(start + chunk_size, n_simulations)
        sub_n = end - start

        z = rng.standard_normal((sub_n, n_steps))
        log_path = np.cumsum(drift + diffusion * z, axis=1)
        paths = S * np.exp(log_path)

        if option_type == "european":
            terminal = paths[:, -1]
            payoffs[start:end] = np.maximum(terminal - K, 0.0)
        else:
            avg = paths.mean(axis=1)
            payoffs[start:end] = np.maximum(avg - K, 0.0)

    discounted = discount * payoffs
    price = float(discounted.mean())
    stderr = float(discounted.std(ddof=1) / math.sqrt(n_simulations))

    return price, stderr


def calculate_greeks(
    S: float,
    K: float,
    T: float,
    r: float,
    sigma: float,
    option_type: str,
) -> dict[str, float]:
    """First-order Greeks for a European option via analytical formulas.

    Args:
        S, K, T, r, sigma: standard model parameters; ``T`` and ``sigma``
            must be strictly positive (Greeks are undefined at the boundary).
        option_type: ``"call"`` or ``"put"``.

    Returns:
        Dict with keys ``delta``, ``gamma``, ``theta``, ``vega``, ``rho``.
        Theta is reported per calendar day (annual / 365). Vega is per unit
        of volatility (multiply by 0.01 for per-vol-point).

    Raises:
        ValueError: on negative inputs, T<=0, sigma<=0, or unknown option_type.

    Complexity: O(1) time and space.
    """
    _validate_market_inputs(S, K, T, r, sigma)

    if T <= 0 or sigma <= 0:
        raise ValueError("T and sigma must be strictly positive for Greeks")

    if S <= 0 or K <= 0:
        raise ValueError("S and K must be strictly positive for Greeks")

    if option_type not in ("call", "put"):
        raise ValueError(f"option_type must be 'call' or 'put', got {option_type!r}")

    sqrt_T = math.sqrt(T)
    d1 = (math.log(S / K) + (r + 0.5 * sigma * sigma) * T) / (sigma * sqrt_T)
    d2 = d1 - sigma * sqrt_T

    pdf_d1 = float(_norm_pdf(d1))
    cdf_d1 = float(_norm_cdf(d1))
    cdf_d2 = float(_norm_cdf(d2))
    discount = math.exp(-r * T)

    gamma = pdf_d1 / (S * sigma * sqrt_T)
    vega = S * pdf_d1 * sqrt_T

    if option_type == "call":
        delta = cdf_d1
        theta_annual = -S * pdf_d1 * sigma / (2.0 * sqrt_T) - r * K * discount * cdf_d2
        rho = K * T * discount * cdf_d2
    else:
        delta = cdf_d1 - 1.0
        cdf_neg_d2 = float(_norm_cdf(-d2))
        theta_annual = -S * pdf_d1 * sigma / (2.0 * sqrt_T) + r * K * discount * cdf_neg_d2
        rho = -K * T * discount * cdf_neg_d2

    return {
        "delta": delta,
        "gamma": gamma,
        "theta": theta_annual / 365.0,
        "vega": vega,
        "rho": rho,
    }


def implied_volatility(
    market_price: float,
    S: float,
    K: float,
    T: float,
    r: float,
    option_type: str,
    tol: float = 1e-8,
    max_iter: int = 100,
) -> Optional[float]:
    """Implied volatility via Newton-Raphson with bisection fallback.

    Args:
        market_price: observed option premium.
        S, K, T, r: standard inputs (T strictly positive).
        option_type: ``"call"`` or ``"put"``.
        tol: convergence tolerance on absolute price difference.
        max_iter: per-method iteration cap.

    Returns:
        Implied vol in [1e-8, 5.0], or ``None`` if the price violates
        no-arbitrage bounds or no root exists in the bracket.

    Raises:
        ValueError: on negative S/K/r/T or unknown option_type.

    Complexity: O(max_iter) BS evaluations.
    """
    if market_price < 0:
        raise ValueError("market_price must be non-negative")

    _validate_market_inputs(S, K, T, r, 0.0)

    if T <= 0:
        raise ValueError("T must be strictly positive")

    if option_type not in ("call", "put"):
        raise ValueError(f"option_type must be 'call' or 'put', got {option_type!r}")

    discount = math.exp(-r * T)

    if option_type == "call":
        intrinsic = max(S - K * discount, 0.0)
        upper_bound = float(S)
    else:
        intrinsic = max(K * discount - S, 0.0)
        upper_bound = K * discount

    if market_price < intrinsic - tol or market_price > upper_bound + tol:
        return None

    sigma_lo, sigma_hi = 1e-8, 5.0
    sigma = 0.2

    for _ in range(max_iter):
        price = float(black_scholes_price(S, K, T, r, sigma, option_type))
        diff = price - market_price

        if abs(diff) < tol:
            return float(sigma)

        sqrt_T = math.sqrt(T)
        d1 = (math.log(S / K) + (r + 0.5 * sigma * sigma) * T) / (sigma * sqrt_T)
        vega = S * float(_norm_pdf(d1)) * sqrt_T

        if vega < 1e-12:
            break

        sigma_next = sigma - diff / vega

        if sigma_next < sigma_lo or sigma_next > sigma_hi or math.isnan(sigma_next):
            break

        sigma = sigma_next

    lo, hi = sigma_lo, sigma_hi
    f_lo = float(black_scholes_price(S, K, T, r, lo, option_type)) - market_price
    f_hi = float(black_scholes_price(S, K, T, r, hi, option_type)) - market_price

    if f_lo * f_hi > 0:
        return None

    for _ in range(max_iter):
        mid = 0.5 * (lo + hi)
        f_mid = float(black_scholes_price(S, K, T, r, mid, option_type)) - market_price

        if abs(f_mid) < tol:
            return float(mid)

        if f_lo * f_mid < 0:
            hi, f_hi = mid, f_mid
        else:
            lo, f_lo = mid, f_mid

    return float(0.5 * (lo + hi))


def parametric_var(
    returns: np.ndarray,
    weights: np.ndarray,
    confidence_level: float = 0.95,
    horizon_days: int = 1,
) -> float:
    """Parametric (variance-covariance) Value-at-Risk on a $1,000,000 portfolio.

    Returns are assumed jointly normal at the asset level. Portfolio returns
    therefore have mean ``w'mu`` and variance ``w'Sigma w``; VaR at the chosen
    confidence is the negative-tail quantile expressed as a positive loss.

    Args:
        returns: ``(n_observations, n_assets)`` matrix of period returns.
        weights: ``(n_assets,)`` portfolio weights summing to 1
            (within tolerance ``1e-6``).
        confidence_level: quantile, e.g. 0.95 for 95% VaR.
        horizon_days: scaling horizon in the same units as ``returns``;
            mean scales linearly, std scales as ``sqrt(horizon_days)``.

    Returns:
        VaR as a positive dollar amount on a $1,000,000 portfolio
        (clipped at zero — a portfolio with deterministic positive return
        has no VaR loss at any confidence level).

    Raises:
        ValueError: shape mismatches, weight sum off-tolerance,
            confidence_level outside (0, 1), or non-positive horizon.

    Complexity: O(n_observations * n_assets^2 + n_assets^2) time;
        O(n_assets^2) space for the covariance matrix.
    """
    returns = np.asarray(returns, dtype=float)
    weights = np.asarray(weights, dtype=float)

    if returns.ndim != 2:
        raise ValueError("returns must be 2D (n_observations, n_assets)")

    if weights.ndim != 1 or weights.shape[0] != returns.shape[1]:
        raise ValueError("weights must be 1D with length n_assets")

    if abs(float(np.sum(weights)) - 1.0) > 1e-6:
        raise ValueError("weights must sum to 1 within tolerance 1e-6")

    if not 0.0 < confidence_level < 1.0:
        raise ValueError("confidence_level must be in (0, 1)")

    if horizon_days <= 0:
        raise ValueError("horizon_days must be positive")

    mu = returns.mean(axis=0)
    cov = np.atleast_2d(np.cov(returns, rowvar=False, ddof=1))

    portfolio_mu = float(weights @ mu)
    portfolio_var = float(weights @ cov @ weights)

    h = float(horizon_days)
    h_mu = portfolio_mu * h
    h_sigma = math.sqrt(max(portfolio_var * h, 0.0))

    z = _norm_ppf(confidence_level)
    portfolio_value = 1_000_000.0
    var = portfolio_value * (z * h_sigma - h_mu)

    return max(var, 0.0)


if __name__ == "__main__":
    rng = np.random.default_rng(0)
    n_options = 10_000
    n_repeats = 100

    S = rng.uniform(80.0, 120.0, n_options)
    K = rng.uniform(80.0, 120.0, n_options)
    T = rng.uniform(0.1, 2.0, n_options)
    r = rng.uniform(0.0, 0.1, n_options)
    sigma = rng.uniform(0.1, 0.5, n_options)

    _ = black_scholes_price(S, K, T, r, sigma, "call")

    start = time.perf_counter()

    for _ in range(n_repeats):
        prices = black_scholes_price(S, K, T, r, sigma, "call")

    elapsed = time.perf_counter() - start

    total = n_options * n_repeats
    print(f"Black-Scholes vector benchmark")
    print(f"  options per call : {n_options:,}")
    print(f"  calls            : {n_repeats:,}")
    print(f"  total pricings   : {total:,}")
    print(f"  elapsed          : {elapsed:.3f} s")
    print(f"  throughput       : {total / elapsed:,.0f} pricings/sec")
