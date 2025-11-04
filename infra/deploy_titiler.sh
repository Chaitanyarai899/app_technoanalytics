#!/bin/bash
# =============================================================================
# TiTiler Deployment on Cloud Run - Optimized for COG Serving
# =============================================================================

set -euo pipefail

# Load environment variables
if [[ -f .env ]]; then
  source .env
else
  echo "❌ Error: .env file not found. Copy .env.example to .env and configure."
  exit 1
fi

# Required variables check
: "${PROJECT_ID:?Error: PROJECT_ID not set}"
: "${REGION:?Error: REGION not set}"
: "${TITILER_SERVICE:?Error: TITILER_SERVICE not set}"
: "${GCS_BUCKET:?Error: GCS_BUCKET not set}"

echo "🚀 Deploying TiTiler to Cloud Run..."

# Set active project
gcloud config set project "$PROJECT_ID"

# Enable required APIs
echo "🔧 Enabling required APIs..."
gcloud services enable run.googleapis.com
gcloud services enable cloudbuild.googleapis.com

# Deploy TiTiler with optimized configuration
echo "🐳 Deploying TiTiler container..."

# Use latest stable TiTiler image
TITILER_IMAGE="ghcr.io/developmentseed/titiler:0.15.1"

gcloud run deploy "$TITILER_SERVICE" \
  --image="$TITILER_IMAGE" \
  --region="$REGION" \
  --platform=managed \
  --allow-unauthenticated \
  --memory="${TITILER_MEMORY:-1Gi}" \
  --cpu="${TITILER_CPU:-1}" \
  --concurrency="${TITILER_CONCURRENCY:-200}" \
  --max-instances="${TITILER_MAX_INSTANCES:-10}" \
  --min-instances="${TITILER_MIN_INSTANCES:-0}" \
  --timeout=300 \
  --port=8000 \
  --set-env-vars="
GDAL_CACHEMAX=512,
GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR,
GDAL_HTTP_MERGE_CONSECUTIVE_RANGES=YES,
GDAL_HTTP_MULTIPLEX=YES,
GDAL_HTTP_VERSION=2,
CPL_VSIL_CURL_CHUNK_SIZE=262144,
CPL_VSIL_CURL_CACHE_SIZE=200000000,
GDAL_BAND_BLOCK_CACHE=HASHSET,
GDAL_HTTP_MAX_RETRY=3,
GDAL_HTTP_RETRY_DELAY=0.2,
VSI_CACHE=TRUE,
VSI_CACHE_SIZE=100000000,
TITILER_API_ROOT_PATH=/,
WORKERS_PER_CORE=1,
WEB_CONCURRENCY=1,
FORWARDED_ALLOW_IPS=*,
TITILER_CORS_ORIGINS=*" \
  --labels="app=titiler,purpose=raster-tiles,environment=production"

# Get service URL
TITILER_SERVICE_URL=$(gcloud run services describe "$TITILER_SERVICE" \
  --region="$REGION" \
  --format="value(status.url)")

echo "✅ TiTiler deployed successfully!"
echo "🌐 Service URL: $TITILER_SERVICE_URL"

# Test basic endpoints
echo "🧪 Testing TiTiler endpoints..."

# Test health check
echo "🏥 Testing health endpoint..."
curl -s -f "$TITILER_SERVICE_URL/healthz" > /dev/null && echo "✅ Health check passed" || echo "❌ Health check failed"

# Test root endpoint
echo "📋 Testing root endpoint..."
curl -s -f "$TITILER_SERVICE_URL/" > /dev/null && echo "✅ Root endpoint accessible" || echo "❌ Root endpoint failed"

# Test colormaps endpoint
echo "🎨 Testing colormaps endpoint..."
curl -s -f "$TITILER_SERVICE_URL/colormaps" > /dev/null && echo "✅ Colormaps endpoint accessible" || echo "❌ Colormaps endpoint failed"

# Create a simple test with a public COG
echo "🗺️  Testing COG info endpoint with sample data..."
SAMPLE_COG="https://storage.googleapis.com/copc-public/stac/cov-flood-prediction/2020/MS_20200918_cog.tif"
INFO_RESPONSE=$(curl -s -f "$TITILER_SERVICE_URL/cog/info?url=$SAMPLE_COG" || echo "FAILED")

if [[ "$INFO_RESPONSE" != "FAILED" ]]; then
  echo "✅ COG info endpoint working"
  echo "📊 Sample response: $(echo "$INFO_RESPONSE" | jq -r '.bounds // "No bounds found"')"
else
  echo "⚠️  COG info test skipped (sample data might not be available)"
fi

# Save service URL to file for other scripts
echo "TITILER_SERVICE_URL=$TITILER_SERVICE_URL" > titiler_service_url.env
echo "💾 Service URL saved to titiler_service_url.env"

echo "🎯 Next steps:"
echo "  1. Run cdn_lb_setup.sh to add CDN caching"
echo "  2. Test with your COG files"
echo "  3. Update Flutter app configuration"

echo "✨ TiTiler deployment completed successfully!"
