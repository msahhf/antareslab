@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM  AntaresStudio - BASE Build (sade)
REM  - Sadece requirements.txt
REM  - Tek dist: dist_base\
REM  - Tek exe: AntaresStudio.exe
REM ============================================================

cd /d "%~dp0"

set "APP=antares_studio_final.py"
set "NAME=AntaresStudio"
set "DIST=dist_base"
set "WORK=build_base_work"

echo ============================================================
echo [*] BASE BUILD START
echo     APP  : %APP%
echo     NAME : %NAME%
echo     DIST : %DIST%
echo ============================================================

REM --- sanity checks ---
if not exist "%APP%" (
  echo [!] ERROR: %APP% bulunamadi. Bu .bat dosyasi proje kokunde olmali.
  exit /b 1
)

REM --- clean ---
echo [*] Cleaning...
if exist "%DIST%" rmdir /s /q "%DIST%"
if exist "%WORK%" rmdir /s /q "%WORK%"
if exist "%NAME%.spec" del /q "%NAME%.spec"

REM --- ensure tools ---
echo [*] Ensuring build tools...
python -m pip install -U pip setuptools wheel pyinstaller

REM --- install deps (sadece requirements.txt) ---
if exist "requirements.txt" (
  echo [*] Installing requirements.txt...
  python -m pip install -r requirements.txt
) else (
  echo [!] WARNING: requirements.txt yok. Devam ediyorum ama build patlayabilir.
)

REM --- build ---
echo [*] PyInstaller (BASE)...
pyinstaller --noconfirm --clean ^
  --workpath "%WORK%" ^
  --distpath "%DIST%" ^
  --name "%NAME%" ^
  --onedir ^
  --windowed ^
  --exclude-module rembg ^
  --exclude-module onnxruntime ^
  "%APP%"

if errorlevel 1 (
  echo [!] BUILD FAILED
  exit /b 1
)

echo ============================================================
echo [✓] BUILD OK
echo Output: %DIST%\%NAME%\%NAME%.exe
echo ============================================================

exit /b 0
