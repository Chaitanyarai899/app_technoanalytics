#!/usr/bin/env python3
"""
=============================================================================
RASTER INGESTION PIPELINE
Proceso completo: TIF → COG → GCS → Supabase
=============================================================================
"""

import os
import sys
import json
import argparse
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple
import logging

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

try:
    import rasterio
    from rasterio.enums import Resampling
    from supabase import create_client, Client
    from dotenv import load_dotenv
except ImportError as e:
    logger.error(f"Error importando dependencias: {e}")
    logger.error("Instalar con: pip install rasterio supabase python-dotenv")
    sys.exit(1)

# Cargar variables de entorno
load_dotenv()

class RasterIngestionPipeline:
    """Pipeline para ingesta de rasters a la arquitectura moderna"""
    
    def __init__(self):
        self.project_id = os.getenv("PROJECT_ID")
        self.gcs_bucket = os.getenv("GCS_BUCKET")
        self.supabase_url = os.getenv("SUPABASE_URL")
        self.supabase_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
        
        # Validar configuración
        if not all([self.project_id, self.gcs_bucket, self.supabase_url, self.supabase_key]):
            logger.error("❌ Variables de entorno faltantes. Revisar .env")
            sys.exit(1)
        
        # Cliente Supabase
        self.supabase = create_client(self.supabase_url, self.supabase_key)
        
        # Configuración COG
        self.cog_options = {
            'COMPRESS': 'LZW',
            'PREDICTOR': '2',
            'BIGTIFF': 'AUTO',
            'BLOCKSIZE': '512',
            'OVERVIEW_RESAMPLING': 'BILINEAR'
        }
        
        # Mapeo de colormaps por tipo de producto
        self.product_colormaps = {
            'ndvi': 'ndvi',
            'ndwi': 'ndwi', 
            'sg': 'sg',
            'maleza': 'maleza',
            'potencial': 'potencial',
            'potencial_ndvi': 'potencial',
            'potencial_ndwi': 'potencial'
        }
        
        # Valores de rescale por defecto
        self.rescale_defaults = {
            'ndvi': (0.0, 1.0),
            'ndwi': (-0.75, 0.5),
            'sg': (20.0, 100.0),
            'maleza': (1.0, 5.0),
            'potencial': (0.0, 4.0)
        }
    
    def detect_product_type(self, filename: str) -> str:
        """Detectar tipo de producto basado en el nombre del archivo"""
        filename_lower = filename.lower()
        
        if 'ndvi' in filename_lower:
            return 'ndvi'
        elif 'ndwi' in filename_lower:
            return 'ndwi'
        elif 'sg' in filename_lower or 'suelo' in filename_lower:
            return 'sg'
        elif 'maleza' in filename_lower:
            return 'maleza'
        elif 'potencial' in filename_lower:
            if 'ndvi' in filename_lower:
                return 'potencial_ndvi'
            elif 'ndwi' in filename_lower:
                return 'potencial_ndwi'
            else:
                return 'potencial'
        else:
            return 'unknown'
    
    def extract_metadata_from_filename(self, filename: str) -> Dict:
        """Extraer metadata del nombre del archivo"""
        # Formato esperado: producto_empresa_ingenio_fecha.tif
        # Ejemplo: ndvi_pantaleon_concepcion_20250901.tif
        
        parts = Path(filename).stem.split('_')
        metadata = {
            'producto': 'unknown',
            'empresa': 'unknown', 
            'ingenio': 'unknown',
            'fecha': datetime.now().date()
        }
        
        if len(parts) >= 4:
            metadata['producto'] = parts[0]
            metadata['empresa'] = parts[1]
            metadata['ingenio'] = parts[2]
            
            # Intentar parsear fecha
            try:
                fecha_str = parts[3]
                if len(fecha_str) == 8:  # YYYYMMDD
                    metadata['fecha'] = datetime.strptime(fecha_str, '%Y%m%d').date()
                elif len(fecha_str) == 6:  # YYMMDD
                    metadata['fecha'] = datetime.strptime(fecha_str, '%y%m%d').date()
            except ValueError:
                logger.warning(f"No se pudo parsear fecha de {filename}")
        
        return metadata
    
    def check_file_exists_in_db(self, filename: str) -> Optional[Dict]:
        """Verificar si el archivo ya existe en la base de datos"""
        try:
            result = self.supabase.rpc('find_product_by_filename', {'filename': filename})
            
            if result.data:
                return result.data[0]
            return None
            
        except Exception as e:
            logger.error(f"Error verificando archivo en DB: {e}")
            return None
    
    def check_file_exists_in_gcs(self, cog_filename: str) -> bool:
        """Verificar si el archivo COG ya existe en GCS"""
        try:
            result = subprocess.run([
                'gsutil', 'ls', f'gs://{self.gcs_bucket}/cogs/{cog_filename}'
            ], capture_output=True, text=True)
            
            return result.returncode == 0
            
        except Exception as e:
            logger.error(f"Error verificando archivo en GCS: {e}")
            return False
    
    def get_raster_metadata(self, file_path: str) -> Dict:
        """Extraer metadata del archivo raster"""
        try:
            with rasterio.open(file_path) as src:
                bounds = src.bounds
                stats = src.read(1, masked=True)
                
                metadata = {
                    'width': src.width,
                    'height': src.height,
                    'bands': src.count,
                    'epsg': src.crs.to_epsg() if src.crs else 4326,
                    'bounds': [bounds.left, bounds.bottom, bounds.right, bounds.top],
                    'min_value': float(stats.min()) if stats.count() > 0 else None,
                    'max_value': float(stats.max()) if stats.count() > 0 else None,
                    'nodata_value': src.nodata
                }
                
                return metadata
                
        except Exception as e:
            logger.error(f"Error leyendo metadata de {file_path}: {e}")
            return {}
    
    def convert_to_cog(self, input_path: str, output_path: str) -> bool:
        """Convertir TIF a COG usando GDAL"""
        try:
            # Crear directorio de salida si no existe
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            
            # Comando gdal_translate para COG
            cmd = [
                'gdal_translate',
                '-of', 'COG',
                '-co', f'COMPRESS={self.cog_options["COMPRESS"]}',
                '-co', f'PREDICTOR={self.cog_options["PREDICTOR"]}',
                '-co', f'BIGTIFF={self.cog_options["BIGTIFF"]}',
                '-co', f'BLOCKSIZE={self.cog_options["BLOCKSIZE"]}',
                '-co', f'OVERVIEW_RESAMPLING={self.cog_options["OVERVIEW_RESAMPLING"]}',
                input_path,
                output_path
            ]
            
            logger.info(f"Convirtiendo a COG: {input_path}")
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info(f"✅ COG creado: {output_path}")
                return True
            else:
                logger.error(f"❌ Error creando COG: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"Error en conversión COG: {e}")
            return False
    
    def upload_to_gcs(self, local_path: str, gcs_path: str) -> bool:
        """Subir archivo a Google Cloud Storage"""
        try:
            cmd = ['gsutil', 'cp', local_path, f'gs://{self.gcs_bucket}/{gcs_path}']
            
            logger.info(f"Subiendo a GCS: {gcs_path}")
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info(f"✅ Archivo subido: gs://{self.gcs_bucket}/{gcs_path}")
                return True
            else:
                logger.error(f"❌ Error subiendo a GCS: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"Error subiendo a GCS: {e}")
            return False
    
    def update_database(self, metadata: Dict) -> bool:
        """Actualizar base de datos con metadata del producto"""
        try:
            # Verificar si el producto ya existe
            existing = self.check_file_exists_in_db(metadata['original_filename'])
            
            if existing:
                # Actualizar registro existente
                result = self.supabase.table('productos').update(metadata).eq('id', existing['id']).execute()
                logger.info(f"✅ Producto actualizado en DB: {existing['id']}")
            else:
                # Crear nuevo registro
                result = self.supabase.table('productos').insert(metadata).execute()
                logger.info(f"✅ Producto creado en DB")
            
            return True
            
        except Exception as e:
            logger.error(f"❌ Error actualizando DB: {e}")
            return False
    
    def process_file(self, file_path: str, force: bool = False) -> bool:
        """Procesar un archivo individual"""
        file_path = Path(file_path)
        
        if not file_path.exists():
            logger.error(f"❌ Archivo no encontrado: {file_path}")
            return False
        
        if file_path.suffix.lower() not in ['.tif', '.tiff']:
            logger.warning(f"⚠️  Saltando archivo no TIF: {file_path}")
            return False
        
        logger.info(f"🔄 Procesando: {file_path.name}")
        
        # Extraer metadata del nombre
        file_metadata = self.extract_metadata_from_filename(file_path.name)
        product_type = self.detect_product_type(file_path.name)
        
        # Verificar si ya existe
        if not force:
            existing = self.check_file_exists_in_db(file_path.name)
            if existing and existing.get('processing_status') == 'completed':
                logger.info(f"⏭️  Archivo ya procesado: {file_path.name}")
                return True
        
        # Generar nombres
        cog_filename = f"{file_path.stem}_cog.tif"
        temp_cog_path = f"temp/{cog_filename}"
        gcs_path = f"cogs/{cog_filename}"
        
        try:
            # Marcar como processing en DB
            processing_metadata = {
                **file_metadata,
                'original_filename': file_path.name,
                'cog_filename': cog_filename,
                'processing_status': 'processing',
                'processing_log': f"Iniciado procesamiento: {datetime.now()}"
            }
            self.update_database(processing_metadata)
            
            # 1. Obtener metadata del raster
            raster_metadata = self.get_raster_metadata(str(file_path))
            
            # 2. Convertir a COG
            if not self.convert_to_cog(str(file_path), temp_cog_path):
                raise Exception("Error en conversión COG")
            
            # 3. Subir a GCS
            if not self.upload_to_gcs(temp_cog_path, gcs_path):
                raise Exception("Error subiendo a GCS")
            
            # 4. Actualizar DB con metadata completa
            complete_metadata = {
                **processing_metadata,
                **raster_metadata,
                'cog_url': f'gs://{self.gcs_bucket}/{gcs_path}',
                'file_size_mb': round(os.path.getsize(temp_cog_path) / (1024*1024), 2),
                'processing_status': 'completed',
                'processing_log': f"Completado: {datetime.now()}",
                'colormap': self.product_colormaps.get(product_type),
                'rescale_min': self.rescale_defaults.get(product_type, (None, None))[0],
                'rescale_max': self.rescale_defaults.get(product_type, (None, None))[1]
            }
            
            if not self.update_database(complete_metadata):
                raise Exception("Error actualizando DB")
            
            # Limpiar archivo temporal
            if os.path.exists(temp_cog_path):
                os.remove(temp_cog_path)
            
            logger.info(f"✅ Procesamiento completado: {file_path.name}")
            return True
            
        except Exception as e:
            logger.error(f"❌ Error procesando {file_path.name}: {e}")
            
            # Marcar como failed en DB
            failed_metadata = {
                **file_metadata,
                'original_filename': file_path.name,
                'processing_status': 'failed',
                'processing_log': f"Error: {str(e)} - {datetime.now()}"
            }
            self.update_database(failed_metadata)
            
            # Limpiar archivo temporal
            if os.path.exists(temp_cog_path):
                os.remove(temp_cog_path)
            
            return False
    
    def process_directory(self, directory: str, force: bool = False) -> Dict:
        """Procesar todos los archivos TIF en un directorio"""
        directory = Path(directory)
        
        if not directory.exists():
            logger.error(f"❌ Directorio no encontrado: {directory}")
            return {'processed': 0, 'failed': 0, 'skipped': 0}
        
        # Encontrar archivos TIF
        tif_files = list(directory.glob('*.tif')) + list(directory.glob('*.tiff'))
        
        if not tif_files:
            logger.warning(f"⚠️  No se encontraron archivos TIF en: {directory}")
            return {'processed': 0, 'failed': 0, 'skipped': 0}
        
        logger.info(f"📁 Procesando directorio: {directory}")
        logger.info(f"📄 Archivos encontrados: {len(tif_files)}")
        
        results = {'processed': 0, 'failed': 0, 'skipped': 0}
        
        for tif_file in tif_files:
            try:
                success = self.process_file(tif_file, force)
                if success:
                    results['processed'] += 1
                else:
                    results['failed'] += 1
            except Exception as e:
                logger.error(f"Error procesando {tif_file}: {e}")
                results['failed'] += 1
        
        return results

def main():
    """Función principal"""
    parser = argparse.ArgumentParser(description='Ingesta de rasters')
    parser.add_argument('input', help='Archivo TIF o directorio a procesar')
    parser.add_argument('--force', action='store_true', help='Forzar reprocesamiento')
    parser.add_argument('--verbose', '-v', action='store_true', help='Logging detallado')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Crear directorio temporal
    os.makedirs('temp', exist_ok=True)
    
    # Inicializar pipeline
    pipeline = RasterIngestionPipeline()
    
    # Procesar entrada
    input_path = Path(args.input)
    
    if input_path.is_file():
        # Procesar archivo individual
        success = pipeline.process_file(args.input, args.force)
        sys.exit(0 if success else 1)
        
    elif input_path.is_dir():
        # Procesar directorio
        results = pipeline.process_directory(args.input, args.force)
        
        print(f"\n📊 Resumen de procesamiento:")
        print(f"✅ Procesados: {results['processed']}")
        print(f"❌ Fallidos: {results['failed']}")
        print(f"⏭️  Saltados: {results['skipped']}")
        
        sys.exit(0 if results['failed'] == 0 else 1)
    else:
        logger.error(f"❌ Entrada no válida: {args.input}")
        sys.exit(1)

if __name__ == "__main__":
    main()
