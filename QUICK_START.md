# ⚡ Techno Analytics - Quick Start Deployment

**Time Required**: 1-2 hours | **Cost**: $20-50/month

---

## 📋 Prerequisites Checklist

- [ ] Google Cloud account with billing enabled
- [ ] Supabase account (free tier works)
- [ ] Google Cloud SDK installed (`gcloud`)
- [ ] GDAL installed (`gdal_translate`)
- [ ] Python 3.8+ installed
- [ ] Flutter SDK 3.0+ (for app development)

---

## 🚀 30-Second Setup

```bash
# 1. Clone repository
git clone https://github.com/YOUR_USERNAME/techno_analytics.git
cd techno_analytics

# 2. Configure environment
cp config/.env.example .env
nano .env  # Edit with your credentials

# 3. Run automated deployment
./deployment/setup.sh

# Done! ✅
```

---

## 📝 Step-by-Step Guide

### 1. Create Google Cloud Project (5 min)

```bash
# Login to GCP
gcloud auth login

# Create project
gcloud projects create YOUR-PROJECT-ID --name="Techno Analytics"
gcloud config set project YOUR-PROJECT-ID

# Enable billing (via console.cloud.google.com/billing)

# Enable APIs
gcloud services enable run.googleapis.com storage.googleapis.com compute.googleapis.com cloudbuild.googleapis.com
```

### 2. Create Supabase Project (3 min)

1. Go to [supabase.com](https://supabase.com) → New Project
2. Name: `techno-analytics`
3. Choose region closest to your users
4. Generate & save database password
5. Copy **Project URL** and **API Keys** from Settings → API

### 3. Configure Environment (5 min)

Edit `.env` file:

```bash
# Required - Update these!
PROJECT_ID=your-gcp-project-id
GCS_BUCKET=your-company-ta-cogs-prod-12345  # Must be globally unique
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGc...your-key

# Optional - Defaults are fine
REGION=us-central1
TITILER_MEMORY=2Gi
TITILER_MAX_INSTANCES=10
```

### 4. Deploy Infrastructure (15 min)

```bash
# Make scripts executable
chmod +x deployment/setup.sh infra/*.sh ingestion/*.sh

# Install Python dependencies
python3 -m venv venv
source venv/bin/activate
pip install -r deployment/requirements.txt

# Deploy everything
./deployment/setup.sh
```

**What gets deployed:**
- ✅ Google Cloud Storage bucket
- ✅ TiTiler service (Cloud Run)
- ✅ CDN + Load Balancer
- ✅ IAM permissions

**Save the TiTiler URL** from output!

### 5. Setup Database (10 min)

In Supabase SQL Editor (Dashboard → SQL Editor):

```sql
-- Run migration 1
-- Copy/paste contents of: supabase/sql/001_products_alter.sql
-- Click "Run"

-- Run migration 2
-- Copy/paste contents of: supabase/sql/002_productos_cog_migration.sql
-- Click "Run"
```

**Create test tables** (if starting fresh):

```sql
-- Users table
CREATE TABLE users (
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

-- Productos table (migration adds COG columns automatically)
CREATE TABLE productos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa TEXT NOT NULL,
  ingenio TEXT NOT NULL,
  producto TEXT NOT NULL,
  fecha DATE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Parcelas table
CREATE TABLE parcelas_ingenios (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company TEXT,
  ingenio TEXT,
  id_parcela TEXT,
  geometry_polygon JSONB,
  area_calculada DECIMAL,
  temporada_activa BOOLEAN DEFAULT true
);

-- Create test user
INSERT INTO users (email, name, company, ingenio, country, activo)
VALUES ('test@example.com', 'Test User', 'AgroTech', 'Ingenio01', 'Guatemala', true);
```

### 6. Ingest Sample Data (10 min)

```bash
# Prepare your GeoTIFF files
# File naming: {producto}_{empresa}_{ingenio}_{date}.tif

# Ingest single file (test)
python3 ingestion/ingest_product.py path/to/ndvi_AgroTech_Ingenio01_2024-01-15.tif

# Ingest batch
python3 ingestion/ingest_rasters.py /path/to/rasters/

# Verify in Supabase SQL Editor
SELECT producto, fecha, processing_status, cog_url
FROM productos
WHERE processing_status = 'completed';
```

### 7. Configure Flutter App (5 min)

Edit `lib/constants.dart`:

```dart
// Update these 3 lines:
const supabaseUrl = 'https://YOUR_PROJECT.supabase.co';
const supabaseAnonKey = 'eyJhbGc...YOUR_ANON_KEY';
const String kTitilerBaseUrl = 'https://titiler-service-xxxxx.run.app';
```

### 8. Run the App (2 min)

```bash
# Install dependencies
flutter pub get

# Run on device/emulator
flutter run

# Build for release
flutter build apk --release  # Android
flutter build ios --release  # iOS
```

---

## ✅ Verification Checklist

### Infrastructure Tests

```bash
# Test TiTiler health
curl https://YOUR_TITILER_URL/healthz
# Expected: {"status": "ok"}

# Test GCS bucket
gsutil ls gs://YOUR_BUCKET/
# Should list uploaded COG files

# Test tile generation
curl -o test.png "https://YOUR_TITILER_URL/cog/tiles/10/100/200.png?url=gs://YOUR_BUCKET/file.cog.tif&colormap_name=viridis"
file test.png
# Expected: PNG image data, 256 x 256
```

### Database Tests

In Supabase SQL Editor:

```sql
-- Check tables exist
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public';

-- Check COG products
SELECT COUNT(*) FROM productos WHERE processing_status = 'completed';

-- Test Flutter function
SELECT * FROM get_producto_info('AgroTech', 'Ingenio01', 'ndvi', '2024-01-15');
```

### App Tests

- [ ] Login with test user
- [ ] Select company, ingenio, date, product from dropdowns
- [ ] Map displays satellite imagery
- [ ] Raster layer appears with colors
- [ ] Parcels visible when zoomed in (zoom ≥ 10)
- [ ] Dashboard shows charts and metrics
- [ ] Weather widget displays data

---

## 🐛 Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| **Tiles not loading** | Check TiTiler URL in `constants.dart` matches deployment |
| **Database errors** | Verify Supabase credentials, check project not paused |
| **Permission denied (GCP)** | Run `gcloud auth login` and enable required APIs |
| **GDAL not found** | Install: `apt-get install gdal-bin` or `brew install gdal` |
| **Out of memory** | Increase TiTiler memory: `gcloud run services update titiler-service --memory 4Gi` |
| **High costs** | Enable CDN caching, set max instances to 10 |

---

## 📊 Cost Breakdown

| Service | Monthly Cost |
|---------|-------------|
| Google Cloud Storage (50GB) | $1-2 |
| Cloud Run (TiTiler) | $5-20 |
| Cloud CDN | $8-15 |
| Load Balancer | $5-7 |
| Supabase | $0-25 |
| **TOTAL** | **$20-70** |

**Savings**: 75-85% vs legacy GeoServer architecture ($150-250/month)

---

## 📚 Resources

- **Full Guide**: [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
- **Architecture**: [docs/README.md](docs/README.md)
- **TiTiler Docs**: https://developmentseed.org/titiler/
- **Supabase Docs**: https://supabase.com/docs
- **GDAL Tutorial**: https://gdal.org/tutorials/

---

## 🎯 Next Steps

1. **Add your own data**: Ingest your GeoTIFF rasters
2. **Configure colormaps**: Edit `lib/constants.dart` → `kProductColormaps`
3. **Customize UI**: Modify Flutter widgets in `lib/views/`
4. **Set up monitoring**: Enable Cloud Logging and Supabase logs
5. **Production deployment**: Configure custom domain, SSL certificate
6. **Scale**: Increase max instances, upgrade Supabase plan

---

## 🆘 Get Help

- GitHub Issues: Report bugs and request features
- Documentation: See `DEPLOYMENT_GUIDE.md` for detailed instructions
- Community: Join discussions on GitHub

---

**Quick Start Version**: 1.0
**Last Updated**: 2024

✨ **You're ready to deploy!** ✨
