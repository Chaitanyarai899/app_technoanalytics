#!/usr/bin/env python3
"""
=============================================================================
MODERN RASTER INGESTION PIPELINE - Production Version
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
import requests

try:
    import rasterio
    from rasterio.enums import Resampling
    RASTERIO_AVAILABLE = True
    print("✅ Rasterio disponible - Conversión COG habilitada")
except ImportError:
    RASTERIO_AVAILABLE = False
    print("⚠️  Rasterio no disponible. Solo modo metadata.")

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def load_env():
    """Cargar variables de entorno desde .env"""
    env_vars = {}
    try:
        with open('.env', 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key] = value
    except FileNotFoundError:
        logger.error("❌ Archivo .env no encontrado")
        return None
    return env_vars

class RasterIngestionPipeline:
    """Pipeline para ingesta de rasters a la arquitectura moderna"""
    
    def __init__(self):
        env_vars = load_env()
        if not env_vars:
            sys.exit(1)
            
        self.project_id = env_vars.get("PROJECT_ID")
        self.gcs_bucket = env_vars.get("GCS_BUCKET")
        self.supabase_url = env_vars.get("SUPABASE_URL")
        self.supabase_key = env_vars.get("SUPABASE_SERVICE_ROLE_KEY")
        
        # Validar configuración
        if not all([self.project_id, self.gcs_bucket, self.supabase_url, self.supabase_key]):
            logger.error("❌ Variables de entorno faltantes. Revisar .env")
            sys.exit(1)
        
        # Headers para Supabase
        self.headers = {
            "Authorization": f"Bearer {self.supabase_key}",
            "apikey": self.supabase_key,
            "Content-Type": "application/json",
            "Prefer": "return=representation"
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
        
        logger.info(f"✅ Pipeline inicializado")
        logger.info(f"   Proyecto: {self.project_id}")
        logger.info(f"   Bucket: {self.gcs_bucket}")
        logger.info(f"   Modo COG: {'Habilitado' if RASTERIO_AVAILABLE else 'Deshabilitado'}")
    
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
        # Formato: mx_gp_ndvi_Huixtla_20241122.tif
        # O formato simple: producto_empresa_ingenio_fecha.tif
        
        parts = Path(filename).stem.split('_')
        metadata = {
            'producto': 'unknown',
            'empresa': 'unknown', 
            'ingenio': 'unknown',
            'fecha': datetime.now().date().isoformat()
        }
        
        if len(parts) >= 4:
            if len(parts) == 5 and parts[0] == 'mx' and parts[1] == 'gp':
                # Formato: mx_gp_ndvi_Huixtla_20241122
                metadata['producto'] = parts[2]
                metadata['empresa'] = 'mx_gp'
                metadata['ingenio'] = parts[3]
                fecha_str = parts[4]
            else:
                # Formato simple: producto_empresa_ingenio_fecha
                metadata['producto'] = parts[0]
                metadata['empresa'] = parts[1]
                metadata['ingenio'] = parts[2]
                fecha_str = parts[3]
            
            # Intentar parsear fecha
            try:
                if len(fecha_str) == 8:  # YYYYMMDD
                    parsed_date = datetime.strptime(fecha_str, '%Y%m%d').date()
                    metadata['fecha'] = parsed_date.isoformat()
                elif len(fecha_str) == 6:  # YYMMDD
                    parsed_date = datetime.strptime(fecha_str, '%y%m%d').date()
                    metadata['fecha'] = parsed_date.isoformat()
            except ValueError:
                logger.warning(f"No se pudo parsear fecha de {filename}")
        
        return metadata
    
    def check_file_exists_in_db(self, filename: str) -> Optional[Dict]:
        """Verificar si el archivo ya existe en la base de datos"""
        try:
            # Buscar por original_filename
            response = requests.get(
                f"{self.supabase_url}/rest/v1/productos?original_filename=eq.{filename}",
                headers=self.headers
            )
            response.raise_for_status()
            
            data = response.json()
            if data and len(data) > 0:
                return data[0]
            return None
            
        except Exception as e:
            logger.error(f"Error verificando archivo en DB: {e}")
            return None
    
    def get_raster_metadata(self, file_path: str) -> Dict:
        """Extraer metadata del archivo raster"""
        if not RASTERIO_AVAILABLE:
            # Metadata básica sin rasterio
            file_size = os.path.getsize(file_path)
            return {
                'width': None,
                'height': None,
                'bands': 1,
                'epsg': 4326,
                'bounds': None,
                'min_value': None,
                'max_value': None,
                'nodata_value': None,
                'file_size_mb': round(file_size / (1024*1024), 2)
            }
        
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
                    'nodata_value': src.nodata,
                    'file_size_mb': round(os.path.getsize(file_path) / (1024*1024), 2)
                }
                
                return metadata
                
        except Exception as e:
            logger.error(f"Error leyendo metadata de {file_path}: {e}")
            return {
                'file_size_mb': round(os.path.getsize(file_path) / (1024*1024), 2)
            }
    
    def convert_to_cog(self, input_path: str, output_path: str) -> bool:
        """Convertir TIF a COG usando rasterio"""
        if not RASTERIO_AVAILABLE:
            logger.warning("⚠️  Conversión COG no disponible sin rasterio")
            # Solo copiar archivo por ahora
            import shutil
            try:
                os.makedirs(os.path.dirname(output_path), exist_ok=True)
                shutil.copy2(input_path, output_path)
                logger.info(f"📋 Archivo copiado: {output_path}")
                return True
            except Exception as e:
                logger.error(f"Error copiando archivo: {e}")
                return False
        
        try:
            # Crear directorio de salida si no existe
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            
            # Usar rasterio para convertir a COG
            with rasterio.open(input_path) as src:
                profile = src.profile.copy()
                
                # Configuración COG
                profile.update({
                    'driver': 'COG',
                    'compress': 'lzw',
                    'predictor': 2,
                    'bigtiff': 'auto',
                    'blocksize': 512
                })
                
                with rasterio.open(output_path, 'w', **profile) as dst:
                    dst.write(src.read())
                    
                    # Construir overviews
                    dst.build_overviews([2, 4, 8, 16], Resampling.bilinear)
                    dst.update_tags(ns='rio_overview', **dst.tags(ns='rio_overview'))
            
            logger.info(f"✅ COG creado: {output_path}")
            return True
                
        except Exception as e:
            logger.error(f"❌ Error creando COG: {e}")
            return False
    
    def upload_to_gcs(self, local_path: str, gcs_path: str) -> bool:
        """Subir archivo a Google Cloud Storage"""
        try:
            cmd = ['gsutil', 'cp', local_path, f'gs://{self.gcs_bucket}/{gcs_path}']
            
            logger.info(f"📤 Subiendo a GCS: {gcs_path}")
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
    
    def update_database(self, metadata: Dict) -> Optional[str]:
        """Actualizar base de datos con metadata del producto"""
        try:
            # Verificar si el producto ya existe
            existing = self.check_file_exists_in_db(metadata['original_filename'])
            
            record_id = None
            if existing:
                # Actualizar registro existente
                response = requests.patch(
                    f"{self.supabase_url}/rest/v1/productos?id=eq.{existing['id']}",
                    headers=self.headers,
                    json=metadata
                )
                response.raise_for_status()
                record_id = existing['id']
                logger.info(f"✅ Producto actualizado en DB: {record_id}")
            else:
                # Crear nuevo registro
                response = requests.post(
                    f"{self.supabase_url}/rest/v1/productos",
                    headers=self.headers,
                    json=metadata
                )
                response.raise_for_status()
                data = response.json()
                if data and len(data) > 0:
                    record_id = data[0]['id']
                    logger.info(f"✅ Producto creado en DB: {record_id}")
                else:
                    logger.info(f"✅ Producto creado en DB")
            
            return record_id
            
        except Exception as e:
            logger.error(f"❌ Error actualizando DB: {e}")
            if hasattr(e, 'response'):
                logger.error(f"Response: {e.response.text}")
            return None
    
    def process_file(self, file_path: str, force: bool = False) -> bool:
        """Procesar archivo con conversión COG completa"""
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
        
        logger.info(f"   Producto: {file_metadata['producto']}")
        logger.info(f"   Empresa: {file_metadata['empresa']}")
        logger.info(f"   Ingenio: {file_metadata['ingenio']}")
        logger.info(f"   Fecha: {file_metadata['fecha']}")
        
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
            record_id = self.update_database(processing_metadata)
            
            # 1. Obtener metadata del raster
            logger.info("📊 Extrayendo metadata del raster...")
            raster_metadata = self.get_raster_metadata(str(file_path))
            if not raster_metadata:
                raise Exception("Error obteniendo metadata del raster")
            
            logger.info(f"   Dimensiones: {raster_metadata.get('width')}x{raster_metadata.get('height')}")
            logger.info(f"   Tamaño: {raster_metadata.get('file_size_mb')} MB")
            
            # 2. Convertir a COG
            logger.info("🔄 Convirtiendo a COG...")
            if not self.convert_to_cog(str(file_path), temp_cog_path):
                raise Exception("Error en conversión COG")
            
            # 3. Subir a GCS
            logger.info("☁️  Subiendo a Google Cloud Storage...")
            if not self.upload_to_gcs(temp_cog_path, gcs_path):
                raise Exception("Error subiendo a GCS")
            
            # 4. Actualizar DB con metadata completa
            complete_metadata = {
                **processing_metadata,
                **raster_metadata,
                'cog_url': f'gs://{self.gcs_bucket}/{gcs_path}',
                'processing_status': 'completed',
                'processing_log': f"Completado: {datetime.now()}",
                'colormap': self.product_colormaps.get(product_type),
                'rescale_min': self.rescale_defaults.get(product_type, (None, None))[0],
                'rescale_max': self.rescale_defaults.get(product_type, (None, None))[1]
            }
            
            final_id = self.update_database(complete_metadata)
            if not final_id:
                raise Exception("Error actualizando DB final")
            
            # Limpiar archivo temporal
            if os.path.exists(temp_cog_path):
                os.remove(temp_cog_path)
            
            logger.info(f"✅ Procesamiento completado: {file_path.name}")
            
            # Mostrar URLs útiles
            titiler_base = "https://ta-titiler-service-1087100331392.us-central1.run.app"
            logger.info(f"🌐 TiTiler URL: {titiler_base}/cog/info?url=gs://{self.gcs_bucket}/{gcs_path}")
            logger.info(f"🗺️  Tiles: {titiler_base}/cog/tiles/WebMercatorQuad/{{z}}/{{x}}/{{y}}.png?url=gs://{self.gcs_bucket}/{gcs_path}")
            
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
    
    def process_directory(self, directory: str, force: bool = False, limit: int = None) -> Dict:
        """Procesar todos los archivos TIF en un directorio"""
        directory = Path(directory)
        
        if not directory.exists():
            logger.error(f"❌ Directorio no encontrado: {directory}")
            return {'processed': 0, 'failed': 0, 'skipped': 0}
        
        # Encontrar archivos TIF (solo archivos principales, no auxiliares)
        tif_files = [f for f in directory.glob('*.tif') if not any(suffix in f.name for suffix in ['.aux.xml', '.ovr'])]
        
        if not tif_files:
            logger.warning(f"⚠️  No se encontraron archivos TIF en: {directory}")
            return {'processed': 0, 'failed': 0, 'skipped': 0}
        
        # Aplicar límite si se especifica
        if limit:
            tif_files = tif_files[:limit]
        
        logger.info(f"📁 Procesando directorio: {directory}")
        logger.info(f"📄 Archivos encontrados: {len(tif_files)}")
        
        results = {'processed': 0, 'failed': 0, 'skipped': 0}
        
        for i, tif_file in enumerate(tif_files, 1):
            logger.info(f"\n═══ ARCHIVO {i}/{len(tif_files)} ═══")
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
    parser = argparse.ArgumentParser(description='Ingesta de rasters a arquitectura moderna')
    parser.add_argument('input', help='Archivo TIF o directorio a procesar')
    parser.add_argument('--force', action='store_true', help='Forzar reprocesamiento')
    parser.add_argument('--limit', type=int, help='Limitar número de archivos a procesar')
    parser.add_argument('--verbose', '-v', action='store_true', help='Logging detallado')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    print("=== MODERN RASTER INGESTION PIPELINE ===")
    print()
    
    # Crear directorio temporal
    os.makedirs('temp', exist_ok=True)
    
    # Inicializar pipeline
    try:
        pipeline = RasterIngestionPipeline()
    except Exception as e:
        logger.error(f"Error inicializando pipeline: {e}")
        sys.exit(1)
    
    # Procesar entrada
    input_path = Path(args.input)
    
    if input_path.is_file():
        # Procesar archivo individual
        success = pipeline.process_file(args.input, args.force)
        sys.exit(0 if success else 1)
        
    elif input_path.is_dir():
        # Procesar directorio
        results = pipeline.process_directory(args.input, args.force, args.limit)
        
        print(f"\n📊 RESUMEN DE PROCESAMIENTO:")
        print(f"✅ Procesados: {results['processed']}")
        print(f"❌ Fallidos: {results['failed']}")
        print(f"⏭️  Saltados: {results['skipped']}")
        
        if results['processed'] > 0:
            print(f"\n🎉 ¡{results['processed']} archivos listos en la nueva infraestructura!")
            print(f"🌐 Accede a Supabase Dashboard: {pipeline.supabase_url.replace('/rest/v1', '')}")
        
        sys.exit(0 if results['failed'] == 0 else 1)
    else:
        logger.error(f"❌ Entrada no válida: {args.input}")
        sys.exit(1)

if __name__ == "__main__":
    main()
