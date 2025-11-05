# 🚀 Techno Analytics - Complete Deployment Guide

Deploy the Techno Analytics agricultural platform with your own infrastructure and data.

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Account Setup](#account-setup)
4. [Infrastructure Deployment](#infrastructure-deployment)
5. [Database Setup](#database-setup)
6. [Data Ingestion](#data-ingestion)
7. [Flutter App Configuration](#flutter-app-configuration)
8. [Testing & Verification](#testing--verification)
9. [Cost Estimation](#cost-estimation)
10. [Troubleshooting](#troubleshooting)

---

## 🎯 Overview

This guide will help you deploy the complete Techno Analytics platform infrastructure, including:

- **Google Cloud Platform**: TiTiler service, Cloud Storage, CDN
- **Supabase**: PostgreSQL database with spatial extensions
- **Flutter App**: Mobile application configuration
- **Data Pipeline**: COG processing and ingestion

**Deployment Time**: 2-3 hours
**Monthly Cost**: $20-50 (vs $200+ for legacy GeoServer)

---

## 📦 Prerequisites

### Required Accounts

| Service | Purpose | Sign Up |
|---------|---------|---------|
| **Google Cloud Platform** | TiTiler hosting, storage, CDN | [cloud.google.com](https://cloud.google.com) |
| **Supabase** | PostgreSQL database | [supabase.com](https://supabase.com) |

### Required Tools

Install the following tools on your development machine:

#### 1. **Google Cloud SDK**
```bash
# Linux/macOS
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# Windows
# Download from: https://cloud.google.com/sdk/docs/install

# Verify installation
gcloud --version
```

#### 2. **GDAL** (Geospatial Data Abstraction Library)
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install gdal-bin python3-gdal

# macOS (Homebrew)
brew install gdal

# Windows
# Download from: https://trac.osgeo.org/osgeo4w/

# Verify installation
gdal_translate --version
```

#### 3. **Python 3.8+**
```bash
# Check version
python3 --version

# Install pip if needed
sudo apt-get install python3-pip  # Ubuntu/Debian
```

#### 4. **Flutter SDK 3.0+** (for app development)
```bash
# Download from: https://docs.flutter.dev/get-started/install

# Verify installation
flutter doctor
```

### System Requirements

- **OS**: Linux, macOS, or Windows 10+
- **RAM**: 8GB minimum (16GB recommended for processing large rasters)
- **Disk Space**: 20GB minimum
- **Network**: Stable internet connection for cloud deployments

---

## 🔑 Account Setup

### Step 1: Google Cloud Platform Setup

#### 1.1 Create a GCP Project

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Click **Create Project**
3. Enter project details:
   - **Project Name**: `techno-analytics-prod` (or your choice)
   - **Project ID**: Note this - you'll need it later
4. Click **Create**

#### 1.2 Enable Required APIs

```bash
# Authenticate with GCP
gcloud auth login

# Set your project
gcloud config set project YOUR_PROJECT_ID

# Enable required APIs
gcloud services enable \
  run.googleapis.com \
  storage.googleapis.com \
  compute.googleapis.com \
  cloudbuild.googleapis.com \
  containerregistry.googleapis.com
```

#### 1.3 Create a Service Account

```bash
# Create service account
gcloud iam service-accounts create titiler-sa \
  --display-name "TiTiler Service Account"

# Grant necessary permissions
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:titiler-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:titiler-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/run.invoker"
```

#### 1.4 Set Up Billing

1. Navigate to **Billing** in GCP Console
2. Link a payment method
3. Set up **Budget Alerts** (recommended):
   - Go to **Billing > Budgets & alerts**
   - Create budget: $100/month
   - Set alert at 50%, 90%, 100%

### Step 2: Supabase Setup

#### 2.1 Create a Supabase Project

1. Go to [supabase.com](https://supabase.com)
2. Click **Start your project**
3. Create a new organization (if needed)
4. Click **New Project**:
   - **Name**: `techno-analytics`
   - **Database Password**: Generate a strong password (save it!)
   - **Region**: Choose closest to your users
   - **Pricing Plan**: Free tier to start (upgrade later if needed)
5. Wait 2-3 minutes for project creation

#### 2.2 Get Supabase Credentials

1. Go to **Project Settings > API**
2. Copy the following:
   - **Project URL**: `https://xxxxx.supabase.co`
   - **anon public** key (for Flutter app)
   - **service_role** key (for backend - keep secret!)

#### 2.3 Configure Database

1. Go to **SQL Editor** in Supabase Dashboard
2. Create the required tables (we'll run migrations later)

---

## 🏗️ Infrastructure Deployment

### Step 1: Clone and Configure Repository

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/techno_analytics.git
cd techno_analytics

# Create .env file from template
cp config/.env.example .env
```

### Step 2: Configure Environment Variables

Edit the `.env` file with your credentials:

```bash
# =============================================================================
# Google Cloud Platform Configuration
# =============================================================================
PROJECT_ID=your-gcp-project-id
GCS_BUCKET=your-unique-bucket-name-12345  # Must be globally unique
DOMAIN_NAME=tiles.yourdomain.com           # Optional: custom domain
REGION=us-central1                         # Or nearest region

# =============================================================================
# Supabase Configuration
# =============================================================================
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGc...your-service-role-key
SUPABASE_SCHEMA=public
SUPABASE_TABLE=productos

# =============================================================================
# TiTiler Configuration
# =============================================================================
TITILER_IMAGE=ghcr.io/developmentseed/titiler:latest
TITILER_SERVICE_NAME=titiler-service
TITILER_MEMORY=2Gi
TITILER_CPU=1000m
TITILER_CONCURRENCY=80
TITILER_MAX_INSTANCES=10
TITILER_MIN_INSTANCES=0

# =============================================================================
# Flutter App Configuration
# =============================================================================
USE_MODERN_TILES=true
TILE_SIZE=256
MAX_ZOOM=18
```

**Important Notes:**
- `GCS_BUCKET` must be globally unique (try: `your-company-ta-cogs-prod`)
- `DOMAIN_NAME` is optional - you can use the Cloud Run URL directly
- Keep `SUPABASE_SERVICE_ROLE_KEY` secret - never commit to git!

### Step 3: Install Python Dependencies

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r deployment/requirements.txt
```

### Step 4: Deploy Infrastructure Components

The automated setup script will deploy all components:

```bash
# Make scripts executable
chmod +x deployment/setup.sh
chmod +x infra/*.sh
chmod +x ingestion/*.sh

# Run complete setup
./deployment/setup.sh
```

**What this does:**
1. ✅ Creates Google Cloud Storage bucket
2. ✅ Deploys TiTiler service to Cloud Run
3. ✅ Configures CDN and Load Balancer (optional)
4. ✅ Sets up IAM permissions
5. ✅ Tests the deployment

**Expected Output:**
```
🚀 MODERN RASTER ARCHITECTURE SETUP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Prerequisites check passed
✅ Environment validated
✅ GCS setup completed
✅ TiTiler deployment completed
✅ CDN and Load Balancer setup completed

📊 Deployment Summary:
   TiTiler URL: https://titiler-service-xxxxx.run.app
   GCS Bucket: gs://your-bucket-name
   CDN URL: https://tiles.yourdomain.com (if configured)

🎉 Modern raster architecture setup completed!
```

### Step 5: Manual Infrastructure Deployment (Alternative)

If the automated script fails, deploy components manually:

#### 5.1 Create GCS Bucket
```bash
# Load environment
source .env

# Create bucket
gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION gs://$GCS_BUCKET/

# Set public read access
gsutil iam ch allUsers:objectViewer gs://$GCS_BUCKET

# Enable CORS
cat > cors.json << EOF
[
  {
    "origin": ["*"],
    "method": ["GET", "HEAD"],
    "responseHeader": ["Content-Type", "Range"],
    "maxAgeSeconds": 3600
  }
]
EOF

gsutil cors set cors.json gs://$GCS_BUCKET
```

#### 5.2 Deploy TiTiler to Cloud Run
```bash
# Deploy TiTiler
gcloud run deploy $TITILER_SERVICE_NAME \
  --image $TITILER_IMAGE \
  --platform managed \
  --region $REGION \
  --allow-unauthenticated \
  --memory $TITILER_MEMORY \
  --cpu $TITILER_CPU \
  --concurrency $TITILER_CONCURRENCY \
  --max-instances $TITILER_MAX_INSTANCES \
  --min-instances $TITILER_MIN_INSTANCES \
  --set-env-vars GDAL_CACHEMAX=512,GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR \
  --timeout 300

# Get the service URL
gcloud run services describe $TITILER_SERVICE_NAME \
  --region $REGION \
  --format 'value(status.url)'
```

**Save the TiTiler URL** - you'll need it for Flutter configuration!

---

## 🗄️ Database Setup

### Step 1: Run Database Migrations

#### Option A: Via Supabase Dashboard (Recommended)

1. Go to **SQL Editor** in Supabase Dashboard
2. Create a new query
3. Copy contents of `supabase/sql/001_products_alter.sql`
4. Click **Run**
5. Repeat for `supabase/sql/002_productos_cog_migration.sql`

#### Option B: Via psql Command Line

```bash
# Get database connection string from Supabase Dashboard
# Settings > Database > Connection string (URI)

# Run migrations
psql "postgresql://postgres:[YOUR-PASSWORD]@db.xxxxx.supabase.co:5432/postgres" \
  -f supabase/sql/001_products_alter.sql

psql "postgresql://postgres:[YOUR-PASSWORD]@db.xxxxx.supabase.co:5432/postgres" \
  -f supabase/sql/002_productos_cog_migration.sql
```

### Step 2: Create Required Tables

If you don't have existing tables, create them:

```sql
-- Users table (if not exists)
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT UNIQUE NOT NULL,
  name TEXT,
  company TEXT,
  ingenio TEXT,
  country TEXT,
  activo BOOLEAN DEFAULT true,
  password_hash TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Productos table (raster metadata)
CREATE TABLE IF NOT EXISTS productos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa TEXT NOT NULL,
  ingenio TEXT NOT NULL,
  producto TEXT NOT NULL,
  fecha DATE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Parcelas_ingenios table (field parcels)
CREATE TABLE IF NOT EXISTS parcelas_ingenios (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company TEXT,
  ingenio TEXT,
  id_parcela TEXT,
  geometry_polygon JSONB,  -- GeoJSON Polygon
  area_calculada DECIMAL,
  temporada_activa BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Inspecciones table (field inspections)
CREATE TABLE IF NOT EXISTS inspecciones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company TEXT,
  ingenio TEXT,
  tipo_registro TEXT,
  fecha_creacion TIMESTAMPTZ DEFAULT now(),
  latitud DECIMAL,
  longitud DECIMAL,
  observaciones TEXT,
  foto_url TEXT
);
```

### Step 3: Verify Migration

```bash
# Run verification script
python3 scripts/verify_supabase.py

# Expected output:
# ✅ Connection successful
# ✅ productos table exists with COG columns
# ✅ Migration completed successfully
```

---

## 📊 Data Ingestion

### Step 1: Prepare Your Data

Your raster files should be:
- **Format**: GeoTIFF (.tif)
- **Projection**: Any (will be reprojected to EPSG:4326)
- **Single band**: Each product should have one band
- **Georeferenced**: Must have coordinate system information

**File Naming Convention:**
```
{producto}_{empresa}_{ingenio}_{fecha}.tif

Examples:
ndvi_AgroTech_Ingenio01_2024-01-15.tif
ndwi_AgroTech_Ingenio01_2024-01-15.tif
sg_AgroTech_Ingenio01_2024-01-15.tif
```

### Step 2: Ingest Single File (Test)

```bash
# Activate virtual environment
source venv/bin/activate

# Ingest a single file
python3 ingestion/ingest_product.py path/to/your_file.tif

# Example output:
# 🚀 Starting COG ingestion pipeline
# ✅ Converting to COG...
# ✅ Uploading to GCS...
# ✅ Updating Supabase metadata...
# 🎉 Successfully ingested: ndvi_2024-01-15.tif
```

**What happens:**
1. **Validation**: Checks file format and projection
2. **COG Conversion**: Uses GDAL to create Cloud Optimized GeoTIFF
3. **Upload**: Transfers to Google Cloud Storage
4. **Metadata**: Registers in Supabase database with bounds, min/max values, etc.

### Step 3: Batch Ingestion

For multiple files:

```bash
# Ingest all TIFFs in a directory
python3 ingestion/ingest_rasters.py /path/to/rasters/

# With progress bar:
# Processing files: 15/15 [████████████████████████████] 100%
# ✅ Successfully ingested: 15 files
# ❌ Failed: 0 files
```

### Step 4: Manual COG Conversion (Alternative)

If you prefer to convert files manually:

```bash
# Convert single file
./ingestion/convert_to_cog.sh input.tif output.cog.tif

# Upload to GCS
./ingestion/upload_to_gcs.sh output.cog.tif

# Update Supabase
python3 ingestion/update_supabase.py output.cog.tif \
  --empresa "AgroTech" \
  --ingenio "Ingenio01" \
  --producto "ndvi" \
  --fecha "2024-01-15"
```

### Step 5: Verify Data Ingestion

```bash
# Check GCS bucket
gsutil ls gs://$GCS_BUCKET/

# Check Supabase database (via SQL Editor)
SELECT
  producto,
  fecha,
  processing_status,
  cog_url
FROM productos
WHERE processing_status = 'completed'
ORDER BY fecha DESC;
```

---

## 📱 Flutter App Configuration

### Step 1: Update Constants

Edit `lib/constants.dart`:

```dart
// Supabase Configuration
const supabaseUrl = 'https://YOUR_PROJECT.supabase.co';  // ← Update this
const supabaseAnonKey = 'eyJhbGc...YOUR_ANON_KEY';        // ← Update this

// TiTiler Configuration
const String kTitilerBaseUrl = 'https://titiler-service-xxxxx.run.app';  // ← Update this

// Mapbox (optional - for satellite basemap)
const String mapboxAccessToken = 'pk.eyJ1...YOUR_TOKEN';  // ← Update or use default OSM

// Modern Raster Settings
const bool kUseModernTiles = true;  // Enable COG tiles
const bool kEnableHybridMode = true;  // Fallback to legacy WMS if needed
```

**Get Your TiTiler URL:**
```bash
# From deployment output, or run:
gcloud run services describe titiler-service \
  --region us-central1 \
  --format 'value(status.url)'
```

### Step 2: Install Flutter Dependencies

```bash
cd /path/to/techno_analytics
flutter pub get
```

### Step 3: Create Test User (if needed)

Run this in Supabase SQL Editor:

```sql
-- Create a test user
INSERT INTO users (email, name, company, ingenio, country, activo, password_hash)
VALUES (
  'test@example.com',
  'Test User',
  'AgroTech',  -- Must match your data
  'Ingenio01',  -- Must match your data
  'Guatemala',
  true,
  -- Password hash for 'password123' (use a real hash in production!)
  '$2b$10$...'
);
```

**Note**: For production, implement proper password hashing. The current implementation uses plain text (for demo only).

### Step 4: Build and Run

```bash
# Run on connected device/emulator
flutter run

# Build for production
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

---

## ✅ Testing & Verification

### Step 1: Test TiTiler Service

```bash
# Health check
curl https://YOUR_TITILER_URL/healthz

# Expected response:
# {"status": "ok"}

# Get COG info
curl "https://YOUR_TITILER_URL/cog/info?url=gs://YOUR_BUCKET/your_file.cog.tif"

# Expected response: JSON with bounds, min/max, bands, etc.
```

### Step 2: Test Tile Generation

```bash
# Generate a sample tile (zoom 10, tile x=100, y=200)
curl -o test_tile.png \
  "https://YOUR_TITILER_URL/cog/tiles/10/100/200.png?url=gs://YOUR_BUCKET/ndvi_2024-01-15.cog.tif&colormap_name=viridis&rescale=0,1"

# Verify file
file test_tile.png
# Expected: PNG image data, 256 x 256
```

### Step 3: Test Database Queries

In Supabase SQL Editor:

```sql
-- Check product count
SELECT COUNT(*) FROM productos WHERE processing_status = 'completed';

-- Get available dates for an ingenio
SELECT DISTINCT fecha
FROM productos
WHERE empresa = 'AgroTech'
  AND ingenio = 'Ingenio01'
  AND processing_status = 'completed'
ORDER BY fecha DESC;

-- Test the Flutter function
SELECT * FROM get_producto_info('AgroTech', 'Ingenio01', 'ndvi', '2024-01-15');
```

### Step 4: Test Flutter App

1. **Login**: Use test credentials
2. **Select filters**: Choose company, ingenio, date, product
3. **View map**: Check if raster tiles load correctly
4. **Check parcels**: Zoom in (≥ level 10) to see field boundaries
5. **Dashboard**: Verify charts and metrics display
6. **Weather**: Check weather widget shows current data

**Troubleshooting Tips:**
- Check browser console (for web) or Logcat (Android) for errors
- Verify TiTiler URL in constants.dart matches deployment
- Ensure Supabase credentials are correct
- Check network connectivity

---

## 💰 Cost Estimation

### Monthly Cost Breakdown (Small to Medium Scale)

| Service | Usage | Cost |
|---------|-------|------|
| **Google Cloud Storage** | 50GB COG files | $1-2 |
| **Cloud Run (TiTiler)** | ~10K requests/month, auto-scale 0-10 | $5-20 |
| **Cloud CDN** | 100GB egress (cached tiles) | $8-15 |
| **Load Balancer** | Basic forwarding | $5-7 |
| **Supabase** | Free tier or Pro ($25) | $0-25 |
| **TOTAL** | | **$20-70/month** |

### Cost Optimization Tips

1. **Enable CDN caching**: Reduces Cloud Run invocations (set TTL to 1 hour)
2. **Use free tier**: Supabase free tier supports up to 500MB database
3. **Lifecycle policies**: Archive old COG files to Nearline storage (50% cheaper)
4. **Set max instances**: Prevent runaway costs (default: 10)
5. **Monitor usage**: Set up budget alerts in GCP

### Cost Comparison

| Architecture | Monthly Cost | Notes |
|--------------|-------------|-------|
| **Legacy (GeoServer)** | $150-250 | Always-on VM, high maintenance |
| **Modern (COG + TiTiler)** | $20-70 | Auto-scaling, 75-85% savings |

---

## 🔧 Troubleshooting

### Issue 1: TiTiler Deployment Fails

**Error**: `Permission denied` or `API not enabled`

**Solution**:
```bash
# Enable required APIs
gcloud services enable run.googleapis.com
gcloud services enable cloudbuild.googleapis.com

# Check IAM permissions
gcloud projects get-iam-policy YOUR_PROJECT_ID
```

### Issue 2: Tiles Not Loading in Flutter

**Error**: Black squares or loading indefinitely

**Checklist**:
1. Verify TiTiler URL in `lib/constants.dart`
2. Check COG file is publicly accessible:
   ```bash
   gsutil ls -L gs://YOUR_BUCKET/file.cog.tif
   # Look for: ACL: allUsers:READER
   ```
3. Test tile URL manually:
   ```bash
   curl "https://TITILER_URL/cog/tiles/10/100/200.png?url=gs://BUCKET/file.cog.tif"
   ```
4. Check Flutter console for CORS errors

### Issue 3: Database Connection Errors

**Error**: `Connection refused` or `Authentication failed`

**Solution**:
1. Verify Supabase URL and keys in `.env` and `constants.dart`
2. Check Supabase project status (Settings > General)
3. Ensure database is not paused (free tier auto-pauses after 1 week inactivity)
4. Test connection:
   ```bash
   python3 scripts/verify_supabase.py
   ```

### Issue 4: COG Conversion Fails

**Error**: `gdal_translate: command not found`

**Solution**:
```bash
# Install GDAL
# Ubuntu/Debian
sudo apt-get install gdal-bin

# macOS
brew install gdal

# Verify
gdal_translate --version
```

### Issue 5: Out of Memory During Processing

**Error**: `MemoryError` or Cloud Run timeout

**Solution**:
1. Increase TiTiler memory:
   ```bash
   gcloud run services update titiler-service \
     --memory 4Gi \
     --region us-central1
   ```
2. Process large files in chunks (use `--tiled` in GDAL)
3. Reduce COG block size (change `COG_BLOCKSIZE=256` in `.env`)

### Issue 6: High Cloud Run Costs

**Symptoms**: Unexpected charges, many cold starts

**Solution**:
1. Enable Cloud CDN (cache tiles for 1 hour)
2. Set minimum instances to 0 (scale to zero when idle)
3. Check for request loops (app continuously fetching tiles)
4. Optimize tile requests (reduce zoom levels, limit pan extent)

### Issue 7: SSL Certificate Not Provisioning

**Error**: `NET::ERR_CERT_COMMON_NAME_INVALID`

**Solution**:
1. Wait up to 60 minutes for Google-managed SSL
2. Verify DNS records point to Load Balancer IP
3. Check certificate status:
   ```bash
   gcloud compute ssl-certificates list
   ```

---

## 📚 Next Steps

### Production Checklist

- [ ] Set up monitoring (Cloud Logging, Supabase Logs)
- [ ] Configure backup schedule for Supabase database
- [ ] Implement proper authentication (JWT, OAuth)
- [ ] Set up CI/CD pipeline (GitHub Actions, GitLab CI)
- [ ] Create staging environment
- [ ] Document data schema and API endpoints
- [ ] Set up error tracking (Sentry, Crashlytics)
- [ ] Enable HTTPS for custom domain
- [ ] Configure rate limiting on Cloud Run
- [ ] Implement data retention policies

### Scaling Considerations

**For 10,000+ users:**
- Upgrade Supabase to Pro plan ($25/month)
- Increase TiTiler max instances to 50-100
- Enable connection pooling (PgBouncer)
- Use Cloud SQL for production database (more control)
- Implement Redis caching layer
- Consider multi-region deployment

### Resources

- **Documentation**: `docs/README.md`
- **Architecture Deep Dive**: `docs/IMPLEMENTATION_SUMMARY.md`
- **Testing Guide**: `testing/README.md`
- **API Reference**: `docs/API.md`
- **TiTiler Docs**: [developmentseed.org/titiler](https://developmentseed.org/titiler/)
- **Supabase Docs**: [supabase.com/docs](https://supabase.com/docs)

---

## 🆘 Getting Help

- **Issues**: Open an issue on GitHub
- **Discussions**: Use GitHub Discussions for questions
- **Email**: support@yourdomain.com (update with your support email)

---

## 📄 License

[Add your license information here]

---

**Deployment Guide Version**: 1.0
**Last Updated**: 2024
**Maintained by**: [Your Team Name]

🎉 **Congratulations on deploying Techno Analytics!** 🎉
