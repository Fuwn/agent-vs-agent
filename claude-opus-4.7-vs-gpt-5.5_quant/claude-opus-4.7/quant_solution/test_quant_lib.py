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
