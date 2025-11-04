#!/usr/bin/env python3
"""
Script para calcular y actualizar los centroides de los ingenios en la vista vw_centroide_global
basándose en las geometrías de las parcelas activas de cada ingenio.
"""

import json

# Configuración directa de Supabase (desde .env)
SUPABASE_CONFIG = {
    'host': 'db.eewlwrgzeypfwjruzshj.supabase.co',
    'database': 'postgres', 
    'user': 'postgres',
    'password': 'Tecnoanalytics2024!',  # Necesitas reemplazar con tu password real
    'port': 5432
}

def main():
    try:
        # Intentar importar psycopg2
        try:
            import psycopg2
        except ImportError:
            print("❌ Error: psycopg2 no está instalado")
            print("💡 Solución: ejecuta 'pip install psycopg2-binary'")
            return False

        # Conexión a Supabase
        conn = psycopg2.connect(**SUPABASE_CONFIG)
        
        cur = conn.cursor()
        print("✅ Conectado a Supabase PostgreSQL")
        
        # Paso 1: Verificar la estructura actual de la vista
        print("\n=== ESTRUCTURA ACTUAL DE vw_centroide_global ===")
        cur.execute("SELECT * FROM vw_centroide_global ORDER BY ingenio;")
        current_data = cur.fetchall()
        
        cur.execute("""
        SELECT column_name, data_type 
        FROM information_schema.columns 
        WHERE table_name = 'vw_centroide_global'
        ORDER BY ordinal_position;
        """)
        columns = cur.fetchall()
        
        print("Columnas de la vista:")
        for col in columns:
            print(f"  - {col[0]}: {col[1]}")
            
        print("\nDatos actuales:")
        for row in current_data:
            print(f"  {row}")
        
        # Paso 2: Calcular centroides desde las parcelas
        print("\n=== CALCULANDO CENTROIDES DESDE PARCELAS ===")
        
        query_centroides = """
        SELECT 
            ingenio,
            COUNT(*) as total_parcelas,
            ST_Y(ST_Centroid(ST_Union(geometry_polygon))) as centroide_lat,
            ST_X(ST_Centroid(ST_Union(geometry_polygon))) as centroide_lng,
            ST_YMin(ST_Union(geometry_polygon)) as min_lat,
            ST_YMax(ST_Union(geometry_polygon)) as max_lat,
            ST_XMin(ST_Union(geometry_polygon)) as min_lng,
            ST_XMax(ST_Union(geometry_polygon)) as max_lng
        FROM parcelas_ingenios 
        WHERE activo = true 
        AND geometry_polygon IS NOT NULL
        GROUP BY ingenio
        ORDER BY ingenio;
        """
        
        cur.execute(query_centroides)
        centroides_calculados = cur.fetchall()
        
        print("Centroides calculados desde parcelas:")
        for row in centroides_calculados:
            ingenio, total, lat, lng, min_lat, max_lat, min_lng, max_lng = row
            print(f"  {ingenio}: ({lat:.6f}, {lng:.6f}) - {total} parcelas")
            print(f"    Bounds: ({min_lat:.6f}, {min_lng:.6f}) a ({max_lat:.6f}, {max_lng:.6f})")
        
        # Paso 3: Verificar si existe una tabla base para la vista
        print("\n=== VERIFICANDO TABLA BASE ===")
        
        # Intentar encontrar la definición de la vista
        cur.execute("""
        SELECT definition FROM pg_views 
        WHERE viewname = 'vw_centroide_global';
        """)
        
        view_def = cur.fetchone()
        if view_def:
            print("Definición actual de la vista:")
            print(view_def[0])
        
        # Verificar si existe una tabla llamada centroide_global o similar
        cur.execute("""
        SELECT table_name FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name LIKE '%centroide%'
        ORDER BY table_name;
        """)
        
        tables = cur.fetchall()
        print(f"\nTablas relacionadas con centroides: {tables}")
        
        # Paso 4: Crear/actualizar la tabla base si no existe
        print("\n=== CREANDO/ACTUALIZANDO TABLA BASE ===")
        
        # Verificar si existe la tabla centroides_ingenios
        cur.execute("""
        SELECT EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_name = 'centroides_ingenios'
        );
        """)
        
        table_exists = cur.fetchone()[0]
        
        if not table_exists:
            print("Creando tabla centroides_ingenios...")
            cur.execute("""
            CREATE TABLE centroides_ingenios (
                id SERIAL PRIMARY KEY,
                ingenio VARCHAR(100) UNIQUE NOT NULL,
                centroide_lat DOUBLE PRECISION NOT NULL,
                centroide_lng DOUBLE PRECISION NOT NULL,
                min_lat DOUBLE PRECISION,
                max_lat DOUBLE PRECISION,
                min_lng DOUBLE PRECISION,
                max_lng DOUBLE PRECISION,
                total_parcelas INTEGER,
                fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
            """)
            
            # Crear índices
            cur.execute("CREATE INDEX idx_centroides_ingenio ON centroides_ingenios(ingenio);")
            print("✅ Tabla centroides_ingenios creada")
        else:
            print("Tabla centroides_ingenios ya existe")
        
        # Paso 5: Insertar/actualizar los centroides calculados
        print("\n=== INSERTANDO/ACTUALIZANDO CENTROIDES ===")
        
        for row in centroides_calculados:
            ingenio, total, lat, lng, min_lat, max_lat, min_lng, max_lng = row
            
            # Usar UPSERT (INSERT ... ON CONFLICT)
            cur.execute("""
            INSERT INTO centroides_ingenios 
            (ingenio, centroide_lat, centroide_lng, min_lat, max_lat, min_lng, max_lng, total_parcelas, fecha_actualizacion, updated_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            ON CONFLICT (ingenio) 
            DO UPDATE SET 
                centroide_lat = EXCLUDED.centroide_lat,
                centroide_lng = EXCLUDED.centroide_lng,
                min_lat = EXCLUDED.min_lat,
                max_lat = EXCLUDED.max_lat,
                min_lng = EXCLUDED.min_lng,
                max_lng = EXCLUDED.max_lng,
                total_parcelas = EXCLUDED.total_parcelas,
                fecha_actualizacion = CURRENT_TIMESTAMP,
                updated_at = CURRENT_TIMESTAMP;
            """, (ingenio, lat, lng, min_lat, max_lat, min_lng, max_lng, total))
            
            print(f"✅ Actualizado centroide para {ingenio}")
        
        # Paso 6: Recrear la vista vw_centroide_global
        print("\n=== RECREANDO VISTA vw_centroide_global ===")
        
        # Eliminar la vista actual si existe
        cur.execute("DROP VIEW IF EXISTS vw_centroide_global;")
        
        # Crear la nueva vista basada en la tabla
        cur.execute("""
        CREATE VIEW vw_centroide_global AS
        SELECT 
            ingenio,
            centroide_lat as latitude,
            centroide_lng as longitude,
            min_lat,
            max_lat,
            min_lng,
            max_lng,
            total_parcelas,
            fecha_actualizacion
        FROM centroides_ingenios
        ORDER BY ingenio;
        """)
        
        print("✅ Vista vw_centroide_global recreada")
        
        # Paso 7: Verificar los resultados
        print("\n=== VERIFICANDO RESULTADOS ===")
        cur.execute("SELECT * FROM vw_centroide_global ORDER BY ingenio;")
        resultados = cur.fetchall()
        
        print("Nueva vista vw_centroide_global:")
        for row in resultados:
            print(f"  {row}")
        
        # Confirmar cambios
        conn.commit()
        print("\n✅ CENTROIDES ACTUALIZADOS EXITOSAMENTE")
        
        # Mostrar resumen final
        print("\n=== RESUMEN FINAL ===")
        print("Centroides por ingenio:")
        for row in resultados:
            ingenio, lat, lng, min_lat, max_lat, min_lng, max_lng, total, fecha = row
            print(f"  • {ingenio}: ({lat:.6f}, {lng:.6f}) - {total} parcelas")
        
        
    except Exception as e:
        print(f"❌ Error: {e}")
        if conn:
            conn.rollback()
        return False
    
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()
        print("\n🔐 Conexión cerrada")
    
    return True

if __name__ == "__main__":
    main()
