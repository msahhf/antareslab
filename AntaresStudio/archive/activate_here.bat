@echo off
cd /d "%~dp0"
call "%~dp0antares_env\Scripts\activate.bat"
echo [OK] antares_env aktif. (python = )
python -V
cmd /k
