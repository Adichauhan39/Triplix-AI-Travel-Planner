# Deploy Triplix backend to Google Cloud Run
# Prerequisites: gcloud CLI installed, authenticated, project set

param(
    [string]$ProjectId = "",
    [string]$Region = "us-central1"
)

if (-not $ProjectId) {
    $ProjectId = gcloud config get-value project 2>$null
    if (-not $ProjectId) {
        Write-Error "No GCP project set. Run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    }
}

Write-Host "🚀 Deploying Triplix to Cloud Run..." -ForegroundColor Cyan
Write-Host "   Project: $ProjectId"
Write-Host "   Region:  $Region"
Write-Host ""

# Build and deploy
Set-Location "$PSScriptRoot\7-multi-agent"

Write-Host "📦 Building Docker image..." -ForegroundColor Yellow
gcloud builds submit --tag "gcr.io/$ProjectId/triplix-server" .

# Load env vars from local .env (excluded from image by .dockerignore) so
# Cloud Run receives the same API keys you use locally.
$envFile = Join-Path $PSScriptRoot "7-multi-agent\.env"
$envPairs = @()
if (Test-Path $envFile) {
    Write-Host "🔐 Loading runtime env from .env..." -ForegroundColor Yellow
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { return }
        $kv = $line -split '=', 2
        if ($kv.Count -ne 2) { return }
        $key = $kv[0].Trim()
        $value = $kv[1].Trim().Trim('"').Trim("'")
        if ($key -eq "" -or $value -eq "") { return }
        # Escape commas in values for --set-env-vars list format
        $escaped = $value -replace ',', '\,'
        $envPairs += "$key=$escaped"
    }
}
# Always ensure MONGODB_DB has a default
if (-not ($envPairs | Where-Object { $_ -like "MONGODB_DB=*" })) {
    $envPairs += "MONGODB_DB=triplix"
}
$envArg = ($envPairs -join ",")

Write-Host "🌐 Deploying to Cloud Run..." -ForegroundColor Yellow
gcloud run deploy triplix-server `
    --image "gcr.io/$ProjectId/triplix-server" `
    --region $Region `
    --platform managed `
    --allow-unauthenticated `
    --memory 1Gi `
    --cpu 1 `
    --timeout 300 `
    --set-env-vars "$envArg"

# Get the service URL
$serviceUrl = gcloud run services describe triplix-server --region $Region --format "value(status.url)" 2>$null
Write-Host ""
Write-Host "✅ Deployed successfully!" -ForegroundColor Green
Write-Host "   URL: $serviceUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "ℹ️  Env vars applied from 7-multi-agent/.env ($($envPairs.Count) keys)" -ForegroundColor DarkCyan

Set-Location $PSScriptRoot
