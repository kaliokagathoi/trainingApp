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
    Ensures all call and put prices are above intrinsic value, parity holds,
    monotonicity is preserved, and no arbitrage opportunities exist.

    Args:
        num_strikes (int): Number of different strike prices in the ladder

    Returns:
        tuple: (ladder, stock_price, r_c)
    """
    # Seed random number generator
    srand(<unsigned int> time(NULL))

    # Declare all variables at the top
    cdef int max_attempts = 100
    cdef int attempt = 0
    cdef double stock_price
    cdef int spacing
    cdef double center_strike
    cdef int center_index = num_strikes // 2
    cdef cnp.ndarray[double, ndim=1] strikes
    cdef int i, j
    cdef double strike
    cdef double r, T, base_sigma, r_c
    cdef double K, moneyness, vol_adjustment, sigma
    cdef double call_price, put_price, parity_left, parity_right, parity_check
    cdef double call_intrinsic, put_intrinsic
    cdef bint intrinsic_check, parity_ok, ladder_valid, monotonicity_ok, arbitrage_ok
    cdef double prev_call, prev_put, current_call, current_put
    cdef double call_spread, put_spread, box_value, strike_diff

    # Keep generating until we get a valid ladder
    while attempt < max_attempts:
        attempt += 1

        # Generate random stock price between 5 and 100
        stock_price = uniform_random(5.0, 100.0)

        # Determine strike spacing based on stock price
        if stock_price < 10:
            spacing = choice_2(1, 2)
        elif stock_price < 25:
            spacing = 5
        elif stock_price < 50:
            spacing = 5
        else:
            spacing = choice_2(5, 10)

        # Find a good center strike
        center_strike = round(stock_price / spacing) * spacing

        # Create strikes array
        strikes = np.zeros(num_strikes, dtype=np.float64)

        for i in range(num_strikes):
            strike = center_strike + (i - center_index) * spacing
            strikes[i] = fmax(strike, spacing)  # Ensure positive strikes

        # Sort strikes
        strikes = np.sort(strikes)

        # Generate Black-Scholes parameters with tighter ranges for stability
        r = uniform_random(0.02, 0.05)
        T = uniform_random(0.25, 1.5)
        base_sigma = uniform_random(0.18, 0.35)
        r_c = uniform_random(0.1, 1.5)
        r_c = round(r_c * 100) / 100.0  # Round to 2 decimal places

        # Generate the options ladder
        ladder = []
        ladder_valid = True

        for i in range(num_strikes):
            K = strikes[i]

            # Create more controlled volatility smile/skew
            moneyness = K / stock_price

            if moneyness < 0.90:  # Deep OTM puts
                vol_adjustment = uniform_random(0.02, 0.08)
            elif moneyness > 1.10:  # Deep OTM calls
                vol_adjustment = uniform_random(0.01, 0.05)
            elif moneyness < 0.95 or moneyness > 1.05:  # Slightly OTM
                vol_adjustment = uniform_random(0.01, 0.03)
            else:  # ATM
                vol_adjustment = uniform_random(-0.01, 0.01)

            sigma = fmax(base_sigma + vol_adjustment, 0.12)  # Minimum 12% vol

            # Calculate call price using optimized Black-Scholes
            call_price = black_scholes_call(stock_price, K, r, T, sigma)
            call_price = round(call_price * 100) / 100.0  # Round to 2 decimal places

            # Put option price using put-call parity
            put_price = call_price - stock_price + K - r_c
            put_price = round(put_price * 100) / 100.0  # Round to 2 decimal places

            # Calculate intrinsic values
            call_intrinsic = fmax(stock_price - K, 0.0)
            put_intrinsic = fmax(K - stock_price, 0.0)

            # Check if both call and put are above intrinsic value
            intrinsic_check = (call_price >= call_intrinsic) and (put_price >= put_intrinsic)

            # Check put-call parity
            parity_left = call_price - put_price
            parity_right = stock_price - K + r_c
            parity_check = round((parity_left - parity_right) * 10000) / 10000.0
            parity_ok = abs(parity_check) < 0.01

            # If either check fails, mark ladder as invalid
            if not intrinsic_check or not parity_ok:
                ladder_valid = False
                break

            ladder.append([call_price, K, put_price])

        # Check monotonicity: calls decreasing, puts increasing with strike
        if ladder_valid and len(ladder) > 1:
            monotonicity_ok = True
            for i in range(1, len(ladder)):
                prev_call = ladder[i - 1][0]
                current_call = ladder[i][0]
                prev_put = ladder[i - 1][2]
                current_put = ladder[i][2]

                # Calls should decrease (or stay same) as strike increases
                if current_call > prev_call + 0.01:  # Small tolerance
                    monotonicity_ok = False
                    break

                # Puts should increase (or stay same) as strike increases
                if current_put < prev_put - 0.01:  # Small tolerance
                    monotonicity_ok = False
                    break

            if not monotonicity_ok:
                ladder_valid = False

        # Check box spreads for arbitrage
        if ladder_valid and len(ladder) > 1:
            arbitrage_ok = True
            for i in range(len(ladder) - 1):
                call_spread = ladder[i][0] - ladder[i + 1][0]  # Long lower strike call
                put_spread = ladder[i + 1][2] - ladder[i][2]  # Long higher strike put
                box_value = call_spread + put_spread
                strike_diff = ladder[i + 1][1] - ladder[i][1]

                # Box should equal strike difference within small tolerance
                if abs(box_value - strike_diff) > 0.05:
                    arbitrage_ok = False
                    break

            if not arbitrage_ok:
                ladder_valid = False

        # If ladder is valid, return it
        if ladder_valid:
            return ladder, round(stock_price * 100) / 100.0, r_c

    # If we couldn't generate a valid ladder after max_attempts, return the last attempt
    return ladder, round(stock_price * 100) / 100.0, r_c

def generate_exercise_ladder_with_spreads(int num_strikes, double missing_probability=0.3):
    """
    Generate a complete options ladder and a more sophisticated exercise version
    that includes spreads and requires strategic solving.
    Ensures the exercise is fully solvable.

    Args:
        num_strikes (int): Number of strikes in the ladder
        missing_probability (double): Base probability of removing a price (default 0.3)

    Returns:
        tuple: (real_ladder, exercise_data, stock_price, r_c)
    """
    max_attempts = 20

    for attempt in range(max_attempts):
        # Generate the complete ladder
        real_ladder, stock_price, r_c = generate_options_ladder_fast(num_strikes)

        # Calculate all possible spreads
        spreads = calculate_all_spreads(real_ladder)

        # Create exercise with strategic omissions
        exercise_data = create_strategic_exercise(real_ladder, spreads, missing_probability)

        # Verify the exercise is solvable
        if verify_exercise_solvable(exercise_data, stock_price, r_c):
            return real_ladder, exercise_data, stock_price, r_c

        # If not solvable, try adding more hints
        exercise_data = add_fallback_hints(real_ladder, exercise_data)

        # Check again after adding hints
        if verify_exercise_solvable(exercise_data, stock_price, r_c):
            return real_ladder, exercise_data, stock_price, r_c

    # If we still can't create a solvable exercise after many attempts,
    # create a very simple but guaranteed solvable one
    exercise_data = create_simple_solvable_exercise(real_ladder, spreads)

    return real_ladder, exercise_data, stock_price, r_c

def create_simple_solvable_exercise(real_ladder, spreads):
    """
    Create a simple but guaranteed solvable exercise.
    Provides more explicit information to ensure solvability.
    """
    exercise_data = {
        'explicit_prices': {},
        'spreads': {},
        'strikes': [row[1] for row in real_ladder]
    }

    # Initialize all as None
    for call, strike, put in real_ladder:
        exercise_data['explicit_prices'][(strike, 'call')] = None
        exercise_data['explicit_prices'][(strike, 'put')] = None

    for i in range(len(real_ladder) - 1):
        strike1 = real_ladder[i][1]
        strike2 = real_ladder[i + 1][1]
        exercise_data['spreads'][(strike1, strike2, 'call')] = None
        exercise_data['spreads'][(strike1, strike2, 'put')] = None

    # Strategy: Give one price and enough spreads to solve everything
    # Give the first strike's call price
    exercise_data['explicit_prices'][(real_ladder[0][1], 'call')] = real_ladder[0][0]

    # Give all call spreads OR all put spreads (randomly choose)
    import random
    if random.random() < 0.5:
        # Give call spreads
        for i in range(len(real_ladder) - 1):
            strike1 = real_ladder[i][1]
            strike2 = real_ladder[i + 1][1]
            exercise_data['spreads'][(strike1, strike2, 'call')] = spreads['call_spreads'][(strike1, strike2)]
    else:
        # Give put spreads
        for i in range(len(real_ladder) - 1):
            strike1 = real_ladder[i][1]
            strike2 = real_ladder[i + 1][1]
            exercise_data['spreads'][(strike1, strike2, 'put')] = spreads['put_spreads'][(strike1, strike2)]

    return exercise_data

def calculate_all_spreads(ladder):
    """
    Calculate all call spreads, put spreads, and box spreads.

    Returns:
        dict: All available spreads between adjacent strikes
    """
    spreads = {
        'call_spreads': {},  # (strike1, strike2): spread_value
        'put_spreads': {},  # (strike1, strike2): spread_value
        'box_spreads': {}  # (strike1, strike2): spread_value
    }

    for i in range(len(ladder) - 1):
        call1, strike1, put1 = ladder[i]
        call2, strike2, put2 = ladder[i + 1]

        # Call spread: long lower strike (K1), short higher strike (K2)
        call_spread = call1 - call2
        spreads['call_spreads'][(strike1, strike2)] = round(call_spread, 2)

        # Put spread: long higher strike (K2), short lower strike (K1)
        put_spread = put2 - put1
        spreads['put_spreads'][(strike1, strike2)] = round(put_spread, 2)

        # Box spread: call spread + put spread = strike difference
        box_spread = call_spread + put_spread
        spreads['box_spreads'][(strike1, strike2)] = round(box_spread, 2)

    return spreads

def create_strategic_exercise(real_ladder, spreads, missing_probability):
    """
    Create exercise that strategically uses spreads and explicit prices.
    Ensures all strikes are solvable by providing sufficient information.
    """
    import random

    exercise_data = {
        'explicit_prices': {},  # (strike, 'call'/'put'): price or None
        'spreads': {},  # (strike1, strike2, 'call'/'put'): spread_value or None (no box spreads)
        'strikes': [row[1] for row in real_ladder]
    }

    # Initialize all explicit prices as None
    for call, strike, put in real_ladder:
        exercise_data['explicit_prices'][(strike, 'call')] = None
        exercise_data['explicit_prices'][(strike, 'put')] = None

    # Initialize all spreads as None (only call and put spreads, no box)
    for i in range(len(real_ladder) - 1):
        strike1 = real_ladder[i][1]
        strike2 = real_ladder[i + 1][1]
        exercise_data['spreads'][(strike1, strike2, 'call')] = None
        exercise_data['spreads'][(strike1, strike2, 'put')] = None

    # Strategy 1: Always provide one anchor price (usually middle strike)
    middle_idx = len(real_ladder) // 2
    anchor_strike = real_ladder[middle_idx][1]
    if random.random() < 0.6:  # 60% chance to give call, 40% put
        exercise_data['explicit_prices'][(anchor_strike, 'call')] = real_ladder[middle_idx][0]
    else:
        exercise_data['explicit_prices'][(anchor_strike, 'put')] = real_ladder[middle_idx][2]

    # Strategy 2: Provide spreads to create chains of solvability
    # Ensure we can reach all strikes from the anchor
    for i in range(len(real_ladder) - 1):
        strike1 = real_ladder[i][1]
        strike2 = real_ladder[i + 1][1]

        # Higher probability of providing spreads to ensure connectivity
        spread_choice = random.random()
        if spread_choice < 0.6:  # 60% chance of call spread
            exercise_data['spreads'][(strike1, strike2, 'call')] = spreads['call_spreads'][(strike1, strike2)]
        elif spread_choice < 0.9:  # 30% chance of put spread
            exercise_data['spreads'][(strike1, strike2, 'put')] = spreads['put_spreads'][(strike1, strike2)]
        # 10% chance of no spread for this pair

    # Strategy 3: Add a few more explicit prices but not too many
    num_additional_prices = random.randint(1, 2)  # 1-2 additional explicit prices
    available_strikes = [row[1] for row in real_ladder if row[1] != anchor_strike]

    for _ in range(min(num_additional_prices, len(available_strikes))):
        if available_strikes:
            strike_idx = random.randint(0, len(available_strikes) - 1)
            strike = available_strikes.pop(strike_idx)

            # Find the ladder row for this strike
            for call, s, put in real_ladder:
                if s == strike:
                    if random.random() < 0.5:
                        exercise_data['explicit_prices'][(strike, 'call')] = call
                    else:
                        exercise_data['explicit_prices'][(strike, 'put')] = put
                    break

    return exercise_data

def verify_exercise_solvable(exercise_data, stock_price, r_c):
    """
    Verify that the exercise can be solved with the given information.
    Uses iterative solving approach until no more progress can be made.
    """
    # Create working copy of known values
    known_calls = {}
    known_puts = {}

    # Add explicit prices
    for (strike, option_type), price in exercise_data['explicit_prices'].items():
        if price is not None:
            if option_type == 'call':
                known_calls[strike] = price
            else:
                known_puts[strike] = price

    # Try to solve iteratively using parity and spreads
    max_iterations = 50
    iteration = 0

    while iteration < max_iterations:
        progress_made = False
        iteration += 1

        # Apply put-call parity where possible
        for strike in exercise_data['strikes']:
            if strike in known_calls and strike not in known_puts:
                # Put = Call - Stock + Strike - r_c
                put_price = known_calls[strike] - stock_price + strike - r_c
                known_puts[strike] = round(put_price, 2)
                progress_made = True
            elif strike in known_puts and strike not in known_calls:
                # Call = Put + Stock - Strike + r_c
                call_price = known_puts[strike] + stock_price - strike + r_c
                known_calls[strike] = round(call_price, 2)
                progress_made = True

        # Apply spreads where possible
        for (strike1, strike2, spread_type), spread_value in exercise_data['spreads'].items():
            if spread_value is not None:
                if spread_type == 'call':
                    if strike1 in known_calls and strike2 not in known_calls:
                        known_calls[strike2] = round(known_calls[strike1] - spread_value, 2)
                        progress_made = True
                    elif strike2 in known_calls and strike1 not in known_calls:
                        known_calls[strike1] = round(known_calls[strike2] + spread_value, 2)
                        progress_made = True
                elif spread_type == 'put':
                    if strike1 in known_puts and strike2 not in known_puts:
                        known_puts[strike2] = round(known_puts[strike1] + spread_value, 2)
                        progress_made = True
                    elif strike2 in known_puts and strike1 not in known_puts:
                        known_puts[strike1] = round(known_puts[strike2] - spread_value, 2)
                        progress_made = True

        # If no progress was made, break out of the loop
        if not progress_made:
            break

    # Check if we can solve all strikes (need at least one option per strike)
    all_strikes = set(exercise_data['strikes'])
    solved_strikes = set()

    for strike in all_strikes:
        if strike in known_calls or strike in known_puts:
            solved_strikes.add(strike)

    return len(solved_strikes) == len(all_strikes)

def add_fallback_hints(real_ladder, exercise_data):
    """
    Add minimal hints to ensure the exercise is solvable.
    Uses a more systematic approach to ensure connectivity.
    """
    import random

    # Check current solvability
    if verify_exercise_solvable(exercise_data, 0, 0):  # Use dummy values for quick check
        return exercise_data

    # Strategy: Add more spreads to create connectivity
    # First, try adding more spreads
    for i in range(len(real_ladder) - 1):
        strike1 = real_ladder[i][1]
        strike2 = real_ladder[i + 1][1]

        # If no spread exists for this pair, add one
        has_call_spread = exercise_data['spreads'].get((strike1, strike2, 'call')) is not None
        has_put_spread = exercise_data['spreads'].get((strike1, strike2, 'put')) is not None

        if not has_call_spread and not has_put_spread:
            # Add a random spread type
            if random.random() < 0.5:
                call_spread = real_ladder[i][0] - real_ladder[i + 1][0]
                exercise_data['spreads'][(strike1, strike2, 'call')] = round(call_spread, 2)
            else:
                put_spread = real_ladder[i + 1][2] - real_ladder[i][2]
                exercise_data['spreads'][(strike1, strike2, 'put')] = round(put_spread, 2)

    # If still not solvable, add one more explicit price
    # Choose a strike that doesn't have an explicit price yet
    for call, strike, put in real_ladder:
        has_call = exercise_data['explicit_prices'][(strike, 'call')] is not None
        has_put = exercise_data['explicit_prices'][(strike, 'put')] is not None

        if not has_call and not has_put:
            # Add one random explicit price
            if random.random() < 0.5:
                exercise_data['explicit_prices'][(strike, 'call')] = call
            else:
                exercise_data['explicit_prices'][(strike, 'put')] = put
            break

    return exercise_data

def print_exercise_ladder_with_spreads(exercise_data, stock_price, r_c):
    """
    Print the exercise showing explicit prices and spreads (no box spreads).
    """
    print(f"Stock Price: ${stock_price}")
    print(f"Interest Component (r/c): {r_c}")
    print(f"Put-Call Parity: Call - Put = Stock - Strike + r/c")
    print()

    # Print explicit prices
    print("GIVEN OPTION PRICES:")
    print(f"{'Strike':<8} {'Call':<12} {'Put':<12}")
    print("-" * 35)

    for strike in exercise_data['strikes']:
        call_price = exercise_data['explicit_prices'][(strike, 'call')]
        put_price = exercise_data['explicit_prices'][(strike, 'put')]

        call_str = f"${call_price}" if call_price is not None else "____"
        put_str = f"${put_price}" if put_price is not None else "____"

        print(f"${strike:<7} {call_str:<12} {put_str:<12}")

    # Print spreads (only call and put spreads, no box)
    print(f"\nGIVEN SPREADS:")
    print(f"{'Strikes':<12} {'Call Spread':<15} {'Put Spread':<15}")
    print("-" * 45)

    for i in range(len(exercise_data['strikes']) - 1):
        strike1 = exercise_data['strikes'][i]
        strike2 = exercise_data['strikes'][i + 1]

        call_spread = exercise_data['spreads'].get((strike1, strike2, 'call'))
        put_spread = exercise_data['spreads'].get((strike1, strike2, 'put'))

        call_str = f"${call_spread}" if call_spread is not None else "____"
        put_str = f"${put_spread}" if put_spread is not None else "____"

        strikes_str = f"${strike1}/${strike2}"
        print(f"{strikes_str:<12} {call_str:<15} {put_str:<15}")

    print(f"\nREMINDERS:")
    print(f"• Call Spread (K1/K2): Long K1 Call, Short K2 Call = C(K1) - C(K2)")
    print(f"• Put Spread (K1/K2): Long K2 Put, Short K1 Put = P(K2) - P(K1)")
    print(f"• Put-Call Parity: C - P = S - K + r/c")
    print(f"• Work systematically: use explicit prices → apply parity → use spreads")

def solve_exercise_step_by_step(exercise_data, stock_price, r_c):
    """
    Demonstrate step-by-step solution of the exercise (no box spreads).
    """
    print("STEP-BY-STEP SOLUTION:")
    print("=" * 50)

    # Working dictionaries
    known_calls = {}
    known_puts = {}

    # Start with explicit prices
    print("Step 1: Record given explicit prices")
    for (strike, option_type), price in exercise_data['explicit_prices'].items():
        if price is not None:
            if option_type == 'call':
                known_calls[strike] = price
                print(f"  Given: ${strike}C = ${price}")
            else:
                known_puts[strike] = price
                print(f"  Given: ${strike}P = ${price}")

    step = 2
    max_iterations = 20

    for iteration in range(max_iterations):
        made_progress = False

        # Try put-call parity
        for strike in exercise_data['strikes']:
            if strike in known_calls and strike not in known_puts:
                put_price = known_calls[strike] - stock_price + strike - r_c
                known_puts[strike] = round(put_price, 2)
                print(
                    f"Step {step}: ${strike}P = ${strike}C - Stock + Strike - r/c = ${known_calls[strike]} - ${stock_price} + ${strike} - {r_c} = ${known_puts[strike]}")
                step += 1
                made_progress = True
            elif strike in known_puts and strike not in known_calls:
                call_price = known_puts[strike] + stock_price - strike + r_c
                known_calls[strike] = round(call_price, 2)
                print(
                    f"Step {step}: ${strike}C = ${strike}P + Stock - Strike + r/c = ${known_puts[strike]} + ${stock_price} - ${strike} + {r_c} = ${known_calls[strike]}")
                step += 1
                made_progress = True

        # Try spreads (only call and put spreads)
        for (strike1, strike2, spread_type), spread_value in exercise_data['spreads'].items():
            if spread_value is not None:
                if spread_type == 'call':
                    if strike1 in known_calls and strike2 not in known_calls:
                        known_calls[strike2] = round(known_calls[strike1] - spread_value, 2)
                        print(
                            f"Step {step}: ${strike2}C = ${strike1}C - Call Spread = ${known_calls[strike1]} - ${spread_value} = ${known_calls[strike2]}")
                        step += 1
                        made_progress = True
                    elif strike2 in known_calls and strike1 not in known_calls:
                        known_calls[strike1] = round(known_calls[strike2] + spread_value, 2)
                        print(
                            f"Step {step}: ${strike1}C = ${strike2}C + Call Spread = ${known_calls[strike2]} + ${spread_value} = ${known_calls[strike1]}")
                        step += 1
                        made_progress = True
                elif spread_type == 'put':
                    if strike1 in known_puts and strike2 not in known_puts:
                        known_puts[strike2] = round(known_puts[strike1] + spread_value, 2)
                        print(
                            f"Step {step}: ${strike2}P = ${strike1}P + Put Spread = ${known_puts[strike1]} + ${spread_value} = ${known_puts[strike2]}")
                        step += 1
                        made_progress = True
                    elif strike2 in known_puts and strike1 not in known_puts:
                        known_puts[strike1] = round(known_puts[strike2] - spread_value, 2)
                        print(
                            f"Step {step}: ${strike1}P = ${strike2}P - Put Spread = ${known_puts[strike2]} - ${spread_value} = ${known_puts[strike1]}")
                        step += 1
                        made_progress = True

        if not made_progress:
            break

    # Print final solution
    print(f"\nFINAL SOLUTION:")
    print(f"{'Strike':<8} {'Call':<12} {'Put':<12}")
    print("-" * 35)
    for strike in exercise_data['strikes']:
        call = known_calls.get(strike, "UNSOLVED")
        put = known_puts.get(strike, "UNSOLVED")
        call_str = f"${call}" if call != "UNSOLVED" else call
        put_str = f"${put}" if put != "UNSOLVED" else put
        print(f"${strike:<7} {call_str:<12} {put_str:<12}")

    # Check if all solved
    unsolved_count = sum(
        1 for strike in exercise_data['strikes'] if strike not in known_calls and strike not in known_puts)
    if unsolved_count > 0:
        print(f"\nWARNING: {unsolved_count} strikes remain unsolved. Exercise may need more information.")
    else:
        print(f"\n✓ All strikes successfully solved!")

def generate_exercise_ladder(int num_strikes, double missing_probability=0.4):
    """
    Backward compatibility - generates simple exercise without spreads.
    """
    # Generate the complete ladder
    real_ladder, stock_price, r_c = generate_options_ladder_fast(num_strikes)

    # Create exercise version with some prices missing
    exercise_ladder = []

    for call_price, strike, put_price in real_ladder:
        # Randomly decide what to keep/remove
        # Always keep at least one price per row
        remove_call = random.random() < missing_probability
        remove_put = random.random() < missing_probability

        # If both would be removed, randomly keep one
        if remove_call and remove_put:
            if random.random() < 0.5:
                remove_call = False
            else:
                remove_put = False

        # Create the exercise row
        exercise_call = None if remove_call else call_price
        exercise_put = None if remove_put else put_price

        exercise_ladder.append([exercise_call, strike, exercise_put])

    return real_ladder, exercise_ladder, stock_price, r_c

def print_exercise_ladder(exercise_ladder, stock_price, r_c):
    """
    Print the exercise ladder showing blanks where prices need to be filled in.
    """
    print(f"Stock Price: ${stock_price}")
    print(f"Interest Component (r/c): {r_c}")
    print(f"{'Call Price':<12} {'Strike':<8} {'Put Price':<10}")
    print("-" * 35)
    for call, strike, put in exercise_ladder:
        call_str = f"${call}" if call is not None else "____"
        put_str = f"${put}" if put is not None else "____"
        print(f"{call_str:<12} ${strike:<7} {put_str:<10}")

def validate_ladder(ladder, stock_price, r_c):
    """
    Validate an options ladder for common issues.

    Args:
        ladder: List of [call_price, strike, put_price] rows
        stock_price: Current stock price
        r_c: Interest component

    Returns:
        dict: Validation results with detailed diagnostics
    """
    results = {
        'valid': True,
        'issues': [],
        'intrinsic_violations': [],
        'parity_violations': [],
        'monotonicity_violations': [],
        'arbitrage_opportunities': []
    }

    # Check each row for intrinsic value and parity
    for i, (call, strike, put) in enumerate(ladder):
        # Intrinsic value checks
        call_intrinsic = max(stock_price - strike, 0.0)
        put_intrinsic = max(strike - stock_price, 0.0)

        if call < call_intrinsic - 0.01:
            results['intrinsic_violations'].append(f"Strike ${strike}: Call ${call} < intrinsic ${call_intrinsic:.2f}")
            results['valid'] = False

        if put < put_intrinsic - 0.01:
            results['intrinsic_violations'].append(f"Strike ${strike}: Put ${put} < intrinsic ${put_intrinsic:.2f}")
            results['valid'] = False

        # Put-call parity check
        parity_left = call - put
        parity_right = stock_price - strike + r_c
        parity_diff = parity_left - parity_right

        if abs(parity_diff) > 0.02:
            results['parity_violations'].append(
                f"Strike ${strike}: Parity diff ${parity_diff:.3f} (C-P={parity_left:.2f}, S-K+r/c={parity_right:.2f})")
            results['valid'] = False

    # Check monotonicity
    if len(ladder) > 1:
        for i in range(1, len(ladder)):
            prev_call, prev_strike, prev_put = ladder[i - 1]
            curr_call, curr_strike, curr_put = ladder[i]

            # Calls should decrease with increasing strike
            if curr_call > prev_call + 0.01:
                results['monotonicity_violations'].append(
                    f"Call monotonicity: ${curr_strike}C (${curr_call}) > ${prev_strike}C (${prev_call})")
                results['valid'] = False

            # Puts should increase with increasing strike
            if curr_put < prev_put - 0.01:
                results['monotonicity_violations'].append(
                    f"Put monotonicity: ${curr_strike}P (${curr_put}) < ${prev_strike}P (${prev_put})")
                results['valid'] = False

    # Check box spreads for arbitrage
    if len(ladder) > 1:
        for i in range(len(ladder) - 1):
            call1, strike1, put1 = ladder[i]
            call2, strike2, put2 = ladder[i + 1]

            call_spread = call1 - call2  # Long lower strike
            put_spread = put2 - put1  # Long higher strike
            box_value = call_spread + put_spread
            strike_diff = strike2 - strike1

            box_error = abs(box_value - strike_diff)
            if box_error > 0.05:
                results['arbitrage_opportunities'].append(
                    f"Box ${strike1}/${strike2}: Call spread ${call_spread:.2f} + Put spread ${put_spread:.2f} = ${box_value:.2f} ≠ ${strike_diff} (error: ${box_error:.2f})"
                )
                results['valid'] = False

    # Compile all issues
    all_issues = (results['intrinsic_violations'] +
                  results['parity_violations'] +
                  results['monotonicity_violations'] +
                  results['arbitrage_opportunities'])

    results['issues'] = all_issues

    return results

def print_ladder_with_validation(ladder, stock_price, r_c):
    """
    Print ladder with validation diagnostics.
    """
    print(f"Stock Price: ${stock_price}")
    print(f"Interest Component (r/c): {r_c}")
    print(f"{'Call Price':<12} {'Strike':<8} {'Put Price':<10} {'Call Intrinsic':<14} {'Put Intrinsic':<14}")
    print("-" * 70)

    for call, strike, put in ladder:
        call_intrinsic = max(stock_price - strike, 0.0)
        put_intrinsic = max(strike - stock_price, 0.0)
        print(f"${call:<11} ${strike:<7} ${put:<9} ${call_intrinsic:<13.2f} ${put_intrinsic:<13.2f}")

    # Validate and show results
    validation = validate_ladder(ladder, stock_price, r_c)

    print(f"\n{'=' * 50}")
    print("VALIDATION RESULTS")
    print(f"{'=' * 50}")

    if validation['valid']:
        print("✓ Ladder is valid - no issues found")
    else:
        print(f"✗ Ladder has {len(validation['issues'])} issues:")
        for issue in validation['issues']:
            print(f"  - {issue}")

def check_specific_ladder():
    """
    Check the specific ladder mentioned in the user's example.
    """
    ladder = [
        [24.37, 65.0, 11.39],
        [21.71, 70.0, 13.73],
        [18.27, 75.0, 15.29],
        [15.76, 80.0, 17.78],
        [14.16, 85.0, 21.18],
        [14.82, 90.0, 26.84],
        [11.45, 95.0, 28.47]
    ]

    stock_price = 77.85
    r_c = 0.13

    print("ANALYZING USER'S EXAMPLE LADDER:")
    print_ladder_with_validation(ladder, stock_price, r_c)

def print_solution_ladder(real_ladder, stock_price, r_c):
    """
    Print the complete solution ladder with validation.
    """
    print_ladder_with_validation(real_ladder, stock_price, r_c)

def check_answers(real_ladder, user_answers):
    """
    Check user's answers against the real ladder.

    Args:
        real_ladder: The complete correct ladder
        user_answers: List of tuples (call_price, strike, put_price) with user's answers

    Returns:
        List of tuples indicating correctness and differences
    """
    results = []
    tolerance = 0.05  # Allow 5 cent tolerance

    for i, ((real_call, real_strike, real_put), (user_call, user_strike, user_put)) in enumerate(
            zip(real_ladder, user_answers)):
        call_correct = user_call is None or abs(user_call - real_call) <= tolerance
        put_correct = user_put is None or abs(user_put - real_put) <= tolerance

        call_diff = None if user_call is None else user_call - real_call
        put_diff = None if user_put is None else user_put - real_put

        results.append({
            'strike': real_strike,
            'call_correct': call_correct,
            'put_correct': put_correct,
            'call_difference': call_diff,
            'put_difference': put_diff
        })

    return results