# Quantitative Finance Algorithm Implementation

Implement a Python library for equity option pricing and risk analytics. All code must be self-contained (no external market data files). Use only the Python standard library and `numpy`.

## Deliverables

Create a single file `quant_lib.py` and a test file `test_quant_lib.py` in a new directory `quant_solution/`.

## Required Implementations

### 1. Black-Scholes Closed-Form Pricer

Implement a function `black_scholes_price(S, K, T, r, sigma, option_type)` where:
- `S`: spot price
- `K`: strike price
- `T`: time to maturity in years
- `r`: risk-free rate
- `sigma`: volatility
- `option_type`: `"call"` or `"put"`

Returns the option price. Validate inputs (raise `ValueError` for negative prices, time, rate, or volatility).

### 2. Monte Carlo Option Pricer

Implement `monte_carlo_option_price(S, K, T, r, sigma, option_type, n_simulations=100_000, n_steps=252, seed=None)`.

Use geometric Brownian motion with Euler-Maruyama discretization. For `"asian"` option type, compute the payoff on the arithmetic average price over the path. For `"european"`, payoff on terminal price only. Return both the price and the standard error of the estimate.

### 3. Greeks Calculation

Implement `calculate_greeks(S, K, T, r, sigma, option_type)` returning a dict with:
- `delta`, `gamma`, `theta`, `vega`, `rho`

Use analytical formulas for European options. Theta should be in **per calendar day** (divide annual by 365).

### 4. Implied Volatility Solver

Implement `implied_volatility(market_price, S, K, T, r, option_type, tol=1e-8, max_iter=100)`.

Use the Newton-Raphson method with vega as the derivative. Fall back to bisection if NR fails to converge. Return `None` if no solution exists within `[1e-8, 5.0]`.

### 5. Portfolio Value-at-Risk (Parametric)

Implement `parametric_var(returns, weights, confidence_level=0.95, horizon_days=1)`.

- `returns`: numpy array of shape `(n_observations, n_assets)` — historical asset returns
- `weights`: numpy array of shape `(n_assets,)` — portfolio weights summing to 1

Assume returns are normally distributed. Compute the portfolio variance from the covariance matrix, then return the VaR as a positive dollar amount assuming a `$1,000,000` portfolio. Return `ValueError` if weights do not sum to 1 within tolerance `1e-6`.

## Constraints

- All functions must be vectorized with `numpy` where possible.
- No `pandas`, `scipy`, or external dependencies beyond `numpy`.
- Every function must include a docstring with args, return value, and a one-line complexity note (time/space).
- Use type hints on all function signatures.

## Testing Requirements

In `test_quant_lib.py`, provide:

1. **Unit tests** for each function with known analytical solutions:
   - Black-Scholes: verify against known values (e.g., S=100, K=100, T=1, r=0.05, sigma=0.2 → call ≈ 10.45, put ≈ 5.57)
   - Greeks: verify delta bounds (call: 0 to 1, put: -1 to 0), gamma > 0, vega > 0
   - Implied vol: round-trip test (price with σ=0.25 → recover σ via implied_vol)
   - VaR: verify monotonicity (higher confidence → higher VaR)

2. **Convergence test**: show that Monte Carlo price approaches Black-Scholes price for a European call as `n_simulations` increases (test with 1k, 10k, 100k).

3. **Edge case tests**: T=0 (intrinsic value), very low volatility, very high volatility.

4. **Performance benchmark**: a `if __name__ == "__main__"` block that times 1 million Black-Scholes evaluations on a vector of 10,000 options × 100 repetitions, and prints the throughput (pricings/second).

## Scoring Rubric (for evaluator)

The evaluator will score the submission on:

| Criterion | Weight |
|-----------|--------|
| Correctness (all tests pass, math is right) | 40% |
| Code quality (clarity, naming, structure, type hints) | 25% |
| Test coverage (edge cases, convergence, benchmarks) | 20% |
| Performance (vectorization, numerical stability) | 15% |

## Submission

Return the complete contents of both files. Do not omit imports or helper functions.
