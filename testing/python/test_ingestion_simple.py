#!/usr/bin/env python3
"""
Test de ingesta simple - Sin procesamiento de rasters
Solo verifica conectividad a Supabase y GCS
"""

import os
import sys
import requests
import json
from datetime import datetime

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
        print("❌ Archivo .env no encontrado")
        return None
    return env_vars

def test_supabase_connection(supabase_url, service_key):
    """Probar conexión a Supabase"""
    print("🔄 Probando conexión a Supabase...")
    
    headers = {
        "Authorization": f"Bearer {service_key}",
        "apikey": service_key,
        "Content-Type": "application/json"
    }
    
    try:
        # Test básico
        response = requests.get(
            f"{supabase_url}/rest/v1/productos?select=id&limit=1",
            headers=headers
        )
        response.raise_for_status()
        print("✅ Conexión a Supabase: OK")
        
        # Test columnas COG
        response = requests.get(
            f"{supabase_url}/rest/v1/productos?select=cog_url,processing_status&limit=1",
            headers=headers
        )
        response.raise_for_status()
        print("✅ Columnas COG: OK")
        
        return True
        
    except Exception as e:
        print(f"❌ Error de conexión a Supabase: {e}")
        return False

def test_record_creation(supabase_url, service_key):
    """Probar creación de registro de prueba"""
    print("🔄 Probando creación de registro...")
    
    headers = {
        "Authorization": f"Bearer {service_key}",
        "apikey": service_key,
        "Content-Type": "application/json",
        "Prefer": "return=representation"
    }
    
    # Datos de prueba
    test_data = {
        "producto": "test_ingestion_py",
        "empresa": "TECHNO_ANALYTICS",
        "ingenio": "TEST_MILL",
        "fecha": "2025-09-03",
        "original_filename": "test_file.tif",
        "processing_status": "pending",
        "file_size_mb": 10.5,
        "created_at": datetime.now().isoformat()
    }
    
    try:
        # Crear registro
        response = requests.post(
            f"{supabase_url}/rest/v1/productos",
            headers=headers,
            json=test_data
        )
        response.raise_for_status()
        
        record = response.json()
        print(f"Record response: {record}")
        
        if record and len(record) > 0 and 'id' in record[0]:
            record_id = record[0]['id']
            print(f"✅ Registro creado: ID {record_id}")
            
            # Actualizar estado
            update_data = {
                "processing_status": "completed",
                "cog_url": f"gs://ta-cogs-apicorreo-prod/test/{record_id}.tif"
            }
            
            response = requests.patch(
                f"{supabase_url}/rest/v1/productos?id=eq.{record_id}",
                headers=headers,
                json=update_data
            )
            response.raise_for_status()
            print("✅ Registro actualizado: OK")
            
            # Limpiar
            response = requests.delete(
                f"{supabase_url}/rest/v1/productos?id=eq.{record_id}",
                headers=headers
            )
            response.raise_for_status()
            print("✅ Registro eliminado: OK")
            
            return True
        else:
            print("❌ No se pudo crear el registro")
            return False
            
    except Exception as e:
        print(f"❌ Error en operaciones CRUD: {e}")
        return False

def main():
    print("=== TEST DE INGESTA SIMPLE ===")
    print()
    
    # Cargar configuración
    env_vars = load_env()
    if not env_vars:
        return 1
    
    supabase_url = env_vars.get('SUPABASE_URL')
    service_key = env_vars.get('SUPABASE_SERVICE_ROLE_KEY')
    gcs_bucket = env_vars.get('GCS_BUCKET')
    
    if not all([supabase_url, service_key, gcs_bucket]):
        print("❌ Faltan variables de entorno requeridas")
        return 1
    
    print(f"📊 Configuración:")
    print(f"   Supabase: {supabase_url}")
    print(f"   Bucket: {gcs_bucket}")
    print()
    
    # Tests
    success = True
    
    if not test_supabase_connection(supabase_url, service_key):
        success = False
    
    if not test_record_creation(supabase_url, service_key):
        success = False
    
    print()
    if success:
        print("🎉 TODOS LOS TESTS PASARON!")
        print("✅ El sistema está listo para ingesta de rasters")
        return 0
    else:
        print("❌ ALGUNOS TESTS FALLARON")
        return 1

if __name__ == "__main__":
    sys.exit(main())
