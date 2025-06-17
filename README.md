### current known issues:
- call (put) spread prices are not monotonically decreasing (increasing) with increasing K / strike

# Options Trading Training App

A comprehensive web-based training application for practising options ladder exercises with put-call parity and spread calculations. Perfect for finance students, trading professionals, and anyone looking to sharpen their derivatives knowledge.

## 🚀 Features

### **Two Exercise Modes**
- **Simple Mode**: Basic put-call parity exercises with one price given per strike
- **Advanced Mode**: Complex exercises using spreads, put-call parity, and strategic relationships

### **Interactive Interface**
- Clean, modern web interface with responsive design
- Built-in timer to track solving speed
- Immediate feedback with detailed scoring and explanations
- Customisable difficulty (3-10 strikes)

### **High-Performance Backend**
- Optimised Cython implementation for lightning-fast ladder generation
- Automatic validation ensuring realistic, arbitrage-free ladders
- Smart exercise generation with guaranteed solvability

### **Educational Focus**
- Comprehensive put-call parity practice
- Spread relationship training (call spreads, put spreads)
- Real-world pricing scenarios with proper validation
- Detailed feedback showing exactly where you went wrong

## 📋 Requirements

- **Python 3.8+** (tested on 3.9-3.11)
- **C Compiler** for Cython compilation:
  - **Windows**: Visual Studio Build Tools or Visual Studio Community
  - **macOS**: Xcode Command Line Tools (`xcode-select --install`)
  - **Linux**: GCC (`sudo apt-get install build-essential`)

## ⚡ Quick Start

### **Windows Users (Recommended)**
1. **Clone the repository**:
   ```bash
   git clone https://github.com/yourusername/trainingApp.git
   cd trainingApp
   ```

2. **Run the setup script**:
   ```bash
   setup_and_run.bat
   ```
   
   This script will automatically:
   - Check Python installation
   - Create virtual environment
   - Install all dependencies
   - Compile the Cython module
   - Launch the application

3. **Open your browser** to `http://127.0.0.1:5001`

### **Manual Installation (All Platforms)**

1. **Clone and navigate**:
   ```bash
   git clone https://github.com/yourusername/trainingApp.git
   cd trainingApp
   ```

2. **Create virtual environment**:
   ```bash
   python -m venv .venv
   
   # Windows
   .venv\Scripts\activate
   
   # macOS/Linux  
   source .venv/bin/activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Compile Cython module**:
   ```bash
   python setup.py build_ext --inplace
   ```

5. **Launch application**:
   ```bash
   python app.py
   ```

6. **Visit** `http://127.0.0.1:5001` in your browser

## 🎯 How to Use

### **Getting Started**
1. **Choose Exercise Type**:
   - **Simple**: Great for beginners learning put-call parity
   - **Advanced**: For experienced users wanting spread practice

2. **Select Number of Strikes** (3-10 based on difficulty preference)

3. **Generate Exercise** and start the timer

4. **Fill in Missing Prices** using:
   - Put-call parity: `Call - Put = Stock - Strike + r/c`
   - Spread relationships for advanced mode
   - Given explicit prices and spreads

5. **Submit Answers** for immediate feedback and scoring

### **Simple Mode Strategy**
- Start with strikes where you have one price given
- Apply put-call parity to find the missing price
- Work systematically through all strikes
- Double-check using the parity relationship

### **Advanced Mode Strategy**
- Use explicit prices as anchor points
- Apply put-call parity to get companion prices
- Use spreads to connect between strikes:
  - **Call Spread (K1/K2)**: C(K1) - C(K2)
  - **Put Spread (K1/K2)**: P(K2) - P(K1)
- Work iteratively until all prices are solved

## 🔧 Troubleshooting

### **Compilation Issues**

**Windows: "Microsoft Visual C++ 14.0 is required"**
```bash
# Install Visual Studio Build Tools
# Or use conda environment
conda install cython numpy
python setup.py build_ext --inplace
```

**macOS: "gcc not found"**
```bash
# Install Xcode command line tools
xcode-select --install
```

**Linux: "Python.h not found"**
```bash
# Install Python development headers
sudo apt-get install python3-dev
```

### **Runtime Issues**

**"ModuleNotFoundError: No module named 'options_ladder_fast'"**
- Ensure Cython compilation completed successfully
- Check for `.so` (Linux/Mac) or `.pyd` (Windows) files in project directory
- Recompile: `python setup.py build_ext --inplace --force`

**"Exercises not generating"**
- Check browser console (F12) for JavaScript errors
- Verify Flask backend is running (check terminal output)
- Try hard refresh: `Ctrl+Shift+R` (Windows) or `Cmd+Shift+R` (Mac)

## 🏗️ Project Structure

```
trainingApp/
├── app.py                          # Flask backend server
├── templates/
│   └── index.html                  # Main HTML interface  
├── static/
│   ├── css/
│   │   └── style.css              # Modern responsive styling
│   └── js/
│       └── app.js                 # Frontend JavaScript logic
├── options_ladder_fast.pyx         # Optimised Cython implementation
├── setup.py                       # Cython compilation configuration
├── requirements.txt               # Python dependencies
├── setup_and_run.bat             # Windows setup script
└── README.md                      # This file
```

## 🎨 Customisation

### **Modify Exercise Difficulty**
Edit `missing_probability` in `app.py`:
```python
# Line ~65 for simple mode
missing_probability=0.4  # 40% of prices hidden

# Line ~45 for advanced mode  
missing_probability=0.3  # 30% of prices hidden
```

### **Adjust Styling**
Modify `static/css/style.css` for different colours, fonts, or layouts.

### **Add Features**
Extend `static/js/app.js` for additional functionality like hints or detailed explanations.

## ⚡ Performance

- **Exercise Generation**: <100ms thanks to optimised Cython backend
- **Interface**: Fully responsive, works on mobile devices
- **Validation**: Comprehensive checks ensure realistic, arbitrage-free ladders
- **Scalability**: Handles complex exercises with 10+ strikes efficiently

## 🤝 Contributing

1. **Fork the repository**
2. **Create feature branch**: `git checkout -b feature/amazing-feature`
3. **Commit changes**: `git commit -m 'Add amazing feature'`
4. **Push to branch**: `git push origin feature/amazing-feature`
5. **Open Pull Request**

### **Development Guidelines**
- Follow Python PEP 8 style guidelines
- Add docstrings for new functions
- Test both simple and advanced modes
- Ensure cross-platform compatibility

## 📚 Educational Background

This application is designed for:
- **Finance Students** learning derivatives pricing
- **Trading Professionals** practising mental maths
- **Risk Managers** understanding option relationships
- **Quantitative Analysts** validating pricing models

### **Key Concepts Covered**
- **Put-Call Parity**: Fundamental arbitrage relationship
- **Intrinsic Value**: Minimum option value at expiration
- **Time Value**: Option premium above intrinsic value
- **Spread Trading**: Risk management through combination strategies
- **Arbitrage Detection**: Identifying mispriced option combinations

## 🙏 Acknowledgements

- Built with Flask (Python web framework)
- Cython for high-performance numerical computing
- Tailwind CSS for modern, responsive design
- Inspired by real-world options trading practices

## 📞 Support

- **Issues**: Please use GitHub Issues for bug reports and feature requests
- **Discussions**: Use GitHub Discussions for questions and general chat
- **Documentation**: Check this README and inline code comments

---

**Happy Trading! 📈**

*Master the fundamentals of options pricing through hands-on practice.*
