# cython: boundscheck=False
# cython: wraparound=False
# cython: cdivision=True

import numpy as np
cimport numpy as cnp
cimport cython
from libc.math cimport log, sqrt, exp, fmax
from libc.stdlib cimport rand, RAND_MAX, srand
from libc.time cimport time
import random

# Fast normal CDF approximation (Abramowitz and Stegun)
cdef double norm_cdf(double x) nogil:
    """Fast approximation of normal CDF with good accuracy"""
    cdef double a1 = 0.254829592
    cdef double a2 = -0.284496736
    cdef double a3 = 1.421413741
    cdef double a4 = -1.453152027
    cdef double a5 = 1.061405429
    cdef double p = 0.3275911
    cdef double sign = 1.0
    cdef double t, y, erf_approx

    if x < 0:
        sign = -1.0
        x = -x

    t = 1.0 / (1.0 + p * x)
    y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * exp(-x * x)

    return 0.5 * (1.0 + sign * y)

cdef double uniform_random(double min_val, double max_val) nogil:
    """Generate uniform random number between min_val and max_val"""
    return min_val + (max_val - min_val) * (<double> rand() / RAND_MAX)

cdef int choice_2(int a, int b) nogil:
    """Choose between two integers randomly"""
    if (<double> rand() / RAND_MAX) < 0.5:
        return a
    else:
        return b

cdef double black_scholes_call(double S, double K, double r, double T, double sigma) nogil:
    """Calculate Black-Scholes call option price"""
    cdef double d1, d2, call_price

    d1 = (log(S / K) + (r + 0.5 * sigma * sigma) * T) / (sigma * sqrt(T))
    d2 = d1 - sigma * sqrt(T)

    call_price = S * norm_cdf(d1) - K * exp(-r * T) * norm_cdf(d2)

    # Ensure call is at least intrinsic value
    return fmax(call_price, fmax(S - K, 0.0))

def generate_options_ladder_fast(int num_strikes):
    """
    Optimized version of generate_options_ladder using Cython.

    Args:
        num_strikes (int): Number of different strike prices in the ladder

    Returns:
        tuple: (ladder, stock_price, r_c, params)
    """
    # Seed random number generator
    srand(<unsigned int> time(NULL))

    # Generate random stock price between 5 and 100
    cdef double stock_price = uniform_random(5.0, 100.0)

    # Determine strike spacing based on stock price
    cdef int spacing
    if stock_price < 10:
        spacing = choice_2(1, 2)
    elif stock_price < 25:
        spacing = 5
    elif stock_price < 50:
        spacing = 5
    else:
        spacing = choice_2(5, 10)

    # Find a good center strike
    cdef double center_strike = round(stock_price / spacing) * spacing

    # Create strikes array
    cdef int center_index = num_strikes // 2
    cdef cnp.ndarray[double, ndim=1] strikes = np.zeros(num_strikes, dtype=np.float64)
    cdef int i
    cdef double strike

    for i in range(num_strikes):
        strike = center_strike + (i - center_index) * spacing
        strikes[i] = fmax(strike, spacing)  # Ensure positive strikes

    # Sort strikes
    strikes = np.sort(strikes)

    # Generate Black-Scholes parameters
    cdef double r = uniform_random(0.02, 0.06)
    cdef double T = uniform_random(0.2, 2.0)
    cdef double base_sigma = uniform_random(0.15, 0.40)
    cdef double r_c = uniform_random(0.1, 2.0)
    r_c = round(r_c * 100) / 100.0  # Round to 2 decimal places

    # Generate the options ladder
    ladder = []
    cdef double K, moneyness, vol_adjustment, sigma
    cdef double call_price, put_price, parity_left, parity_right, parity_check

    for i in range(num_strikes):
        K = strikes[i]

        # Create volatility smile/skew
        moneyness = K / stock_price

        if moneyness < 0.95:  # Deep OTM puts
            vol_adjustment = uniform_random(0.05, 0.15)
        elif moneyness > 1.05:  # Deep OTM calls
            vol_adjustment = uniform_random(0.03, 0.10)
        elif moneyness < 0.98 or moneyness > 1.02:  # Slightly OTM
            vol_adjustment = uniform_random(0.02, 0.06)
        else:  # ATM
            vol_adjustment = uniform_random(-0.02, 0.02)

        sigma = fmax(base_sigma + vol_adjustment, 0.10)  # Minimum 10% vol

        # Calculate call price using optimized Black-Scholes
        call_price = black_scholes_call(stock_price, K, r, T, sigma)
        call_price = round(call_price * 100) / 100.0  # Round to 2 decimal places

        # Put option price using put-call parity
        put_price = call_price - stock_price + K - r_c
        put_price = round(put_price * 100) / 100.0  # Round to 2 decimal places

        # Check put-call parity
        parity_left = call_price - put_price
        parity_right = stock_price - K + r_c
        parity_check = round((parity_left - parity_right) * 10000) / 10000.0

        ladder.append([call_price, K, put_price, parity_check])

    params = {
        'risk_free_rate': round(r * 100) / 100.0,
        'time_to_expiry': round(T * 100) / 100.0,
        'volatility': round(sigma * 100) / 100.0
    }

    return ladder, round(stock_price * 100) / 100.0, r_c, params

def print_ladder(ladder, stock_price, r_c, params):
    """
    Pretty print the options ladder.
    """
    print(f"Stock Price: ${stock_price}")
    print(f"Interest Component (r/c): {r_c}")
    print(f"Risk-free rate: {params['risk_free_rate'] * 100:.2f}%")
    print(f"Time to expiry: {params['time_to_expiry']:.2f} years")
    print(f"Volatility: {params['volatility'] * 100:.1f}%")
    print(f"{'Call Price':<12} {'Strike':<8} {'Put Price':<10} {'Parity':<8}")
    print("-" * 40)
    for call, strike, put, parity_check in ladder:
        parity_status = "True" if abs(parity_check) < 0.01 else "False"
        print(f"${call:<11} ${strike:<7} ${put:<9} {parity_status}")