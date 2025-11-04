#!/usr/bin/env python3
"""
=============================================================================
ROLLBACK DE EMERGENCIA
Revertir migración en caso de problemas críticos
=============================================================================
"""

import os
import json
import requests
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

def backup_current_state():
    """Crear backup del estado actual antes del rollback"""
    env_vars = load_env()
    if not env_vars:
        return False
    
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
        
        backup_data = {
            "timestamp": datetime.now().isoformat(),
            "products": response.json()
        }
        
        backup_filename = f"backup_before_rollback_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(backup_filename, 'w') as f:
            json.dump(backup_data, f, indent=2)
        
        logger.info(f"✅ Backup creado: {backup_filename}")
        return True
        
    except Exception as e:
        logger.error(f"❌ Error creando backup: {e}")
        return False

def reset_processing_status():
    """Resetear estados de procesamiento problemáticos"""
    env_vars = load_env()
    if not env_vars:
        return False
    
    headers = {
        "Authorization": f"Bearer {env_vars.get('SUPABASE_SERVICE_ROLE_KEY')}",
        "apikey": env_vars.get('SUPABASE_SERVICE_ROLE_KEY'),
        "Content-Type": "application/json",
        "Prefer": "return=representation"
    }
    
    try:
        # Resetear productos en estado 'processing' a 'pending'
        response = requests.patch(
            f"{env_vars.get('SUPABASE_URL')}/rest/v1/productos?processing_status=eq.processing",
            headers=headers,
            json={
                "processing_status": "pending",
                "processing_log": f"Reset by rollback script: {datetime.now()}"
            }
        )
        response.raise_for_status()
        
        # Resetear productos 'failed' a 'pending' para reintento
        response2 = requests.patch(
            f"{env_vars.get('SUPABASE_URL')}/rest/v1/productos?processing_status=eq.failed",
            headers=headers,
            json={
                "processing_status": "pending",
                "processing_log": f"Reset by rollback script: {datetime.now()}"
            }
        )
        response2.raise_for_status()
        
        logger.info("✅ Estados de procesamiento reseteados")
        return True
        
    except Exception as e:
        logger.error(f"❌ Error reseteando estados: {e}")
        return False

def clear_problematic_cogs():
    """Limpiar COGs problemáticos de la base de datos"""
    env_vars = load_env()
    if not env_vars:
        return False
    
    headers = {
        "Authorization": f"Bearer {env_vars.get('SUPABASE_SERVICE_ROLE_KEY')}",
        "apikey": env_vars.get('SUPABASE_SERVICE_ROLE_KEY'),
        "Content-Type": "application/json"
    }
    
    try:
        # Limpiar URLs de COG que podrían estar corruptas
        response = requests.patch(
            f"{env_vars.get('SUPABASE_URL')}/rest/v1/productos?processing_status=eq.failed",
            headers=headers,
            json={
                "cog_url": None,
                "cog_filename": None,
                "processing_status": "pending",
                "processing_log": f"Cleared by rollback script: {datetime.now()}"
            }
        )
        response.raise_for_status()
        
        logger.info("✅ COGs problemáticos limpiados")
        return True
        
    except Exception as e:
        logger.error(f"❌ Error limpiando COGs: {e}")
        return False

def main():
    """Función principal del rollback"""
    print("🔧 ROLLBACK DE EMERGENCIA")
    print("=" * 50)
    print("⚠️  Este script revertirá cambios de la migración")
    print("⚠️  Solo usar en caso de problemas críticos")
    print()
    
    # Confirmación del usuario
    confirm = input("¿Estás seguro de que quieres proceder? (escribir 'CONFIRMAR'): ")
    if confirm != "CONFIRMAR":
        print("❌ Rollback cancelado")
        return 0
    
    print("\n🔄 Iniciando proceso de rollback...")
    
    # Paso 1: Crear backup
    print("\n📦 Paso 1/3: Creando backup del estado actual...")
    if not backup_current_state():
        print("❌ Error creando backup. Rollback abortado.")
        return 1
    
    # Paso 2: Resetear estados
    print("\n🔄 Paso 2/3: Reseteando estados de procesamiento...")
    if not reset_processing_status():
        print("❌ Error reseteando estados")
        return 1
    
    # Paso 3: Limpiar COGs problemáticos
    print("\n🧹 Paso 3/3: Limpiando COGs problemáticos...")
    if not clear_problematic_cogs():
        print("❌ Error limpiando COGs")
        return 1
    
    print("\n✅ ROLLBACK COMPLETADO")
    print()
    print("📋 ACCIONES COMPLETADAS:")
    print("   ✅ Backup del estado actual creado")
    print("   ✅ Estados de procesamiento reseteados")
    print("   ✅ COGs problemáticos limpiados")
    print()
    print("🚀 PRÓXIMOS PASOS:")
    print("   1. Revisar logs para identificar problemas")
    print("   2. Corregir configuración si es necesario")
    print("   3. Reiniciar migración: python ingest_production.py test_files/")
    print()
    print("📞 Si persisten problemas, contactar al equipo técnico")
    
    return 0

if __name__ == "__main__":
    exit(main())
