# =============================================================================
# Setup Script for Modern Raster Architecture - Windows
# =============================================================================

Write-Host "Setting up Modern Raster Architecture environment..." -ForegroundColor Blue

# Function to check if command exists
function Test-Command($cmdname) {
    return [bool](Get-Command -Name $cmdname -ErrorAction SilentlyContinue)
}

# Check Python installation
Write-Host "`nChecking Python installation..." -ForegroundColor Yellow

if (Test-Command "python") {
    $pythonVersion = python --version
    Write-Host "Python found: $pythonVersion" -ForegroundColor Green
} elseif (Test-Command "py") {
    $pythonVersion = py --version
    Write-Host "Python found via 'py': $pythonVersion" -ForegroundColor Green
    # Create alias for consistency
    Set-Alias -Name python -Value py
} else {
    Write-Host "Python not found in PATH. Please:" -ForegroundColor Red
    Write-Host "1. Restart PowerShell/Terminal" -ForegroundColor Yellow
    Write-Host "2. Or install Python from: https://python.org" -ForegroundColor Yellow
    Write-Host "3. Make sure to check 'Add Python to PATH' during installation" -ForegroundColor Yellow
    exit 1
}

# Check pip
Write-Host "`nChecking pip..." -ForegroundColor Yellow
if (Test-Command "pip") {
    $pipVersion = pip --version
    Write-Host "pip found: $pipVersion" -ForegroundColor Green
} else {
    Write-Host "pip not found. Installing..." -ForegroundColor Yellow
    python -m ensurepip --default-pip
}

# Install Python dependencies
Write-Host "`nInstalling Python dependencies..." -ForegroundColor Yellow

# Create a minimal requirements file for testing
$minimalRequirements = @"
supabase>=2.0.0
requests>=2.28.0
"@

$minimalRequirements | Out-File -FilePath "requirements_minimal.txt" -Encoding UTF8

try {
    pip install -r requirements_minimal.txt
    Write-Host "Python dependencies installed successfully" -ForegroundColor Green
} catch {
    Write-Host "Error installing Python dependencies: $($_.Exception.Message)" -ForegroundColor Red
}

# Check GDAL availability
Write-Host "`nChecking GDAL..." -ForegroundColor Yellow
if (Test-Command "gdal_translate") {
    $gdalVersion = gdal_translate --version
    Write-Host "GDAL found: $gdalVersion" -ForegroundColor Green
} else {
    Write-Host "GDAL not found. For full functionality, install GDAL:" -ForegroundColor Yellow
    Write-Host "1. Download from: https://gdal.org/download.html" -ForegroundColor Gray
    Write-Host "2. Or use conda: conda install gdal" -ForegroundColor Gray
    Write-Host "3. Or use OSGeo4W: https://trac.osgeo.org/osgeo4w/" -ForegroundColor Gray
    Write-Host "Note: You can test Supabase connection without GDAL" -ForegroundColor Cyan
}

# Test Supabase connection
Write-Host "`nTesting Supabase connection..." -ForegroundColor Yellow

try {
    python scripts/verify_supabase.py
    Write-Host "Supabase connection test completed" -ForegroundColor Green
} catch {
    Write-Host "Could not run Supabase test. Manual verification needed." -ForegroundColor Yellow
}

Write-Host "`n" + "="*60 -ForegroundColor Blue
Write-Host "SETUP SUMMARY" -ForegroundColor Blue
Write-Host "="*60 -ForegroundColor Blue

Write-Host "Python: " -NoNewline
if (Test-Command "python") { Write-Host "✓ Installed" -ForegroundColor Green } else { Write-Host "✗ Missing" -ForegroundColor Red }

Write-Host "Supabase Client: " -NoNewline
try {
    python -c "import supabase; print('✓ Available')"
    $supabaseOk = $true
} catch {
    Write-Host "✗ Missing" -ForegroundColor Red
    $supabaseOk = $false
}

Write-Host "GDAL: " -NoNewline
if (Test-Command "gdal_translate") { Write-Host "✓ Available" -ForegroundColor Green } else { Write-Host "⚠ Not installed (optional for testing)" -ForegroundColor Yellow }

Write-Host "`nNext steps:" -ForegroundColor Cyan
if ($supabaseOk) {
    Write-Host "1. Test Supabase: python scripts/verify_supabase.py"
    Write-Host "2. Install GDAL for raster processing"
    Write-Host "3. Test raster ingestion: python ingestion/ingest_rasters.py --help"
} else {
    Write-Host "1. Install dependencies: pip install -r requirements.txt"
    Write-Host "2. Test Supabase connection"
    Write-Host "3. Install GDAL for raster processing"
}

Write-Host "`nModern Raster Architecture setup ready for testing!" -ForegroundColor Green
