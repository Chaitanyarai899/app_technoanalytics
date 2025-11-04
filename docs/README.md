# 🚀 Modern Raster Architecture for Techno Analytics

This project migrates from expensive GeoServer WMS to a modern, cost-effective Cloud Optimized GeoTIFF (COG) + TiTiler architecture on Google Cloud Platform.

## 📋 Architecture Overview

### Before: Legacy WMS
- **GeoServer** on GCP → $200/month + downtime issues
- **WMS tiles** → Heavy processing per request
- **Monolithic** → Single point of failure

### After: Modern COG + TiTiler
- **Cloud Optimized GeoTIFF** (COG) in Google Cloud Storage
- **TiTiler** on Cloud Run → Scales to zero, ~$20-50/month
- **Cloud CDN** → Fast global delivery with caching
- **Flutter app** → Seamless fallback WMS ↔ COG tiles

## 🏗️ Infrastructure Components

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Flutter App   │───→│   Cloud CDN      │───→│   TiTiler       │
│                 │    │   (Cache tiles)  │    │   (Cloud Run)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                         │
                                                         ▼
                                               ┌─────────────────┐
                                               │   COG Files     │
                                               │   (Cloud        │
                                               │    Storage)     │
                                               └─────────────────┘
                                                         ▲
                                                         │
                                               ┌─────────────────┐
                                               │   Supabase DB   │
                                               │   (Metadata)    │
                                               └─────────────────┘
```

## 🚀 Quick Start

### 1. Prerequisites

```bash
# Install required tools
gcloud auth login
gsutil --version
gdal-translate --version
python3 --version

# Clone and setup
git clone <repository>
cd techno_analytics
cp .env.example .env
```

### 2. Configure Environment

Edit `.env` with your settings:

```bash
# GCP Configuration
PROJECT_ID=your-gcp-project-id
REGION=us-central1
GCS_BUCKET=ta-cogs-prod
DOMAIN_NAME=tiles.yourdomain.com

# Supabase Configuration  
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

### 3. Deploy Infrastructure

```bash
# Setup Google Cloud Storage
./infra/gcs_setup.sh

# Deploy TiTiler service
./infra/deploy_titiler.sh

# Setup CDN and Load Balancer
./infra/cdn_lb_setup.sh

# (Optional) Deploy MapProxy for WMS compatibility
./infra/deploy_mapproxy.sh
```

### 4. Database Migration

```bash
# Run Supabase migration
psql -h your-db-host -d postgres -f supabase/sql/001_products_alter.sql
```

### 5. Ingest Sample Data

```bash
# Convert and upload a sample TIF
python3 ingestion/ingest_product.py sample_data/mx_gp_Huixtla_ndvi_20250426.tif

# Batch process multiple files
python3 ingestion/ingest_product.py *.tif --output-json results.json
```

### 6. Update Flutter App

Update `lib/constants.dart`:

```dart
const String kTitilerBaseUrl = 'https://tiles.yourdomain.com';
const bool kUseModernTiles = true;
```

See `flutter/snippets_modern_tiles.md` for detailed integration steps.

## 📊 Cost Comparison

| Component | Legacy (Monthly) | Modern (Monthly) |
|-----------|------------------|------------------|
| Compute | $150 (always-on VM) | $10-30 (Cloud Run) |
| Storage | $20 (VM disk) | $5-10 (Cloud Storage) |
| Bandwidth | $30 (egress) | $5-15 (CDN cached) |
| **Total** | **~$200** | **~$20-55** |

*Estimated costs for medium traffic (100k-500k tile requests/month)*

## 📁 Project Structure

```
├── infra/                   # Infrastructure scripts
│   ├── gcs_setup.sh        # Google Cloud Storage setup
│   ├── deploy_titiler.sh   # TiTiler deployment
│   ├── cdn_lb_setup.sh     # CDN + Load Balancer
│   └── monitoring.md       # Observability setup
├── ingestion/              # Data processing pipeline
│   ├── convert_to_cog.sh   # GDAL COG conversion
│   ├── upload_to_gcs.sh    # GCS upload with metadata
│   ├── update_supabase.py  # Database metadata update
│   └── ingest_product.py   # End-to-end orchestration
├── supabase/               # Database migrations
│   └── sql/
│       ├── 001_products_alter.sql
│       └── 002_products_views.sql
├── flutter/                # App integration guides
│   └── snippets_modern_tiles.md
├── docs/                   # Documentation
├── .env.example           # Environment template
└── README.md              # This file
```

## 🔧 Data Processing Pipeline

### File Naming Convention

Input TIF files should follow this pattern:
```
{country}_{company}_{ingenio}_{product}_{date}.tif
Example: mx_gp_Huixtla_ndvi_20250426.tif
```

### Processing Steps

1. **TIF → COG**: Convert to Cloud Optimized GeoTIFF with overviews
2. **Upload**: Store in Google Cloud Storage with metadata
3. **Database**: Update Supabase with COG URL and raster statistics
4. **Tiles**: TiTiler serves tiles on-demand with caching

### Batch Processing

```bash
# Process all TIF files in directory
find /path/to/tifs -name "*.tif" | \
  xargs python3 ingestion/ingest_product.py

# With parallel processing (future)
python3 ingestion/ingest_product.py *.tif --parallel 4
```

## 🎨 Colormap Configuration

### Default Colormaps

| Product | Colormap | Range |
|---------|----------|-------|
| NDVI | ndvi | 0.0 - 1.0 |
| NDWI | ndwi | -0.75 - 0.5 |
| SG | sg | 20 - 100 |
| Maleza | maleza | 1 - 5 |
| Potencial | potencial | 0 - 4 |

### Custom Colormaps

Add to TiTiler or define in `constants.dart`:

```dart
const Map<String, List<double>> kProductRescaleDefaults = {
  'custom_product': [0.0, 255.0],
};
```

## 🔍 Monitoring & Observability

### Health Checks

```bash
# TiTiler health
curl https://tiles.yourdomain.com/healthz

# CDN cache status
curl -I https://tiles.yourdomain.com/cog/tiles/10/512/512.png?url=...

# Database connectivity
psql -h your-db-host -c "SELECT COUNT(*) FROM productos WHERE cog_url IS NOT NULL;"
```

### Key Metrics

- **CDN Hit Ratio**: Should be >90% after warmup
- **TiTiler Response Time**: <2s for tile requests
- **Storage Costs**: Monitor GCS usage trends
- **Error Rates**: Track 4xx/5xx from TiTiler

### Alerting

Setup alerts for:
- TiTiler service availability
- CDN hit ratio drops
- Storage quota limits
- Database connection failures

## 🚨 Troubleshooting

### Common Issues

#### COG tiles not loading
```bash
# Check TiTiler health
curl https://tiles.yourdomain.com/healthz

# Verify COG accessibility
curl -I "https://storage.googleapis.com/your-bucket/cogs/file_cog.tif"

# Test tile generation
curl "https://tiles.yourdomain.com/cog/info?url=https://storage.googleapis.com/your-bucket/cogs/file_cog.tif"
```

#### SSL certificate issues
```bash
# Check certificate status
gcloud compute ssl-certificates describe your-ssl-cert --global

# DNS propagation
nslookup tiles.yourdomain.com
```

#### Database connection errors
```bash
# Test Supabase connectivity
curl -H "apikey: your-anon-key" "https://your-project.supabase.co/rest/v1/productos?limit=1"
```

### Performance Optimization

#### COG Optimization
```bash
# Check COG validation
rio cogeo validate your_file_cog.tif

# Add more overviews for large files
gdaladdo -r nearest your_file_cog.tif 2 4 8 16 32
```

#### CDN Cache Tuning
```bash
# Check cache headers
curl -I "https://tiles.yourdomain.com/cog/tiles/10/512/512.png?url=..."

# Update cache TTL
gcloud compute backend-services update your-backend --cache-key-include-query-string
```

## 🔄 Migration Strategy

### Phase 1: Parallel Testing
- Deploy modern infrastructure
- Ingest subset of products
- Test Flutter app with feature flags
- Compare performance vs WMS

### Phase 2: Gradual Migration
- Migrate products by priority (NDVI first)
- Monitor costs and performance
- Keep WMS as fallback

### Phase 3: Full Migration
- Migrate all products
- Optimize CDN settings
- Decommission legacy GeoServer

### Rollback Plan
- Flutter app supports immediate WMS fallback
- Keep legacy infrastructure during transition
- Database migration is non-destructive

## 📈 Scaling Considerations

### Traffic Growth
- **CDN**: Automatically handles global scaling
- **TiTiler**: Increase Cloud Run max instances
- **Storage**: GCS scales transparently

### Cost Optimization
- **CDN**: Use Cloud CDN for high traffic, Cloudflare for lower
- **TiTiler**: Fine-tune memory/CPU allocation
- **Storage**: Use lifecycle policies for old versions

### High Availability
- **Multi-region**: Deploy TiTiler in multiple regions
- **Monitoring**: Setup comprehensive alerting
- **Backup**: Regular database backups via Supabase

## 🤝 Contributing

### Development Setup
```bash
# Setup development environment
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Run tests
python3 -m pytest tests/

# Lint code
flake8 ingestion/
```

### Adding New Features
1. Update `.env.example` with new variables
2. Add infrastructure scripts to `infra/`
3. Update Flutter integration guide
4. Add tests and documentation

## 📝 License

MIT License - see LICENSE file for details.

## 🆘 Support

For issues and questions:
1. Check troubleshooting section above
2. Review logs in Cloud Console
3. Open GitHub issue with:
   - Error logs
   - Environment details
   - Steps to reproduce

---

**Next Steps:**
1. 🚀 Run `./infra/gcs_setup.sh` to get started
2. 📖 Read `flutter/snippets_modern_tiles.md` for app integration
3. 🔄 Process your first COG with `ingestion/ingest_product.py`
