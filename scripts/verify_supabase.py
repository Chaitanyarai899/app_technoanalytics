#!/usr/bin/env python3
"""
Quick verification script for database setup
No dependencies on GDAL - just checks DB structure
"""

import os
import sys
from supabase import create_client

# Load environment variables manually (no dotenv dependency)
def load_env():
    env_vars = {}
    try:
        with open('.env', 'r') as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    key, value = line.strip().split('=', 1)
                    env_vars[key] = value
    except FileNotFoundError:
        print("❌ .env file not found")
        return {}
    return env_vars

def main():
    print("🔍 Verificando configuración de Supabase...")
    
    # Load environment
    env = load_env()
    
    supabase_url = env.get('SUPABASE_URL')
    supabase_key = env.get('SUPABASE_SERVICE_ROLE_KEY')
    
    if not supabase_url or not supabase_key:
        print("❌ SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY no configurados")
        return False
    
    try:
        # Create Supabase client
        supabase = create_client(supabase_url, supabase_key)
        
        # Test connection by checking table structure
        result = supabase.table('productos').select('*').limit(1).execute()
        
        print("✅ Conexión a Supabase exitosa")
        print(f"   URL: {supabase_url}")
        
        # Check if new columns exist
        try:
            # Try to select new columns
            result = supabase.table('productos').select('cog_url,processing_status,created_at').limit(1).execute()
            print("✅ Nuevas columnas COG detectadas")
            print("   La migración parece haber sido ejecutada")
        except Exception as e:
            print("⚠️  Nuevas columnas COG no encontradas")
            print("   Es necesario ejecutar la migración SQL")
        
        # Get table stats
        try:
            result = supabase.table('productos').select('*', count='exact').execute()
            count = result.count
            print(f"📊 Total productos en DB: {count}")
        except:
            print("⚠️  No se pudo obtener estadísticas")
        
        return True
        
    except Exception as e:
        print(f"❌ Error conectando a Supabase: {e}")
        return False

if __name__ == "__main__":
    if main():
        print("\n🎉 Configuración verificada correctamente!")
        print("\n📝 Próximos pasos:")
        print("1. Si no has ejecutado la migración SQL, hazlo ahora")
        print("2. Instalar Python y GDAL para procesar rasters")
        print("3. Probar ingesta con archivo de ejemplo")
    else:
        print("\n❌ Verificación falló")
        sys.exit(1)
