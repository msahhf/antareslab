@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

REM ============================================================
REM  AntaresStudio - BASE Build + (optional) Inno Setup Installer
REM  - Only requirements.txt
REM  - Output: dist_base\AntaresStudio\AntaresStudio.exe
REM  - If ISCC.exe exists -> builds installer to installer\
REM ============================================================

set "APP=antares_studio_final.py"
set "NAME=AntaresStudio"
set "DIST=dist_base"
set "WORK=build_base_work"
set "VENV=antares_env"
set "ISS=AntaresStudio.iss"
set "ICON=app.ico"

echo ============================================================
echo [*] BASE BUILD
echo     CWD : %CD%
echo ============================================================

REM --- Sanity ---
if not exist "%APP%" (
  echo [!] ERROR: %APP% bulunamadi. BAT dosyasini proje kokune koy.
  exit /b 1
)

if not exist "requirements.txt" (
  echo [!] ERROR: requirements.txt bulunamadi.
  exit /b 1
)

if not exist "%ICON%" (
  echo [!] ERROR: %ICON% bulunamadi. Icon istiyorsan bu dosya gerekli.
  exit /b 1
)

REM --- Ensure venv ---
if not exist "%VENV%\Scripts\python.exe" (
  echo [*] Creating venv: %VENV% ...
  python -m venv "%VENV%"
  if errorlevel 1 (
    echo [!] ERROR: venv olusturulamadi. Python kurulumunu kontrol et.
    exit /b 1
  )
)

call "%VENV%\Scripts\activate.bat"
if errorlevel 1 (
  echo [!] ERROR: venv activate basarisiz.
  exit /b 1
)

echo [*] Upgrading build tools...
python -m pip install -U pip setuptools wheel pyinstaller
if errorlevel 1 exit /b 1

echo [*] Installing requirements.txt ...
python -m pip install -r requirements.txt
if errorlevel 1 exit /b 1

REM --- Clean outputs ---
echo [*] Cleaning outputs...
if exist "%DIST%" rmdir /s /q "%DIST%"
if exist "%WORK%" rmdir /s /q "%WORK%"
if exist "%NAME%.spec" del /q "%NAME%.spec"

REM --- PyInstaller build ---
echo [*] PyInstaller building BASE...
pyinstaller --noconfirm --clean ^
  --workpath "%WORK%" ^
  --distpath "%DIST%" ^
  --name "%NAME%" ^
  --onedir ^
  --windowed ^
  --icon "%ICON%" ^
  --exclude-module rembg ^
  --exclude-module onnxruntime ^
  "%APP%"

if errorlevel 1 (
  echo [!] ERROR: PyInstaller build failed.
  exit /b 1
)

if not exist "%DIST%\%NAME%\%NAME%.exe" (
  echo [!] ERROR: EXE cikmadi: %DIST%\%NAME%\%NAME%.exe
  exit /b 2
)

echo [OK] EXE: %DIST%\%NAME%\%NAME%.exe

REM --- Optional: Inno Setup compile ---
if not exist "%ISS%" (
  echo [*] Inno Setup script yok (%ISS%). Installer adimi atlandi.
  goto DONE
)

REM Inno Setup Compiler path (common installs)
set "ISCC1=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
set "ISCC2=%ProgramFiles%\Inno Setup 6\ISCC.exe"

set "ISCC="
if exist "%ISCC1%" set "ISCC=%ISCC1%"
if exist "%ISCC2%" set "ISCC=%ISCC2%"

if "%ISCC%"=="" (
  echo [*] ISCC.exe bulunamadi. Installer derleme atlandi.
  echo     Inno Setup kuruluysa ISCC.exe yolunu PATH'e ekleyebilirsin.
  goto DONE
)

echo [*] Building installer with Inno Setup...
"%ISCC%" "%ISS%"
if errorlevel 1 (
  echo [!] ERROR: Inno Setup derleme basarisiz.
  exit /b 3
)

echo [OK] Installer: installer\AntaresStudio_Setup.exe

:DONE
echo.
echo ============================================================
echo [✓] DONE
echo ============================================================
pause
endlocal
