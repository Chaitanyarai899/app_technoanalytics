#!/usr/bin/env python3
"""
Script para corregir los nombres de empresa en la base de datos
"""

import requests
import json

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

def fix_empresa_names(supabase_url, service_key):
    """Corregir nombres de empresa en Supabase"""
    
    headers = {
        "Authorization": f"Bearer {service_key}",
        "apikey": service_key,
        "Content-Type": "application/json",
        "Prefer": "return=representation"
    }
    
    try:
        # Buscar registros con empresa "mx_gp"
        check_response = requests.get(
            f"{supabase_url}/rest/v1/productos?empresa=eq.mx_gp",
            headers=headers
        )
        
        if check_response.status_code == 200:
            records = check_response.json()
            print(f"📊 Encontrados {len(records)} registros con empresa 'mx_gp'")
            
            if len(records) == 0:
                print("ℹ️  No hay registros que corregir")
                return 0
            
            # Actualizar cada registro
            updated_count = 0
            for record in records:
                record_id = record['id']
                
                # Actualizar el registro
                update_response = requests.patch(
                    f"{supabase_url}/rest/v1/productos?id=eq.{record_id}",
                    headers=headers,
                    json={"empresa": "Grupo Porres"}
                )
                
                if update_response.status_code == 204:
                    print(f"✅ Actualizado registro ID: {record_id}")
                    updated_count += 1
                else:
                    print(f"❌ Error actualizando registro {record_id}: {update_response.text}")
            
            return updated_count
        else:
            print(f"❌ Error consultando registros: {check_response.text}")
            return 0
            
    except Exception as e:
        print(f"❌ Error en fix_empresa_names: {e}")
        return 0

def main():
    print("=== CORREGIR NOMBRES DE EMPRESA EN SUPABASE ===")
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
    
    # Corregir nombres
    updated = fix_empresa_names(supabase_url, service_key)
    
    print(f"\n📊 RESUMEN:")
    print(f"✅ Registros actualizados: {updated}")
    
    if updated > 0:
        print(f"\n🎉 ¡Nombres de empresa corregidos!")
        print(f"✅ 'mx_gp' → 'Grupo Porres'")
    
    return 0

if __name__ == "__main__":
    import sys
    sys.exit(main())
