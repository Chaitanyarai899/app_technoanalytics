#!/usr/bin/env python3
"""
Script para actualizar los nombres de ingenios en la tabla parcelas_ingenios
Convierte espacios a guiones bajos para mantener consistencia con el frontend
"""

import os
from supabase import create_client, Client

def get_supabase_client():
    """Crear cliente de Supabase"""
    url = "https://eewlwrgzeypfwjruzshj.supabase.co"
    key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVld2x3cmd6ZXlwZndqcnV6c2hqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzE2MzQ0MzEsImV4cCI6MjA0NzIxMDQzMX0.Jgk9rwKV07ya4a21QGUjfGbCIgC6b4wWJgPeNZ9jIOo"
    return create_client(url, key)

def fix_ingenio_names():
    """Actualizar nombres de ingenios reemplazando espacios con guiones bajos"""
    supabase = get_supabase_client()
    
    try:
        print("🔍 Obteniendo ingenios únicos de parcelas_ingenios...")
        
        # Obtener todos los ingenios únicos
        response = supabase.table('parcelas_ingenios').select('ingenio').execute()
        
        if not response.data:
            print("❌ No se encontraron datos en parcelas_ingenios")
            return
        
        # Obtener ingenios únicos
        ingenios_unicos = list(set([row['ingenio'] for row in response.data if row['ingenio']]))
        
        print(f"📊 Encontrados {len(ingenios_unicos)} ingenios únicos:")
        for ingenio in sorted(ingenios_unicos):
            print(f"  - {ingenio}")
        
        # Buscar ingenios que tengan espacios
        ingenios_con_espacios = [ing for ing in ingenios_unicos if ' ' in ing]
        
        if not ingenios_con_espacios:
            print("✅ No se encontraron ingenios con espacios")
            return
        
        print(f"\n🔧 Ingenios que necesitan actualización ({len(ingenios_con_espacios)}):")
        for ingenio in ingenios_con_espacios:
            nuevo_nombre = ingenio.replace(' ', '_')
            print(f"  - '{ingenio}' → '{nuevo_nombre}'")
        
        # Confirmar antes de proceder
        respuesta = input("\n¿Proceder con la actualización? (s/N): ").strip().lower()
        if respuesta != 's':
            print("❌ Operación cancelada")
            return
        
        # Actualizar cada ingenio
        for ingenio_original in ingenios_con_espacios:
            ingenio_nuevo = ingenio_original.replace(' ', '_')
            
            print(f"\n🔄 Actualizando '{ingenio_original}' → '{ingenio_nuevo}'...")
            
            # Actualizar en parcelas_ingenios
            response = supabase.table('parcelas_ingenios')\
                .update({'ingenio': ingenio_nuevo})\
                .eq('ingenio', ingenio_original)\
                .execute()
            
            if response.data:
                print(f"✅ Actualizados {len(response.data)} registros en parcelas_ingenios")
            else:
                print(f"⚠️ No se actualizaron registros para {ingenio_original}")
        
        print(f"\n🎯 Proceso completado. Verificando resultados...")
        
        # Verificar que ya no hay espacios
        response = supabase.table('parcelas_ingenios').select('ingenio').execute()
        ingenios_verificacion = list(set([row['ingenio'] for row in response.data if row['ingenio']]))
        ingenios_con_espacios_final = [ing for ing in ingenios_verificacion if ' ' in ing]
        
        if ingenios_con_espacios_final:
            print(f"⚠️ Aún quedan {len(ingenios_con_espacios_final)} ingenios con espacios:")
            for ingenio in ingenios_con_espacios_final:
                print(f"  - {ingenio}")
        else:
            print("✅ Todos los ingenios ahora usan guiones bajos correctamente")
            
    except Exception as e:
        print(f"❌ Error durante la actualización: {e}")

if __name__ == "__main__":
    print("🚀 Iniciando actualización de nombres de ingenios...")
    fix_ingenio_names()
    print("🏁 Proceso terminado")
