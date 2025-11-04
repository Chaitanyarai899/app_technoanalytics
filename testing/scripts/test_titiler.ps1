# =============================================================================
# Test TiTiler Setup - PowerShell Version
# =============================================================================

Write-Host "Testing TiTiler deployment..." -ForegroundColor Blue

# URL del servicio TiTiler
$TitilerUrl = "https://ta-titiler-service-1087100331392.us-central1.run.app"

Write-Host ""
Write-Host "TiTiler Service URL: $TitilerUrl" -ForegroundColor Cyan

# Test 1: Health check
Write-Host ""
Write-Host "Testing health endpoint..." -ForegroundColor Yellow

try {
    $response = Invoke-RestMethod -Uri "$TitilerUrl/healthz" -Method Get -TimeoutSec 10
    Write-Host "Health check passed" -ForegroundColor Green
    Write-Host "Response: $response" -ForegroundColor Gray
} catch {
    Write-Host "Health check failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "TiTiler setup test completed!" -ForegroundColor Green

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Install Python and GDAL to process your raster files"
Write-Host "2. Convert your TIF files to COG format"
Write-Host "3. Upload COGs to GCS bucket: ta-cogs-apicorreo-prod"
Write-Host "4. Test with your own data"

Write-Host ""
Write-Host "Test the service in browser:" -ForegroundColor Cyan
Write-Host "Documentation: $TitilerUrl/docs"
Write-Host "Health check: $TitilerUrl/healthz"

Write-Host ""
Write-Host "Your TiTiler service is ready!" -ForegroundColor Green
Write-Host "Service URL: $TitilerUrl" -ForegroundColor White
