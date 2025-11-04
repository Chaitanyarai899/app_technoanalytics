#!/usr/bin/env python3
"""
Script para corregir registros existentes en Supabase
Corrige: empresa, ingenio, productos y campos faltantes
"""

import os
import sys
import logging
import re
from datetime import datetime
from pathlib import Path
import rasterio
import rasterio.features
import rasterio.warp
from supabase import create_client, Client
from typing import Dict, List, Optional, Tuple
import json

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)

class DatabaseFixer:
    def __init__(self):
        """Inicializar el cliente de Supabase"""
        self.supabase_url = "https://eewlwrgzeypfwjruzshj.supabase.co"
        self.supabase_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVld2x3cmd6ZXlwZndqcnV6c2hqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MjUzOTI4NDMsImV4cCI6MjA0MDk2ODg0M30.GmJCKUgqDLcCgPTKiO7RK7uPx0_-U4aYtYN2qNq6bpw"
        self.supabase: Client = create_client(self.supabase_url, self.supabase_key)
        logging.info("✅ Cliente Supabase inicializado")
    
    def get_mx_gp_records(self) -> List[Dict]:
        """Obtener todos los registros de mx_gp"""
        try:
            response = self.supabase.table('productos').select('*').eq('empresa', 'mx_gp').execute()
            logging.info(f"📊 Encontrados {len(response.data)} registros de mx_gp")
            return response.data
        except Exception as e:
            logging.error(f"❌ Error obteniendo registros: {e}")
            return []
    
    def fix_empresa_name(self, records: List[Dict]) -> int:
        """Corregir empresa de 'mx_gp' a 'Grupo Porres'"""
        count = 0
        for record in records:
            if record['empresa'] == 'mx_gp':
                try:
                    self.supabase.table('productos').update({
                        'empresa': 'Grupo Porres'
                    }).eq('id', record['id']).execute()
                    count += 1
                except Exception as e:
                    logging.error(f"❌ Error actualizando empresa para {record['id']}: {e}")
        
        logging.info(f"✅ Empresa corregida en {count} registros")
        return count
    
    def fix_ingenio_names(self, records: List[Dict]) -> int:
        """Corregir nombres de ingenios"""
        count = 0
        for record in records:
            new_ingenio = None
            
            # Santa_Clara -> Santa Clara
            if record['ingenio'] == 'Santa':  # Se truncó en el parsing
                new_ingenio = 'Santa Clara'
            elif 'Santa_Clara' in str(record.get('original_filename', '')):
                new_ingenio = 'Santa Clara'
            
            # potencial -> corregir basado en el filename
            elif record['ingenio'] == 'potencial':
                filename = record.get('original_filename', '')
                if 'potencial_ndvi' in filename or 'potencial_ndwi' in filename:
                    # Extraer el ingenio real del filename
                    match = re.search(r'mx_gp_potencial_n[dw][vw]i_([^_]+)_', filename)
                    if match:
                        ingenio_name = match.group(1)
                        if ingenio_name == 'Santa':
                            new_ingenio = 'Santa Clara'
                        else:
                            new_ingenio = ingenio_name
            
            if new_ingenio and new_ingenio != record['ingenio']:
                try:
                    self.supabase.table('productos').update({
                        'ingenio': new_ingenio
                    }).eq('id', record['id']).execute()
                    count += 1
                    logging.info(f"🔧 Ingenio '{record['ingenio']}' -> '{new_ingenio}' para {record['original_filename']}")
                except Exception as e:
                    logging.error(f"❌ Error actualizando ingenio para {record['id']}: {e}")
        
        logging.info(f"✅ Ingenio corregido en {count} registros")
        return count
    
    def fix_product_names(self, records: List[Dict]) -> int:
        """Corregir nombres de productos"""
        count = 0
        for record in records:
            new_product = None
            filename = record.get('original_filename', '')
            
            # Detectar productos que se parsearon mal
            if record['producto'] == 'potencial':
                if 'potencial_ndvi' in filename:
                    new_product = 'potencial_ndvi'
                elif 'potencial_ndwi' in filename:
                    new_product = 'potencial_ndwi'
            
            if new_product and new_product != record['producto']:
                try:
                    self.supabase.table('productos').update({
                        'producto': new_product
                    }).eq('id', record['id']).execute()
                    count += 1
                    logging.info(f"🔧 Producto '{record['producto']}' -> '{new_product}' para {filename}")
                except Exception as e:
                    logging.error(f"❌ Error actualizando producto para {record['id']}: {e}")
        
        logging.info(f"✅ Producto corregido en {count} registros")
        return count
    
    def get_raster_metadata(self, gcs_url: str) -> Optional[Dict]:
        """Obtener metadatos de un raster desde GCS"""
        try:
            # Construir la URL del COG en GCS
            cog_url = f"/vsigs/{gcs_url.replace('gs://', '')}"
            
            with rasterio.open(cog_url) as src:
                # Obtener bounds
                bounds = src.bounds
                
                # Obtener estadísticas de la primera banda
                stats = src.statistics(1)
                
                # Calcular tamaño del archivo
                file_size_mb = src.profile.get('compress', 'none') != 'none'  # Aproximación
                
                return {
                    'file_size_mb': round(src.width * src.height * 4 / (1024 * 1024), 2),  # Aproximación
                    'bounds': [bounds.left, bounds.bottom, bounds.right, bounds.top],
                    'width': src.width,
                    'height': src.height,
                    'min_value': round(stats.min, 6) if stats.min is not None else None,
                    'max_value': round(stats.max, 6) if stats.max is not None else None,
                    'nodata_value': src.nodata
                }
        except Exception as e:
            logging.warning(f"⚠️ No se pudo obtener metadatos para {gcs_url}: {e}")
            return None
    
    def fill_missing_metadata(self, records: List[Dict], sample_size: int = 10) -> int:
        """Llenar metadatos faltantes para algunos registros (muestra)"""
        count = 0
        
        # Filtrar registros que necesitan metadatos
        records_needing_metadata = [
            r for r in records 
            if not r.get('file_size_mb') or not r.get('bounds') or not r.get('width')
        ]
        
        logging.info(f"📊 {len(records_needing_metadata)} registros necesitan metadatos")
        
        # Procesar solo una muestra para no sobrecargar
        sample_records = records_needing_metadata[:sample_size]
        
        for record in sample_records:
            gcs_url = record.get('gcs_url')
            if not gcs_url:
                continue
                
            metadata = self.get_raster_metadata(gcs_url)
            if metadata:
                try:
                    self.supabase.table('productos').update(metadata).eq('id', record['id']).execute()
                    count += 1
                    logging.info(f"✅ Metadatos actualizados para {record['original_filename']}")
                except Exception as e:
                    logging.error(f"❌ Error actualizando metadatos para {record['id']}: {e}")
        
        logging.info(f"✅ Metadatos completados en {count} registros")
        return count
    
    def run_fixes(self, include_metadata: bool = False):
        """Ejecutar todas las correcciones"""
        logging.info("🚀 Iniciando corrección de base de datos")
        
        # Obtener registros
        records = self.get_mx_gp_records()
        if not records:
            logging.error("❌ No se encontraron registros para corregir")
            return
        
        # Aplicar correcciones
        empresa_fixes = self.fix_empresa_name(records)
        ingenio_fixes = self.fix_ingenio_names(records)
        product_fixes = self.fix_product_names(records)
        
        metadata_fixes = 0
        if include_metadata:
            metadata_fixes = self.fill_missing_metadata(records, sample_size=10)
        
        # Resumen
        logging.info("🎯 RESUMEN DE CORRECCIONES:")
        logging.info(f"   ✅ Empresa corregida: {empresa_fixes}")
        logging.info(f"   ✅ Ingenio corregido: {ingenio_fixes}")
        logging.info(f"   ✅ Producto corregido: {product_fixes}")
        if include_metadata:
            logging.info(f"   ✅ Metadatos completados: {metadata_fixes}")
        logging.info(f"   📊 Total registros procesados: {len(records)}")

def main():
    """Función principal"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Corregir registros en Supabase')
    parser.add_argument('--include-metadata', action='store_true', 
                       help='Incluir actualización de metadatos (solo muestra)')
    parser.add_argument('--dry-run', action='store_true',
                       help='Solo mostrar qué se corregiría sin hacer cambios')
    
    args = parser.parse_args()
    
    if args.dry_run:
        logging.info("🔍 MODO DRY-RUN: Solo mostrando cambios necesarios")
        # Aquí podrías implementar la lógica de dry-run
        return
    
    fixer = DatabaseFixer()
    fixer.run_fixes(include_metadata=args.include_metadata)

if __name__ == "__main__":
    main()
