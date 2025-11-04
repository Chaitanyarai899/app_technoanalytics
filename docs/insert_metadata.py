#!/usr/bin/env python3
"""
Script para insertar metadatos de los archivos subidos a Supabase
"""

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

def insert_product_metadata(supabase_url, service_key):
    """Insertar metadatos de productos en Supabase"""
    
    headers = {
        "Authorization": f"Bearer {service_key}",
        "apikey": service_key,
        "Content-Type": "application/json",
        "Prefer": "return=representation"
    }
    
    # Archivos que hemos subido
    productos = [
        {
            "producto": "ndvi",
            "empresa": "mx_gp", 
            "ingenio": "Huixtla",
            "fecha": "2024-11-22",
            "original_filename": "mx_gp_ndvi_Huixtla_20241122.tif",
            "cog_filename": "mx_gp_ndvi_Huixtla_20241122_cog.tif",
            "cog_url": "gs://ta-cogs-apicorreo-prod/cogs/mx_gp_ndvi_Huixtla_20241122_cog.tif",
            "file_size_mb": 9.8,
            "processing_status": "completed",
            "colormap": "viridis",
            "rescale_min": 0.0,
            "rescale_max": 1.0,
            "epsg": 4326,
            "bands": 1
        },
        {
            "producto": "ndvi",
            "empresa": "mx_gp",
            "ingenio": "Huixtla", 
            "fecha": "2024-11-27",
            "original_filename": "mx_gp_ndvi_Huixtla_20241127.tif",
            "cog_filename": "mx_gp_ndvi_Huixtla_20241127_cog.tif",
            "cog_url": "gs://ta-cogs-apicorreo-prod/cogs/mx_gp_ndvi_Huixtla_20241127_cog.tif",
            "file_size_mb": 10.5,
            "processing_status": "completed",
            "colormap": "viridis",
            "rescale_min": 0.0,
            "rescale_max": 1.0,
            "epsg": 4326,
            "bands": 1
        },
        {
            "producto": "ndvi",
            "empresa": "mx_gp",
            "ingenio": "Huixtla",
            "fecha": "2024-12-02", 
            "original_filename": "mx_gp_ndvi_Huixtla_20241202.tif",
            "cog_filename": "mx_gp_ndvi_Huixtla_20241202_cog.tif",
            "cog_url": "gs://ta-cogs-apicorreo-prod/cogs/mx_gp_ndvi_Huixtla_20241202_cog.tif",
            "file_size_mb": 10.5,
            "processing_status": "completed",
            "colormap": "viridis",
            "rescale_min": 0.0,
            "rescale_max": 1.0,
            "epsg": 4326,
            "bands": 1
        },
        {
            "producto": "ndvi",
            "empresa": "mx_gp",
            "ingenio": "Huixtla",
            "fecha": "2025-01-06",
            "original_filename": "mx_gp_ndvi_Huixtla_20250106.tif", 
            "cog_filename": "mx_gp_ndvi_Huixtla_20250106_cog.tif",
            "cog_url": "gs://ta-cogs-apicorreo-prod/cogs/mx_gp_ndvi_Huixtla_20250106_cog.tif",
            "file_size_mb": 364.0,
            "processing_status": "completed",
            "colormap": "viridis",
            "rescale_min": 0.0,
            "rescale_max": 1.0,
            "epsg": 4326,
            "bands": 1
        }
    ]
    
    created_count = 0
    
    for producto in productos:
        try:
            # Verificar si ya existe
            check_response = requests.get(
                f"{supabase_url}/rest/v1/productos?original_filename=eq.{producto['original_filename']}",
                headers=headers
            )
            
            if check_response.status_code == 200 and len(check_response.json()) > 0:
                print(f"⏭️  Ya existe: {producto['original_filename']}")
                continue
            
            # Crear nuevo registro
            response = requests.post(
                f"{supabase_url}/rest/v1/productos",
                headers=headers,
                json=producto
            )
            
            if response.status_code == 201:
                data = response.json()
                if data and len(data) > 0:
                    record_id = data[0]['id']
                    print(f"✅ Creado: {producto['original_filename']} (ID: {record_id})")
                    created_count += 1
                else:
                    print(f"✅ Creado: {producto['original_filename']}")
                    created_count += 1
            else:
                print(f"❌ Error creando {producto['original_filename']}: {response.text}")
                
        except Exception as e:
            print(f"❌ Error procesando {producto['original_filename']}: {e}")
    
    return created_count

def main():
    print("=== INSERTAR METADATOS EN SUPABASE ===")
    print()
    
    # Cargar configuración
    env_vars = load_env()
    if not env_vars:
        return 1
    
    supabase_url = env_vars.get('SUPABASE_URL')
    service_key = env_vars.get('SUPABASE_SERVICE_ROLE_KEY')
    
    if not all([supabase_url, service_key]):
        print("❌ Faltan variables de entorno requeridas")
        return 1
    
    # Insertar metadatos
    created = insert_product_metadata(supabase_url, service_key)
    
    print(f"\n📊 RESUMEN:")
    print(f"✅ Productos creados: {created}")
    
    if created > 0:
        print(f"\n🎉 ¡{created} productos listos en la nueva infraestructura!")
        print(f"")
        print(f"📱 URLs de ejemplo para la app:")
        print(f"   TiTiler Info: {env_vars.get('TITILER_BASE_URL', 'https://ta-titiler-service-1087100331392.us-central1.run.app')}/cog/info?url=gs://ta-cogs-apicorreo-prod/cogs/mx_gp_ndvi_Huixtla_20250106_cog.tif")
        print(f"   Tiles: {env_vars.get('TITILER_BASE_URL', 'https://ta-titiler-service-1087100331392.us-central1.run.app')}/cog/tiles/WebMercatorQuad/{{z}}/{{x}}/{{y}}.png?url=gs://ta-cogs-apicorreo-prod/cogs/mx_gp_ndvi_Huixtla_20250106_cog.tif&rescale=0,1&colormap_name=viridis")
        print(f"")
        print(f"🌐 Dashboard: {supabase_url.replace('/rest/v1', '')}")
    
    return 0

if __name__ == "__main__":
    import sys
    sys.exit(main())
