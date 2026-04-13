@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0"

echo [*] CWD = %CD%

if not exist "antares_env\Scripts\python.exe" (
  echo [!] venv yok: antares_env bulunamadi
  exit /b 1
)

call "antares_env\Scripts\activate.bat"

echo [*] Upgrading build tools...
python -m pip install -U pip setuptools wheel pyinstaller

echo [*] Cleaning build/dist...
rmdir /s /q "build" 2>nul
rmdir /s /q "dist" 2>nul

echo [*] PyInstaller build (explicit dist/work paths)...
pyinstaller --noconfirm --clean ^
  --distpath "%CD%\dist" ^
  --workpath "%CD%\build" ^
  "AntaresStudio.spec"

echo [*] Checking output...
if not exist "dist\AntaresStudio\AntaresStudio.exe" (
  echo [!] EXE yok! Araniyor...
  where /r "%CD%" AntaresStudio.exe
  exit /b 2
)

echo [OK] Built: %CD%\dist\AntaresStudio\AntaresStudio.exe
dir "dist\AntaresStudio" | more

endlocal
