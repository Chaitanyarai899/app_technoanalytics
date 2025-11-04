#!/bin/bash
# =============================================================================
# Cloud CDN + HTTPS Load Balancer Setup for TiTiler
# =============================================================================

set -euo pipefail

# Load environment variables
if [[ -f .env ]]; then
  source .env
fi

if [[ -f titiler_service_url.env ]]; then
  source titiler_service_url.env
fi

# Required variables check
: "${PROJECT_ID:?Error: PROJECT_ID not set}"
: "${REGION:?Error: REGION not set}"
: "${TITILER_SERVICE:?Error: TITILER_SERVICE not set}"
: "${DOMAIN_NAME:?Error: DOMAIN_NAME not set}"
: "${TITILER_SERVICE_URL:?Error: TITILER_SERVICE_URL not set}"

echo "🚀 Setting up Cloud CDN + HTTPS Load Balancer..."

# Set active project
gcloud config set project "$PROJECT_ID"

# Enable required APIs
echo "🔧 Enabling required APIs..."
gcloud services enable compute.googleapis.com

# Create serverless NEG for Cloud Run service
NEG_NAME="${TITILER_SERVICE}-neg"
echo "📡 Creating serverless NEG: $NEG_NAME"

gcloud compute network-endpoint-groups create "$NEG_NAME" \
  --region="$REGION" \
  --network-endpoint-type=serverless \
  --cloud-run-service="$TITILER_SERVICE" \
  --quiet || echo "⚠️  NEG might already exist"

# Create backend service with CDN enabled
BACKEND_SERVICE="${TITILER_SERVICE}-backend"
echo "🔄 Creating backend service with CDN: $BACKEND_SERVICE"

gcloud compute backend-services create "$BACKEND_SERVICE" \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --global \
  --enable-cdn \
  --cache-mode=CACHE_ALL_STATIC \
  --default-ttl="${CDN_TTL:-31536000}" \
  --max-ttl="${CDN_TTL:-31536000}" \
  --client-ttl="${TILE_CACHE_TTL:-86400}" \
  --quiet || echo "⚠️  Backend service might already exist"

# Configure cache key policy for tiles
echo "🔑 Configuring cache key policy..."
gcloud compute backend-services update "$BACKEND_SERVICE" \
  --cache-key-include-protocol \
  --cache-key-include-host \
  --cache-key-include-query-string \
  --cache-key-query-string-whitelist="url,rescale,colormap_name,colormap,color_formula,algorithm,algorithm_params,nodata,unscale,resampling,return_mask,coord_crs,dst_crs,width,height" \
  --global

# Add NEG to backend service
echo "🔗 Adding NEG to backend service..."
gcloud compute backend-services add-backend "$BACKEND_SERVICE" \
  --network-endpoint-group="$NEG_NAME" \
  --network-endpoint-group-region="$REGION" \
  --global

# Create URL map
URL_MAP="${TITILER_SERVICE}-url-map"
echo "🗺️  Creating URL map: $URL_MAP"

gcloud compute url-maps create "$URL_MAP" \
  --default-service="$BACKEND_SERVICE" \
  --global \
  --quiet || echo "⚠️  URL map might already exist"

# Create managed SSL certificate
SSL_CERT="${TITILER_SERVICE}-ssl-cert"
echo "🔒 Creating managed SSL certificate: $SSL_CERT"

gcloud compute ssl-certificates create "$SSL_CERT" \
  --domains="$DOMAIN_NAME" \
  --global \
  --quiet || echo "⚠️  SSL certificate might already exist"

# Create HTTPS proxy
HTTPS_PROXY="${TITILER_SERVICE}-https-proxy"
echo "🔐 Creating HTTPS proxy: $HTTPS_PROXY"

gcloud compute target-https-proxies create "$HTTPS_PROXY" \
  --url-map="$URL_MAP" \
  --ssl-certificates="$SSL_CERT" \
  --global \
  --quiet || echo "⚠️  HTTPS proxy might already exist"

# Reserve static IP
STATIC_IP="${TITILER_SERVICE}-ip"
echo "📍 Reserving static IP: $STATIC_IP"

gcloud compute addresses create "$STATIC_IP" \
  --ip-version=IPV4 \
  --global \
  --quiet || echo "⚠️  Static IP might already exist"

# Get the reserved IP
RESERVED_IP=$(gcloud compute addresses describe "$STATIC_IP" \
  --global \
  --format="value(address)")

echo "🌐 Reserved IP: $RESERVED_IP"

# Create forwarding rule
FORWARDING_RULE="${TITILER_SERVICE}-forwarding-rule"
echo "➡️  Creating forwarding rule: $FORWARDING_RULE"

gcloud compute forwarding-rules create "$FORWARDING_RULE" \
  --address="$STATIC_IP" \
  --target-https-proxy="$HTTPS_PROXY" \
  --global \
  --ports=443 \
  --quiet || echo "⚠️  Forwarding rule might already exist"

echo "✅ Load Balancer setup completed!"
echo "🌐 Domain: https://$DOMAIN_NAME"
echo "📍 IP Address: $RESERVED_IP"

# Save configuration
cat > lb_config.env << EOF
LOAD_BALANCER_IP=$RESERVED_IP
TITILER_CDN_URL=https://$DOMAIN_NAME
BACKEND_SERVICE=$BACKEND_SERVICE
URL_MAP=$URL_MAP
SSL_CERT=$SSL_CERT
EOF

echo "💾 Configuration saved to lb_config.env"

echo "⚠️  IMPORTANT DNS SETUP:"
echo "   Add the following DNS record to your domain:"
echo "   Type: A"
echo "   Name: $(echo "$DOMAIN_NAME" | cut -d'.' -f1)"
echo "   Value: $RESERVED_IP"
echo "   TTL: 300"

echo ""
echo "🔄 SSL Certificate Status:"
gcloud compute ssl-certificates describe "$SSL_CERT" \
  --global \
  --format="table(name,managed.status,managed.domainStatus)"

echo ""
echo "🧪 Testing endpoints (after DNS propagation):"
echo "   Health: https://$DOMAIN_NAME/healthz"
echo "   Info: https://$DOMAIN_NAME/cog/info?url=YOUR_COG_URL"
echo "   Tile: https://$DOMAIN_NAME/cog/tiles/10/512/512.png?url=YOUR_COG_URL"

echo "⏱️  Note: SSL certificate provisioning may take up to 60 minutes"
echo "🎯 Next step: Update TITILER_BASE_URL in .env to https://$DOMAIN_NAME"

echo "✨ CDN + Load Balancer setup completed!"
