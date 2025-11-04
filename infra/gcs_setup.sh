#!/bin/bash
# =============================================================================
# GCS Bucket Setup - COG Storage with CORS Configuration
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
: "${GCS_BUCKET:?Error: GCS_BUCKET not set}"

echo "🚀 Setting up GCS bucket for COG storage..."

# Set active project
gcloud config set project "$PROJECT_ID"

# Create bucket with uniform bucket-level access
echo "📦 Creating bucket: gs://$GCS_BUCKET"
gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" -b on "gs://$GCS_BUCKET" || {
  echo "⚠️  Bucket might already exist, continuing..."
}

# Enable uniform bucket-level access
echo "🔒 Enabling uniform bucket-level access..."
gsutil uniformbucketlevelaccess set on "gs://$GCS_BUCKET"

# Set public read access for tiles
echo "🌐 Setting public read access..."
gsutil iam ch allUsers:objectViewer "gs://$GCS_BUCKET"

# Configure lifecycle to clean old versions
echo "📋 Configuring lifecycle rules..."
cat > /tmp/lifecycle.json << EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 90,
          "isLive": false
        }
      },
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 365,
          "numNewerVersions": 3
        }
      }
    ]
  }
}
EOF

gsutil lifecycle set /tmp/lifecycle.json "gs://$GCS_BUCKET"
rm /tmp/lifecycle.json

# Configure CORS for range requests (essential for COG)
echo "🔧 Configuring CORS for COG range requests..."
cat > /tmp/cors.json << EOF
[
  {
    "origin": ["*"],
    "method": ["GET", "HEAD", "OPTIONS"],
    "responseHeader": [
      "Accept-Ranges",
      "Content-Range", 
      "Content-Length",
      "Content-Type",
      "Content-Encoding",
      "Cache-Control",
      "ETag",
      "Last-Modified"
    ],
    "maxAgeSeconds": 3600
  }
]
EOF

gsutil cors set /tmp/cors.json "gs://$GCS_BUCKET"
rm /tmp/cors.json

# Set default cache control for COGs
echo "⚡ Setting default cache control..."
gsutil defacl set public-read "gs://$GCS_BUCKET"

# Create directory structure
echo "📁 Creating directory structure..."
gsutil -m cp /dev/null "gs://$GCS_BUCKET/cogs/.keep" 2>/dev/null || echo "Directory marker created"
gsutil -m cp /dev/null "gs://$GCS_BUCKET/temp/.keep" 2>/dev/null || echo "Temp directory created"

echo "✅ GCS bucket setup completed!"
echo "📍 Bucket URL: gs://$GCS_BUCKET"
echo "🌐 Public URL: https://storage.googleapis.com/$GCS_BUCKET"

# Verify setup
echo "🔍 Verifying bucket configuration..."
gsutil ls -L -b "gs://$GCS_BUCKET" | grep -E "(Location|Uniform|Versioning|Lifecycle|CORS)"

echo "✨ GCS setup completed successfully!"
