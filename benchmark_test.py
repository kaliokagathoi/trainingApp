#!/usr/bin/env python3
"""
Benchmark script to compare original vs optimized options ladder generation.
"""

import time
import numpy as np
import random
from scipy.stats import norm


# Original function (for comparison)
def generate_options_ladder_original(num_strikes):
    """Original implementation for comparison"""
    stock_price = random.uniform(5, 100)

    if stock_price < 10:
        spacing = random.choice([1, 2])
    elif stock_price < 25:
        spacing = 5
    elif stock_price < 50:
        spacing = 5
    else:
        spacing = random.choice([5, 10])

    center_strike = round(stock_price / spacing) * spacing
    center_index = num_strikes // 2
    strikes = []
    for i in range(num_strikes):
        strike = center_strike + (i - center_index) * spacing
        strikes.append(max(strike, spacing))
    strikes.sort()

    r = random.uniform(0.02, 0.06)
    T = random.uniform(0.2, 2)
    base_sigma = random.uniform(0.15, 0.40)
    r_c = random.uniform(0.1, 2)
    r_c = round(r_c, 2)

    ladder = []
    for K in strikes:
        moneyness = K / stock_price

        if moneyness < 0.95:
            vol_adjustment = random.uniform(0.05, 0.15)
        elif moneyness > 1.05:
            vol_adjustment = random.uniform(0.03, 0.10)
        elif moneyness < 0.98 or moneyness > 1.02:
            vol_adjustment = random.uniform(0.02, 0.06)
        else:
            vol_adjustment = random.uniform(-0.02, 0.02)

        sigma = max(base_sigma + vol_adjustment, 0.10)

        d1 = (np.log(stock_price / K) + (r + 0.5 * sigma ** 2) * T) / (sigma * np.sqrt(T))
        d2 = d1 - sigma * np.sqrt(T)

        call_price = stock_price * norm.cdf(d1) - K * np.exp(-r * T) * norm.cdf(d2)
        call_price = max(call_price, max(stock_price - K, 0))
        call_price = round(call_price, 2)

        put_price = call_price - stock_price + K - r_c
        put_price = round(put_price, 2)

        parity_left = call_price - put_price
        parity_right = stock_price - K + r_c
        parity_check = round(parity_left - parity_right, 4)

        ladder.append([call_price, K, put_price, parity_check])

    params = {
        'risk_free_rate': round(r, 2),
        'time_to_expiry': round(T, 2),
        'volatility': round(sigma, 2)
    }

    return ladder, round(stock_price, 2), r_c, params


def benchmark_functions(num_iterations=1000, num_strikes=10):
    """Benchmark both implementations"""

    print(f"Benchmarking with {num_iterations} iterations, {num_strikes} strikes each...")
    print("=" * 60)

    # Import the compiled Cython module
    try:
        import options_ladder_fast
        cython_available = True
        print("✓ Cython module loaded successfully")
    except ImportError:
        print("✗ Cython module not found. Please compile first using:")
        print("  python setup.py build_ext --inplace")
        cython_available = False
        return

    # Benchmark original implementation
    print("\nTesting original implementation...")
    start_time = time.time()

    for i in range(num_iterations):
        ladder, stock_price, r_c, params = generate_options_ladder_original(num_strikes)

    original_time = time.time() - start_time
    print(f"Original implementation: {original_time:.4f} seconds")

    # Benchmark Cython implementation
    print("\nTesting Cython implementation...")
    start_time = time.time()

    for i in range(num_iterations):
        ladder, stock_price, r_c, params = options_ladder_fast.generate_options_ladder_fast(num_strikes)

    cython_time = time.time() - start_time
    print(f"Cython implementation: {cython_time:.4f} seconds")

    # Calculate speedup
    speedup = original_time / cython_time
    print(f"\nSpeedup: {speedup:.2f}x faster")
    print(f"Time reduction: {((original_time - cython_time) / original_time * 100):.1f}%")

    # Test correctness - generate a few ladders and compare structure
    print("\nTesting correctness...")

    # Original
    orig_ladder, orig_stock, orig_rc, orig_params = generate_options_ladder_original(5)
    print(f"Original - Stock: ${orig_stock}, Strikes: {len(orig_ladder)}")

    # Cython
    cython_ladder, cython_stock, cython_rc, cython_params = options_ladder_fast.generate_options_ladder_fast(5)
    print(f"Cython   - Stock: ${cython_stock}, Strikes: {len(cython_ladder)}")

    # Test parity checks
    orig_parity_ok = all(abs(row[3]) < 0.01 for row in orig_ladder)
    cython_parity_ok = all(abs(row[3]) < 0.01 for row in cython_ladder)

    print(f"Original parity checks: {'✓' if orig_parity_ok else '✗'}")
    print(f"Cython parity checks: {'✓' if cython_parity_ok else '✗'}")

    return speedup


def test_example_usage():
    """Test the optimized function with example usage"""
    try:
        import options_ladder_fast

        print("\nExample usage of optimized function:")
        print("=" * 40)

        # Generate a 3-strike ladder
        ladder, stock_price, r_c, params = options_ladder_fast.generate_options_ladder_fast(3)
        options_ladder_fast.print_ladder(ladder, stock_price, r_c, params)

        print("\n" + "=" * 40 + "\n")

        # Generate a 5-strike ladder
        ladder2, stock_price2, r_c2, params2 = options_ladder_fast.generate_options_ladder_fast(5)
        options_ladder_fast.print_ladder(ladder2, stock_price2, r_c2, params2)

    except ImportError:
        print("Please compile the Cython module first using:")
        print("python setup.py build_ext --inplace")


if __name__ == "__main__":
    # Run benchmarks
    benchmark_functions(num_iterations=1000, num_strikes=4)

    # Show example usage
    test_example_usage()

    print("\n" + "=" * 60)
    print("To use the optimized version in your code:")
    print("import options_ladder_fast")
    print("ladder, stock, rc, params = options_ladder_fast.generate_options_ladder_fast(num_strikes)")