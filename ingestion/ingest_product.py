#!/usr/bin/env python3
"""
Complete COG ingestion pipeline: TIF → COG → GCS → Supabase
"""

import os
import sys
import subprocess
import tempfile
import shutil
from pathlib import Path
import argparse
import json
from datetime import datetime

def run_command(cmd, description=""):
    """Run shell command with error handling"""
    if description:
        print(f"🔄 {description}")
    
    print(f"   Command: {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    
    try:
        if isinstance(cmd, str):
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True)
        else:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        
        if result.stdout.strip():
            print(f"   Output: {result.stdout.strip()}")
        
        return result
    except subprocess.CalledProcessError as e:
        print(f"❌ Error in {description}: {e}")
        if e.stdout:
            print(f"   Stdout: {e.stdout}")
        if e.stderr:
            print(f"   Stderr: {e.stderr}")
        raise

def validate_environment():
    """Validate required environment variables and tools"""
    required_env_vars = [
        'GCS_BUCKET',
        'SUPABASE_URL',
        'SUPABASE_SERVICE_ROLE_KEY'
    ]
    
    missing_vars = []
    for var in required_env_vars:
        if not os.getenv(var):
            missing_vars.append(var)
    
    if missing_vars:
        print(f"❌ Missing environment variables: {', '.join(missing_vars)}")
        print("   Please set them in .env file or environment")
        return False
    
    # Check required tools
    required_tools = ['gdal_translate', 'gsutil']
    missing_tools = []
    
    for tool in required_tools:
        if shutil.which(tool) is None:
            missing_tools.append(tool)
    
    if missing_tools:
        print(f"❌ Missing required tools: {', '.join(missing_tools)}")
        print("   Please install GDAL and Google Cloud SDK")
        return False
    
    return True

def load_env_file(env_path=".env"):
    """Load environment variables from .env file"""
    if os.path.exists(env_path):
        with open(env_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    os.environ[key.strip()] = value.strip()

def generate_cog_path(input_file, gcs_bucket):
    """Generate COG path in GCS bucket"""
    filename = Path(input_file).stem
    if not filename.endswith('_cog'):
        filename += '_cog'
    return f"cogs/{filename}.tif"

def ingest_product(input_tif, temp_dir=None, cleanup=True, dry_run=False):
    """Complete ingestion pipeline for a single product"""
    
    print(f"🚀 Starting ingestion pipeline for: {input_tif}")
    print(f"   Timestamp: {datetime.now().isoformat()}")
    
    # Validate input
    if not os.path.exists(input_tif):
        raise FileNotFoundError(f"Input file not found: {input_tif}")
    
    # Create temporary directory if not provided
    if temp_dir is None:
        temp_dir = tempfile.mkdtemp(prefix="cog_ingestion_")
        cleanup_temp = cleanup
    else:
        cleanup_temp = False
    
    print(f"📁 Working directory: {temp_dir}")
    
    try:
        # Step 1: Convert to COG
        input_path = Path(input_tif)
        cog_filename = input_path.stem + "_cog.tif"
        cog_path = os.path.join(temp_dir, cog_filename)
        
        script_dir = Path(__file__).parent
        convert_script = script_dir / "convert_to_cog.sh"
        
        if dry_run:
            print(f"🔍 DRY RUN: Would convert {input_tif} to {cog_path}")
        else:
            run_command([str(convert_script), input_tif, cog_path], 
                       "Converting to COG")
        
        # Step 2: Upload to GCS
        gcs_bucket = os.getenv('GCS_BUCKET')
        gcs_path = generate_cog_path(input_tif, gcs_bucket)
        
        upload_script = script_dir / "upload_to_gcs.sh"
        
        if dry_run:
            print(f"🔍 DRY RUN: Would upload to gs://{gcs_bucket}/{gcs_path}")
            cog_url = f"https://storage.googleapis.com/{gcs_bucket}/{gcs_path}"
        else:
            result = run_command([str(upload_script), cog_path, gcs_path], 
                                "Uploading to GCS")
            
            # Extract COG URL from upload script output
            cog_url = f"https://storage.googleapis.com/{gcs_bucket}/{gcs_path}"
        
        # Step 3: Update Supabase
        update_script = script_dir / "update_supabase.py"
        
        if dry_run:
            print(f"🔍 DRY RUN: Would update Supabase with {cog_url}")
            record = {"status": "dry_run", "cog_url": cog_url}
        else:
            result = run_command([
                sys.executable, str(update_script), 
                cog_path, cog_url
            ], "Updating Supabase")
            
            # Parse the JSON output from update_supabase.py
            try:
                # Extract JSON from the output (it should be at the end)
                output_lines = result.stdout.strip().split('\n')
                json_start = -1
                for i, line in enumerate(output_lines):
                    if line.strip().startswith('{'):
                        json_start = i
                        break
                
                if json_start >= 0:
                    json_output = '\n'.join(output_lines[json_start:])
                    record = json.loads(json_output)
                else:
                    record = {"status": "completed", "cog_url": cog_url}
            except (json.JSONDecodeError, IndexError):
                record = {"status": "completed", "cog_url": cog_url}
        
        print("✅ Ingestion pipeline completed successfully!")
        
        # Return summary
        summary = {
            "input_file": input_tif,
            "cog_url": cog_url,
            "gcs_path": f"gs://{gcs_bucket}/{gcs_path}",
            "status": "completed" if not dry_run else "dry_run",
            "timestamp": datetime.now().isoformat(),
            "record": record
        }
        
        return summary
        
    except Exception as e:
        error_summary = {
            "input_file": input_tif,
            "status": "error",
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }
        print(f"❌ Ingestion failed: {e}")
        return error_summary
        
    finally:
        # Cleanup temporary directory if created by us
        if cleanup_temp and os.path.exists(temp_dir):
            print(f"🧹 Cleaning up temporary directory: {temp_dir}")
            shutil.rmtree(temp_dir)

def main():
    parser = argparse.ArgumentParser(description='Complete COG ingestion pipeline')
    parser.add_argument('input_files', nargs='+', help='Input TIF files to process')
    parser.add_argument('--env-file', default='.env', help='Path to .env file')
    parser.add_argument('--temp-dir', help='Temporary directory for processing')
    parser.add_argument('--keep-temp', action='store_true', help='Keep temporary files')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done without executing')
    parser.add_argument('--parallel', type=int, default=1, help='Number of parallel processes (future use)')
    parser.add_argument('--output-json', help='Save results to JSON file')
    
    args = parser.parse_args()
    
    # Load environment
    load_env_file(args.env_file)
    
    # Validate environment
    if not args.dry_run and not validate_environment():
        sys.exit(1)
    
    if args.dry_run:
        print("🔍 DRY RUN MODE - No actual processing will occur")
    
    print(f"📋 Processing {len(args.input_files)} files")
    
    results = []
    failed_files = []
    
    for i, input_file in enumerate(args.input_files, 1):
        print(f"\n{'='*60}")
        print(f"📦 Processing file {i}/{len(args.input_files)}: {input_file}")
        print(f"{'='*60}")
        
        try:
            result = ingest_product(
                input_file, 
                temp_dir=args.temp_dir,
                cleanup=not args.keep_temp,
                dry_run=args.dry_run
            )
            results.append(result)
            
            if result['status'] != 'completed' and not args.dry_run:
                failed_files.append(input_file)
                
        except KeyboardInterrupt:
            print("\n⚠️  Process interrupted by user")
            break
        except Exception as e:
            print(f"❌ Unexpected error processing {input_file}: {e}")
            failed_files.append(input_file)
            results.append({
                "input_file": input_file,
                "status": "error",
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            })
    
    # Summary
    print(f"\n{'='*60}")
    print("📊 INGESTION SUMMARY")
    print(f"{'='*60}")
    
    successful = [r for r in results if r['status'] == 'completed' or r['status'] == 'dry_run']
    failed = [r for r in results if r['status'] == 'error']
    
    print(f"✅ Successful: {len(successful)}")
    print(f"❌ Failed: {len(failed)}")
    print(f"📁 Total processed: {len(results)}")
    
    if failed_files:
        print(f"\n❌ Failed files:")
        for file in failed_files:
            print(f"   - {file}")
    
    # Save results to JSON if requested
    if args.output_json:
        with open(args.output_json, 'w') as f:
            json.dump({
                "summary": {
                    "total_files": len(args.input_files),
                    "successful": len(successful),
                    "failed": len(failed),
                    "dry_run": args.dry_run
                },
                "results": results
            }, f, indent=2)
        print(f"💾 Results saved to: {args.output_json}")
    
    # Exit with error code if any files failed
    if failed_files and not args.dry_run:
        sys.exit(1)
    
    print("✨ Ingestion pipeline completed!")

if __name__ == "__main__":
    main()
