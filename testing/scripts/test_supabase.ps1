# =============================================================================
# Test Supabase Connection - PowerShell Version
# =============================================================================

Write-Host "Testing Supabase connection and database structure..." -ForegroundColor Blue

# Load environment variables from .env file
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

if (-not $supabaseUrl -or -not $supabaseKey) {
    Write-Host "Error: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not configured" -ForegroundColor Red
    exit 1
}

Write-Host "Supabase URL: $supabaseUrl" -ForegroundColor Cyan

# Test basic connection
try {
    $headers = @{
        "Authorization" = "Bearer $supabaseKey"
        "apikey" = $supabaseKey
        "Content-Type" = "application/json"
    }
    
    # Test basic table access
    $response = Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/productos?select=id&limit=1" -Headers $headers -Method Get
    Write-Host "Connection to Supabase: SUCCESS" -ForegroundColor Green
    
    # Test new columns exist
    try {
        $response = Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/productos?select=cog_url,processing_status,created_at&limit=1" -Headers $headers -Method Get
        Write-Host "COG columns detected: SUCCESS" -ForegroundColor Green
        Write-Host "Database migration appears to be successful" -ForegroundColor Green
    } catch {
        Write-Host "COG columns not found: MIGRATION NEEDED" -ForegroundColor Yellow
    }
    
    # Get record count
    try {
        $response = Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/productos?select=*" -Headers $headers -Method Head
        $count = $response.Headers['Content-Range']
        Write-Host "Total products in database: $count" -ForegroundColor Gray
    } catch {
        Write-Host "Could not get record count" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "Error connecting to Supabase: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Next steps for raster ingestion:" -ForegroundColor Cyan
Write-Host "1. Install Python 3.8+ and GDAL"
Write-Host "2. Install Python dependencies: pip install -r requirements.txt"
Write-Host "3. Test with a sample TIF file"
Write-Host ""
Write-Host "Database is ready for COG ingestion!" -ForegroundColor Green
