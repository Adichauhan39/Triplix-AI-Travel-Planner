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

Write-Host "🌐 Deploying to Cloud Run..." -ForegroundColor Yellow
gcloud run deploy triplix-server `
    --image "gcr.io/$ProjectId/triplix-server" `
    --region $Region `
    --platform managed `
    --allow-unauthenticated `
    --memory 1Gi `
    --cpu 1 `
    --timeout 300 `
    --set-env-vars "MONGODB_DB=triplix"

# Get the service URL
$serviceUrl = gcloud run services describe triplix-server --region $Region --format "value(status.url)" 2>$null
Write-Host ""
Write-Host "✅ Deployed successfully!" -ForegroundColor Green
Write-Host "   URL: $serviceUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠️  Remember to set secrets:" -ForegroundColor Yellow
Write-Host "   gcloud run services update triplix-server --region $Region --set-env-vars `"GOOGLE_API_KEY=xxx,MONGODB_URI=xxx,OPENWEATHER_API_KEY=xxx`""

Set-Location $PSScriptRoot
