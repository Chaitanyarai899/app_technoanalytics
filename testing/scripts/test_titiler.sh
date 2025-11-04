#!/bin/bash

# =============================================================================
# Test TiTiler Setup
# =============================================================================

echo "🧪 Testing TiTiler deployment..."

# URL del servicio TiTiler
TITILER_URL="https://ta-titiler-service-1087100331392.us-central1.run.app"

echo ""
echo "📍 TiTiler Service URL: $TITILER_URL"

# Test 1: Health check
echo ""
echo "🔍 Testing health endpoint..."
curl -s "$TITILER_URL/healthz" && echo " ✅ Health check passed" || echo " ❌ Health check failed"

# Test 2: Info endpoint
echo ""
echo "🔍 Testing info endpoint with sample COG..."
# Using a public COG for testing
SAMPLE_COG="https://storage.googleapis.com/pdd-stac/disasters/hurricane-harvey/hurricane-harvey-0831.tif"
curl -s "$TITILER_URL/cog/info?url=$SAMPLE_COG" | head -10

# Test 3: Tile endpoint
echo ""
echo "🔍 Testing tile generation..."
TILE_URL="$TITILER_URL/cog/tiles/WebMercatorQuad/8/67/97?url=$SAMPLE_COG"
echo "Tile URL: $TILE_URL"
curl -I "$TILE_URL" 2>/dev/null | head -5

echo ""
echo "🎉 TiTiler setup test completed!"
echo ""
echo "📝 Next steps:"
echo "1. Install Python and GDAL to process your raster files"
echo "2. Convert your TIF files to COG format"
echo "3. Upload COGs to GCS bucket: ta-cogs-apicorreo-prod"
echo "4. Test with your own data"
echo ""
echo "💡 Test the service in browser:"
echo "   Documentation: $TITILER_URL/docs"
echo "   Sample tile: $TILE_URL"
