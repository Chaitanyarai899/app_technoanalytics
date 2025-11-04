#!/bin/bash
# =============================================================================
# Complete Modern Raster Architecture Setup
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Banner
print_banner() {
    echo -e "${BLUE}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║  🚀 MODERN RASTER ARCHITECTURE SETUP                        ║
║     Cloud Optimized GeoTIFF + TiTiler on GCP                ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    for tool in gcloud gsutil gdal_translate python3; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Please install:"
        echo "• Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
        echo "• GDAL: https://gdal.org/download.html"
        echo "• Python 3: https://python.org"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 > /dev/null; then
        log_error "Not authenticated with Google Cloud"
        echo "Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Setup environment
setup_environment() {
    log_info "Setting up environment..."
    
    if [[ ! -f .env ]]; then
        if [[ -f .env.example ]]; then
            cp .env.example .env
            log_warning ".env file created from template"
            log_warning "Please edit .env with your configuration before continuing"
            echo ""
            echo "Required variables to set:"
            echo "• PROJECT_ID"
            echo "• GCS_BUCKET" 
            echo "• DOMAIN_NAME"
            echo "• SUPABASE_URL"
            echo "• SUPABASE_SERVICE_ROLE_KEY"
            echo ""
            read -p "Press Enter after editing .env file..."
        else
            log_error ".env.example not found"
            exit 1
        fi
    fi
    
    # Load environment variables
    source .env
    
    # Validate required variables
    local required_vars=(
        "PROJECT_ID"
        "GCS_BUCKET"
        "DOMAIN_NAME"
        "SUPABASE_URL"
        "SUPABASE_SERVICE_ROLE_KEY"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        exit 1
    fi
    
    log_success "Environment validated"
}

# Install Python dependencies
install_python_deps() {
    log_info "Installing Python dependencies..."
    
    # Create requirements.txt if it doesn't exist
    if [[ ! -f requirements.txt ]]; then
        cat > requirements.txt << EOF
supabase>=2.0.0
rasterio>=1.3.0
requests>=2.28.0
python-dotenv>=1.0.0
EOF
    fi
    
    # Check if we're in a virtual environment
    if [[ -z "${VIRTUAL_ENV:-}" ]]; then
        log_warning "Not in a virtual environment. Creating one..."
        python3 -m venv venv
        source venv/bin/activate
        log_success "Virtual environment created and activated"
    fi
    
    pip install -r requirements.txt
    log_success "Python dependencies installed"
}

# Deploy infrastructure step by step
deploy_infrastructure() {
    log_info "Deploying infrastructure components..."
    
    # Make scripts executable
    chmod +x infra/*.sh ingestion/*.sh
    
    # Step 1: Setup GCS
    log_info "Step 1/3: Setting up Google Cloud Storage..."
    if ./infra/gcs_setup.sh; then
        log_success "GCS setup completed"
    else
        log_error "GCS setup failed"
        return 1
    fi
    
    # Step 2: Deploy TiTiler
    log_info "Step 2/3: Deploying TiTiler service..."
    if ./infra/deploy_titiler.sh; then
        log_success "TiTiler deployment completed"
    else
        log_error "TiTiler deployment failed"
        return 1
    fi
    
    # Step 3: Setup CDN and Load Balancer
    log_info "Step 3/3: Setting up CDN and Load Balancer..."
    if ./infra/cdn_lb_setup.sh; then
        log_success "CDN and Load Balancer setup completed"
    else
        log_error "CDN setup failed"
        return 1
    fi
}

# Deploy database migration
deploy_database() {
    log_info "Deploying database migration..."
    
    # Check if psql is available
    if command -v psql &> /dev/null; then
        # Try to run migration via psql
        log_info "Running migration via psql..."
        # Note: User needs to provide connection details
        log_warning "Please run the following command manually with your database credentials:"
        echo "psql -h <your-db-host> -d postgres -f supabase/sql/001_products_alter.sql"
    else
        log_warning "psql not found. Please run migration manually:"
        echo "1. Connect to your Supabase database"
        echo "2. Execute: supabase/sql/001_products_alter.sql"
    fi
}

# Test the deployment
test_deployment() {
    log_info "Testing deployment..."
    
    # Test TiTiler health
    if [[ -f titiler_service_url.env ]]; then
        source titiler_service_url.env
        if curl -s -f "$TITILER_SERVICE_URL/healthz" > /dev/null; then
            log_success "TiTiler service is healthy"
        else
            log_error "TiTiler service health check failed"
        fi
    fi
    
    # Test GCS bucket
    if gsutil ls "gs://$GCS_BUCKET" > /dev/null 2>&1; then
        log_success "GCS bucket accessible"
    else
        log_error "GCS bucket not accessible"
    fi
    
    # Test domain (if CDN is setup)
    if [[ -f lb_config.env ]]; then
        source lb_config.env
        log_info "CDN URL: $TITILER_CDN_URL"
        log_warning "Note: SSL certificate may take up to 60 minutes to provision"
    fi
}

# Sample data ingestion
ingest_sample_data() {
    log_info "Setting up sample data ingestion..."
    
    # Create sample directory if it doesn't exist
    mkdir -p sample_data
    
    log_info "Sample data ingestion setup complete"
    log_info "To ingest data, run:"
    echo "  python3 ingestion/ingest_product.py path/to/your_file.tif"
}

# Flutter integration guide
show_flutter_guide() {
    log_info "Flutter integration next steps:"
    echo ""
    echo "1. Update lib/constants.dart:"
    echo "   const String kTitilerBaseUrl = 'https://$DOMAIN_NAME';"
    echo ""
    echo "2. Follow the integration guide:"
    echo "   cat flutter/snippets_modern_tiles.md"
    echo ""
    echo "3. Test the integration with:"
    echo "   flutter run"
}

# Main setup flow
main() {
    print_banner
    
    log_info "Starting modern raster architecture setup..."
    echo ""
    
    # Check if user wants to proceed
    read -p "This will setup the complete modern raster architecture. Continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Setup cancelled by user"
        exit 0
    fi
    
    echo ""
    
    # Run setup steps
    check_prerequisites
    setup_environment
    install_python_deps
    
    if deploy_infrastructure; then
        log_success "Infrastructure deployment completed!"
    else
        log_error "Infrastructure deployment failed"
        exit 1
    fi
    
    deploy_database
    test_deployment
    ingest_sample_data
    show_flutter_guide
    
    echo ""
    log_success "🎉 Modern raster architecture setup completed!"
    echo ""
    echo "📝 Next steps:"
    echo "1. Wait for SSL certificate provisioning (up to 60 minutes)"
    echo "2. Run database migration if not done automatically" 
    echo "3. Ingest your first COG file"
    echo "4. Update Flutter app configuration"
    echo ""
    echo "📊 Cost estimate: \$20-50/month (vs \$200/month legacy)"
    echo "📖 Full documentation: docs/README.md"
    echo ""
    log_info "Happy coding! 🚀"
}

# Handle script interruption
trap 'log_error "Setup interrupted by user"; exit 1' SIGINT SIGTERM

# Run main function
main "$@"
