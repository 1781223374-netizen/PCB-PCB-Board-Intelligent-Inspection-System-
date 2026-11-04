@echo off
cd /d "%~dp0"
python -m pip install -r requirements.txt
if errorlevel 1 goto end
python tools\build_app.py
:end
pause
