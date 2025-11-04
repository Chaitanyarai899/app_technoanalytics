#!/usr/bin/env python3
"""
=============================================================================
VALIDACIÓN MASIVA DE MIGRACIÓN
Verificar que todos los COGs son accesibles vía TiTiler
=============================================================================
"""

import os
import requests
import json
from datetime import datetime
import concurrent.futures
import logging
from urllib.parse import quote

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

def get_completed_products():
    """Obtener productos completados de la base de datos"""
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
            f"{env_vars.get('SUPABASE_URL')}/rest/v1/productos?processing_status=eq.completed&select=*",
            headers=headers
        )
        response.raise_for_status()
        return response.json()
    except Exception as e:
        logger.error(f"Error consultando DB: {e}")
        return []

def test_titiler_access(product):
    """Probar acceso a TiTiler para un producto"""
    cog_url = product.get('cog_url')
    if not cog_url:
        return {
            'product': product.get('original_filename', 'unknown'),
            'status': 'error',
            'message': 'No COG URL found'
        }
    
    titiler_base = "https://ta-titiler-service-1087100331392.us-central1.run.app"
    encoded_url = quote(cog_url, safe='')
    
    # Test 1: Info endpoint
    info_url = f"{titiler_base}/cog/info?url={encoded_url}"
    
    try:
        response = requests.get(info_url, timeout=10)
        
        if response.status_code == 200:
            info_data = response.json()
            
            # Test 2: Sample tile
            tile_url = f"{titiler_base}/cog/tiles/WebMercatorQuad/12/2048/1024.png?url={encoded_url}"
            tile_response = requests.head(tile_url, timeout=10)
            
            tile_ok = tile_response.status_code == 200
            
            return {
                'product': product.get('original_filename', 'unknown'),
                'status': 'success' if tile_ok else 'partial',
                'info_status': response.status_code,
                'tile_status': tile_response.status_code,
                'width': info_data.get('width'),
                'height': info_data.get('height'),
                'bands': info_data.get('band_metadata', [{}]).__len__(),
                'message': 'All endpoints working' if tile_ok else 'Info OK, tile failed'
            }
        else:
            return {
                'product': product.get('original_filename', 'unknown'),
                'status': 'error',
                'info_status': response.status_code,
                'message': f'TiTiler info failed: {response.status_code}'
            }
            
    except requests.exceptions.Timeout:
        return {
            'product': product.get('original_filename', 'unknown'),
            'status': 'timeout',
            'message': 'Request timeout'
        }
    except Exception as e:
        return {
            'product': product.get('original_filename', 'unknown'),
            'status': 'error',
            'message': f'Exception: {str(e)}'
        }

def main():
    """Función principal"""
    print("🔍 VALIDACIÓN MASIVA DE MIGRACIÓN")
    print("=" * 50)
    
    # Obtener productos completados
    products = get_completed_products()
    
    if not products:
        print("❌ No se encontraron productos completados para validar")
        return 1
    
    print(f"📊 Productos a validar: {len(products)}")
    print("🔄 Iniciando validación paralela...")
    
    # Validación paralela
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        future_to_product = {executor.submit(test_titiler_access, product): product 
                           for product in products}
        
        for i, future in enumerate(concurrent.futures.as_completed(future_to_product), 1):
            try:
                result = future.result()
                results.append(result)
                
                status_emoji = "✅" if result['status'] == 'success' else "⚠️" if result['status'] == 'partial' else "❌"
                print(f"   {status_emoji} {i}/{len(products)}: {result['product']} - {result['status']}")
                
            except Exception as exc:
                product = future_to_product[future]
                print(f"   ❌ {i}/{len(products)}: {product.get('original_filename', 'unknown')} - Exception: {exc}")
                results.append({
                    'product': product.get('original_filename', 'unknown'),
                    'status': 'exception',
                    'message': str(exc)
                })
    
    # Analizar resultados
    status_counts = {}
    for result in results:
        status = result['status']
        status_counts[status] = status_counts.get(status, 0) + 1
    
    print(f"\n📊 RESULTADOS DE VALIDACIÓN:")
    for status, count in status_counts.items():
        emoji = "✅" if status == "success" else "⚠️" if status == "partial" else "❌"
        print(f"   {emoji} {status}: {count}")
    
    # Problemas encontrados
    problems = [r for r in results if r['status'] not in ['success']]
    if problems:
        print(f"\n⚠️ PROBLEMAS ENCONTRADOS ({len(problems)}):")
        for problem in problems[:5]:  # Mostrar primeros 5
            print(f"   📄 {problem['product']}: {problem['message']}")
        
        if len(problems) > 5:
            print(f"   ... y {len(problems) - 5} más")
    
    # Generar reporte
    report = {
        "timestamp": datetime.now().isoformat(),
        "total_products": len(products),
        "validation_results": status_counts,
        "success_rate": f"{status_counts.get('success', 0)}/{len(products)}",
        "problems": problems
    }
    
    with open('validation_report.json', 'w') as f:
        json.dump(report, f, indent=2)
    
    print(f"\n📄 Reporte detallado guardado en: validation_report.json")
    
    # Recomendaciones
    success_rate = status_counts.get('success', 0) / len(products) * 100
    
    if success_rate >= 95:
        print(f"\n🎉 ¡MIGRACIÓN EXITOSA!")
        print(f"   {success_rate:.1f}% de los productos funcionan correctamente")
        print(f"   🚀 Sistema listo para producción")
    elif success_rate >= 80:
        print(f"\n⚠️ MIGRACIÓN MAYORMENTE EXITOSA")
        print(f"   {success_rate:.1f}% de los productos funcionan correctamente")
        print(f"   📋 Revisar productos con problemas")
    else:
        print(f"\n❌ MIGRACIÓN CON PROBLEMAS")
        print(f"   Solo {success_rate:.1f}% de los productos funcionan correctamente")
        print(f"   🔧 Necesario revisar configuración")
    
    return 0 if success_rate >= 95 else 1

if __name__ == "__main__":
    exit(main())
