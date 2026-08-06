param(
    [int]$Port = 8004,
    [switch]$Detached
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$venvAdk = Join-Path $projectRoot '.venv\Scripts\adk.exe'
$envFile = Join-Path $scriptDir '.env1'

if (-not (Test-Path $venvAdk)) {
    Write-Error "ADK executable not found at: $venvAdk"
}

if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#')) {
            $parts = $line -split '=', 2
            if ($parts.Count -eq 2) {
                $name = $parts[0].Trim()
                $value = $parts[1].Trim().Trim('"')
                Set-Item -Path "Env:$name" -Value $value
            }
        }
    }
}

if (-not $env:GOOGLE_API_KEY) {
    Write-Host "GOOGLE_API_KEY is not set."
    Write-Host "Create legal_ca_agent/.env1 with a line: GOOGLE_API_KEY=your_real_key"
    exit 1
}

function Test-PortAvailable {
    param([int]$TestPort)

    $conn = Get-NetTCPConnection -LocalPort $TestPort -State Listen -ErrorAction SilentlyContinue
    return -not $conn
}

$selectedPort = $Port
for ($i = 0; $i -lt 25; $i++) {
    if (Test-PortAvailable -TestPort $selectedPort) {
        break
    }
    $selectedPort++
}

if (-not (Test-PortAvailable -TestPort $selectedPort)) {
    Write-Error "Could not find a free port in range $Port-$($Port + 24)."
}

if ($selectedPort -ne $Port) {
    Write-Host "Port $Port is busy. Switching to $selectedPort."
}

Write-Host "Starting ADK web on port $selectedPort..."
Write-Host "Open: http://localhost:$selectedPort"

if ($Detached) {
    $proc = Start-Process -FilePath $venvAdk -ArgumentList @('web', $projectRoot, '--port', $selectedPort) -PassThru
    Write-Host "ADK started in background (PID: $($proc.Id))."
} else {
    & $venvAdk web $projectRoot --port $selectedPort
}
