#!/usr/bin/env python3
"""
=============================================================================
INGESTA ESPECÍFICA PARA GRUPO PORRES
Maneja estructura: Grupo_Porres/[producto]/archivos.tif
Con soporte para actualizaciones y detección automática de productos
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

class GrupoPorresIngestionPipeline:
    def __init__(self):
        """Inicializar pipeline específico para Grupo Porres"""
        env_vars = load_env()
        if not env_vars:
            raise Exception("No se pudieron cargar las variables de entorno")
        
        self.project_id = env_vars.get('GOOGLE_CLOUD_PROJECT')
        self.gcs_bucket = env_vars.get('GCS_BUCKET_NAME', 'ta-cogs-apicorreo-prod')
        self.supabase_url = env_vars.get('SUPABASE_URL')
        self.supabase_key = env_vars.get('SUPABASE_SERVICE_ROLE_KEY')
        
        self.headers = {
            "Authorization": f"Bearer {self.supabase_key}",
            "apikey": self.supabase_key,
            "Content-Type": "application/json",
            "Prefer": "return=representation"
        }
        
        # Mapeo específico de productos Grupo Porres
        self.product_mapping = {
            'ndvi': 'ndvi',
            'ndwi': 'ndwi', 
            'sg': 'sg',
            'maleza': 'maleza',
            'potencial_ndvi': 'potencial',
            'potencial_ndwi': 'potencial'
        }
        
        # Colormaps específicos por producto
        self.colormap_mapping = {
            'ndvi': 'ndvi_custom',
            'potencial_ndvi': 'ndvi_custom',
            'ndwi': 'blues',
            'potencial_ndwi': 'blues',
            'sg': 'viridis',
            'maleza': 'reds'
        }
        
        # Valores de rescale específicos
        self.rescale_defaults = {
            'ndvi': (0.0, 1.0),
            'potencial_ndvi': (0.0, 1.0),
            'ndwi': (-0.75, 0.5),
            'potencial_ndwi': (-0.75, 0.5),
            'sg': (20.0, 100.0),
            'maleza': (1.0, 5.0)
        }
        
        logger.info(f"✅ Pipeline Grupo Porres inicializado")
        logger.info(f"   Proyecto: {self.project_id}")
        logger.info(f"   Bucket: {self.gcs_bucket}")
        logger.info(f"   Productos soportados: {list(self.product_mapping.keys())}")
    
    def extract_metadata_from_path(self, file_path: Path) -> Dict:
        """Extraer metadata del path y nombre del archivo"""
        # Estructura: rasters_to_migrate/Grupo_Porres/[producto]/archivo.tif
        parts = file_path.parts
        filename = file_path.stem
        
        # Detectar producto desde la carpeta padre
        if len(parts) >= 3:
            folder_product = parts[-2]  # Carpeta del producto
            
            metadata = {
                'producto': folder_product,
                'empresa': 'mx_gp',  # Siempre mx_gp para Grupo Porres
                'ingenio': 'unknown',
                'fecha': datetime.now().date().isoformat(),
                'original_filename': file_path.name
            }
            
            # Intentar extraer información del filename
            file_parts = filename.split('_')
            
            # Buscar fecha en el filename (formato YYYYMMDD o YYMMDD)
            for part in file_parts:
                if part.isdigit() and len(part) in [6, 8]:
                    try:
                        if len(part) == 8:  # YYYYMMDD
                            parsed_date = datetime.strptime(part, '%Y%m%d').date()
                        else:  # YYMMDD
                            parsed_date = datetime.strptime(part, '%y%m%d').date()
                        metadata['fecha'] = parsed_date.isoformat()
                        break
                    except ValueError:
                        continue
            
            # Buscar ingenio en el filename
            for part in file_parts:
                if part.lower() not in ['mx', 'gp', folder_product.lower()] and not part.isdigit() and len(part) > 2:
                    metadata['ingenio'] = part
                    break
            
            return metadata
        
        # Fallback si no se puede extraer la estructura
        return {
            'producto': 'unknown',
            'empresa': 'mx_gp',
            'ingenio': 'unknown',
            'fecha': datetime.now().date().isoformat(),
            'original_filename': file_path.name
        }
    
    def check_file_exists_in_db(self, filename: str) -> Optional[Dict]:
        """Verificar si el archivo ya existe en la base de datos"""
        try:
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
    
    def convert_to_cog(self, input_path: Path, output_path: Path) -> bool:
        """Convertir TIF a COG usando rasterio"""
        if not RASTERIO_AVAILABLE:
            logger.error("Rasterio no disponible para conversión COG")
            return False
        
        try:
            with rasterio.open(input_path) as src:
                profile = src.profile.copy()
                profile.update({
                    'driver': 'GTiff',
                    'interleave': 'pixel',
                    'tiled': True,
                    'blockxsize': 512,
                    'blockysize': 512,
                    'compress': 'lzw',
                    'BIGTIFF': 'IF_SAFER'
                })
                
                # Agregar overviews
                overview_levels = [2, 4, 8, 16]
                
                with rasterio.open(output_path, 'w', **profile) as dst:
                    dst.write(src.read())
                    dst.build_overviews(overview_levels, Resampling.average)
                    dst.update_tags(ns='gdal', **dst.tags())
            
            logger.info(f"✅ COG creado: {output_path}")
            return True
            
        except Exception as e:
            logger.error(f"❌ Error convirtiendo a COG {input_path}: {e}")
            return False
    
    def upload_to_gcs(self, local_path: Path, gcs_path: str) -> bool:
        """Subir archivo a Google Cloud Storage"""
        try:
            # Usar gcloud storage en lugar de gsutil
            cmd = [
                'gcloud', 'storage', 'cp', str(local_path), f'gs://{self.gcs_bucket}/{gcs_path}'
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, shell=True)
            
            if result.returncode == 0:
                logger.info(f"✅ Subido a GCS: gs://{self.gcs_bucket}/{gcs_path}")
                return True
            else:
                logger.error(f"❌ Error subiendo a GCS: {result.stderr}")
                # Intentar con gsutil como fallback
                cmd_gsutil = [
                    'gsutil', 'cp', str(local_path), f'gs://{self.gcs_bucket}/{gcs_path}'
                ]
                result_gsutil = subprocess.run(cmd_gsutil, capture_output=True, text=True, shell=True)
                if result_gsutil.returncode == 0:
                    logger.info(f"✅ Subido a GCS (gsutil): gs://{self.gcs_bucket}/{gcs_path}")
                    return True
                else:
                    logger.error(f"❌ Error con gsutil: {result_gsutil.stderr}")
                    return False
                
        except Exception as e:
            logger.error(f"❌ Error ejecutando gcloud storage: {e}")
            return False
    
    def update_supabase_record(self, record_data: Dict, existing_record: Optional[Dict] = None) -> bool:
        """Actualizar o crear registro en Supabase"""
        try:
            if existing_record:
                # Actualizar registro existente
                record_id = existing_record['id']
                response = requests.patch(
                    f"{self.supabase_url}/rest/v1/productos?id=eq.{record_id}",
                    headers=self.headers,
                    json=record_data
                )
                logger.info(f"🔄 Actualizando registro ID: {record_id}")
            else:
                # Crear nuevo registro
                response = requests.post(
                    f"{self.supabase_url}/rest/v1/productos",
                    headers=self.headers,
                    json=record_data
                )
                logger.info(f"✅ Creando nuevo registro")
            
            response.raise_for_status()
            logger.info(f"✅ Registro guardado en Supabase")
            return True
            
        except Exception as e:
            logger.error(f"❌ Error guardando en Supabase: {e}")
            return False
    
    def process_file(self, file_path: Path, force_update: bool = False) -> bool:
        """Procesar un archivo TIF individual"""
        logger.info(f"🔄 Procesando: {file_path}")
        
        # Extraer metadata
        metadata = self.extract_metadata_from_path(file_path)
        logger.info(f"   📝 Producto: {metadata['producto']}")
        logger.info(f"   🏢 Empresa: {metadata['empresa']}")
        logger.info(f"   🏭 Ingenio: {metadata['ingenio']}")
        logger.info(f"   📅 Fecha: {metadata['fecha']}")
        
        # Verificar si ya existe
        existing_record = self.check_file_exists_in_db(metadata['original_filename'])
        
        if existing_record and not force_update:
            logger.info(f"⏭️  Archivo ya existe en DB (usar --force para actualizar)")
            return True
        
        # Crear COG
        cog_filename = f"{file_path.stem}_cog.tif"
        cog_local_path = Path(f"temp/{cog_filename}")
        cog_local_path.parent.mkdir(exist_ok=True)
        
        if not self.convert_to_cog(file_path, cog_local_path):
            return False
        
        # Subir a GCS
        gcs_path = f"cogs/{cog_filename}"
        if not self.upload_to_gcs(cog_local_path, gcs_path):
            return False
        
        # Preparar datos para Supabase
        producto_tipo = self.product_mapping.get(metadata['producto'], metadata['producto'])
        colormap = self.colormap_mapping.get(metadata['producto'], 'viridis')
        rescale_min, rescale_max = self.rescale_defaults.get(metadata['producto'], (0.0, 1.0))
        
        record_data = {
            'empresa': metadata['empresa'],
            'ingenio': metadata['ingenio'],
            'fecha': metadata['fecha'],
            'producto': producto_tipo,
            'original_filename': metadata['original_filename'],
            'cog_filename': cog_filename,
            'cog_url': f"gs://{self.gcs_bucket}/{gcs_path}",
            'rescale_min': rescale_min,
            'rescale_max': rescale_max,
            'colormap': colormap,
            'processing_status': 'completed',
            'processing_log': f"Procesado por ingest_grupo_porres.py: {datetime.now()}"
        }
        
        # Guardar en Supabase
        if not self.update_supabase_record(record_data, existing_record):
            return False
        
        # Limpiar archivo temporal
        try:
            cog_local_path.unlink()
        except:
            pass
        
        logger.info(f"✅ Archivo procesado completamente: {file_path.name}")
        return True
    
    def scan_and_process(self, base_path: Path, force_update: bool = False, dry_run: bool = False):
        """Escanear y procesar todos los archivos en la estructura Grupo Porres"""
        grupo_porres_path = base_path / "Grupo_Porres"
        
        if not grupo_porres_path.exists():
            logger.error(f"❌ No se encontró la carpeta Grupo_Porres en {base_path}")
            return
        
        logger.info(f"🔍 Escaneando: {grupo_porres_path}")
        
        # Encontrar todos los archivos TIF
        tif_files = list(grupo_porres_path.rglob("*.tif"))
        logger.info(f"📊 Encontrados {len(tif_files)} archivos TIF")
        
        if dry_run:
            logger.info("🧪 MODO DRY RUN - Solo mostrando lo que se procesaría:")
            for file_path in tif_files:
                metadata = self.extract_metadata_from_path(file_path)
                existing = self.check_file_exists_in_db(metadata['original_filename'])
                status = "ACTUALIZAR" if existing and force_update else "CREAR" if not existing else "OMITIR"
                logger.info(f"   {status}: {file_path.relative_to(base_path)} -> {metadata['producto']}")
            return
        
        # Procesar archivos
        successful = 0
        failed = 0
        
        for i, file_path in enumerate(tif_files, 1):
            logger.info(f"📁 [{i}/{len(tif_files)}] Procesando archivo...")
            
            try:
                if self.process_file(file_path, force_update):
                    successful += 1
                else:
                    failed += 1
            except Exception as e:
                logger.error(f"❌ Error procesando {file_path}: {e}")
                failed += 1
        
        logger.info(f"🎯 RESUMEN FINAL:")
        logger.info(f"   ✅ Exitosos: {successful}")
        logger.info(f"   ❌ Fallidos: {failed}")
        logger.info(f"   📊 Total: {len(tif_files)}")

def main():
    """Función principal"""
    parser = argparse.ArgumentParser(description="Ingesta específica para Grupo Porres")
    parser.add_argument("path", help="Ruta base donde está la carpeta Grupo_Porres")
    parser.add_argument("--force", action="store_true", help="Forzar actualización de archivos existentes")
    parser.add_argument("--dry-run", action="store_true", help="Solo mostrar qué se procesaría sin ejecutar")
    parser.add_argument("--verbose", action="store_true", help="Logging detallado")
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    base_path = Path(args.path)
    
    if not base_path.exists():
        logger.error(f"❌ Ruta no encontrada: {base_path}")
        return 1
    
    try:
        pipeline = GrupoPorresIngestionPipeline()
        pipeline.scan_and_process(base_path, args.force, args.dry_run)
        return 0
    except Exception as e:
        logger.error(f"❌ Error en el pipeline: {e}")
        return 1

if __name__ == "__main__":
    exit(main())
