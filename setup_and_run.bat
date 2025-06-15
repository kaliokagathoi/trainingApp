@echo off
echo ================================================================
echo   Options Trading Training App - Setup and Launch Script
echo ================================================================
echo.

REM Change to script directory
cd /d "%~dp0"

REM Check if Python is installed
echo [1/6] Checking Python installation...
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python 3.8+ from https://python.org
    echo Make sure to tick "Add Python to PATH" during installation
    pause
    exit /b 1
)
echo ✓ Python found

REM Check if virtual environment exists
echo.
echo [2/6] Setting up virtual environment...
if not exist ".venv" (
    echo Creating new virtual environment...
    python -m venv .venv
    if errorlevel 1 (
        echo ERROR: Failed to create virtual environment
        pause
        exit /b 1
    )
    echo ✓ Virtual environment created
) else (
    echo ✓ Virtual environment already exists
)

REM Activate virtual environment
echo.
echo [3/6] Activating virtual environment...
call .venv\Scripts\activate.bat
if errorlevel 1 (
    echo ERROR: Failed to activate virtual environment
    pause
    exit /b 1
)
echo ✓ Virtual environment activated

REM Upgrade pip
echo.
echo [4/6] Upgrading pip...
python -m pip install --upgrade pip

REM Install requirements
echo.
echo [5/6] Installing Python dependencies...
if exist "requirements.txt" (
    pip install -r requirements.txt
    if errorlevel 1 (
        echo ERROR: Failed to install requirements
        pause
        exit /b 1
    )
    echo ✓ Dependencies installed
) else (
    echo WARNING: requirements.txt not found, installing manually...
    pip install Flask Cython numpy setuptools wheel
)

REM Clean previous builds
echo.
echo [6/6] Compiling Cython module...
echo Cleaning previous builds...
if exist "build" rmdir /s /q build
if exist "options_ladder_fast.c" del options_ladder_fast.c
for %%f in (*.so *.pyd) do del "%%f" 2>nul

REM Compile Cython module
echo Compiling Cython extension...
python setup.py build_ext --inplace
if errorlevel 1 (
    echo ERROR: Failed to compile Cython module
    echo Make sure you have:
    echo - Visual Studio Build Tools (Windows)
    echo - All dependencies installed correctly
    pause
    exit /b 1
)
echo ✓ Cython module compiled successfully

REM Check if compilation produced expected files
echo Checking compilation results...
set "found_module="
for %%f in (*.so *.pyd) do set "found_module=%%f"
if not defined found_module (
    echo WARNING: No compiled module found (.so or .pyd file)
    echo The app may not work correctly
)

echo.
echo ================================================================
echo   Setup Complete! Starting the application...
echo ================================================================
echo.
echo The app will be available at: http://127.0.0.1:5000
echo Press Ctrl+C to stop the server
echo.

REM Start Flask app
python app.py

REM If we get here, the app has stopped
echo.
echo ================================================================
echo   Application stopped
echo ================================================================
pause