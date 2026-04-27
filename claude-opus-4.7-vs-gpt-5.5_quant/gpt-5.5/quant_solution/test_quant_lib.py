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


class BlackScholesTests(unittest.TestCase):
    def test_known_call_and_put_values(self) -> None:
        call_price = black_scholes_price(100.0, 100.0, 1.0, 0.05, 0.2, "call")
        put_price = black_scholes_price(100.0, 100.0, 1.0, 0.05, 0.2, "put")

        self.assertAlmostEqual(call_price, 10.45, places=2)
        self.assertAlmostEqual(put_price, 5.57, places=2)

    def test_rejects_negative_inputs(self) -> None:
        with self.assertRaises(ValueError):
            black_scholes_price(-100.0, 100.0, 1.0, 0.05, 0.2, "call")

        with self.assertRaises(ValueError):
            black_scholes_price(100.0, 100.0, 1.0, -0.05, 0.2, "call")

    def test_vectorized_pricing(self) -> None:
        spots = np.array([90.0, 100.0, 110.0])
        prices = black_scholes_price(spots, 100.0, 1.0, 0.05, 0.2, "call")

        self.assertEqual(prices.shape, spots.shape)
        self.assertTrue(np.all(np.diff(prices) > 0.0))


class MonteCarloTests(unittest.TestCase):
    def test_european_call_converges_toward_black_scholes(self) -> None:
        target = black_scholes_price(100.0, 100.0, 1.0, 0.05, 0.2, "call")
        simulation_counts = [1_000, 10_000, 100_000]
        estimates = [
            monte_carlo_option_price(
                100.0,
                100.0,
                1.0,
                0.05,
                0.2,
                "european",
                n_simulations=count,
                n_steps=252,
                seed=7,
            )
            for count in simulation_counts
        ]
        prices = [estimate[0] for estimate in estimates]
        standard_errors = [estimate[1] for estimate in estimates]
        absolute_errors = [abs(price - target) for price in prices]

        self.assertLess(standard_errors[2], standard_errors[1])
        self.assertLess(standard_errors[1], standard_errors[0])
        self.assertLess(absolute_errors[2], absolute_errors[0])
        self.assertLess(absolute_errors[2], 0.35)

    def test_asian_option_returns_positive_estimate_and_error(self) -> None:
        price, standard_error = monte_carlo_option_price(
            100.0,
            100.0,
            1.0,
            0.05,
            0.2,
            "asian_call",
            n_simulations=20_000,
            n_steps=64,
            seed=11,
        )

        self.assertGreater(price, 0.0)
        self.assertGreater(standard_error, 0.0)


class GreeksTests(unittest.TestCase):
    def test_greeks_have_expected_signs_and_bounds(self) -> None:
        call_greeks = calculate_greeks(100.0, 100.0, 1.0, 0.05, 0.2, "call")
        put_greeks = calculate_greeks(100.0, 100.0, 1.0, 0.05, 0.2, "put")

        self.assertGreaterEqual(call_greeks["delta"], 0.0)
        self.assertLessEqual(call_greeks["delta"], 1.0)
        self.assertGreaterEqual(put_greeks["delta"], -1.0)
        self.assertLessEqual(put_greeks["delta"], 0.0)
        self.assertGreater(call_greeks["gamma"], 0.0)
        self.assertGreater(call_greeks["vega"], 0.0)
        self.assertGreater(put_greeks["gamma"], 0.0)
        self.assertGreater(put_greeks["vega"], 0.0)


class ImpliedVolatilityTests(unittest.TestCase):
    def test_round_trip_recovers_input_volatility(self) -> None:
        price = black_scholes_price(100.0, 100.0, 1.0, 0.05, 0.25, "call")
        volatility = implied_volatility(price, 100.0, 100.0, 1.0, 0.05, "call")

        self.assertIsNotNone(volatility)
        self.assertAlmostEqual(volatility, 0.25, places=6)

    def test_returns_none_when_no_solution_exists(self) -> None:
        volatility = implied_volatility(500.0, 100.0, 100.0, 1.0, 0.05, "call")

        self.assertIsNone(volatility)


class ParametricVarTests(unittest.TestCase):
    def test_var_increases_with_confidence_level(self) -> None:
        returns = np.array(
            [
                [0.010, 0.005],
                [-0.020, -0.010],
                [0.015, 0.007],
                [-0.005, -0.002],
                [0.012, 0.004],
                [-0.011, -0.006],
            ]
        )
        weights = np.array([0.6, 0.4])
        var_95 = parametric_var(returns, weights, confidence_level=0.95)
        var_99 = parametric_var(returns, weights, confidence_level=0.99)

        self.assertGreater(var_95, 0.0)
        self.assertGreater(var_99, var_95)

    def test_rejects_weights_that_do_not_sum_to_one(self) -> None:
        returns = np.array([[0.01, 0.02], [0.02, -0.01], [-0.01, 0.00]])
        weights = np.array([0.7, 0.4])

        with self.assertRaises(ValueError):
            parametric_var(returns, weights)


class EdgeCaseTests(unittest.TestCase):
    def test_zero_maturity_returns_intrinsic_value(self) -> None:
        call_price = black_scholes_price(105.0, 100.0, 0.0, 0.05, 0.2, "call")
        put_price = black_scholes_price(95.0, 100.0, 0.0, 0.05, 0.2, "put")
        mc_price, mc_error = monte_carlo_option_price(
            105.0,
            100.0,
            0.0,
            0.05,
            0.2,
            "european_call",
            seed=1,
        )

        self.assertEqual(call_price, 5.0)
        self.assertEqual(put_price, 5.0)
        self.assertEqual(mc_price, 5.0)
        self.assertEqual(mc_error, 0.0)

    def test_very_low_volatility_approaches_discounted_forward_payoff(self) -> None:
        price = black_scholes_price(100.0, 100.0, 1.0, 0.05, 1e-8, "call")
        deterministic_price = black_scholes_price(100.0, 100.0, 1.0, 0.05, 0.0, "call")

        self.assertAlmostEqual(price, deterministic_price, places=5)

    def test_very_high_volatility_has_large_call_value(self) -> None:
        price = black_scholes_price(100.0, 100.0, 1.0, 0.05, 3.0, "call")

        self.assertGreater(price, 80.0)
        self.assertLess(price, 100.0)


def benchmark_black_scholes() -> None:
    spots = np.linspace(80.0, 120.0, 10_000)
    strikes = np.full(10_000, 100.0)
    maturities = np.linspace(0.1, 2.0, 10_000)
    rates = np.full(10_000, 0.05)
    volatilities = np.full(10_000, 0.2)
    repetitions = 100
    pricing_count = spots.size * repetitions
    start = time.perf_counter()

    for _ in range(repetitions):
        black_scholes_price(spots, strikes, maturities, rates, volatilities, "call")

    elapsed = time.perf_counter() - start
    throughput = pricing_count / elapsed

    print(f"Black-Scholes throughput: {throughput:,.0f} pricings/second")


if __name__ == "__main__":
    result = unittest.main(exit=False)

    if result.result.wasSuccessful():
        benchmark_black_scholes()
