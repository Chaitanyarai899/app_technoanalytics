#!/bin/bash
# =============================================================================
# Upload COG to Google Cloud Storage with optimized settings
# =============================================================================

set -euo pipefail

# Load environment variables
if [[ -f .env ]]; then
  source .env
fi

# Required variables check
: "${GCS_BUCKET:?Error: GCS_BUCKET not set}"

# Function to show usage
usage() {
  cat << EOF
Usage: $0 <cog_file> [destination_path]

Upload a Cloud Optimized GeoTIFF to Google Cloud Storage

Arguments:
  cog_file         Path to the COG file to upload
  destination_path Optional destination path in bucket (defaults to cogs/filename)

Environment variables:
  GCS_BUCKET       Google Cloud Storage bucket name

Examples:
  $0 mx_gp_Huixtla_ndvi_20250426_cog.tif
  $0 file_cog.tif custom/path/file_cog.tif
EOF
}

# Check arguments
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

COG_FILE="$1"
if [[ $# -ge 2 ]]; then
  DESTINATION_PATH="$2"
else
  # Generate destination path
  FILENAME=$(basename "$COG_FILE")
  DESTINATION_PATH="cogs/$FILENAME"
fi

# Validate input file
if [[ ! -f "$COG_FILE" ]]; then
  echo "❌ Error: COG file '$COG_FILE' not found"
  exit 1
fi

# Check if gsutil is available
if ! command -v gsutil &> /dev/null; then
  echo "❌ Error: gsutil not found. Please install Google Cloud SDK"
  echo "   Visit: https://cloud.google.com/sdk/docs/install"
  exit 1
fi

# Verify bucket access
echo "🔍 Verifying bucket access..."
if ! gsutil ls "gs://$GCS_BUCKET/" > /dev/null 2>&1; then
  echo "❌ Error: Cannot access bucket gs://$GCS_BUCKET"
  echo "   Check if bucket exists and you have proper permissions"
  exit 1
fi

echo "📤 Uploading COG to GCS..."
echo "   Source: $COG_FILE"
echo "   Destination: gs://$GCS_BUCKET/$DESTINATION_PATH"

# Get file info
FILE_SIZE=$(du -h "$COG_FILE" | cut -f1)
echo "   File size: $FILE_SIZE"

# Calculate SHA256 for integrity check
echo "🔐 Calculating SHA256 hash..."
if command -v sha256sum &> /dev/null; then
  SHA256=$(sha256sum "$COG_FILE" | cut -d' ' -f1)
elif command -v shasum &> /dev/null; then
  SHA256=$(shasum -a 256 "$COG_FILE" | cut -d' ' -f1)
else
  echo "⚠️  Warning: No SHA256 utility found, skipping hash calculation"
  SHA256=""
fi

if [[ -n "$SHA256" ]]; then
  echo "   SHA256: $SHA256"
fi

# Upload with optimized settings
echo "⚡ Starting upload..."

# Use parallel upload for large files and set optimal metadata
gsutil -m cp \
  -n \
  "$COG_FILE" \
  "gs://$GCS_BUCKET/$DESTINATION_PATH"

# Set object metadata for optimal COG serving
echo "🔧 Setting object metadata..."

# Set Content-Type for proper MIME type
gsutil setmeta \
  -h "Content-Type:image/tiff" \
  "gs://$GCS_BUCKET/$DESTINATION_PATH"

# Set Cache-Control for long-term caching (COGs are immutable)
gsutil setmeta \
  -h "Cache-Control:public, max-age=31536000, immutable" \
  "gs://$GCS_BUCKET/$DESTINATION_PATH"

# Set custom metadata if SHA256 was calculated
if [[ -n "$SHA256" ]]; then
  gsutil setmeta \
    -h "x-goog-meta-sha256:$SHA256" \
    "gs://$GCS_BUCKET/$DESTINATION_PATH"
fi

# Add upload timestamp
UPLOAD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
gsutil setmeta \
  -h "x-goog-meta-upload-time:$UPLOAD_TIME" \
  "gs://$GCS_BUCKET/$DESTINATION_PATH"

echo "✅ Upload completed successfully!"

# Generate public URL
PUBLIC_URL="https://storage.googleapis.com/$GCS_BUCKET/$DESTINATION_PATH"
echo "🌐 Public URL: $PUBLIC_URL"

# Verify upload integrity if possible
echo "🔍 Verifying upload..."
REMOTE_SIZE=$(gsutil stat "gs://$GCS_BUCKET/$DESTINATION_PATH" | grep "Content-Length" | awk '{print $2}' || echo "0")
LOCAL_SIZE=$(stat -f%z "$COG_FILE" 2>/dev/null || stat -c%s "$COG_FILE" 2>/dev/null || echo "0")

if [[ "$REMOTE_SIZE" == "$LOCAL_SIZE" ]]; then
  echo "✅ Size verification passed"
else
  echo "⚠️  Warning: Size mismatch (local: $LOCAL_SIZE, remote: $REMOTE_SIZE)"
fi

# Test if file is accessible via HTTP
echo "🌐 Testing HTTP access..."
if curl -s -I --fail "$PUBLIC_URL" > /dev/null; then
  echo "✅ HTTP access verified"
else
  echo "⚠️  Warning: HTTP access test failed (might take a moment to propagate)"
fi

# Output structured data for further processing
cat << EOF

📋 Upload Summary:
{
  "cog_url": "$PUBLIC_URL",
  "gcs_path": "gs://$GCS_BUCKET/$DESTINATION_PATH",
  "sha256": "$SHA256",
  "file_size_bytes": $LOCAL_SIZE,
  "upload_time": "$UPLOAD_TIME",
  "status": "completed"
}
EOF

echo "✨ COG upload completed: $PUBLIC_URL"
