class OptionsTrainingApp {
    constructor() {
        this.currentExercise = null;
        this.timer = {
            start: null,
            interval: null,
            running: false
        };

        this.initializeEventListeners();
    }

    initializeEventListeners() {
        document.getElementById('generate-btn').addEventListener('click', () => this.generateExercise());
        document.getElementById('submit-btn').addEventListener('click', () => this.submitAnswers());
        document.getElementById('new-exercise-btn').addEventListener('click', () => this.resetToControls());
        document.getElementById('retry-btn').addEventListener('click', () => this.generateExercise());
    }

    async generateExercise() {
        try {
            this.showLoading();

            const useSpreadString = document.getElementById('use-spreads').value;
            const useSpreads = useSpreadString === 'true';
            const numStrikes = parseInt(document.getElementById('num-strikes').value);

            console.log(`Generating exercise: spreads=${useSpreads}, strikes=${numStrikes}`);

            const response = await fetch('/generate_ladder', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    use_spreads: useSpreads,
                    num_strikes: numStrikes
                })
            });

            const data = await response.json();
            console.log('Received data:', data);

            if (data.success) {
                this.currentExercise = data;
                this.displayExercise(data);
                this.startTimer();
            } else {
                this.showError(data.error);
            }
        } catch (error) {
            console.error('Generate exercise error:', error);
            this.showError(`Network error: ${error.message}`);
        }
    }

    displayExercise(data) {
        this.hideAllSections();

        // Show market info
        const marketInfo = document.getElementById('market-info');
        marketInfo.innerHTML = `
            <h3>Market Information</h3>
            <p><strong>Stock Price:</strong> $${data.stock_price}</p>
            <p><strong>Interest Component (r/c):</strong> ${data.r_c}</p>
            <p><strong>Put-Call Parity:</strong> Call - Put = Stock - Strike + r/c</p>
        `;

        // Display exercise content
        const exerciseContent = document.getElementById('exercise-content');

        if (data.exercise_type === 'spreads') {
            this.displaySpreadsExercise(data, exerciseContent);
        } else {
            this.displaySimpleExercise(data, exerciseContent);
        }

        document.getElementById('exercise-section').style.display = 'block';
    }

    displaySimpleExercise(data, container) {
        const exerciseLadder = data.exercise_ladder;

        let html = `
            <h3>Complete the Options Ladder</h3>
            <p>Fill in the missing option prices. Use put-call parity to help solve.</p>
            
            <table class="exercise-table">
                <thead>
                    <tr>
                        <th>Call Price</th>
                        <th>Strike</th>
                        <th>Put Price</th>
                    </tr>
                </thead>
                <tbody>
        `;

        exerciseLadder.forEach((row, index) => {
            const [call, strike, put] = row;

            // Check if call price exists and is not null
            const callDisplay = (call !== null && call !== undefined) ?
                `<span class="given-price">$${call}</span>` :
                `<input type="number" class="price-input" data-type="call" data-strike="${strike}" step="0.01" placeholder="Enter price">`;

            // Check if put price exists and is not null
            const putDisplay = (put !== null && put !== undefined) ?
                `<span class="given-price">$${put}</span>` :
                `<input type="number" class="price-input" data-type="put" data-strike="${strike}" step="0.01" placeholder="Enter price">`;

            html += `
                <tr>
                    <td>${callDisplay}</td>
                    <td>$${strike}</td>
                    <td>${putDisplay}</td>
                </tr>
            `;
        });

        html += `
                </tbody>
            </table>
            
            <div class="reminders">
                <h4>Reminders:</h4>
                <ul>
                    <li>Put-Call Parity: C - P = S - K + r/c</li>
                    <li>Where C = Call price, P = Put price, S = Stock price, K = Strike price</li>
                    <li>Use the given prices and parity relationship to find missing values</li>
                </ul>
            </div>
        `;

        container.innerHTML = html;
    }

    displaySpreadsExercise(data, container) {
        const exerciseData = data.exercise_data;
        const strikes = exerciseData.strikes;

        console.log('Exercise data:', exerciseData);
        console.log('Available explicit price keys:', Object.keys(exerciseData.explicit_prices));
        console.log('Available spread keys:', Object.keys(exerciseData.spreads));
        console.log('Strikes:', strikes);

        let html = `
            <h3>Complete the Options Ladder Using Spreads</h3>
            <p>Use the given prices and spreads to complete the ladder. Apply put-call parity and spread relationships.</p>
            
            <table class="exercise-table">
                <thead>
                    <tr>
                        <th>Call Price</th>
                        <th>Strike</th>
                        <th>Put Price</th>
                    </tr>
                </thead>
                <tbody>
        `;

        strikes.forEach(strike => {
            // Find the correct keys by searching available keys
            const availableKeys = Object.keys(exerciseData.explicit_prices);

            // Try multiple key formats to match both integer and decimal formats
            const callKey = availableKeys.find(key =>
                key.includes('call') && (
                    key.startsWith(`${strike}_`) ||           // 85_call
                    key.startsWith(`${strike.toString()}_`) || // 85_call
                    key.startsWith(`${strike}.0_`) ||          // 85.0_call
                    key.startsWith(`${parseFloat(strike)}_`)   // 85.0_call
                )
            );
            const putKey = availableKeys.find(key =>
                key.includes('put') && (
                    key.startsWith(`${strike}_`) ||            // 85_put
                    key.startsWith(`${strike.toString()}_`) ||  // 85_put
                    key.startsWith(`${strike}.0_`) ||           // 85.0_put
                    key.startsWith(`${parseFloat(strike)}_`)    // 85.0_put
                )
            );

            const callPrice = callKey ? exerciseData.explicit_prices[callKey] : undefined;
            const putPrice = putKey ? exerciseData.explicit_prices[putKey] : undefined;

            console.log(`Strike ${strike}:`);
            console.log(`  Found callKey: ${callKey} -> ${callPrice}`);
            console.log(`  Found putKey: ${putKey} -> ${putPrice}`);

            // Check if prices exist and are not null/undefined
            const callDisplay = (callPrice !== null && callPrice !== undefined) ?
                `<span class="given-price">$${callPrice}</span>` :
                `<input type="number" class="price-input" data-type="call" data-strike="${strike}" step="0.01" placeholder="Enter price">`;

            const putDisplay = (putPrice !== null && putPrice !== undefined) ?
                `<span class="given-price">$${putPrice}</span>` :
                `<input type="number" class="price-input" data-type="put" data-strike="${strike}" step="0.01" placeholder="Enter price">`;

            html += `
                <tr>
                    <td>${callDisplay}</td>
                    <td>$${strike}</td>
                    <td>${putDisplay}</td>
                </tr>
            `;
        });

        html += `</tbody></table>`;

        // Add spreads information
        html += `
            <div class="spread-info">
                <h4>Given Spreads</h4>
                <table class="spreads-table">
                    <thead>
                        <tr>
                            <th>Strikes</th>
                            <th>Call Spread</th>
                            <th>Put Spread</th>
                        </tr>
                    </thead>
                    <tbody>
        `;

        const availableSpreadKeys = Object.keys(exerciseData.spreads);

        for (let i = 0; i < strikes.length - 1; i++) {
            const strike1 = strikes[i];
            const strike2 = strikes[i + 1];

            // Find spread keys by searching available keys
            const callSpreadKey = availableSpreadKeys.find(key =>
                key.includes('call') && (
                    key.startsWith(`${strike1}_${strike2}_`) ||                    // 85_90_call
                    key.startsWith(`${strike1.toString()}_${strike2.toString()}_`) || // 85_90_call
                    key.startsWith(`${strike1}.0_${strike2}.0_`) ||                // 85.0_90.0_call
                    key.startsWith(`${parseFloat(strike1)}_${parseFloat(strike2)}_`) // 85.0_90.0_call
                )
            );
            const putSpreadKey = availableSpreadKeys.find(key =>
                key.includes('put') && (
                    key.startsWith(`${strike1}_${strike2}_`) ||                     // 85_90_put
                    key.startsWith(`${strike1.toString()}_${strike2.toString()}_`) || // 85_90_put
                    key.startsWith(`${strike1}.0_${strike2}.0_`) ||                 // 85.0_90.0_put
                    key.startsWith(`${parseFloat(strike1)}_${parseFloat(strike2)}_`) // 85.0_90.0_put
                )
            );

            const callSpread = callSpreadKey ? exerciseData.spreads[callSpreadKey] : undefined;
            const putSpread = putSpreadKey ? exerciseData.spreads[putSpreadKey] : undefined;

            console.log(`Spread ${strike1}/${strike2}:`);
            console.log(`  Found callSpreadKey: ${callSpreadKey} -> ${callSpread}`);
            console.log(`  Found putSpreadKey: ${putSpreadKey} -> ${putSpread}`);

            // Check if spreads exist and are not null/undefined
            const callSpreadDisplay = (callSpread !== null && callSpread !== undefined) ?
                `$${callSpread}` : '____';
            const putSpreadDisplay = (putSpread !== null && putSpread !== undefined) ?
                `$${putSpread}` : '____';

            html += `
                <tr>
                    <td>$${strike1}/$${strike2}</td>
                    <td>${callSpreadDisplay}</td>
                    <td>${putSpreadDisplay}</td>
                </tr>
            `;
        }

        html += `
                    </tbody>
                </table>
            </div>
            
            <div class="reminders">
                <h4>Reminders:</h4>
                <ul>
                    <li>Put-Call Parity: C - P = S - K + r/c</li>
                    <li>Call Spread (K1/K2): Long K1 Call, Short K2 Call = C(K1) - C(K2)</li>
                    <li>Put Spread (K1/K2): Long K2 Put, Short K1 Put = P(K2) - P(K1)</li>
                    <li>Work systematically: use explicit prices → apply parity → use spreads</li>
                </ul>
            </div>
        `;

        container.innerHTML = html;
    }

    async submitAnswers() {
        try {
            const userAnswers = this.collectUserAnswers();
            this.stopTimer();

            const response = await fetch('/check_answers', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    real_ladder: this.currentExercise.real_ladder,
                    user_answers: userAnswers,
                    exercise_type: this.currentExercise.exercise_type
                })
            });

            const data = await response.json();

            if (data.success) {
                this.displayResults(data);
            } else {
                this.showError(data.error);
            }
        } catch (error) {
            this.showError(`Error submitting answers: ${error.message}`);
        }
    }

    collectUserAnswers() {
        const inputs = document.querySelectorAll('.price-input');
        const answers = [];

        if (this.currentExercise.exercise_type === 'spreads') {
            const strikes = this.currentExercise.exercise_data.strikes;

            strikes.forEach(strike => {
                const callInput = document.querySelector(`input[data-type="call"][data-strike="${strike}"]`);
                const putInput = document.querySelector(`input[data-type="put"][data-strike="${strike}"]`);

                // Convert empty strings to null
                const callValue = callInput && callInput.value.trim() !== '' ? callInput.value : null;
                const putValue = putInput && putInput.value.trim() !== '' ? putInput.value : null;

                answers.push({
                    strike: strike,
                    call: callValue,
                    put: putValue
                });
            });
        } else {
            // Simple mode
            const strikes = this.currentExercise.exercise_ladder.map(row => row[1]);

            strikes.forEach(strike => {
                const callInput = document.querySelector(`input[data-type="call"][data-strike="${strike}"]`);
                const putInput = document.querySelector(`input[data-type="put"][data-strike="${strike}"]`);

                // Convert empty strings to null
                const callValue = callInput && callInput.value.trim() !== '' ? callInput.value : null;
                const putValue = putInput && putInput.value.trim() !== '' ? putInput.value : null;

                answers.push({
                    strike: strike,
                    call: callValue,
                    put: putValue
                });
            });
        }

        console.log('Collected user answers:', answers);
        return answers;
    }

    displayResults(data) {
        this.hideAllSections();

        const resultsSection = document.getElementById('results-section');
        const scoreSummary = document.getElementById('score-summary');
        const detailedResults = document.getElementById('detailed-results');

        // Score summary
        const score = data.summary.score;
        const scoreColor = score >= 80 ? '#27ae60' : score >= 60 ? '#f39c12' : '#e74c3c';

        scoreSummary.innerHTML = `
            <h4>Your Score</h4>
            <div class="score" style="color: ${scoreColor}">${score}%</div>
            <p>${data.summary.total_correct} out of ${data.summary.total_attempted} correct</p>
            <p><strong>Time:</strong> ${this.getElapsedTime()}</p>
        `;

        // Detailed results
        let resultsTable = `
            <table class="results-table">
                <thead>
                    <tr>
                        <th>Strike</th>
                        <th>Call</th>
                        <th>Your Call</th>
                        <th>Call Result</th>
                        <th>Put</th>
                        <th>Your Put</th>
                        <th>Put Result</th>
                    </tr>
                </thead>
                <tbody>
        `;

        data.results.forEach(result => {
            const callResultClass = result.call_result.attempted ?
                (result.call_result.correct ? 'correct' : 'incorrect') : 'not-attempted';
            const putResultClass = result.put_result.attempted ?
                (result.put_result.correct ? 'correct' : 'incorrect') : 'not-attempted';

            const callResultText = result.call_result.attempted ?
                (result.call_result.correct ? '✓ Correct' : `✗ Off by $${Math.abs(result.call_result.difference)}`) : 'Not attempted';
            const putResultText = result.put_result.attempted ?
                (result.put_result.correct ? '✓ Correct' : `✗ Off by $${Math.abs(result.put_result.difference)}`) : 'Not attempted';

            // Get user answers
            const userCall = this.getUserAnswer('call', result.strike);
            const userPut = this.getUserAnswer('put', result.strike);

            resultsTable += `
                <tr>
                    <td>$${result.strike}</td>
                    <td>$${result.real_call}</td>
                    <td>${userCall || '-'}</td>
                    <td class="${callResultClass}">${callResultText}</td>
                    <td>$${result.real_put}</td>
                    <td>${userPut || '-'}</td>
                    <td class="${putResultClass}">${putResultText}</td>
                </tr>
            `;
        });

        resultsTable += '</tbody></table>';
        detailedResults.innerHTML = resultsTable;

        resultsSection.style.display = 'block';
    }

    getUserAnswer(type, strike) {
        const answers = this.collectUserAnswers();
        const answer = answers.find(a => a.strike === strike);
        return answer && answer[type] ? `$${answer[type]}` : null;
    }

    startTimer() {
        this.timer.start = Date.now();
        this.timer.running = true;

        document.getElementById('timer-section').style.display = 'block';

        this.timer.interval = setInterval(() => {
            this.updateTimerDisplay();
        }, 1000);
    }

    stopTimer() {
        if (this.timer.interval) {
            clearInterval(this.timer.interval);
            this.timer.running = false;
        }
    }

    updateTimerDisplay() {
        if (!this.timer.running) return;

        const elapsed = Date.now() - this.timer.start;
        const minutes = Math.floor(elapsed / 60000);
        const seconds = Math.floor((elapsed % 60000) / 1000);

        document.getElementById('timer-display').textContent =
            `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
    }

    getElapsedTime() {
        if (!this.timer.start) return 'N/A';

        const elapsed = Date.now() - this.timer.start;
        const minutes = Math.floor(elapsed / 60000);
        const seconds = Math.floor((elapsed % 60000) / 1000);

        return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
    }

    resetToControls() {
        this.hideAllSections();
        this.stopTimer();
        this.currentExercise = null;

        // Reset form values
        document.getElementById('use-spreads').value = 'false';
        document.getElementById('num-strikes').value = '5';
    }

    showLoading() {
        this.hideAllSections();
        document.getElementById('loading').style.display = 'block';
    }

    showError(message) {
        this.hideAllSections();
        document.getElementById('error-message').textContent = message;
        document.getElementById('error-section').style.display = 'block';
    }

    hideAllSections() {
        const sections = [
            'timer-section', 'exercise-section', 'results-section',
            'loading', 'error-section'
        ];

        sections.forEach(id => {
            document.getElementById(id).style.display = 'none';
        });
    }
}

// Initialize the app when the page loads
document.addEventListener('DOMContentLoaded', () => {
    new OptionsTrainingApp();
});