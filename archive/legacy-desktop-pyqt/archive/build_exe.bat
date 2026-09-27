@echo off
setlocal
cd /d "%~dp0"

call antares_env\Scripts\activate.bat

echo [*] Cleaning old builds...
rmdir /s /q build 2>nul
rmdir /s /q dist  2>nul

echo [*] Building AntaresStudio (console ON)...
pyinstaller ^
  --console ^
  --onedir ^
  --name "AntaresStudio" ^
  --clean ^
  --collect-all PyQt6 ^
  --collect-all cv2 ^
  antares_studio_final.py

if errorlevel 1 (
  echo [ERROR] Build failed.
  pause
  exit /b 1
)

echo.
echo [OK] Output: dist\AntaresStudio\AntaresStudio.exe
echo Test:  dist\AntaresStudio\AntaresStudio.exe
echo.
pause
endlocal
