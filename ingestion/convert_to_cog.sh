#!/bin/bash
# =============================================================================
# Convert GeoTIFF to Cloud Optimized GeoTIFF (COG)
# =============================================================================

set -euo pipefail

# Load environment variables
if [[ -f .env ]]; then
  source .env
fi

# Default values
COG_COMPRESS="${COG_COMPRESS:-DEFLATE}"
COG_PREDICTOR="${COG_PREDICTOR:-2}"
COG_BIGTIFF="${COG_BIGTIFF:-AUTO}"
COG_OVERVIEW_RESAMPLING="${COG_OVERVIEW_RESAMPLING:-NEAREST}"

# Function to show usage
usage() {
  cat << EOF
Usage: $0 <input_tif> [output_cog]

Convert a GeoTIFF to Cloud Optimized GeoTIFF (COG)

Arguments:
  input_tif     Path to input GeoTIFF file
  output_cog    Path to output COG file (optional, defaults to input_cog.tif)

Environment variables:
  COG_COMPRESS            Compression type (default: DEFLATE)
  COG_PREDICTOR          Predictor for compression (default: 2)
  COG_BIGTIFF            BigTIFF setting (default: AUTO)
  COG_OVERVIEW_RESAMPLING Overview resampling method (default: NEAREST)

Examples:
  $0 mx_gp_Huixtla_ndvi_20250426.tif
  $0 input.tif output_cog.tif
EOF
}

# Check arguments
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

INPUT_TIF="$1"
if [[ $# -ge 2 ]]; then
  OUTPUT_COG="$2"
else
  # Generate output filename
  OUTPUT_COG="${INPUT_TIF%.*}_cog.tif"
fi

# Validate input file
if [[ ! -f "$INPUT_TIF" ]]; then
  echo "❌ Error: Input file '$INPUT_TIF' not found"
  exit 1
fi

echo "🔄 Converting to COG: $INPUT_TIF -> $OUTPUT_COG"

# Check if GDAL is available
if ! command -v gdal_translate &> /dev/null; then
  echo "❌ Error: GDAL not found. Please install GDAL tools"
  echo "   Ubuntu/Debian: sudo apt-get install gdal-bin"
  echo "   macOS: brew install gdal"
  echo "   Windows: Use OSGeo4W or conda"
  exit 1
fi

# Get input file info
echo "📊 Analyzing input file..."
INPUT_INFO=$(gdalinfo "$INPUT_TIF" 2>/dev/null || echo "ERROR")
if [[ "$INPUT_INFO" == "ERROR" ]]; then
  echo "❌ Error: Could not read input file. Is it a valid GeoTIFF?"
  exit 1
fi

# Extract basic metadata
SIZE_X=$(echo "$INPUT_INFO" | grep "Size is" | cut -d' ' -f3 | tr -d ',')
SIZE_Y=$(echo "$INPUT_INFO" | grep "Size is" | cut -d' ' -f4)
BANDS=$(echo "$INPUT_INFO" | grep -c "Band [0-9]")
DATATYPE=$(echo "$INPUT_INFO" | grep "Band 1" -A1 | grep "Type=" | cut -d'=' -f2 | cut -d',' -f1 || echo "Unknown")

echo "📏 Input file info:"
echo "   Size: ${SIZE_X}x${SIZE_Y}"
echo "   Bands: $BANDS"
echo "   Data type: $DATATYPE"

# Determine optimal settings based on data type and size
TILE_SIZE=512
if [[ $SIZE_X -gt 10000 || $SIZE_Y -gt 10000 ]]; then
  TILE_SIZE=1024
fi

# Calculate number of overview levels
MAX_DIM=$((SIZE_X > SIZE_Y ? SIZE_X : SIZE_Y))
OVERVIEW_LEVELS=$(python3 -c "
import math
max_dim = $MAX_DIM
tile_size = $TILE_SIZE
levels = max(1, int(math.log2(max_dim / tile_size)) + 1)
print(min(levels, 6))  # Cap at 6 levels
" 2>/dev/null || echo "4")

echo "🔧 COG settings:"
echo "   Compression: $COG_COMPRESS"
echo "   Predictor: $COG_PREDICTOR"
echo "   Tile size: ${TILE_SIZE}x${TILE_SIZE}"
echo "   Overview levels: $OVERVIEW_LEVELS"
echo "   BigTIFF: $COG_BIGTIFF"

# Build GDAL command
GDAL_CMD=(
  gdal_translate
  -of COG
  -co "COMPRESS=$COG_COMPRESS"
  -co "PREDICTOR=$COG_PREDICTOR"
  -co "BLOCKSIZE=$TILE_SIZE"
  -co "BIGTIFF=$COG_BIGTIFF"
  -co "NUM_THREADS=ALL_CPUS"
  -co "OVERVIEW_RESAMPLING=$COG_OVERVIEW_RESAMPLING"
  -co "OVERVIEW_COUNT=$OVERVIEW_LEVELS"
)

# Add specific optimizations based on data type
if [[ "$DATATYPE" == "Byte" ]]; then
  GDAL_CMD+=(-co "NBITS=8")
elif [[ "$DATATYPE" == "UInt16" ]]; then
  GDAL_CMD+=(-co "NBITS=16")
fi

# Add input and output
GDAL_CMD+=("$INPUT_TIF" "$OUTPUT_COG")

# Execute conversion
echo "⚡ Running GDAL conversion..."
echo "Command: ${GDAL_CMD[*]}"

if "${GDAL_CMD[@]}"; then
  echo "✅ COG conversion completed successfully!"
else
  echo "❌ COG conversion failed!"
  exit 1
fi

# Validate the output COG
echo "🔍 Validating COG..."
if command -v rio &> /dev/null; then
  # Use rasterio if available
  if rio cogeo validate "$OUTPUT_COG" 2>/dev/null; then
    echo "✅ COG validation passed!"
  else
    echo "⚠️  COG validation warning (but file was created)"
  fi
else
  # Fallback to gdalinfo
  if gdalinfo "$OUTPUT_COG" | grep -q "Block="; then
    echo "✅ COG appears to be tiled correctly"
  else
    echo "⚠️  Warning: COG might not be properly tiled"
  fi
fi

# Show file sizes
INPUT_SIZE=$(du -h "$INPUT_TIF" | cut -f1)
OUTPUT_SIZE=$(du -h "$OUTPUT_COG" | cut -f1)

echo "📈 File size comparison:"
echo "   Input:  $INPUT_SIZE ($INPUT_TIF)"
echo "   Output: $OUTPUT_SIZE ($OUTPUT_COG)"

# Calculate compression ratio
INPUT_BYTES=$(stat -f%z "$INPUT_TIF" 2>/dev/null || stat -c%s "$INPUT_TIF" 2>/dev/null || echo "0")
OUTPUT_BYTES=$(stat -f%z "$OUTPUT_COG" 2>/dev/null || stat -c%s "$OUTPUT_COG" 2>/dev/null || echo "0")

if [[ $INPUT_BYTES -gt 0 && $OUTPUT_BYTES -gt 0 ]]; then
  RATIO=$(python3 -c "print(f'{$INPUT_BYTES / $OUTPUT_BYTES:.2f}')" 2>/dev/null || echo "N/A")
  echo "   Compression ratio: ${RATIO}x"
fi

echo "✨ COG conversion completed: $OUTPUT_COG"
