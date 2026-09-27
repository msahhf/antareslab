@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

call antares_env\Scripts\activate.bat

set "APP=antares_studio_final.py"
set "NAME=AntaresStudio"

REM PyInstaller'in geçici çıktıları
set "WORKDIR=build"
set "DISTDIR=dist"

echo [*] Cleaning...
rmdir /s /q "%WORKDIR%" 2>nul
rmdir /s /q "%DISTDIR%"  2>nul
rmdir /s /q dist_base 2>nul
rmdir /s /q dist_open3d 2>nul
rmdir /s /q dist_rembg_cpu 2>nul
rmdir /s /q dist_rembg_gpu 2>nul
rmdir /s /q dist_full 2>nul
rmdir /s /q release 2>nul

python -m pip install -U pip setuptools wheel pyinstaller

REM ==================== BUILD FUNCTION ====================
REM call :BUILD <outDir>
:BUILD
set "OUT=%~1"

echo [*] PyInstaller...
pyinstaller --noconfirm --clean ^
  --workpath "%WORKDIR%" ^
  --distpath "%DISTDIR%" ^
  --name "%NAME%" ^
  --onedir ^
  --console ^
  --collect-all PyQt6 ^
  --collect-all cv2 ^
  "%APP%"
if errorlevel 1 exit /b 1

echo [*] Copying to %OUT%...
if exist "%OUT%\%NAME%" rmdir /s /q "%OUT%\%NAME%" 2>nul
xcopy /E /I /Y "%DISTDIR%\%NAME%" "%OUT%\%NAME%" >nul

REM sadece build klasörünü temizle, dist'i silme (debug için kalsın)
rmdir /s /q "%WORKDIR%" 2>nul

exit /b 0

REM ==================== VARIANTS ====================

echo.
echo ==================== 1) BASE ====================
python -m pip install -r requirements.txt
call :BUILD dist_base || goto FAIL

echo.
echo ==================== 2) OPEN3D ====================
python -m pip install -r requirements.txt
python -m pip install -r requirements_open3d.txt
call :BUILD dist_open3d || goto FAIL

echo.
echo ==================== 3) REMBG CPU ====================
python -m pip install -r requirements.txt
python -m pip install -r requirements_rembg_cpu.txt
call :BUILD dist_rembg_cpu || goto FAIL

echo.
echo ==================== 4) REMBG GPU ====================
python -m pip install -r requirements.txt
python -m pip install -r requirements_rembg_gpu.txt
call :BUILD dist_rembg_gpu || goto FAIL

echo.
echo ==================== 5) FULL ====================
python -m pip install -r requirements.txt
python -m pip install -r requirements_open3d.txt
python -m pip install -r requirements_rembg_gpu.txt
call :BUILD dist_full || goto FAIL

echo.
echo [*] Creating final release from FULL...
mkdir release 2>nul
if exist "release\%NAME%" rmdir /s /q "release\%NAME%" 2>nul
xcopy /E /I /Y "dist_full\%NAME%" "release\%NAME%" >nul

echo.
echo [OK] All variants built:
echo   dist_base\%NAME%\%NAME%.exe
echo   dist_open3d\%NAME%\%NAME%.exe
echo   dist_rembg_cpu\%NAME%\%NAME%.exe
echo   dist_rembg_gpu\%NAME%\%NAME%.exe
echo   dist_full\%NAME%\%NAME%.exe
echo.
echo [OK] FINAL installer folder:
echo   release\%NAME%\%NAME%.exe
pause
exit /b 0

:FAIL
echo.
echo [ERROR] Variant build failed.
pause
exit /b 1
