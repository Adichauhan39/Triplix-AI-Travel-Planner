@echo off
REM Ultra-Simple Hotel Search Server Launcher
REM This starts the backend on port 8001

cd /d "%~dp0"

echo.
echo ============================================================
echo   ULTRA-SIMPLE HOTEL SEARCH SERVER
echo ============================================================
echo.
echo   Starting server on port 8001...
echo   CSV + Gemini AI mode (No ADK complexity)
echo.
echo   Once running, test with:
echo   - Python: python test_ultra_simple.py
echo   - Flutter: Run the app and search hotels
echo.
echo ============================================================
echo.

if exist "..\.venv\Scripts\python.exe" (
	..\.venv\Scripts\python.exe ultra_simple_server.py
) else if exist ".venv\Scripts\python.exe" (
	.venv\Scripts\python.exe ultra_simple_server.py
) else (
	python ultra_simple_server.py
)

pause
