# ============================================================
# Deploy Triplix Backend to Google Cloud Run
# ============================================================
# Prerequisites:
#   1. Install gcloud CLI: https://cloud.google.com/sdk/docs/install
#   2. Run: gcloud auth login
#   3. Create a GCP project with billing enabled
#   4. Enable required APIs (done automatically below)
# ============================================================

param(
    [string]$ProjectId,          # Your GCP project ID (required)
    [string]$Region = "asia-south1",  # Mumbai region (closest to India)
    [string]$ServiceName = "triplix-api"
)

if (-not $ProjectId) {
    Write-Host "Usage: .\deploy_to_gcp.ps1 -ProjectId YOUR_PROJECT_ID" -ForegroundColor Red
    Write-Host ""
    Write-Host "Example:" -ForegroundColor Yellow
    Write-Host '  .\deploy_to_gcp.ps1 -ProjectId my-triplix-project' -ForegroundColor Gray
    Write-Host '  .\deploy_to_gcp.ps1 -ProjectId my-triplix-project -Region us-central1' -ForegroundColor Gray
    exit 1
}

Write-Host "`n=== Triplix GCP Cloud Run Deployment ===" -ForegroundColor Cyan

# Step 1: Set project
Write-Host "`n[1/5] Setting GCP project: $ProjectId" -ForegroundColor Yellow
gcloud config set project $ProjectId

# Step 2: Enable required APIs
Write-Host "`n[2/5] Enabling required GCP APIs..." -ForegroundColor Yellow
gcloud services enable run.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable artifactregistry.googleapis.com

# Step 3: Build and deploy to Cloud Run (from source)
Write-Host "`n[3/5] Building and deploying to Cloud Run..." -ForegroundColor Yellow
Write-Host "  Region: $Region" -ForegroundColor Gray
Write-Host "  Service: $ServiceName" -ForegroundColor Gray

Set-Location -Path "$PSScriptRoot\7-multi-agent"

gcloud run deploy $ServiceName `
    --source . `
    --region $Region `
    --allow-unauthenticated `
    --update-env-vars "GOOGLE_API_KEY=$env:GOOGLE_API_KEY,GOOGLE_PLACES_API_KEY=$env:GOOGLE_PLACES_API_KEY,OPENWEATHER_API_KEY=$env:OPENWEATHER_API_KEY" `
    --memory 1Gi `
    --cpu 1 `
    --timeout 300 `
    --min-instances 0 `
    --max-instances 10

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ERROR] Deployment failed!" -ForegroundColor Red
    exit 1
}

# Step 4: Get the deployed URL
Write-Host "`n[4/5] Getting service URL..." -ForegroundColor Yellow
$serviceUrl = gcloud run services describe $ServiceName --region $Region --format "value(status.url)"

# Step 5: Test the deployment
Write-Host "`n[5/5] Testing deployment..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$serviceUrl/" -Method Get -TimeoutSec 30
    Write-Host "  Status: $($response.status)" -ForegroundColor Green
} catch {
    Write-Host "  Warning: Could not reach server yet (may still be starting)" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "API URL:  $serviceUrl" -ForegroundColor White
Write-Host "API Docs: $serviceUrl/docs" -ForegroundColor White
Write-Host ""
Write-Host "Next step: Update your Flutter app's baseUrl to:" -ForegroundColor Yellow
Write-Host "  static const String baseUrl = '$serviceUrl';" -ForegroundColor Gray
Write-Host "========================================`n" -ForegroundColor Cyan
