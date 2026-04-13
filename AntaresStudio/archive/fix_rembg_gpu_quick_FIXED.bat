@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "VENV_DIR=antares_env"

echo ===============================================================
echo  rembg GPU Quick Setup (ONNX Runtime GPU)
echo ===============================================================
echo.

REM Use existing venv created by start_antares or create one
set "PY_CMD="
where py >nul 2>&1
if %errorlevel%==0 set "PY_CMD=py -3"
if "%PY_CMD%"=="" (
  where python >nul 2>&1
  if %errorlevel%==0 set "PY_CMD=python"
)
if "%PY_CMD%"=="" (
  echo [ERROR] Python not found.
  pause
  exit /b 1
)

if not exist "%VENV_DIR%\Scripts\python.exe" (
  echo [*] Creating virtual environment: %VENV_DIR%
  %PY_CMD% -m venv "%VENV_DIR%"
  if not %errorlevel%==0 (
    echo [ERROR] Failed to create venv.
    pause
    exit /b 1
  )
)

call "%VENV_DIR%\Scripts\activate.bat"
if not %errorlevel%==0 (
  echo [ERROR] Failed to activate venv.
  pause
  exit /b 1
)

python -m pip install --upgrade pip setuptools wheel >nul 2>&1

echo [*] Installing rembg + Pillow + onnxruntime-gpu ...
pip install --upgrade rembg Pillow onnxruntime-gpu
if not %errorlevel%==0 (
  echo [ERROR] Install failed.
  pause
  exit /b 1
)

echo.
echo [*] Running GPU checker...
python fix_rembg_gpu_FIXED.py

echo.
pause
endlocal
