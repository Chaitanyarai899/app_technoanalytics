#!/usr/bin/env python3
"""
=============================================================================
Database Verification and Migration Script
=============================================================================
"""

import os
import sys
from supabase import create_client, Client
from dotenv import load_dotenv

# Cargar variables de entorno
load_dotenv()

def get_supabase_client() -> Client:
    """Crear cliente de Supabase"""
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    
    if not url or not key:
        print("❌ Error: SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY deben estar configurados en .env")
        sys.exit(1)
    
    return create_client(url, key)

def verify_table_structure(supabase: Client):
    """Verificar estructura actual de la tabla"""
    print("🔍 Verificando estructura actual de la tabla productos...")
    
    try:
        # Obtener información de columnas
        result = supabase.rpc('exec_sql', {
            'sql': """
            SELECT column_name, data_type, is_nullable, column_default
            FROM information_schema.columns 
            WHERE table_name = 'productos' AND table_schema = 'public'
            ORDER BY ordinal_position;
            """
        })
        
        if result.data:
            print("✅ Tabla productos encontrada")
            print("\n📋 Columnas actuales:")
            for col in result.data:
                print(f"  • {col['column_name']} ({col['data_type']})")
        else:
            print("❌ No se pudo obtener información de la tabla")
            
    except Exception as e:
        print(f"❌ Error al verificar tabla: {e}")
        return False
    
    return True

def check_new_columns(supabase: Client):
    """Verificar si las nuevas columnas ya existen"""
    print("\n🔍 Verificando columnas para COG...")
    
    required_columns = [
        'cog_url', 'cog_filename', 'original_filename', 'file_size_mb',
        'bounds', 'epsg', 'width', 'height', 'bands',
        'min_value', 'max_value', 'nodata_value', 'processing_status',
        'created_at', 'updated_at', 'processing_log', 'colormap',
        'rescale_min', 'rescale_max'
    ]
    
    try:
        result = supabase.rpc('exec_sql', {
            'sql': """
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'productos' 
            AND table_schema = 'public'
            AND column_name = ANY(%s);
            """ % str(required_columns).replace('[', 'ARRAY[').replace("'", "''")
        })
        
        existing_columns = [col['column_name'] for col in result.data] if result.data else []
        missing_columns = [col for col in required_columns if col not in existing_columns]
        
        if missing_columns:
            print(f"⚠️  Faltan {len(missing_columns)} columnas para COG:")
            for col in missing_columns:
                print(f"  • {col}")
            return False
        else:
            print("✅ Todas las columnas para COG están presentes")
            return True
            
    except Exception as e:
        print(f"❌ Error al verificar columnas: {e}")
        return False

def apply_migration(supabase: Client):
    """Aplicar migración si es necesaria"""
    print("\n🚀 Aplicando migración...")
    
    # Leer archivo de migración
    migration_file = "supabase/sql/002_productos_cog_migration.sql"
    
    if not os.path.exists(migration_file):
        print(f"❌ Archivo de migración no encontrado: {migration_file}")
        return False
    
    try:
        with open(migration_file, 'r', encoding='utf-8') as f:
            sql_content = f.read()
        
        # Ejecutar migración
        print("⏳ Ejecutando migración...")
        
        # Dividir en statements individuales y ejecutar
        statements = [stmt.strip() for stmt in sql_content.split(';') if stmt.strip()]
        
        for i, statement in enumerate(statements):
            if statement.upper().startswith(('ALTER', 'CREATE', 'COMMENT')):
                try:
                    result = supabase.rpc('exec_sql', {'sql': statement})
                    print(f"✅ Statement {i+1}/{len(statements)} ejecutado")
                except Exception as e:
                    # Algunos statements pueden fallar si ya existen (ALTER TABLE IF NOT EXISTS)
                    if "already exists" in str(e) or "duplicate" in str(e).lower():
                        print(f"⚠️  Statement {i+1} ya existe, continuando...")
                    else:
                        print(f"❌ Error en statement {i+1}: {e}")
        
        print("✅ Migración completada")
        return True
        
    except Exception as e:
        print(f"❌ Error al aplicar migración: {e}")
        return False

def verify_functions(supabase: Client):
    """Verificar que las funciones se crearon correctamente"""
    print("\n🔍 Verificando funciones...")
    
    functions = [
        'get_products_with_cog',
        'find_product_by_filename',
        'get_processing_stats'
    ]
    
    try:
        for func in functions:
            result = supabase.rpc('exec_sql', {
                'sql': f"""
                SELECT routine_name 
                FROM information_schema.routines 
                WHERE routine_name = '{func}' 
                AND routine_schema = 'public';
                """
            })
            
            if result.data:
                print(f"✅ Función {func} disponible")
            else:
                print(f"❌ Función {func} no encontrada")
    
    except Exception as e:
        print(f"❌ Error al verificar funciones: {e}")

def test_functions(supabase: Client):
    """Probar las funciones creadas"""
    print("\n🧪 Probando funciones...")
    
    try:
        # Probar get_processing_stats
        result = supabase.rpc('get_processing_stats')
        if result.data:
            stats = result.data[0]
            print(f"📊 Estadísticas actuales:")
            print(f"  • Total productos: {stats.get('total_products', 0)}")
            print(f"  • Completados: {stats.get('completed', 0)}")
            print(f"  • Pendientes: {stats.get('pending', 0)}")
            print(f"  • Fallidos: {stats.get('failed', 0)}")
            
    except Exception as e:
        print(f"⚠️  Error al probar funciones: {e}")

def main():
    """Función principal"""
    print("🗄️  VERIFICACIÓN Y MIGRACIÓN DE BASE DE DATOS")
    print("=" * 50)
    
    # Crear cliente Supabase
    supabase = get_supabase_client()
    
    # Verificar estructura actual
    if not verify_table_structure(supabase):
        print("❌ No se pudo verificar la tabla. Saliendo...")
        sys.exit(1)
    
    # Verificar si necesita migración
    needs_migration = not check_new_columns(supabase)
    
    if needs_migration:
        print("\n⚡ Se requiere migración")
        response = input("\n¿Desea aplicar la migración? (s/N): ")
        
        if response.lower() in ['s', 'si', 'sí', 'y', 'yes']:
            if apply_migration(supabase):
                print("\n✅ Migración aplicada exitosamente")
            else:
                print("\n❌ Error en la migración")
                sys.exit(1)
        else:
            print("⏹️  Migración cancelada")
            sys.exit(0)
    
    # Verificar funciones
    verify_functions(supabase)
    
    # Probar funciones
    test_functions(supabase)
    
    print("\n🎉 Verificación completada!")
    print("\n📝 Próximos pasos:")
    print("1. Actualizar archivo .env con credenciales de Supabase")
    print("2. Ejecutar script de ingesta de rasters")
    print("3. Verificar datos en Supabase")

if __name__ == "__main__":
    main()
