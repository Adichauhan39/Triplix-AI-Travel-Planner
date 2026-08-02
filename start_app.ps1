# Travel App Startup Script
# This script starts both the Python backend and Flutter frontend

Write-Host " Starting Travel App..." -ForegroundColor Green
Write-Host ""

# Start Python Backend in a new window
Write-Host " Starting Python ADK Backend on port 8000..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd 'c:\Hack2skill\Hack2skill finale\7-multi-agent'; python -m uvicorn api_server:app --reload --host 127.0.0.1 --port 8000"

# Wait a bit for backend to start
Write-Host "⏳ Waiting for backend to initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

# Start Flutter Frontend in a new window
Write-Host "📱 Starting Flutter App in Chrome..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd 'c:\Hack2skill\Hack2skill finale\flutter_travel_app'; flutter run -d chrome --hot"

Write-Host ""
Write-Host "✅ Both services are starting!" -ForegroundColor Green
Write-Host ""
Write-Host "Backend API: http://127.0.0.1:8000" -ForegroundColor White
Write-Host "API Docs: http://127.0.0.1:8000/docs" -ForegroundColor White
Write-Host ""
Write-Host "Press Ctrl+C in the respective windows to stop the services." -ForegroundColor Gray
