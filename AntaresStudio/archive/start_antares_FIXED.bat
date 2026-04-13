@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ===============================================================
echo  ANTARES - Studio Launcher (Windows)
echo ===============================================================

REM ---- Python 3.11 hard pin (sende dogru path) ----
set "PY311=C:\Users\MUHAMMET\AppData\Local\Programs\Python\Python311\python.exe"
if not exist "%PY311%" goto ERR_NO_PY

REM ---- flags (no delayed expansion; safe parsing) ----
set "DO_DIAG=0"
set "EXTRA_OPEN3D=0"
set "EXTRA_REMBG_CPU=0"
set "EXTRA_REMBG_GPU=0"

:ARG_LOOP
if "%~1"=="" goto ARG_DONE
if /I "%~1"=="--diag" set "DO_DIAG=1"
if /I "%~1"=="--open3d" set "EXTRA_OPEN3D=1"
if /I "%~1"=="--rembg-cpu" set "EXTRA_REMBG_CPU=1"
if /I "%~1"=="--rembg-gpu" set "EXTRA_REMBG_GPU=1"
shift
goto ARG_LOOP
:ARG_DONE

REM ---- venv create ----
if exist "antares_env\Scripts\python.exe" goto VENV_OK
echo [*] Creating virtual environment (Python 3.11)...
"%PY311%" -m venv antares_env
if errorlevel 1 goto ERR_VENV
:VENV_OK

REM ---- activate ----
call "antares_env\Scripts\activate.bat"
if errorlevel 1 goto ERR_ACT

echo [*] Upgrading pip/setuptools/wheel...
python -m pip install -U pip setuptools wheel
if errorlevel 1 goto ERR_PIP

echo [*] Installing BASE requirements (wheel-only)...
python -m pip install --only-binary=:all: -r requirements.txt
if errorlevel 1 goto ERR_REQ

if "%EXTRA_OPEN3D%"=="1" call :INSTALL_OPEN3D
if "%EXTRA_REMBG_CPU%"=="1" call :INSTALL_REMBG_CPU
if "%EXTRA_REMBG_GPU%"=="1" call :INSTALL_REMBG_GPU

if "%DO_DIAG%"=="1" goto RUN_DIAG

echo.
echo [*] Starting application...
echo.
python antares_studio_final.py
goto END

:RUN_DIAG
echo.
echo [*] Running diagnostics...
echo.
python test_system.py
goto END

:INSTALL_OPEN3D
if not exist "requirements_open3d.txt" (
  echo [WARN] requirements_open3d.txt bulunamadi.
  goto :eof
)
echo [*] Installing Open3D extras...
python -m pip install --only-binary=:all: -r requirements_open3d.txt
if errorlevel 1 (
  echo [WARN] Open3D kurulumu basarisiz (opsiyonel).
)
goto :eof

:INSTALL_REMBG_CPU
if not exist "requirements_rembg_cpu.txt" (
  echo [WARN] requirements_rembg_cpu.txt bulunamadi.
  goto :eof
)
echo [*] Installing rembg CPU extras...
python -m pip install -r requirements_rembg_cpu.txt
if errorlevel 1 (
  echo [WARN] rembg CPU kurulumu basarisiz (opsiyonel).
)
goto :eof

:INSTALL_REMBG_GPU
if not exist "requirements_rembg_gpu.txt" (
  echo [WARN] requirements_rembg_gpu.txt bulunamadi.
  goto :eof
)
echo [*] Installing rembg GPU extras...
python -m pip install -r requirements_rembg_gpu.txt
if errorlevel 1 (
  echo [WARN] rembg GPU kurulumu basarisiz (opsiyonel).
)
goto :eof

:ERR_NO_PY
echo [ERROR] Python 3.11 bulunamadi:
echo         %PY311%
echo Python 3.11 (64-bit) kur ve tekrar dene.
goto FAIL

:ERR_VENV
echo [ERROR] Venv olusturma basarisiz.
goto FAIL

:ERR_ACT
echo [ERROR] Venv activate basarisiz.
goto FAIL

:ERR_PIP
echo [ERROR] pip upgrade basarisiz.
goto FAIL

:ERR_REQ
echo [ERROR] requirements kurulumu basarisiz.
goto FAIL

:FAIL
echo.
pause
exit /b 1

:END
echo.
pause
endlocal
