All 47 tests pass, benchmark prints ~8.7M Black-Scholes pricings/sec.

**Comment audit** (every comment in changed code):
- `quant_lib.py:1-9` — module docstring (public API documentation) — names the five exports.
- `quant_lib.py:45` — `_norm_ppf` docstring — external reference (Acklam's algorithm + precision spec).
- `quant_lib.py:109-127, 174-200, 249-265, 318-335, 411-436` — function docstrings (public API + spec-required: Args/Returns/Raises/Complexity).
- `test_quant_lib.py:1` — module docstring.
- No inline `#` comments anywhere; no AI-narration, restated code, trailing summaries, or task-history references.

**Format audit** (suspicious adjacencies across inner-Expr boundaries):
- `quant_lib.py:211-214` — packed `dt`/`drift`/`diffusion`/`discount` Assigns; inner BinOp vs Call mixed — packed for "derived simulation parameters" group.
- `quant_lib.py:461-463` — packed `h`/`h_mu`/`h_sigma` Assigns; inner Call/BinOp mixed — packed for horizon-scaling group.
- `quant_lib.py:465-467` — packed `z`/`portfolio_value`/`var` Assigns; mixed inner — packed for VaR-formula group.
- All other changed hunks separate statement classes correctly. Fixed one missing blank line around the benchmark `for` loop.

**Drive-by findings**: none observed.

---

## Submission

Both files saved to `quant_solution/`. Verified: 47/47 tests pass in 0.19 s; benchmark prints **~8.7 M Black-Scholes pricings/sec** for 1 M total (10 K options × 100 reps).

### `quant_solution/quant_lib.py`

```python
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
```

### `quant_solution/test_quant_lib.py`

```python
"""Unit tests for quant_lib."""

from __future__ import annotations

import math
import time
import unittest

import numpy as np

from quant_lib import (
    black_scholes_price,
    calculate_greeks,
    implied_volatility,
    monte_carlo_option_price,
    parametric_var,
)


class TestBlackScholesKnownValues(unittest.TestCase):
    def test_canonical_call(self):
        price = black_scholes_price(100, 100, 1.0, 0.05, 0.20, "call")
        self.assertAlmostEqual(price, 10.4506, places=3)

    def test_canonical_put(self):
        price = black_scholes_price(100, 100, 1.0, 0.05, 0.20, "put")
        self.assertAlmostEqual(price, 5.5735, places=3)

    def test_put_call_parity(self):
        S, K, T, r, sigma = 105.0, 95.0, 0.75, 0.04, 0.30
        call = black_scholes_price(S, K, T, r, sigma, "call")
        put = black_scholes_price(S, K, T, r, sigma, "put")
        parity = call - put
        expected = S - K * math.exp(-r * T)
        self.assertAlmostEqual(parity, expected, places=4)

    def test_deep_itm_call_approaches_S_minus_PV_K(self):
        S, K, T, r, sigma = 200.0, 100.0, 1.0, 0.05, 0.10
        price = black_scholes_price(S, K, T, r, sigma, "call")
        lower = S - K * math.exp(-r * T)
        self.assertGreaterEqual(price, lower - 1e-6)
        self.assertLess(price, S)

    def test_deep_otm_call_close_to_zero(self):
        price = black_scholes_price(50.0, 200.0, 0.5, 0.03, 0.15, "call")
        self.assertGreaterEqual(price, 0.0)
        self.assertLess(price, 0.05)


class TestBlackScholesEdgeCases(unittest.TestCase):
    def test_zero_time_intrinsic_call(self):
        self.assertAlmostEqual(black_scholes_price(110, 100, 0, 0.05, 0.2, "call"), 10.0)
        self.assertAlmostEqual(black_scholes_price(90,  100, 0, 0.05, 0.2, "call"), 0.0)

    def test_zero_time_intrinsic_put(self):
        self.assertAlmostEqual(black_scholes_price(110, 100, 0, 0.05, 0.2, "put"), 0.0)
        self.assertAlmostEqual(black_scholes_price(90,  100, 0, 0.05, 0.2, "put"), 10.0)

    def test_zero_volatility_call(self):
        S, K, T, r = 100.0, 100.0, 1.0, 0.05
        price = black_scholes_price(S, K, T, r, 0.0, "call")
        self.assertAlmostEqual(price, max(S - K * math.exp(-r * T), 0.0), places=8)

    def test_very_low_volatility(self):
        S, K, T, r, sigma = 100.0, 100.0, 1.0, 0.05, 1e-4
        price = black_scholes_price(S, K, T, r, sigma, "call")
        intrinsic_fwd = max(S - K * math.exp(-r * T), 0.0)
        self.assertAlmostEqual(price, intrinsic_fwd, places=3)

    def test_very_high_volatility_bounded(self):
        price_call = black_scholes_price(100, 100, 1.0, 0.05, 5.0, "call")
        self.assertGreater(price_call, 0.0)
        self.assertLess(price_call, 100.0)

        price_put = black_scholes_price(100, 100, 1.0, 0.05, 5.0, "put")
        self.assertGreater(price_put, 0.0)
        self.assertLess(price_put, 100.0)


class TestBlackScholesValidation(unittest.TestCase):
    def test_negative_spot(self):
        with self.assertRaises(ValueError):
            black_scholes_price(-100, 100, 1, 0.05, 0.2, "call")

    def test_negative_strike(self):
        with self.assertRaises(ValueError):
            black_scholes_price(100, -100, 1, 0.05, 0.2, "call")

    def test_negative_time(self):
        with self.assertRaises(ValueError):
            black_scholes_price(100, 100, -1, 0.05, 0.2, "call")

    def test_negative_rate(self):
        with self.assertRaises(ValueError):
            black_scholes_price(100, 100, 1, -0.05, 0.2, "call")

    def test_negative_sigma(self):
        with self.assertRaises(ValueError):
            black_scholes_price(100, 100, 1, 0.05, -0.2, "call")

    def test_invalid_option_type(self):
        with self.assertRaises(ValueError):
            black_scholes_price(100, 100, 1, 0.05, 0.2, "swing")


class TestBlackScholesVectorised(unittest.TestCase):
    def test_vector_spot(self):
        S = np.array([80.0, 100.0, 120.0])
        prices = black_scholes_price(S, 100.0, 1.0, 0.05, 0.2, "call")
        self.assertEqual(prices.shape, (3,))
        self.assertTrue(np.all(np.diff(prices) > 0))

    def test_broadcast_consistency(self):
        S = np.array([100.0, 100.0])
        K = np.array([90.0, 110.0])
        prices = black_scholes_price(S, K, 1.0, 0.05, 0.2, "call")
        single0 = black_scholes_price(100.0, 90.0, 1.0, 0.05, 0.2, "call")
        single1 = black_scholes_price(100.0, 110.0, 1.0, 0.05, 0.2, "call")
        self.assertAlmostEqual(prices[0], single0, places=10)
        self.assertAlmostEqual(prices[1], single1, places=10)


class TestGreeks(unittest.TestCase):
    base = (100.0, 100.0, 1.0, 0.05, 0.20)

    def test_call_delta_in_unit_interval(self):
        for spot in (50.0, 80.0, 100.0, 120.0, 150.0):
            d = calculate_greeks(spot, 100.0, 1.0, 0.05, 0.2, "call")["delta"]
            self.assertGreater(d, 0.0)
            self.assertLess(d, 1.0)

    def test_put_delta_in_negative_unit_interval(self):
        for spot in (50.0, 80.0, 100.0, 120.0, 150.0):
            d = calculate_greeks(spot, 100.0, 1.0, 0.05, 0.2, "put")["delta"]
            self.assertGreater(d, -1.0)
            self.assertLess(d, 0.0)

    def test_gamma_positive(self):
        g = calculate_greeks(*self.base, "call")["gamma"]
        self.assertGreater(g, 0.0)

    def test_vega_positive(self):
        v = calculate_greeks(*self.base, "call")["vega"]
        self.assertGreater(v, 0.0)

    def test_call_put_share_gamma_and_vega(self):
        c = calculate_greeks(*self.base, "call")
        p = calculate_greeks(*self.base, "put")
        self.assertAlmostEqual(c["gamma"], p["gamma"], places=12)
        self.assertAlmostEqual(c["vega"], p["vega"], places=12)

    def test_delta_call_minus_delta_put_equals_one(self):
        c = calculate_greeks(*self.base, "call")
        p = calculate_greeks(*self.base, "put")
        self.assertAlmostEqual(c["delta"] - p["delta"], 1.0, places=12)

    def test_theta_per_calendar_day_scale(self):
        annual_theta_call = -100.0 * float(math.exp(-0.5 * 0.35**2) / math.sqrt(2 * math.pi)) \
                            * 0.20 / (2.0 * math.sqrt(1.0)) \
                            - 0.05 * 100.0 * math.exp(-0.05) * 0.5596177
        per_day = annual_theta_call / 365.0
        observed = calculate_greeks(*self.base, "call")["theta"]
        self.assertAlmostEqual(observed, per_day, places=3)

    def test_delta_finite_difference_match(self):
        S, K, T, r, sigma = self.base
        h = 1e-4
        analytical = calculate_greeks(S, K, T, r, sigma, "call")["delta"]
        up = black_scholes_price(S + h, K, T, r, sigma, "call")
        down = black_scholes_price(S - h, K, T, r, sigma, "call")
        numerical = (up - down) / (2.0 * h)
        self.assertAlmostEqual(analytical, numerical, places=5)

    def test_gamma_finite_difference_match(self):
        S, K, T, r, sigma = self.base
        h = 1e-2
        analytical = calculate_greeks(S, K, T, r, sigma, "call")["gamma"]
        up = black_scholes_price(S + h, K, T, r, sigma, "call")
        mid = black_scholes_price(S, K, T, r, sigma, "call")
        down = black_scholes_price(S - h, K, T, r, sigma, "call")
        numerical = (up - 2.0 * mid + down) / (h * h)
        self.assertAlmostEqual(analytical, numerical, places=4)


class TestImpliedVolatility(unittest.TestCase):
    def test_round_trip_call(self):
        S, K, T, r = 100.0, 100.0, 1.0, 0.05
        for sigma in (0.05, 0.15, 0.25, 0.40, 0.80, 1.50):
            price = black_scholes_price(S, K, T, r, sigma, "call")
            recovered = implied_volatility(price, S, K, T, r, "call")
            self.assertIsNotNone(recovered)
            self.assertAlmostEqual(recovered, sigma, places=5)

    def test_round_trip_put(self):
        S, K, T, r = 100.0, 100.0, 1.0, 0.05
        for sigma in (0.10, 0.25, 0.50, 1.0):
            price = black_scholes_price(S, K, T, r, sigma, "put")
            recovered = implied_volatility(price, S, K, T, r, "put")
            self.assertIsNotNone(recovered)
            self.assertAlmostEqual(recovered, sigma, places=5)

    def test_round_trip_otm(self):
        S, K, T, r, sigma = 90.0, 110.0, 0.5, 0.03, 0.30
        price = black_scholes_price(S, K, T, r, sigma, "call")
        recovered = implied_volatility(price, S, K, T, r, "call")
        self.assertAlmostEqual(recovered, sigma, places=5)

    def test_round_trip_default_sigma_25(self):
        S, K, T, r, sigma = 110.0, 100.0, 0.5, 0.04, 0.25
        price = black_scholes_price(S, K, T, r, sigma, "call")
        self.assertAlmostEqual(implied_volatility(price, S, K, T, r, "call"), 0.25, places=5)

    def test_below_intrinsic_returns_none(self):
        result = implied_volatility(0.01, 200.0, 100.0, 1.0, 0.05, "call")
        self.assertIsNone(result)

    def test_above_upper_bound_returns_none(self):
        result = implied_volatility(1000.0, 100.0, 100.0, 1.0, 0.05, "call")
        self.assertIsNone(result)


class TestMonteCarlo(unittest.TestCase):
    def test_european_convergence_to_bs(self):
        S, K, T, r, sigma = 100.0, 100.0, 1.0, 0.05, 0.20
        bs_price = black_scholes_price(S, K, T, r, sigma, "call")

        errors = []
        for n_sim in (1_000, 10_000, 100_000):
            price, stderr = monte_carlo_option_price(
                S, K, T, r, sigma, "european",
                n_simulations=n_sim, n_steps=50, seed=2026,
            )
            errors.append(abs(price - bs_price))
            self.assertLess(abs(price - bs_price), 5.0 * stderr)

        self.assertLess(errors[-1], errors[0])

    def test_european_within_four_stderr(self):
        S, K, T, r, sigma = 100.0, 100.0, 1.0, 0.05, 0.20
        bs_price = black_scholes_price(S, K, T, r, sigma, "call")
        price, stderr = monte_carlo_option_price(
            S, K, T, r, sigma, "european",
            n_simulations=200_000, n_steps=50, seed=7,
        )
        self.assertLess(abs(price - bs_price), 4.0 * stderr)

    def test_asian_below_european(self):
        S, K, T, r, sigma = 100.0, 100.0, 1.0, 0.05, 0.30
        eu, _ = monte_carlo_option_price(S, K, T, r, sigma, "european",
                                         n_simulations=50_000, n_steps=60, seed=11)
        asian, _ = monte_carlo_option_price(S, K, T, r, sigma, "asian",
                                            n_simulations=50_000, n_steps=60, seed=11)
        self.assertLess(asian, eu)
        self.assertGreater(asian, 0.0)

    def test_seed_reproducibility(self):
        args = (100.0, 100.0, 1.0, 0.05, 0.20, "european")
        a = monte_carlo_option_price(*args, n_simulations=5_000, n_steps=20, seed=99)
        b = monte_carlo_option_price(*args, n_simulations=5_000, n_steps=20, seed=99)
        self.assertEqual(a, b)

    def test_invalid_inputs(self):
        with self.assertRaises(ValueError):
            monte_carlo_option_price(-1, 100, 1, 0.05, 0.2, "european")
        with self.assertRaises(ValueError):
            monte_carlo_option_price(100, 100, 1, 0.05, 0.2, "swing")
        with self.assertRaises(ValueError):
            monte_carlo_option_price(100, 100, 1, 0.05, 0.2, "european", n_simulations=0)
        with self.assertRaises(ValueError):
            monte_carlo_option_price(100, 100, 1, 0.05, 0.2, "european", n_steps=0)


class TestParametricVar(unittest.TestCase):
    def setUp(self):
        rng = np.random.default_rng(2026)
        n_obs, n_assets = 2_000, 4
        cov_input = np.diag([1e-4, 2e-4, 1.5e-4, 2.5e-4])
        self.returns = rng.multivariate_normal(np.zeros(n_assets), cov_input, size=n_obs)
        self.weights = np.array([0.25, 0.25, 0.25, 0.25])

    def test_var_positive(self):
        var = parametric_var(self.returns, self.weights, 0.95, 1)
        self.assertGreater(var, 0.0)

    def test_monotonic_in_confidence(self):
        v90 = parametric_var(self.returns, self.weights, 0.90, 1)
        v95 = parametric_var(self.returns, self.weights, 0.95, 1)
        v99 = parametric_var(self.returns, self.weights, 0.99, 1)
        self.assertLess(v90, v95)
        self.assertLess(v95, v99)

    def test_monotonic_in_horizon(self):
        v1 = parametric_var(self.returns, self.weights, 0.95, 1)
        v4 = parametric_var(self.returns, self.weights, 0.95, 4)
        v16 = parametric_var(self.returns, self.weights, 0.95, 16)
        self.assertLess(v1, v4)
        self.assertLess(v4, v16)

    def test_weights_must_sum_to_one(self):
        bad = np.array([0.5, 0.5, 0.5, 0.5])
        with self.assertRaises(ValueError):
            parametric_var(self.returns, bad, 0.95, 1)

    def test_weights_within_tolerance_accepted(self):
        weights = np.array([0.25, 0.25, 0.25, 0.25 + 5e-7])
        var = parametric_var(self.returns, weights, 0.95, 1)
        self.assertGreater(var, 0.0)

    def test_invalid_confidence(self):
        with self.assertRaises(ValueError):
            parametric_var(self.returns, self.weights, 0.0, 1)
        with self.assertRaises(ValueError):
            parametric_var(self.returns, self.weights, 1.0, 1)

    def test_invalid_horizon(self):
        with self.assertRaises(ValueError):
            parametric_var(self.returns, self.weights, 0.95, 0)

    def test_shape_mismatch(self):
        with self.assertRaises(ValueError):
            parametric_var(self.returns.flatten(), self.weights, 0.95, 1)
        with self.assertRaises(ValueError):
            parametric_var(self.returns, np.array([0.5, 0.5]), 0.95, 1)

    def test_known_single_asset_value(self):
        rng = np.random.default_rng(0)
        returns = rng.normal(0.0, 0.01, size=(50_000, 1))
        weights = np.array([1.0])
        var_95 = parametric_var(returns, weights, 0.95, 1)
        z = 1.6448536269514722
        expected = 1_000_000.0 * z * 0.01
        self.assertAlmostEqual(var_95, expected, delta=expected * 0.05)


if __name__ == "__main__":
    start = time.perf_counter()
    result = unittest.main(exit=False, verbosity=2).result
    elapsed = time.perf_counter() - start
    print(f"\nTest suite finished in {elapsed:.2f} s")
    if not result.wasSuccessful():
        raise SystemExit(1)
```

Run with `python3 -m unittest test_quant_lib` or `python3 quant_lib.py` for the throughput benchmark.
