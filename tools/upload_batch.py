#!/usr/bin/env python3
"""
=============================================================================
SCRIPT DE CARGA MASIVA - PRODUCTION READY
Cargar múltiples rasters a la nueva infraestructura
=============================================================================
"""

import os
import sys
from pathlib import Path
import subprocess
import logging

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def upload_file_to_gcs(local_file, gcs_path):
    """Subir archivo a Google Cloud Storage"""
    try:
        cmd = ['gsutil', 'cp', str(local_file), f'gs://ta-cogs-apicorreo-prod/{gcs_path}']
        
        logger.info(f"📤 Subiendo: {local_file.name}")
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            logger.info(f"✅ Subido: {gcs_path}")
            return True
        else:
            logger.error(f"❌ Error: {result.stderr}")
            return False
            
    except Exception as e:
        logger.error(f"Error subiendo {local_file}: {e}")
        return False

def main():
    """Función principal"""
    print("=== CARGA MASIVA DE RASTERS ===")
    print()
    
    # Directorio de archivos
    test_files_dir = Path("test_files")
    
    if not test_files_dir.exists():
        logger.error(f"❌ Directorio no encontrado: {test_files_dir}")
        return 1
    
    # Encontrar archivos TIF principales (sin auxiliares)
    tif_files = [f for f in test_files_dir.glob('*.tif') 
                if not any(suffix in f.name for suffix in ['.aux.xml', '.ovr'])]
    
    if not tif_files:
        logger.warning("⚠️ No se encontraron archivos TIF")
        return 0
    
    logger.info(f"📁 Archivos encontrados: {len(tif_files)}")
    
    # Contadores
    uploaded = 0
    failed = 0
    
    # Procesar archivos
    for i, tif_file in enumerate(tif_files, 1):
        print(f"\n═══ ARCHIVO {i}/{len(tif_files)} ═══")
        
        # Generar path en GCS
        gcs_path = f"cogs/{tif_file.stem}_cog.tif"
        
        # Subir archivo (usando el original como COG por ahora)
        if upload_file_to_gcs(tif_file, gcs_path):
            uploaded += 1
            
            # Mostrar URL de TiTiler
            titiler_url = f"https://ta-titiler-service-1087100331392.us-central1.run.app/cog/info?url=gs://ta-cogs-apicorreo-prod/{gcs_path}"
            logger.info(f"🌐 TiTiler: {titiler_url}")
        else:
            failed += 1
    
    # Resumen
    print(f"\n📊 RESUMEN DE CARGA:")
    print(f"✅ Subidos: {uploaded}")
    print(f"❌ Fallidos: {failed}")
    
    if uploaded > 0:
        print(f"\n🎉 ¡{uploaded} archivos disponibles en la nueva infraestructura!")
        print(f"🌐 TiTiler Service: https://ta-titiler-service-1087100331392.us-central1.run.app")
        print(f"📊 Supabase Dashboard: https://eewlwrgzeypfwjruzshj.supabase.co")
        
        print(f"\n📱 PRÓXIMO PASO:")
        print(f"   Abre tu app Flutter y verifica que los rasters se cargan correctamente")
        print(f"   con la nueva infraestructura moderna.")
    
    return 0 if failed == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
