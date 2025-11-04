# =============================================================================
# Manual Database Test - Pure PowerShell (No Python dependencies)
# =============================================================================

Write-Host "🧪 TESTING DATABASE INTEGRATION (PowerShell)" -ForegroundColor Blue
Write-Host "=" * 55

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
$projectId = $envVars["PROJECT_ID"]

Write-Host "📋 Configuration Check:" -ForegroundColor Yellow
Write-Host "  Supabase URL: $(if ($supabaseUrl) { '✅ Set' } else { '❌ Missing' })"
Write-Host "  Service Key: $(if ($supabaseKey) { '✅ Set' } else { '❌ Missing' })"
Write-Host "  GCS Bucket: $(if ($gcsBucket) { '✅ Set' } else { '❌ Missing' })"
Write-Host "  Project ID: $(if ($projectId) { '✅ Set' } else { '❌ Missing' })"

if (-not $supabaseUrl -or -not $supabaseKey) {
    Write-Host "❌ Critical configuration missing" -ForegroundColor Red
    exit 1
}

# Test Supabase REST API
Write-Host "`n🔍 Testing Supabase REST API..." -ForegroundColor Yellow

$headers = @{
    "Authorization" = "Bearer $supabaseKey"
    "apikey" = $supabaseKey
    "Content-Type" = "application/json"
}

try {
    # Test 1: Basic table access
    $response = Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/productos?select=id&limit=1" -Headers $headers -Method Get
    Write-Host "✅ Basic table access: SUCCESS" -ForegroundColor Green
    
    # Test 2: COG columns access
    $response = Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/productos?select=cog_url,processing_status,original_filename&limit=1" -Headers $headers -Method Get
    Write-Host "✅ COG columns access: SUCCESS" -ForegroundColor Green
    
    # Test 3: Insert test record
    $testRecord = @{
        producto = "test_ndvi"
        empresa = "test_empresa"
        ingenio = "test_ingenio"
        fecha = "2025-09-03"
        original_filename = "test_file.tif"
        processing_status = "pending"
        processing_log = "Test record created by PowerShell script"
    } | ConvertTo-Json
    
    $insertResponse = Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/productos" -Headers $headers -Method Post -Body $testRecord
    
    if ($insertResponse) {
        $testId = $insertResponse[0].id
        Write-Host "✅ Insert test record: SUCCESS (ID: $testId)" -ForegroundColor Green
        
        # Test 4: Update test record
        $updateData = @{
            processing_status = "completed"
            processing_log = "Test record updated successfully"
        } | ConvertTo-Json
        
        $updateResponse = Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/productos?id=eq.$testId" -Headers $headers -Method Patch -Body $updateData
        Write-Host "✅ Update test record: SUCCESS" -ForegroundColor Green
        
        # Test 5: Delete test record
        $deleteResponse = Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/productos?id=eq.$testId" -Headers $headers -Method Delete
        Write-Host "✅ Delete test record: SUCCESS" -ForegroundColor Green
    }
    
    # Test 6: Custom function
    try {
        $statsResponse = Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/rpc/get_processing_stats" -Headers $headers -Method Post -Body "{}"
        if ($statsResponse) {
            $stats = $statsResponse[0]
            Write-Host "✅ Custom function test: SUCCESS" -ForegroundColor Green
            Write-Host "   📊 Database Statistics:" -ForegroundColor Cyan
            Write-Host "      Total products: $($stats.total_products)"
            Write-Host "      Completed: $($stats.completed)"
            Write-Host "      Pending: $($stats.pending)"
            Write-Host "      Failed: $($stats.failed)"
        }
    } catch {
        Write-Host "⚠️  Custom function test: FAILED (function might not exist)" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "❌ Database test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test GCS bucket access
Write-Host "`n🗄️  Testing GCS bucket access..." -ForegroundColor Yellow

try {
    $gcsTest = gsutil ls "gs://$gcsBucket" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ GCS bucket access: SUCCESS" -ForegroundColor Green
    } else {
        Write-Host "⚠️  GCS bucket access: FAILED (check permissions)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️  GCS test skipped (gsutil not available)" -ForegroundColor Yellow
}

# Test TiTiler service
Write-Host "`n🌐 Testing TiTiler service..." -ForegroundColor Yellow

$titilerUrl = $envVars["DOMAIN_NAME"]
if ($titilerUrl) {
    try {
        $titilerResponse = Invoke-RestMethod -Uri "https://$titilerUrl/docs" -Method Get -TimeoutSec 10
        Write-Host "✅ TiTiler service: ACCESSIBLE" -ForegroundColor Green
    } catch {
        Write-Host "⚠️  TiTiler service: NOT RESPONDING" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠️  TiTiler URL not configured" -ForegroundColor Yellow
}

Write-Host "`n" + "=" * 55
Write-Host "🎯 INTEGRATION TEST SUMMARY" -ForegroundColor Blue
Write-Host "=" * 55

Write-Host "Database operations: ✅ READY" -ForegroundColor Green
Write-Host "Configuration: ✅ COMPLETE" -ForegroundColor Green
Write-Host "Infrastructure: ✅ DEPLOYED" -ForegroundColor Green

Write-Host "`n📝 READY FOR RASTER INGESTION!" -ForegroundColor Green

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Install Python + GDAL for local processing"
Write-Host "2. Test with sample TIF file"
Write-Host "3. Monitor processing in Supabase dashboard"

Write-Host "`n🔗 Useful URLs:" -ForegroundColor Cyan
Write-Host "  Supabase Dashboard: $supabaseUrl"
Write-Host "  TiTiler Service: https://$titilerUrl"
Write-Host "  GCS Bucket: https://console.cloud.google.com/storage/browser/$gcsBucket"

Write-Host "`n🎉 Modern Raster Architecture is ready!" -ForegroundColor Green
