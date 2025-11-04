#!/usr/bin/env python3
"""
Update Supabase with COG metadata after successful upload
"""

import json
import hashlib
import os
import sys
from datetime import datetime
from pathlib import Path
import argparse
import subprocess
from typing import Dict, Optional, Tuple, List

try:
    import rasterio
    from rasterio.warp import transform_bounds
    HAS_RASTERIO = True
except ImportError:
    HAS_RASTERIO = False
    print("⚠️  Warning: rasterio not found. Install with: pip install rasterio")

try:
    from supabase import create_client, Client
    HAS_SUPABASE = True
except ImportError:
    HAS_SUPABASE = False
    print("❌ Error: supabase-py not found. Install with: pip install supabase")
    sys.exit(1)

def load_env_file(env_path: str = ".env") -> Dict[str, str]:
    """Load environment variables from .env file"""
    env_vars = {}
    if os.path.exists(env_path):
        with open(env_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key.strip()] = value.strip()
    return env_vars

def get_raster_metadata(file_path: str) -> Dict:
    """Extract metadata from raster file using rasterio or gdalinfo"""
    metadata = {
        'bounds': None,
        'epsg': 3857,
        'nodata': None,
        'min_value': None,
        'max_value': None,
        'width': None,
        'height': None,
        'bands': None
    }
    
    if HAS_RASTERIO:
        try:
            with rasterio.open(file_path) as src:
                # Get bounds in WGS84
                bounds = transform_bounds(src.crs, 'EPSG:4326', *src.bounds)
                metadata['bounds'] = list(bounds)  # [west, south, east, north]
                metadata['epsg'] = src.crs.to_epsg() if src.crs else 3857
                metadata['nodata'] = src.nodata
                metadata['width'] = src.width
                metadata['height'] = src.height
                metadata['bands'] = src.count
                
                # Calculate min/max values from first band
                try:
                    band_data = src.read(1, masked=True)
                    metadata['min_value'] = float(band_data.min())
                    metadata['max_value'] = float(band_data.max())
                except Exception as e:
                    print(f"⚠️  Could not calculate min/max values: {e}")
                    
        except Exception as e:
            print(f"⚠️  Could not read raster metadata with rasterio: {e}")
    
    # Fallback to gdalinfo if rasterio failed or not available
    if metadata['bounds'] is None:
        try:
            result = subprocess.run(['gdalinfo', '-json', file_path], 
                                  capture_output=True, text=True, check=True)
            gdalinfo = json.loads(result.stdout)
            
            # Extract bounds
            if 'wgs84Extent' in gdalinfo:
                coords = gdalinfo['wgs84Extent']['coordinates'][0]
                # Convert from polygon to bbox [west, south, east, north]
                lons = [coord[0] for coord in coords]
                lats = [coord[1] for coord in coords]
                metadata['bounds'] = [min(lons), min(lats), max(lons), max(lats)]
            
            # Extract other metadata
            if 'coordinateSystem' in gdalinfo and 'wkt' in gdalinfo['coordinateSystem']:
                # Try to extract EPSG from WKT
                wkt = gdalinfo['coordinateSystem']['wkt']
                if 'EPSG' in wkt:
                    import re
                    epsg_match = re.search(r'EPSG["\',](\d+)', wkt)
                    if epsg_match:
                        metadata['epsg'] = int(epsg_match.group(1))
            
            metadata['width'] = gdalinfo.get('size', [None])[0]
            metadata['height'] = gdalinfo.get('size', [None, None])[1]
            metadata['bands'] = len(gdalinfo.get('bands', []))
            
            # Get nodata value
            bands = gdalinfo.get('bands', [])
            if bands and 'noDataValue' in bands[0]:
                metadata['nodata'] = bands[0]['noDataValue']
                
        except Exception as e:
            print(f"⚠️  Could not read raster metadata with gdalinfo: {e}")
    
    return metadata

def calculate_sha256(file_path: str) -> str:
    """Calculate SHA256 hash of file"""
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        # Read in chunks to handle large files
        for chunk in iter(lambda: f.read(4096), b""):
            sha256_hash.update(chunk)
    return sha256_hash.hexdigest()

def get_file_size(file_path: str) -> int:
    """Get file size in bytes"""
    return os.path.getsize(file_path)

def parse_filename(filename: str) -> Dict[str, str]:
    """Parse filename to extract metadata
    Expected format: {pais}_{company}_{ingenio}_{producto}_{fecha}_cog.tif
    Example: mx_gp_Huixtla_ndvi_20250426_cog.tif
    """
    basename = Path(filename).stem
    parts = basename.replace('_cog', '').split('_')
    
    if len(parts) < 5:
        raise ValueError(f"Invalid filename format: {filename}")
    
    # Map company initials to full names
    company_mapping = {
        'gp': 'Grupo Porres',
        # Add more mappings as needed
    }
    
    pais = parts[0]
    company_initials = parts[1]
    company = company_mapping.get(company_initials, company_initials.upper())
    ingenio = parts[2]
    producto = parts[3]
    fecha = parts[4]
    
    # Format date as YYYY-MM-DD
    if len(fecha) == 8:  # YYYYMMDD
        formatted_fecha = f"{fecha[:4]}-{fecha[4:6]}-{fecha[6:8]}"
    else:
        formatted_fecha = fecha
    
    return {
        'pais': pais,
        'empresa': company,
        'ingenio': ingenio,
        'producto': producto,
        'fecha': formatted_fecha
    }

def get_palette_for_product(producto: str) -> str:
    """Get default palette for product type"""
    palette_mapping = {
        'ndvi': 'ndvi',
        'ndwi': 'ndwi', 
        'sg': 'sg',
        'maleza': 'maleza',
        'potencial': 'potencial',
        'potencial_ndvi': 'potencial',
        'potencial_ndwi': 'potencial'
    }
    return palette_mapping.get(producto.lower(), 'viridis')

def update_supabase_record(
    client: Client,
    table: str,
    product_info: Dict[str, str],
    cog_url: str,
    metadata: Dict,
    sha256: str,
    file_size: int
) -> Dict:
    """Update or insert record in Supabase"""
    
    # Prepare the data
    record_data = {
        'empresa': product_info['empresa'],
        'ingenio': product_info['ingenio'],
        'producto': product_info['producto'],
        'fecha': product_info['fecha'],
        'cog_url': cog_url,
        'bounds': metadata['bounds'],
        'epsg': metadata['epsg'],
        'nodata': metadata['nodata'],
        'min_value': metadata['min_value'],
        'max_value': metadata['max_value'],
        'palette': get_palette_for_product(product_info['producto']),
        'sha256': sha256,
        'file_size_bytes': file_size,
        'processing_status': 'completed',
        'cog_created_at': datetime.utcnow().isoformat(),
        'error_message': None
    }
    
    # Remove None values
    record_data = {k: v for k, v in record_data.items() if v is not None}
    
    try:
        # Try to upsert (insert or update)
        result = client.table(table).upsert(
            record_data,
            on_conflict='empresa,ingenio,producto,fecha'
        ).execute()
        
        if result.data:
            print(f"✅ Successfully updated record in {table}")
            return result.data[0]
        else:
            raise Exception("No data returned from upsert operation")
            
    except Exception as e:
        print(f"❌ Error updating Supabase: {e}")
        # Try to mark as error instead
        try:
            error_data = {
                'empresa': product_info['empresa'],
                'ingenio': product_info['ingenio'],
                'producto': product_info['producto'],
                'fecha': product_info['fecha'],
                'processing_status': 'error',
                'error_message': str(e)
            }
            client.table(table).upsert(error_data).execute()
            print(f"⚠️  Marked record as error in database")
        except:
            pass
        raise

def main():
    parser = argparse.ArgumentParser(description='Update Supabase with COG metadata')
    parser.add_argument('cog_file', help='Path to the COG file')
    parser.add_argument('cog_url', help='Public URL of the uploaded COG')
    parser.add_argument('--env-file', default='.env', help='Path to .env file')
    parser.add_argument('--table', help='Supabase table name (overrides env)')
    parser.add_argument('--force-metadata', action='store_true', 
                       help='Force metadata extraction even if file is large')
    
    args = parser.parse_args()
    
    # Load environment variables
    env_vars = load_env_file(args.env_file)
    
    # Override with environment variables
    for key, value in env_vars.items():
        if key not in os.environ:
            os.environ[key] = value
    
    # Get required environment variables
    supabase_url = os.getenv('SUPABASE_URL')
    supabase_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')
    table_name = args.table or os.getenv('SUPABASE_TABLE', 'productos')
    
    if not supabase_url or not supabase_key:
        print("❌ Error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (or SUPABASE_ANON_KEY) must be set")
        sys.exit(1)
    
    # Validate inputs
    if not os.path.exists(args.cog_file):
        print(f"❌ Error: COG file not found: {args.cog_file}")
        sys.exit(1)
    
    print(f"🔄 Processing COG metadata for: {args.cog_file}")
    
    try:
        # Parse filename to extract product information
        print("📝 Parsing filename...")
        product_info = parse_filename(args.cog_file)
        print(f"   Product: {product_info}")
        
        # Calculate file hash and size
        print("🔐 Calculating file hash and size...")
        sha256 = calculate_sha256(args.cog_file)
        file_size = get_file_size(args.cog_file)
        print(f"   SHA256: {sha256}")
        print(f"   Size: {file_size} bytes ({file_size / 1024 / 1024:.1f} MB)")
        
        # Extract raster metadata
        print("📊 Extracting raster metadata...")
        metadata = get_raster_metadata(args.cog_file)
        print(f"   Bounds: {metadata['bounds']}")
        print(f"   EPSG: {metadata['epsg']}")
        print(f"   Value range: {metadata['min_value']} - {metadata['max_value']}")
        
        # Connect to Supabase
        print("🔌 Connecting to Supabase...")
        client = create_client(supabase_url, supabase_key)
        
        # Update database
        print("💾 Updating database record...")
        record = update_supabase_record(
            client, table_name, product_info, args.cog_url, 
            metadata, sha256, file_size
        )
        
        # Output final record as JSON
        print("\n📋 Final record:")
        print(json.dumps(record, indent=2, default=str))
        
        print("✅ Successfully updated Supabase record!")
        
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
