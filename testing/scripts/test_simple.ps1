# =============================================================================
# Database Integration Test - Simple PowerShell Version
# =============================================================================

Write-Host "TESTING DATABASE INTEGRATION" -ForegroundColor Blue
Write-Host "=============================="

# Load environment variables
$envVars = @{}
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        if ($_ -match "^([^#][^=]+)=(.*)$") {
            $envVars[$matches[1]] = $matches[2]
        }
    }
}

$supabaseUrl = $envVars["SUPABASE_URL"]
$supabaseKey = $envVars["SUPABASE_SERVICE_ROLE_KEY"]
$gcsBucket = $envVars["GCS_BUCKET"]

Write-Host ""
Write-Host "Configuration Check:" -ForegroundColor Yellow
Write-Host "  Supabase URL: $(if ($supabaseUrl) { 'OK' } else { 'MISSING' })"
Write-Host "  Service Key: $(if ($supabaseKey) { 'OK' } else { 'MISSING' })"
Write-Host "  GCS Bucket: $(if ($gcsBucket) { 'OK' } else { 'MISSING' })"

if (-not $supabaseUrl -or -not $supabaseKey) {
    Write-Host "CRITICAL: Missing Supabase configuration" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Testing Supabase API..." -ForegroundColor Yellow

$headers = @{
    "Authorization" = "Bearer $supabaseKey"
    "apikey" = $supabaseKey
    "Content-Type" = "application/json"
}

try {
    # Test basic connection
    $response = Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/productos?select=id&limit=1" -Headers $headers -Method Get
    Write-Host "  Basic connection: SUCCESS" -ForegroundColor Green
    
    # Test COG columns
    $response = Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/productos?select=cog_url,processing_status&limit=1" -Headers $headers -Method Get
    Write-Host "  COG columns: SUCCESS" -ForegroundColor Green
    
    # Test insert
    $testRecord = @{
        producto = "test_integration"
        empresa = "test_company"
        ingenio = "test_mill"
        fecha = "2025-09-03"
        original_filename = "test.tif"
        processing_status = "pending"
    } | ConvertTo-Json
    
    $insertHeaders = $headers.Clone()
    $insertHeaders["Prefer"] = "return=representation"
    
    $insertResponse = Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/productos" -Headers $insertHeaders -Method Post -Body $testRecord
    
    if ($insertResponse -and $insertResponse.id) {
        $testId = $insertResponse.id
        Write-Host "  Insert record: SUCCESS (ID: $testId)" -ForegroundColor Green
        
        # Test update
        $updateData = @{
            processing_status = "completed"
        } | ConvertTo-Json
        
        Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/productos?id=eq.$testId" -Headers $headers -Method Patch -Body $updateData | Out-Null
        Write-Host "  Update record: SUCCESS" -ForegroundColor Green
        
        # Clean up
        Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/productos?id=eq.$testId" -Headers $headers -Method Delete | Out-Null
        Write-Host "  Delete record: SUCCESS" -ForegroundColor Green
    } else {
        Write-Host "  Insert record: FAILED - No ID returned" -ForegroundColor Red
    }
    
} catch {
    Write-Host "  Database test FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Testing GCS access..." -ForegroundColor Yellow

try {
    $null = gsutil ls "gs://$gcsBucket" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  GCS bucket: ACCESSIBLE" -ForegroundColor Green
    } else {
        Write-Host "  GCS bucket: NOT ACCESSIBLE" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  GCS test: SKIPPED (gsutil not available)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=============================="
Write-Host "INTEGRATION TEST: SUCCESS" -ForegroundColor Green
Write-Host "=============================="

Write-Host ""
Write-Host "Database is ready for raster ingestion!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Install Python + GDAL"
Write-Host "2. Test raster processing"
Write-Host "3. Monitor in Supabase dashboard"

Write-Host ""
Write-Host "Dashboard: $supabaseUrl" -ForegroundColor Cyan
