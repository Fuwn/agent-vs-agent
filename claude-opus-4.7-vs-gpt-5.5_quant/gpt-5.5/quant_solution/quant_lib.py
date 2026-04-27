from __future__ import annotations

from statistics import NormalDist
from typing import Literal

import numpy as np


ArrayLike = float | np.ndarray
OptionKind = Literal["call", "put"]

PORTFOLIO_VALUE = 1_000_000.0
MIN_IMPLIED_VOLATILITY = 1e-8
MAX_IMPLIED_VOLATILITY = 5.0
STANDARD_NORMAL = NormalDist()


def black_scholes_price(
    S: ArrayLike,
    K: ArrayLike,
    T: ArrayLike,
    r: ArrayLike,
    sigma: ArrayLike,
    option_type: str,
) -> float | np.ndarray:
    """Price a European option with the Black-Scholes closed form.

    Args:
        S: Spot price.
        K: Strike price.
        T: Time to maturity in years.
        r: Non-negative continuously compounded risk-free rate.
        sigma: Non-negative volatility.
        option_type: Either "call" or "put".

    Returns:
        The option price as a float for scalar inputs, otherwise a numpy array.

    Complexity:
        O(n) time and O(n) space for n broadcast input elements.
    """
    kind = _validate_option_kind(option_type)
    spot, strike, maturity, rate, volatility = _broadcast_numeric_inputs(S, K, T, r, sigma)
    scalar_output = all(np.ndim(value) == 0 for value in (S, K, T, r, sigma))

    _validate_non_negative_inputs(spot, strike, maturity, rate, volatility)

    price = np.empty_like(spot, dtype=float)
    discount_factor = np.exp(-rate * maturity)
    expired = maturity == 0.0
    zero_strike = (strike == 0.0) & ~expired
    zero_spot = (spot == 0.0) & ~expired & ~zero_strike
    deterministic = (volatility == 0.0) & ~expired & ~zero_strike & ~zero_spot
    regular = ~(expired | zero_strike | zero_spot | deterministic)

    if kind == "call":
        price[expired] = np.maximum(spot[expired] - strike[expired], 0.0)
        price[zero_strike] = spot[zero_strike]
        price[zero_spot] = 0.0
    else:
        price[expired] = np.maximum(strike[expired] - spot[expired], 0.0)
        price[zero_strike] = 0.0
        price[zero_spot] = strike[zero_spot] * discount_factor[zero_spot]

    if np.any(deterministic):
        forward = spot[deterministic] * np.exp(rate[deterministic] * maturity[deterministic])
        intrinsic = (
            np.maximum(forward - strike[deterministic], 0.0)
            if kind == "call"
            else np.maximum(strike[deterministic] - forward, 0.0)
        )
        price[deterministic] = discount_factor[deterministic] * intrinsic

    if np.any(regular):
        square_root_time = np.sqrt(maturity[regular])
        d1 = (
            np.log(spot[regular] / strike[regular])
            + (rate[regular] + 0.5 * volatility[regular] ** 2) * maturity[regular]
        ) / (volatility[regular] * square_root_time)
        d2 = d1 - volatility[regular] * square_root_time

        if kind == "call":
            price[regular] = (
                spot[regular] * _normal_cdf(d1)
                - strike[regular] * discount_factor[regular] * _normal_cdf(d2)
            )
        else:
            price[regular] = (
                strike[regular] * discount_factor[regular] * _normal_cdf(-d2)
                - spot[regular] * _normal_cdf(-d1)
            )

    return _as_scalar_if_needed(price, scalar_output)


def monte_carlo_option_price(
    S: float,
    K: float,
    T: float,
    r: float,
    sigma: float,
    option_type: str,
    n_simulations: int = 100_000,
    n_steps: int = 252,
    seed: int | None = None,
) -> tuple[float, float]:
    """Estimate an option price by Euler-Maruyama geometric Brownian motion.

    Args:
        S: Spot price.
        K: Strike price.
        T: Time to maturity in years.
        r: Non-negative continuously compounded risk-free rate.
        sigma: Non-negative volatility.
        option_type: "european", "asian", "call", "put", or an explicit combination like "asian_put".
        n_simulations: Number of Monte Carlo paths.
        n_steps: Number of time steps per path.
        seed: Optional random seed for reproducibility.

    Returns:
        A tuple of discounted price estimate and standard error.

    Complexity:
        O(n_simulations * n_steps) time and O(n_simulations) space.
    """
    _validate_scalar_inputs(S, K, T, r, sigma)

    if n_simulations <= 0:
        raise ValueError("n_simulations must be positive")

    if n_steps <= 0:
        raise ValueError("n_steps must be positive")

    style, kind = _parse_monte_carlo_option_type(option_type)

    if T == 0.0:
        payoff = _payoff(np.array([S], dtype=float), K, kind)[0]

        return float(payoff), 0.0

    rng = np.random.default_rng(seed)
    dt = T / n_steps
    drift = r * dt
    diffusion = sigma * np.sqrt(dt)
    prices = np.full(n_simulations, S, dtype=float)
    running_sum = np.zeros(n_simulations, dtype=float)

    for _ in range(n_steps):
        shocks = rng.standard_normal(n_simulations)
        prices += prices * (drift + diffusion * shocks)

        if style == "asian":
            running_sum += prices

    payoff_basis = running_sum / n_steps if style == "asian" else prices
    payoffs = _payoff(payoff_basis, K, kind)
    discount_factor = np.exp(-r * T)
    discounted_payoffs = discount_factor * payoffs
    price = float(np.mean(discounted_payoffs))
    standard_error = (
        0.0
        if n_simulations == 1
        else float(np.std(discounted_payoffs, ddof=1) / np.sqrt(n_simulations))
    )

    return price, standard_error


def calculate_greeks(
    S: ArrayLike,
    K: ArrayLike,
    T: ArrayLike,
    r: ArrayLike,
    sigma: ArrayLike,
    option_type: str,
) -> dict[str, float | np.ndarray]:
    """Calculate analytical Black-Scholes Greeks for a European option.

    Args:
        S: Spot price.
        K: Strike price.
        T: Time to maturity in years.
        r: Non-negative continuously compounded risk-free rate.
        sigma: Non-negative volatility.
        option_type: Either "call" or "put".

    Returns:
        A dict with delta, gamma, theta, vega, and rho; theta is per calendar day.

    Complexity:
        O(n) time and O(n) space for n broadcast input elements.
    """
    kind = _validate_option_kind(option_type)
    spot, strike, maturity, rate, volatility = _broadcast_numeric_inputs(S, K, T, r, sigma)
    scalar_output = all(np.ndim(value) == 0 for value in (S, K, T, r, sigma))

    _validate_non_negative_inputs(spot, strike, maturity, rate, volatility)

    delta = np.zeros_like(spot, dtype=float)
    gamma = np.zeros_like(spot, dtype=float)
    theta = np.zeros_like(spot, dtype=float)
    vega = np.zeros_like(spot, dtype=float)
    rho = np.zeros_like(spot, dtype=float)
    regular = (spot > 0.0) & (strike > 0.0) & (maturity > 0.0) & (volatility > 0.0)

    if kind == "call":
        delta[(maturity == 0.0) & (spot > strike)] = 1.0
    else:
        delta[(maturity == 0.0) & (spot < strike)] = -1.0

    if np.any(regular):
        square_root_time = np.sqrt(maturity[regular])
        d1 = (
            np.log(spot[regular] / strike[regular])
            + (rate[regular] + 0.5 * volatility[regular] ** 2) * maturity[regular]
        ) / (volatility[regular] * square_root_time)
        d2 = d1 - volatility[regular] * square_root_time
        density = _normal_pdf(d1)
        discount_factor = np.exp(-rate[regular] * maturity[regular])

        gamma[regular] = density / (spot[regular] * volatility[regular] * square_root_time)
        vega[regular] = spot[regular] * density * square_root_time

        common_theta = -spot[regular] * density * volatility[regular] / (2.0 * square_root_time)

        if kind == "call":
            normal_d1 = _normal_cdf(d1)
            normal_d2 = _normal_cdf(d2)
            delta[regular] = normal_d1
            theta[regular] = (
                common_theta
                - rate[regular] * strike[regular] * discount_factor * normal_d2
            ) / 365.0
            rho[regular] = strike[regular] * maturity[regular] * discount_factor * normal_d2
        else:
            normal_negative_d1 = _normal_cdf(-d1)
            normal_negative_d2 = _normal_cdf(-d2)
            delta[regular] = -normal_negative_d1
            theta[regular] = (
                common_theta
                + rate[regular] * strike[regular] * discount_factor * normal_negative_d2
            ) / 365.0
            rho[regular] = -strike[regular] * maturity[regular] * discount_factor * normal_negative_d2

    return {
        "delta": _as_scalar_if_needed(delta, scalar_output),
        "gamma": _as_scalar_if_needed(gamma, scalar_output),
        "theta": _as_scalar_if_needed(theta, scalar_output),
        "vega": _as_scalar_if_needed(vega, scalar_output),
        "rho": _as_scalar_if_needed(rho, scalar_output),
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
) -> float | None:
    """Solve for Black-Scholes implied volatility by Newton-Raphson and bisection.

    Args:
        market_price: Observed option price.
        S: Spot price.
        K: Strike price.
        T: Time to maturity in years.
        r: Non-negative continuously compounded risk-free rate.
        option_type: Either "call" or "put".
        tol: Absolute price tolerance for convergence.
        max_iter: Maximum iterations per method.

    Returns:
        The implied volatility in [1e-8, 5.0], or None if no solution exists.

    Complexity:
        O(max_iter) time and O(1) space.
    """
    kind = _validate_option_kind(option_type)
    _validate_scalar_inputs(S, K, T, r, 0.0)

    if market_price < 0.0:
        raise ValueError("market_price must be non-negative")

    if tol <= 0.0:
        raise ValueError("tol must be positive")

    if max_iter <= 0:
        raise ValueError("max_iter must be positive")

    lower_price = black_scholes_price(S, K, T, r, MIN_IMPLIED_VOLATILITY, kind)
    upper_price = black_scholes_price(S, K, T, r, MAX_IMPLIED_VOLATILITY, kind)

    if market_price < lower_price - tol or market_price > upper_price + tol:
        return None

    if abs(market_price - lower_price) <= tol:
        return MIN_IMPLIED_VOLATILITY

    if abs(market_price - upper_price) <= tol:
        return MAX_IMPLIED_VOLATILITY

    volatility = 0.2

    for _ in range(max_iter):
        price = black_scholes_price(S, K, T, r, volatility, kind)
        price_error = price - market_price

        if abs(price_error) <= tol:
            return float(volatility)

        vega = calculate_greeks(S, K, T, r, volatility, kind)["vega"]

        if vega <= 1e-12:
            break

        next_volatility = volatility - price_error / vega

        if not (MIN_IMPLIED_VOLATILITY <= next_volatility <= MAX_IMPLIED_VOLATILITY):
            break

        volatility = next_volatility

    low = MIN_IMPLIED_VOLATILITY
    high = MAX_IMPLIED_VOLATILITY

    for _ in range(max_iter):
        middle = 0.5 * (low + high)
        price = black_scholes_price(S, K, T, r, middle, kind)
        price_error = price - market_price

        if abs(price_error) <= tol or high - low <= tol:
            return float(middle)

        if price_error < 0.0:
            low = middle
        else:
            high = middle

    return None


def parametric_var(
    returns: np.ndarray,
    weights: np.ndarray,
    confidence_level: float = 0.95,
    horizon_days: int = 1,
) -> float:
    """Compute normally distributed portfolio Value-at-Risk for a $1,000,000 portfolio.

    Args:
        returns: Historical returns with shape (n_observations, n_assets).
        weights: Portfolio weights with shape (n_assets,) and sum 1.
        confidence_level: VaR confidence level.
        horizon_days: Time horizon in trading days.

    Returns:
        Positive dollar VaR for the configured confidence level and horizon.

    Complexity:
        O(n_observations * n_assets^2) time and O(n_assets^2) space.
    """
    returns_array = np.asarray(returns, dtype=float)
    weights_array = np.asarray(weights, dtype=float)

    if returns_array.ndim != 2:
        raise ValueError("returns must have shape (n_observations, n_assets)")

    if weights_array.ndim != 1:
        raise ValueError("weights must have shape (n_assets,)")

    if returns_array.shape[1] != weights_array.shape[0]:
        raise ValueError("returns and weights asset dimensions must match")

    if returns_array.shape[0] < 2:
        raise ValueError("returns must include at least two observations")

    if not np.isclose(np.sum(weights_array), 1.0, atol=1e-6):
        raise ValueError("weights must sum to 1 within tolerance 1e-6")

    if not (0.0 < confidence_level < 1.0):
        raise ValueError("confidence_level must be between 0 and 1")

    if horizon_days <= 0:
        raise ValueError("horizon_days must be positive")

    mean_returns = np.mean(returns_array, axis=0)
    covariance_matrix = np.cov(returns_array, rowvar=False)
    portfolio_mean = float(weights_array @ mean_returns)
    portfolio_variance = float(weights_array @ covariance_matrix @ weights_array)
    portfolio_volatility = np.sqrt(max(portfolio_variance, 0.0))
    z_score = STANDARD_NORMAL.inv_cdf(confidence_level)
    horizon_mean = portfolio_mean * horizon_days
    horizon_volatility = portfolio_volatility * np.sqrt(horizon_days)
    value_at_risk = PORTFOLIO_VALUE * (z_score * horizon_volatility - horizon_mean)

    return float(max(value_at_risk, 0.0))


def _broadcast_numeric_inputs(*values: ArrayLike) -> tuple[np.ndarray, ...]:
    """Broadcast numeric inputs to float numpy arrays.

    Args:
        values: Scalar or array-like numeric values.

    Returns:
        Broadcast numpy arrays with float dtype.

    Complexity:
        O(n) time and O(n) space for n broadcast input elements.
    """
    arrays = [np.asarray(value, dtype=float) for value in values]

    return tuple(np.broadcast_arrays(*arrays))


def _validate_non_negative_inputs(*arrays: np.ndarray) -> None:
    """Validate that numeric arrays contain no negative values.

    Args:
        arrays: Numeric arrays to validate.

    Returns:
        None.

    Complexity:
        O(n) time and O(1) space for n total input elements.
    """
    if any(np.any(array < 0.0) for array in arrays):
        raise ValueError("prices, time, rate, and volatility must be non-negative")


def _validate_scalar_inputs(S: float, K: float, T: float, r: float, sigma: float) -> None:
    """Validate that scalar pricing inputs contain no negative values.

    Args:
        S: Spot price.
        K: Strike price.
        T: Time to maturity in years.
        r: Risk-free rate.
        sigma: Volatility.

    Returns:
        None.

    Complexity:
        O(1) time and O(1) space.
    """
    values = np.array([S, K, T, r, sigma], dtype=float)

    if np.any(values < 0.0):
        raise ValueError("prices, time, rate, and volatility must be non-negative")


def _validate_option_kind(option_type: str) -> OptionKind:
    """Normalize and validate a call or put option kind.

    Args:
        option_type: Raw option type string.

    Returns:
        Normalized option kind.

    Complexity:
        O(1) time and O(1) space.
    """
    normalized = option_type.lower().strip()

    if normalized not in {"call", "put"}:
        raise ValueError("option_type must be 'call' or 'put'")

    return normalized  # type: ignore[return-value]


def _parse_monte_carlo_option_type(option_type: str) -> tuple[str, OptionKind]:
    """Parse Monte Carlo style and payoff direction from option_type.

    Args:
        option_type: Raw Monte Carlo option type string.

    Returns:
        A tuple of option style and payoff kind.

    Complexity:
        O(1) time and O(1) space.
    """
    normalized = option_type.lower().replace("-", "_").replace(" ", "_").strip()
    parts = set(normalized.split("_"))

    if normalized in {"call", "put"}:
        return "european", _validate_option_kind(normalized)

    style = "asian" if "asian" in parts else "european" if "european" in parts else ""

    if not style:
        raise ValueError("option_type must describe a european or asian option")

    kind = "put" if "put" in parts else "call"

    if "call" in parts and "put" in parts:
        raise ValueError("option_type cannot contain both call and put")

    return style, kind  # type: ignore[return-value]


def _payoff(price_basis: np.ndarray, strike: float, kind: OptionKind) -> np.ndarray:
    """Calculate call or put payoff values.

    Args:
        price_basis: Terminal or average simulated prices.
        strike: Strike price.
        kind: Option payoff kind.

    Returns:
        Payoff values.

    Complexity:
        O(n) time and O(n) space for n price values.
    """
    if kind == "call":
        return np.maximum(price_basis - strike, 0.0)

    return np.maximum(strike - price_basis, 0.0)


def _normal_pdf(value: np.ndarray) -> np.ndarray:
    """Calculate the standard-normal probability density.

    Args:
        value: Points at which to evaluate the density.

    Returns:
        Standard-normal density values.

    Complexity:
        O(n) time and O(n) space for n input elements.
    """
    return np.exp(-0.5 * value * value) / np.sqrt(2.0 * np.pi)


def _normal_cdf(value: np.ndarray) -> np.ndarray:
    """Approximate the standard-normal cumulative distribution.

    Args:
        value: Points at which to evaluate the cumulative distribution.

    Returns:
        Standard-normal cumulative probabilities.

    Complexity:
        O(n) time and O(n) space for n input elements.
    """
    x = np.asarray(value, dtype=float)
    positive = x >= 0.0
    abs_x = np.abs(x)
    t = 1.0 / (1.0 + 0.2316419 * abs_x)
    polynomial = (
        0.319381530 * t
        - 0.356563782 * t**2
        + 1.781477937 * t**3
        - 1.821255978 * t**4
        + 1.330274429 * t**5
    )
    cdf_positive = 1.0 - _normal_pdf(abs_x) * polynomial

    return np.where(positive, cdf_positive, 1.0 - cdf_positive)


def _as_scalar_if_needed(value: np.ndarray, scalar_output: bool) -> float | np.ndarray:
    """Convert array output to scalar output when requested.

    Args:
        value: Output array.
        scalar_output: Whether the original inputs were scalar-only.

    Returns:
        A float when scalar_output is true, otherwise the original array.

    Complexity:
        O(1) time and O(1) space.
    """
    if scalar_output:
        return float(np.asarray(value).item())

    return value
