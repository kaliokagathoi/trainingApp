import numpy as np
import random
from scipy.stats import norm


def generate_options_ladder(num_strikes):
    """
    Generate an options ladder with call and put prices.

    Args:
        num_strikes (int): Number of different strike prices in the ladder

    Returns:
        tuple: (ladder, stock_price, r_c, params) where ladder is a list of [call_price, strike, put_price, parity_check],
               stock_price is the randomly generated underlying price, r_c is the interest component,
               and params is a dict with the Black-Scholes parameters used
    """

    # Generate random stock price between 5 and 100
    stock_price = random.uniform(5, 100)

    # Determine strike spacing based on stock price (multiples of 2 or 5)
    if stock_price < 10:
        spacing = random.choice([1, 2])
    elif stock_price < 25:
        spacing = 5
    elif stock_price < 50:
        spacing = 5
    else:
        spacing = random.choice([5, 10])

    # Find a good center strike (round number close to stock price)
    center_strike = round(stock_price / spacing) * spacing

    # Create strikes centered around the center strike
    center_index = num_strikes // 2
    strikes = []
    for i in range(num_strikes):
        strike = center_strike + (i - center_index) * spacing
        strikes.append(max(strike, spacing))  # Ensure positive strikes, minimum is one spacing unit

    strikes.sort()  # Ensure ascending order for proper option pricing

    # Generate reasonable Black-Scholes parameters
    r = random.uniform(0.02, 0.06)  # Risk-free rate (2-6% annually)
    T = random.uniform(0.2, 2)  # Time to expiration (10 weeks to 2 years)
    base_sigma = random.uniform(0.15, 0.40)  # Base volatility (15-40% annually)

    # Generate random interest component (same for all strikes)
    r_c = random.uniform(0.1, 2)  # Random positive interest component between 0.1 and 2
    r_c = round(r_c, 2)

    # Generate the options ladder
    ladder = []

    for K in strikes:
        # Create volatility smile/skew - higher vol for OTM options
        moneyness = K / stock_price  # Strike/Spot ratio

        # Volatility skew: higher vol for lower strikes (OTM puts) and higher strikes (OTM calls)
        if moneyness < 0.95:  # Deep OTM puts (low strikes)
            vol_adjustment = random.uniform(0.05, 0.15)
        elif moneyness > 1.05:  # Deep OTM calls (high strikes)
            vol_adjustment = random.uniform(0.03, 0.10)
        elif moneyness < 0.98 or moneyness > 1.02:  # Slightly OTM
            vol_adjustment = random.uniform(0.02, 0.06)
        else:  # ATM
            vol_adjustment = random.uniform(-0.02, 0.02)

        sigma = base_sigma + vol_adjustment
        sigma = max(sigma, 0.10)  # Minimum 10% vol

        # Black-Scholes call option pricing with strike-specific volatility
        d1 = (np.log(stock_price / K) + (r + 0.5 * sigma ** 2) * T) / (sigma * np.sqrt(T))
        d2 = d1 - sigma * np.sqrt(T)

        # Call option price
        call_price = stock_price * norm.cdf(d1) - K * np.exp(-r * T) * norm.cdf(d2)
        # Ensure call is at least intrinsic value
        call_price = max(call_price, max(stock_price - K, 0))
        # Round call price to 2 decimal places
        call_price = round(call_price, 2)

        # Put option price using put-call parity: C - P = S - K + r/c
        # Therefore: P = C - S + K - r/c
        put_price = call_price - stock_price + K - r_c

        # Round put price to 2dp
        put_price = round(put_price, 2)

        # Check put-call parity with 2dp figures: C - P = S - K + r/c
        parity_left = call_price - put_price
        parity_right = stock_price - K + r_c
        parity_check = round(parity_left - parity_right, 4)  # Difference (should be ~0)

        ladder.append([call_price, K, put_price, parity_check])

    params = {
        'risk_free_rate': round(r, 2),
        'time_to_expiry': round(T, 2),
        'volatility': round(sigma, 2)
    }

    return ladder, round(stock_price, 2), r_c, params


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


# Example usage
if __name__ == "__main__":
    # Generate a 3-strike ladder
    ladder, stock_price, r_c, params = generate_options_ladder(3)
    print_ladder(ladder, stock_price, r_c, params)

    print("\n" + "=" * 40 + "\n")

    # Generate a 4-strike ladder
    ladder2, stock_price2, r_c2, params2 = generate_options_ladder(4)
    print_ladder(ladder2, stock_price2, r_c2, params2)