#!/usr/bin/env python3
"""
=============================================================================
INVENTARIO RÁPIDO DE RASTERS
Listar todos los rasters y su estado de migración
=============================================================================
"""

import os
import json
import requests
from pathlib import Path
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
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

def get_database_status():
    """Obtener estado actual de la base de datos"""
    env_vars = load_env()
    if not env_vars:
        return []
    
    headers = {
        "Authorization": f"Bearer {env_vars.get('SUPABASE_SERVICE_ROLE_KEY')}",
        "apikey": env_vars.get('SUPABASE_SERVICE_ROLE_KEY'),
        "Content-Type": "application/json"
    }
    
    try:
        response = requests.get(
            f"{env_vars.get('SUPABASE_URL')}/rest/v1/productos?select=*",
            headers=headers
        )
        response.raise_for_status()
        return response.json()
    except Exception as e:
        logger.error(f"Error consultando DB: {e}")
        return []

def main():
    """Función principal"""
    print("🔍 INVENTARIO RÁPIDO DE RASTERS")
    print("=" * 50)
    
    # Escanear archivos locales
    test_files_dir = Path("test_files")
    local_files = []
    
    if test_files_dir.exists():
        local_files = [f for f in test_files_dir.glob('*.tif') 
                      if not any(suffix in f.name for suffix in ['.aux.xml', '.ovr'])]
    
    # Obtener estado de la DB
    db_records = get_database_status()
    
    print(f"\n📁 ARCHIVOS LOCALES: {len(local_files)}")
    print(f"💾 REGISTROS EN DB: {len(db_records)}")
    
    # Análisis por estado
    status_counts = {}
    migrated_files = set()
    
    for record in db_records:
        status = record.get('processing_status', 'unknown')
        status_counts[status] = status_counts.get(status, 0) + 1
        
        if status == 'completed' and record.get('cog_url'):
            migrated_files.add(record.get('original_filename', ''))
    
    print(f"\n📊 ESTADO DE MIGRACIÓN:")
    for status, count in status_counts.items():
        emoji = "✅" if status == "completed" else "🔄" if status == "processing" else "❌"
        print(f"   {emoji} {status}: {count}")
    
    # Archivos pendientes
    pending_files = [f for f in local_files if f.name not in migrated_files]
    
    print(f"\n⏳ ARCHIVOS PENDIENTES DE MIGRACIÓN: {len(pending_files)}")
    for file in pending_files[:10]:  # Mostrar primeros 10
        print(f"   📄 {file.name}")
    
    if len(pending_files) > 10:
        print(f"   ... y {len(pending_files) - 10} más")
    
    # Generar reporte JSON
    report = {
        "timestamp": datetime.now().isoformat(),
        "local_files_count": len(local_files),
        "db_records_count": len(db_records),
        "status_breakdown": status_counts,
        "pending_migration": len(pending_files),
        "migration_progress": f"{len(migrated_files)}/{len(local_files)}" if local_files else "0/0"
    }
    
    with open('migration_inventory.json', 'w') as f:
        json.dump(report, f, indent=2)
    
    print(f"\n📄 Reporte detallado guardado en: migration_inventory.json")
    
    # Recomendaciones
    if pending_files:
        print(f"\n🚀 PRÓXIMO PASO:")
        print(f"   python ingest_production.py test_files/ --force")
        print(f"   (Procesará {len(pending_files)} archivos pendientes)")
    else:
        print(f"\n🎉 ¡MIGRACIÓN COMPLETA!")
        print(f"   Todos los archivos están migrados al nuevo sistema.")

if __name__ == "__main__":
    main()
