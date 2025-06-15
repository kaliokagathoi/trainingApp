from flask import Flask, render_template, request, jsonify
import json
import traceback

# Import the compiled Cython module
try:
    import options_ladder_fast

    CYTHON_AVAILABLE = True
    print("✓ Successfully imported options_ladder_fast")

    # Check what functions are available
    available_functions = [attr for attr in dir(options_ladder_fast) if not attr.startswith('_')]
    print(f"Available functions: {available_functions}")

    # Check for required functions
    required_functions = ['generate_options_ladder_fast', 'generate_exercise_ladder',
                          'generate_exercise_ladder_with_spreads']
    missing_functions = [func for func in required_functions if not hasattr(options_ladder_fast, func)]

    if missing_functions:
        print(f"⚠️  Missing functions: {missing_functions}")
        print("You may need to recompile the Cython module with the latest code.")

except ImportError as e:
    CYTHON_AVAILABLE = False
    print(f"✗ Failed to import options_ladder_fast: {e}")
    print("Please compile first with: python setup.py build_ext --inplace")

app = Flask(__name__)


@app.route('/')
def index():
    return render_template('index.html')


@app.route('/generate_ladder', methods=['POST'])
def generate_ladder():
    """Generate a new options ladder exercise"""
    try:
        if not CYTHON_AVAILABLE:
            return jsonify({
                'success': False,
                'error': 'Cython module not compiled. Run: python setup.py build_ext --inplace'
            })

        data = request.get_json()
        num_strikes = int(data.get('num_strikes', 5))
        use_spreads = data.get('use_spreads', False)

        if use_spreads:
            # Check if the function exists
            if not hasattr(options_ladder_fast, 'generate_exercise_ladder_with_spreads'):
                return jsonify({
                    'success': False,
                    'error': 'Function generate_exercise_ladder_with_spreads not found. Please recompile the Cython module with the latest code.'
                })

            # Generate exercise with spreads
            real_ladder, exercise_data, stock_price, r_c = options_ladder_fast.generate_exercise_ladder_with_spreads(
                num_strikes, missing_probability=0.3
            )

            # Convert the keys for JSON serialization and fix any None issues
            explicit_prices_json = {}
            for (strike, option_type), value in exercise_data['explicit_prices'].items():
                key = f"{strike}_{option_type}"
                explicit_prices_json[key] = value
                print(f"Converting explicit price: {strike}, {option_type} -> {key} = {value}")

            spreads_json = {}
            for (strike1, strike2, spread_type), value in exercise_data['spreads'].items():
                key = f"{strike1}_{strike2}_{spread_type}"
                spreads_json[key] = value
                print(f"Converting spread: {strike1}, {strike2}, {spread_type} -> {key} = {value}")

            # Debug logging
            print(f"Final explicit prices JSON: {explicit_prices_json}")
            print(f"Final spreads JSON: {spreads_json}")
            print(f"Strikes: {exercise_data['strikes']}")
            print(f"Strike types: {[type(s) for s in exercise_data['strikes']]}")

            response = {
                'success': True,
                'exercise_type': 'spreads',
                'real_ladder': real_ladder,
                'exercise_data': {
                    'explicit_prices': explicit_prices_json,
                    'spreads': spreads_json,
                    'strikes': exercise_data['strikes']
                },
                'stock_price': stock_price,
                'r_c': r_c
            }
        else:
            # Check if the function exists
            if not hasattr(options_ladder_fast, 'generate_exercise_ladder'):
                # Fallback to basic function if available
                if hasattr(options_ladder_fast, 'generate_options_ladder_fast'):
                    return jsonify({
                        'success': False,
                        'error': 'Function generate_exercise_ladder not found. Only basic ladder generation available. Please recompile with the latest code.'
                    })
                else:
                    return jsonify({
                        'success': False,
                        'error': 'Required functions not found. Please recompile the Cython module.'
                    })

            # Generate simple exercise without spreads
            real_ladder, exercise_ladder, stock_price, r_c = options_ladder_fast.generate_exercise_ladder(
                num_strikes, missing_probability=0.4
            )

            # Modify exercise_ladder to ensure only ONE price per row (either call OR put)
            # But don't create double None rows
            modified_exercise_ladder = []

            for call_price, strike, put_price in exercise_ladder:
                # Check if both are None (shouldn't happen but safety check)
                if call_price is None and put_price is None:
                    # If both are None, randomly assign one from the real ladder
                    real_row = next((row for row in real_ladder if row[1] == strike), None)
                    if real_row:
                        import random
                        if random.random() < 0.5:
                            modified_exercise_ladder.append([real_row[0], strike, None])  # Give call
                        else:
                            modified_exercise_ladder.append([None, strike, real_row[2]])  # Give put
                    else:
                        modified_exercise_ladder.append([call_price, strike, put_price])  # Fallback
                elif call_price is not None and put_price is not None:
                    # If both are present, randomly keep only one
                    import random
                    if random.random() < 0.5:
                        modified_exercise_ladder.append([call_price, strike, None])  # Keep call
                    else:
                        modified_exercise_ladder.append([None, strike, put_price])  # Keep put
                else:
                    # One is None, one is not None - this is what we want
                    modified_exercise_ladder.append([call_price, strike, put_price])

            # Debug logging
            print(f"Real ladder: {real_ladder}")
            print(f"Original exercise ladder: {exercise_ladder}")
            print(f"Modified exercise ladder (one price per row): {modified_exercise_ladder}")
            print(f"Stock price: {stock_price}, r_c: {r_c}")

            response = {
                'success': True,
                'exercise_type': 'simple',
                'real_ladder': real_ladder,
                'exercise_ladder': modified_exercise_ladder,
                'stock_price': stock_price,
                'r_c': r_c
            }

        return jsonify(response)

    except Exception as e:
        return jsonify({
            'success': False,
            'error': f"Error generating ladder: {str(e)}",
            'traceback': traceback.format_exc()
        })


@app.route('/check_answers', methods=['POST'])
def check_answers():
    """Check user's answers against the correct solution"""
    try:
        data = request.get_json()
        real_ladder = data['real_ladder']
        user_answers = data['user_answers']
        exercise_type = data.get('exercise_type', 'simple')

        results = []
        total_attempted = 0
        total_correct = 0
        tolerance = 0.05  # 5 cent tolerance

        for i, (real_row, user_row) in enumerate(zip(real_ladder, user_answers)):
            real_call, real_strike, real_put = real_row
            user_call, user_put = user_row.get('call'), user_row.get('put')

            call_result = {'attempted': False, 'correct': False, 'difference': None}
            put_result = {'attempted': False, 'correct': False, 'difference': None}

            # Check call option
            if user_call is not None and user_call != '':
                call_result['attempted'] = True
                total_attempted += 1
                user_call_float = float(user_call)
                difference = user_call_float - real_call
                call_result['difference'] = round(difference, 3)

                if abs(difference) <= tolerance:
                    call_result['correct'] = True
                    total_correct += 1

            # Check put option
            if user_put is not None and user_put != '':
                put_result['attempted'] = True
                total_attempted += 1
                user_put_float = float(user_put)
                difference = user_put_float - real_put
                put_result['difference'] = round(difference, 3)

                if abs(difference) <= tolerance:
                    put_result['correct'] = True
                    total_correct += 1

            results.append({
                'strike': real_strike,
                'real_call': real_call,
                'real_put': real_put,
                'call_result': call_result,
                'put_result': put_result
            })

        score = (total_correct / total_attempted * 100) if total_attempted > 0 else 0

        return jsonify({
            'success': True,
            'results': results,
            'summary': {
                'total_attempted': total_attempted,
                'total_correct': total_correct,
                'score': round(score, 1)
            }
        })

    except Exception as e:
        return jsonify({
            'success': False,
            'error': f"Error checking answers: {str(e)}",
            'traceback': traceback.format_exc()
        })


if __name__ == '__main__':
    app.run(debug=True, host='127.0.0.1', port=5001)