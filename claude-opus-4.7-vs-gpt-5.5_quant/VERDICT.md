---

## Evaluation Results

### Test Run Summary

| Agent | Tests | Result | Benchmark |
|-------|-------|--------|-----------|
| **Claude Opus 4.7** | 47 | ✅ All pass | ~8.7M pricings/sec |
| **GPT-5.5** | 13 | ✅ All pass | ~16.3M pricings/sec |

---

## Detailed Scoring

### 1. Correctness (40%)

**Claude Opus 4.7 — 40/40**
- Black-Scholes: exact closed-form, handles all degenerate cases (T=0, σ=0, S=0, K=0) correctly via a unified `np.where` mask.
- Greeks: analytical formulas are exact. Finite-difference verification in tests matches to 1e-5 (delta) and 1e-4 (gamma). Theta correctly scaled to per calendar day.
- Implied vol: Newton-Raphson with bisection fallback. Round-trip recovery to 1e-5 for σ ∈ [0.05, 1.50]. No-arbitrage bounds checked before solving.
- Monte Carlo: uses log-Euler (exact transition for constant-coefficient GBM), chunked memory, returns price + standard error. Convergence to BS verified.
- VaR: parametric formula correct. Single-asset test matches theoretical value within 5%.

**GPT-5.5 — 33/40**
- Black-Scholes: correct. Edge cases handled via explicit boolean masking.
- **Bug in Greeks at zero volatility:** `calculate_greeks(100, 100, 1, 0.05, 0, "call")` returns `delta=0.0` when it should be `1.0` (ITM by forward). The code only sets delta for `maturity == 0.0`, leaving zero-vol ITM options mis-characterized. This is a real pricing desk bug.
- Implied vol: correct round-trip recovery. Bisection fallback works.
- Monte Carlo: uses price-level Euler-Maruyama (`S += S*(r·dt + σ·√dt·Z)`). Technically satisfies the prompt, but can produce negative prices for extreme shocks. Log-Euler is strictly better.
- VaR: correct.
- CDF approximation error ~7e-8, acceptable but not exact.

---

### 2. Code Quality (25%)

**Claude Opus 4.7 — 24/25**
- Clean module-level docstring.
- Type hints throughout (`ArrayLike = Union[float, np.ndarray]`).
- Docstrings include args, returns, raises, and complexity notes per requirement.
- Helper functions are well-factored (`_validate_market_inputs`, `_norm_cdf`, `_norm_pdf`, `_norm_ppf`).
- The Acklam PPF implementation is ~40 lines of magic numbers — necessary for accuracy but slightly dense.

**GPT-5.5 — 22/25**
- Modern syntax (`float | np.ndarray`, `OptionKind = Literal["call", "put"]`).
- Good helper decomposition (`_broadcast_numeric_inputs`, `_as_scalar_if_needed`).
- Boolean masking in `black_scholes_price` and `calculate_greeks` makes the control flow harder to follow than Claude's unified formula approach.
- `_parse_monte_carlo_option_type` is over-engineered for the prompt (accepts `"asian_call"`, `"european_put"`, etc.).

---

### 3. Test Coverage (20%)

**Claude Opus 4.7 — 20/20**
- **47 tests** vs GPT's 13.
- Includes finite-difference verification for Greeks, put-call parity, deep ITM/OTM bound checks, multiple σ round-trips for IV, VaR single-asset known-value test, MC seed reproducibility, Asian < European monotonicity, and invalid-input coverage for every function.

**GPT-5.5 — 13/20**
- Covers the rubric basics (known values, signs/bounds, round-trip, monotonicity, edge cases, benchmark).
- Missing: finite-difference Greek verification, multiple IV round-trips across a vol surface, put-call parity, deep ITM/OTM bounds, MC seed reproducibility, VaR known-value test.

---

### 4. Performance (15%)

**Claude Opus 4.7 — 10/15**
- ~8.7M pricings/sec.
- Bottleneck: `_norm_cdf` uses `np.frompyfunc(math.erf, 1, 1)`, which introduces Python-level per-element call overhead. Accurate to machine epsilon, but slower.

**GPT-5.5 — 14/15**
- ~16.3M pricings/sec — nearly **2× faster**.
- Polynomial CDF approximation avoids `math.erf` ufunc overhead. Trading ~1e-7 accuracy for speed is a valid engineering choice for this domain.

---

## Final Scores

| Criterion | Claude Opus 4.7 | GPT-5.5 |
|-----------|-----------------|---------|
| Correctness | **40 / 40** | 33 / 40 |
| Code Quality | **24 / 25** | 22 / 25 |
| Test Coverage | **20 / 20** | 13 / 20 |
| Performance | 10 / 15 | **14 / 15** |
| **Total** | **94 / 100** | **82 / 100** |

---

## Verdict

**Claude Opus 4.7 wins.** It is materially more correct (zero-vol Greeks bug in GPT), dramatically better tested (47 vs 13 tests), and only modestly slower. GPT-5.5's ~2× speed advantage comes from a faster CDF approximation, but that speedup is offset by a real correctness defect and significantly thinner test coverage. In quant finance, getting the Greeks right at the boundary matters more than raw throughput.
