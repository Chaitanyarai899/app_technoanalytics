#!/usr/bin/env python3
"""
Script para verificar y arreglar TiTiler, y crear tiles con la paleta exacta de NDVI
"""

import requests
import json
from PIL import Image
import numpy as np
from matplotlib.colors import ListedColormap
import matplotlib.pyplot as plt

# Tu paleta exacta de NDVI
NDVI_COLORS = [
    "#000000", "#734C00", "#FF0000", "#E60000",
    "#FFAA00", "#FFFF73", "#D1FF73", "#55FF00", 
    "#38A800", "#73DFFF", "#0070FF", "#002673",
    "#C500FF", "#A80084"
]

def test_titiler_service():
    """Probar el servicio TiTiler"""
    base_url = "https://ta-titiler-service-1087100331392.us-central1.run.app"
    
    # Probar diferentes endpoints
    endpoints = [
        "/",
        "/docs",
        "/health", 
        "/colorMaps",
        "/cog/info?url=gs://ta-cogs-apicorreo-prod/cogs/mx_gp_ndvi_Huixtla_20241202_cog.tif"
    ]
    
    for endpoint in endpoints:
        try:
            response = requests.get(f"{base_url}{endpoint}", timeout=10)
            print(f"✅ {endpoint}: Status {response.status_code}")
            if response.status_code == 200:
                print(f"   Response: {response.text[:100]}...")
        except Exception as e:
            print(f"❌ {endpoint}: Error {e}")

def create_ndvi_colormap():
    """Crear un colormap matplotlib con tu paleta exacta"""
    # Convertir hex a RGB normalizado
    rgb_colors = []
    for hex_color in NDVI_COLORS:
        hex_color = hex_color.lstrip('#')
        rgb = tuple(int(hex_color[i:i+2], 16)/255.0 for i in (0, 2, 4))
        rgb_colors.append(rgb)
    
    # Crear colormap personalizado
    custom_cmap = ListedColormap(rgb_colors, name='custom_ndvi')
    
    # Guardar como imagen de referencia
    fig, ax = plt.subplots(figsize=(10, 2))
    gradient = np.linspace(0, 1, 256).reshape(1, -1)
    ax.imshow(gradient, aspect='auto', cmap=custom_cmap)
    ax.set_xlim(0, 256)
    ax.set_xticks([0, 64, 128, 192, 256])
    ax.set_xticklabels(['0.0', '0.25', '0.5', '0.75', '1.0'])
    ax.set_title('Paleta NDVI Exacta')
    plt.tight_layout()
    plt.savefig('ndvi_colormap.png', dpi=150, bbox_inches='tight')
    print("✅ Colormap guardado como 'ndvi_colormap.png'")
    
    return custom_cmap

def generate_titiler_post_request():
    """Generar una solicitud POST para TiTiler con tu colormap personalizado"""
    # Convertir colores a formato TiTiler
    colormap_data = []
    for i, color in enumerate(NDVI_COLORS):
        value = i / (len(NDVI_COLORS) - 1)  # Normalizar 0-1
        colormap_data.append([value, color])
    
    # Ejemplo de solicitud POST que podrías usar
    post_data = {
        "url": "gs://ta-cogs-apicorreo-prod/cogs/mx_gp_ndvi_Huixtla_20241202_cog.tif",
        "rescale": "0,1",
        "colormap": colormap_data
    }
    
    print("\n📋 Datos para solicitud POST a TiTiler:")
    print(json.dumps(post_data, indent=2))
    
    return post_data

if __name__ == "__main__":
    print("🔍 Verificando TiTiler y creando paleta NDVI exacta...\n")
    
    # Probar TiTiler
    test_titiler_service()
    
    print("\n🎨 Creando colormap personalizado...")
    create_ndvi_colormap()
    
    print("\n📡 Generando datos para TiTiler...")
    generate_titiler_post_request()
    
    print("\n✅ Proceso completado. Revisa 'ndvi_colormap.png' para ver tu paleta exacta.")
