# 🗺️ Acceso Dinámico a Rasters - Arquitectura Técnica Detallada

## 📋 Índice
1. [Resumen Ejecutivo](#resumen-ejecutivo)
2. [Arquitectura General](#arquitectura-general)
3. [Flujo de Datos Completo](#flujo-de-datos-completo)
4. [Componentes Técnicos](#componentes-técnicos)
5. [Proceso de Ingesta](#proceso-de-ingesta)
6. [Consumo desde la Aplicación](#consumo-desde-la-aplicación)
7. [Integración en Aplicación Web](#integración-en-aplicación-web)
8. [Ejemplos de Implementación](#ejemplos-de-implementación)
9. [Optimizaciones y Mejores Prácticas](#optimizaciones-y-mejores-prácticas)

---

## 🎯 Resumen Ejecutivo

Tu aplicación utiliza una **arquitectura moderna de rasters basada en Cloud-Optimized GeoTIFFs (COG)** servidos dinámicamente a través de **TiTiler**, almacenados en **Google Cloud Storage**, con metadata indexada en **Supabase PostgreSQL**.

### Beneficios Clave
- **90% reducción de costos**: $200/mes → $20-50/mes
- **Performance global**: Tiles servidos desde CDN
- **Escalabilidad automática**: 0-10 instancias según demanda
- **Compatible multi-plataforma**: Mobile (Flutter) y Web (cualquier framework)

---

## 🏗️ Arquitectura General

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLUJO DE DATOS COMPLETO                       │
└─────────────────────────────────────────────────────────────────┘

1. INGESTA (Una vez)
   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
   │ TIF File │ -> │ COG Conv │ -> │   GCS    │ -> │ Supabase │
   │  Local   │    │  (GDAL)  │    │  Bucket  │    │ Metadata │
   └──────────┘    └──────────┘    └──────────┘    └──────────┘

2. CONSULTA (Cada request)
   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
   │  Client  │ -> │ Supabase │ -> │ TiTiler  │ -> │   CDN    │
   │   App    │    │ Metadata │    │  Server  │    │  Tiles   │
   └──────────┘    └──────────┘    └──────────┘    └──────────┘
```

---

## 🔄 Flujo de Datos Completo

### Fase 1: Ingesta de Rasters (Backend)

```python
# Script: ingest_simple.py

1. Detectar archivos TIF en directorio
   📁 ndvi_pantaleon_concepcion_20250903.tif
   
2. Extraer metadata del nombre
   • Producto: ndvi
   • Empresa: pantaleon
   • Ingenio: concepcion
   • Fecha: 2025-09-03
   
3. Convertir a COG (Cloud-Optimized GeoTIFF)
   rio cogeo create input.tif output_cog.tif \
     --cog-profile lzw \
     --overview-level 5
   
4. Subir a Google Cloud Storage
   gsutil cp output_cog.tif gs://ta-cogs-apicorreo-prod/
   
5. Extraer estadísticas del raster
   • Bounds: [minx, miny, maxx, maxy]
   • Dimensiones: width x height
   • Rango de valores: min, max, nodata
   • EPSG: 4326 (WGS84)
   
6. Insertar/actualizar en Supabase
   INSERT INTO productos (
     empresa, ingenio, producto, fecha,
     cog_url, bounds, min_value, max_value,
     colormap, rescale_min, rescale_max,
     processing_status
   ) VALUES (...)
```

### Fase 2: Consulta desde Cliente

```dart
// 1. Obtener metadata desde Supabase
final metadata = await supabaseService.getProductoInfo(
  'pantaleon',           // empresa
  'concepcion',          // ingenio
  'ndvi',                // producto
  '2025-09-03'          // fecha
);

// 2. Construir URL de TiTiler
final cogUrl = metadata['cog_url'];
final rescaleMin = metadata['rescale_min'] ?? 0.0;
final rescaleMax = metadata['rescale_max'] ?? 1.0;

final tileUrl = buildTileUrl(
  'https://ta-titiler-service-1087100331392.us-central1.run.app',
  cogUrl,
  'ndvi_custom',
  rescaleMin,
  rescaleMax
);

// 3. Renderizar tiles en mapa
TileLayer(
  urlTemplate: tileUrl,  // Se expanden automáticamente {z}/{x}/{y}
  minZoom: 8,
  maxZoom: 18
)
```

---

## 🔧 Componentes Técnicos

### 1. Base de Datos (Supabase PostgreSQL)

**Tabla: `productos`**

```sql
CREATE TABLE public.productos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Identificadores
  empresa TEXT NOT NULL,
  ingenio TEXT NOT NULL,
  producto TEXT NOT NULL,
  fecha DATE NOT NULL,
  
  -- URLs y archivos
  cog_url TEXT,                    -- URL pública del COG en GCS
  cog_filename TEXT,               -- Nombre del archivo en el bucket
  original_filename TEXT,          -- Nombre del archivo original
  
  -- Metadata espacial
  bounds JSONB,                    -- [minx, miny, maxx, maxy]
  epsg INTEGER DEFAULT 4326,       -- Sistema de coordenadas
  width INTEGER,                   -- Ancho en píxeles
  height INTEGER,                  -- Alto en píxeles
  bands INTEGER DEFAULT 1,         -- Número de bandas
  
  -- Valores estadísticos
  min_value DECIMAL(10,6),         -- Valor mínimo del raster
  max_value DECIMAL(10,6),         -- Valor máximo del raster
  nodata_value DECIMAL(10,6),      -- Valor NoData
  
  -- Visualización
  colormap TEXT,                   -- Paleta de colores (ndvi, ndwi, etc.)
  rescale_min DECIMAL(10,6),       -- Rango para normalización
  rescale_max DECIMAL(10,6),
  
  -- Estado y timestamps
  processing_status TEXT DEFAULT 'pending',
  processing_log TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  -- Constraints
  CONSTRAINT productos_processing_status_check 
    CHECK (processing_status IN ('pending', 'processing', 'completed', 'failed'))
);

-- Índices para performance
CREATE INDEX productos_empresa_idx ON productos(empresa);
CREATE INDEX productos_ingenio_idx ON productos(ingenio);
CREATE INDEX productos_producto_idx ON productos(producto);
CREATE INDEX productos_processing_status_idx ON productos(processing_status);
CREATE INDEX productos_bounds_idx ON productos USING gin(bounds);
```

**Queries Clave:**

```sql
-- Obtener productos disponibles para una fecha
SELECT producto, cog_url, colormap, rescale_min, rescale_max
FROM productos
WHERE empresa = 'pantaleon'
  AND ingenio = 'concepcion'
  AND fecha = '2025-09-03'
  AND processing_status = 'completed'
  AND cog_url IS NOT NULL;

-- Obtener fechas disponibles
SELECT DISTINCT fecha
FROM productos
WHERE empresa = 'pantaleon'
  AND ingenio = 'concepcion'
  AND processing_status = 'completed'
ORDER BY fecha DESC;

-- Obtener productos por fecha
SELECT DISTINCT producto
FROM productos
WHERE empresa = 'pantaleon'
  AND ingenio = 'concepcion'
  AND fecha = '2025-09-03'
  AND processing_status = 'completed';
```

---

### 2. Servicio Supabase (Dart/Flutter)

**Archivo: `lib/services/supabase_service.dart`**

```dart
class SupabaseService {
  final supabase = Supabase.instance.client;

  /// Obtener información completa de un producto
  Future<Map<String, dynamic>?> getProductoInfo(
    String empresa, 
    String ingenio, 
    String producto, 
    String fecha
  ) async {
    try {
      final response = await supabase
          .from('productos')
          .select('*')
          .eq('empresa', empresa)
          .eq('ingenio', ingenio)
          .eq('producto', producto)
          .eq('fecha', fecha)
          .eq('processing_status', 'completed')
          .not('cog_url', 'is', null)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      
      return response;
    } catch (e) {
      print('❌ Error getting product info: $e');
      return null;
    }
  }

  /// Verificar si hay tiles modernos disponibles
  Future<bool> isModernTilesAvailable(
    String empresa, 
    String ingenio, 
    String producto, 
    String fecha
  ) async {
    try {
      final response = await supabase
          .from('productos')
          .select('cog_url, processing_status')
          .eq('empresa', empresa)
          .eq('ingenio', ingenio)
          .eq('producto', producto)
          .eq('fecha', fecha)
          .eq('processing_status', 'completed')
          .not('cog_url', 'is', null)
          .maybeSingle();
      
      return response != null;
    } catch (e) {
      return false;
    }
  }

  /// Obtener fechas disponibles para un ingenio
  Future<List<String>> getFechasDisponibles(
    String empresa, 
    String ingenio
  ) async {
    final response = await supabase
        .from('productos')
        .select('fecha')
        .eq('empresa', empresa)
        .eq('ingenio', ingenio)
        .order('fecha', ascending: true);

    final fechas = (response as List)
        .map((e) => e['fecha'].toString().split('T')[0])
        .toSet()
        .toList()
      ..sort();

    return fechas;
  }

  /// Obtener productos disponibles para una fecha
  Future<List<String>> getProductosPorFecha(
    String empresa, 
    String ingenio, 
    String fecha
  ) async {
    final response = await supabase
        .from('productos')
        .select('producto')
        .eq('empresa', empresa)
        .eq('ingenio', ingenio)
        .eq('fecha', fecha);

    final productos = (response as List)
        .map((e) => e['producto'].toString())
        .toSet()
        .toList();

    return productos;
  }
}
```

---

### 3. Servicio TiTiler (Cloud Run)

**URL Base:** `https://ta-titiler-service-1087100331392.us-central1.run.app`

**Endpoints Clave:**

```bash
# Health check
GET /healthz

# Información del COG
GET /cog/info?url=https://storage.googleapis.com/ta-cogs-apicorreo-prod/ndvi_cog.tif

# Tiles dinámicos (el más importante)
GET /cog/tiles/WebMercatorQuad/{z}/{x}/{y}.png?
    url=<COG_URL>&
    rescale=<min>,<max>&
    colormap=<JSON_COLORMAP>

# Colormaps disponibles
GET /colormaps
```

**Construcción de URL de Tiles:**

```dart
String buildTileUrl(
  String baseUrl,      // Base de TiTiler
  String cogUrl,       // URL del COG en GCS
  String colormap,     // Paleta de colores
  double rescaleMin,   // Valor mínimo
  double rescaleMax    // Valor máximo
) {
  // Construir URL base con WebMercatorQuad
  String url = '$baseUrl/cog/tiles/WebMercatorQuad/{z}/{x}/{y}.png?'
               'url=$cogUrl&'
               'rescale=$rescaleMin,$rescaleMax';
  
  // Agregar colormap personalizado
  if (colormap.endsWith('_custom')) {
    final customColormapJSON = buildCustomColormapJSON(colormap);
    url += '&colormap=${Uri.encodeComponent(customColormapJSON)}';
  } else {
    // Usar colormap predefinido
    url += '&colormap_name=$colormap';
  }
  
  return url;
}
```

**Formato de Colormap Personalizado:**

```dart
String buildCustomColormapJSON(String colormap) {
  List<String> colorsHex;
  
  switch (colormap) {
    case 'ndvi_custom':
      colorsHex = [
        '#000000', '#734C00', '#FF0000', '#E60000',
        '#FFAA00', '#FFFF73', '#D1FF73', '#55FF00',
        '#38A800', '#73DFFF', '#0070FF', '#002673',
        '#C500FF', '#A80084'
      ];
      break;
    case 'ndwi_custom':
      colorsHex = [
        '#5C09FC', '#6B84FD', '#3ADFFE', '#89FDCC',
        '#D2FD77', '#F8E71C', '#FF9A0B', '#FE230A'
      ];
      break;
    // ... más paletas
  }
  
  return _createColormapJSON(colorsHex);
}

String _createColormapJSON(List<String> colorsHex) {
  Map<String, List<int>> colormapDict = {};
  
  // Convertir colores hex a RGB
  List<List<int>> rgbColors = colorsHex.map((hex) {
    String cleanHex = hex.substring(1);
    int r = int.parse(cleanHex.substring(0, 2), radix: 16);
    int g = int.parse(cleanHex.substring(2, 4), radix: 16);
    int b = int.parse(cleanHex.substring(4, 6), radix: 16);
    return [r, g, b];
  }).toList();
  
  // Interpolar valores de 0 a 255
  for (int i = 0; i <= 255; i++) {
    double position = i / 255.0;
    int colorIndex = (position * (rgbColors.length - 1)).floor();
    
    if (colorIndex >= rgbColors.length - 1) {
      colormapDict[i.toString()] = rgbColors.last;
    } else {
      // Interpolación lineal entre colores
      double localPos = (position * (rgbColors.length - 1)) - colorIndex;
      List<int> color1 = rgbColors[colorIndex];
      List<int> color2 = rgbColors[colorIndex + 1];
      
      int r = (color1[0] + (color2[0] - color1[0]) * localPos).round();
      int g = (color1[1] + (color2[1] - color1[1]) * localPos).round();
      int b = (color1[2] + (color2[2] - color1[2]) * localPos).round();
      
      colormapDict[i.toString()] = [r, g, b];
    }
  }
  
  return jsonEncode(colormapDict);
}
```

---

### 4. Implementación en Vista (Flutter)

**Archivo: `lib/views/explorar_view.dart`**

```dart
// 1. Obtener metadata del producto
FutureBuilder<Map<String, dynamic>?>(
  future: supabaseService.getProductoInfo(
    selectedEmpresa,    // 'pantaleon'
    selectedIngenio,    // 'concepcion'
    selectedProducto,   // 'ndvi'
    selectedFecha       // '2025-09-03'
  ),
  builder: (context, snapshot) {
    if (snapshot.hasData && snapshot.data != null) {
      final producto = snapshot.data!;
      final cogUrl = producto['cog_url'] as String?;
      final processingStatus = producto['processing_status'] as String?;
      
      if (cogUrl != null && processingStatus == 'completed') {
        // 2. Configurar visualización
        final titilerBaseUrl = 'https://ta-titiler-service-1087100331392.us-central1.run.app';
        final customColormap = buildCustomColormap('ndvi');
        final rescaleMin = producto['rescale_min'] ?? 0.0;
        final rescaleMax = producto['rescale_max'] ?? 1.0;
        
        // 3. Construir URL de tiles
        final tileUrl = buildTileUrl(
          titilerBaseUrl,
          cogUrl,
          customColormap,
          rescaleMin,
          rescaleMax
        );
        
        // 4. Renderizar capa en el mapa
        return TileLayer(
          urlTemplate: tileUrl,
          userAgentPackageName: 'com.example.techno_analytics',
          minZoom: 8,
          maxZoom: 18,
          maxNativeZoom: 18,
          tileProvider: CancellableNetworkTileProvider(
            silenceExceptions: true,
          ),
          tileBuilder: (context, widget, tile) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              child: widget,
            );
          },
        );
      }
    }
    
    return Container(); // Sin datos disponibles
  },
)
```

---

## 🌐 Integración en Aplicación Web

### Opción 1: Leaflet.js (Recomendado)

```html
<!DOCTYPE html>
<html>
<head>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    #map { height: 600px; }
  </style>
</head>
<body>
  <div id="map"></div>
  
  <script>
    // 1. Inicializar mapa
    const map = L.map('map').setView([14.6418, -90.5328], 13);
    
    // 2. Agregar capa base
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap contributors'
    }).addTo(map);
    
    // 3. Función para obtener metadata de Supabase
    async function getProductMetadata(empresa, ingenio, producto, fecha) {
      const url = 'https://eewlwrgzeypfwjruzshj.supabase.co/rest/v1/productos';
      const params = new URLSearchParams({
        empresa: `eq.${empresa}`,
        ingenio: `eq.${ingenio}`,
        producto: `eq.${producto}`,
        fecha: `eq.${fecha}`,
        processing_status: 'eq.completed',
        select: '*',
        limit: '1'
      });
      
      const response = await fetch(`${url}?${params}`, {
        headers: {
          'apikey': 'TU_SUPABASE_ANON_KEY',
          'Authorization': 'Bearer TU_SUPABASE_ANON_KEY'
        }
      });
      
      const data = await response.json();
      return data[0] || null;
    }
    
    // 4. Función para construir URL de TiTiler
    function buildTileUrl(cogUrl, colormap, rescaleMin, rescaleMax) {
      const baseUrl = 'https://ta-titiler-service-1087100331392.us-central1.run.app';
      const params = new URLSearchParams({
        url: cogUrl,
        rescale: `${rescaleMin},${rescaleMax}`,
        colormap_name: colormap
      });
      
      return `${baseUrl}/cog/tiles/WebMercatorQuad/{z}/{x}/{y}.png?${params}`;
    }
    
    // 5. Cargar y mostrar raster
    async function loadRaster(empresa, ingenio, producto, fecha) {
      const metadata = await getProductMetadata(empresa, ingenio, producto, fecha);
      
      if (!metadata || !metadata.cog_url) {
        console.error('No hay COG disponible');
        return;
      }
      
      const tileUrl = buildTileUrl(
        metadata.cog_url,
        metadata.colormap || 'viridis',
        metadata.rescale_min || 0,
        metadata.rescale_max || 1
      );
      
      // Agregar capa de raster al mapa
      const rasterLayer = L.tileLayer(tileUrl, {
        maxZoom: 18,
        opacity: 0.8
      }).addTo(map);
      
      console.log('✅ Raster cargado:', producto);
    }
    
    // 6. Ejemplo de uso
    loadRaster('pantaleon', 'concepcion', 'ndvi', '2025-09-03');
  </script>
</body>
</html>
```

### Opción 2: Mapbox GL JS

```html
<!DOCTYPE html>
<html>
<head>
  <script src='https://api.mapbox.com/mapbox-gl-js/v2.15.0/mapbox-gl.js'></script>
  <link href='https://api.mapbox.com/mapbox-gl-js/v2.15.0/mapbox-gl.css' rel='stylesheet' />
  <style>
    #map { height: 600px; }
  </style>
</head>
<body>
  <div id="map"></div>
  
  <script>
    mapboxgl.accessToken = 'TU_MAPBOX_TOKEN';
    
    const map = new mapboxgl.Map({
      container: 'map',
      style: 'mapbox://styles/mapbox/satellite-v9',
      center: [-90.5328, 14.6418],
      zoom: 13
    });
    
    map.on('load', async () => {
      // Obtener metadata de Supabase
      const metadata = await getProductMetadata('pantaleon', 'concepcion', 'ndvi', '2025-09-03');
      
      if (!metadata) return;
      
      // Construir URL de TiTiler
      const tileUrl = buildTileUrl(
        metadata.cog_url,
        metadata.colormap,
        metadata.rescale_min,
        metadata.rescale_max
      );
      
      // Agregar fuente raster
      map.addSource('raster-tiles', {
        'type': 'raster',
        'tiles': [tileUrl],
        'tileSize': 256,
        'maxzoom': 18
      });
      
      // Agregar capa
      map.addLayer({
        'id': 'raster-layer',
        'type': 'raster',
        'source': 'raster-tiles',
        'paint': {
          'raster-opacity': 0.8
        }
      });
    });
    
    // Funciones auxiliares (igual que en ejemplo de Leaflet)
    async function getProductMetadata(empresa, ingenio, producto, fecha) { /* ... */ }
    function buildTileUrl(cogUrl, colormap, rescaleMin, rescaleMax) { /* ... */ }
  </script>
</body>
</html>
```

### Opción 3: React con React-Leaflet

```jsx
import React, { useState, useEffect } from 'react';
import { MapContainer, TileLayer, useMap } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';

// Componente para capa de raster dinámica
function RasterLayer({ empresa, ingenio, producto, fecha }) {
  const [tileUrl, setTileUrl] = useState(null);
  const map = useMap();
  
  useEffect(() => {
    async function loadRaster() {
      // 1. Obtener metadata de Supabase
      const metadata = await getProductMetadata(empresa, ingenio, producto, fecha);
      
      if (!metadata || !metadata.cog_url) {
        console.error('No hay COG disponible');
        return;
      }
      
      // 2. Construir URL de TiTiler
      const url = buildTileUrl(
        metadata.cog_url,
        metadata.colormap || 'viridis',
        metadata.rescale_min || 0,
        metadata.rescale_max || 1
      );
      
      setTileUrl(url);
    }
    
    loadRaster();
  }, [empresa, ingenio, producto, fecha]);
  
  if (!tileUrl) return null;
  
  return (
    <TileLayer
      url={tileUrl}
      maxZoom={18}
      opacity={0.8}
    />
  );
}

// Funciones auxiliares
async function getProductMetadata(empresa, ingenio, producto, fecha) {
  const url = 'https://eewlwrgzeypfwjruzshj.supabase.co/rest/v1/productos';
  const params = new URLSearchParams({
    empresa: `eq.${empresa}`,
    ingenio: `eq.${ingenio}`,
    producto: `eq.${producto}`,
    fecha: `eq.${fecha}`,
    processing_status: 'eq.completed',
    select: '*',
    limit: '1'
  });
  
  const response = await fetch(`${url}?${params}`, {
    headers: {
      'apikey': process.env.REACT_APP_SUPABASE_KEY,
      'Authorization': `Bearer ${process.env.REACT_APP_SUPABASE_KEY}`
    }
  });
  
  const data = await response.json();
  return data[0] || null;
}

function buildTileUrl(cogUrl, colormap, rescaleMin, rescaleMax) {
  const baseUrl = 'https://ta-titiler-service-1087100331392.us-central1.run.app';
  const params = new URLSearchParams({
    url: cogUrl,
    rescale: `${rescaleMin},${rescaleMax}`,
    colormap_name: colormap
  });
  
  return `${baseUrl}/cog/tiles/WebMercatorQuad/{z}/{x}/{y}.png?${params}`;
}

// Componente principal
export default function MapView() {
  const [selectedProduct, setSelectedProduct] = useState({
    empresa: 'pantaleon',
    ingenio: 'concepcion',
    producto: 'ndvi',
    fecha: '2025-09-03'
  });
  
  return (
    <div>
      <MapContainer
        center={[14.6418, -90.5328]}
        zoom={13}
        style={{ height: '600px', width: '100%' }}
      >
        <TileLayer
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        />
        
        <RasterLayer
          empresa={selectedProduct.empresa}
          ingenio={selectedProduct.ingenio}
          producto={selectedProduct.producto}
          fecha={selectedProduct.fecha}
        />
      </MapContainer>
    </div>
  );
}
```

---

## 📊 Ejemplos de Implementación Completos

### Ejemplo 1: Selector de Producto Dinámico

```jsx
// React Component con filtros dinámicos
import React, { useState, useEffect } from 'react';

function ProductSelector({ onProductChange }) {
  const [empresas, setEmpresas] = useState([]);
  const [ingenios, setIngenios] = useState([]);
  const [fechas, setFechas] = useState([]);
  const [productos, setProductos] = useState([]);
  
  const [selected, setSelected] = useState({
    empresa: '',
    ingenio: '',
    fecha: '',
    producto: ''
  });
  
  // Cargar empresas al montar
  useEffect(() => {
    loadEmpresas();
  }, []);
  
  // Cargar ingenios cuando cambia empresa
  useEffect(() => {
    if (selected.empresa) {
      loadIngenios(selected.empresa);
    }
  }, [selected.empresa]);
  
  // Cargar fechas cuando cambia ingenio
  useEffect(() => {
    if (selected.empresa && selected.ingenio) {
      loadFechas(selected.empresa, selected.ingenio);
    }
  }, [selected.empresa, selected.ingenio]);
  
  // Cargar productos cuando cambia fecha
  useEffect(() => {
    if (selected.empresa && selected.ingenio && selected.fecha) {
      loadProductos(selected.empresa, selected.ingenio, selected.fecha);
    }
  }, [selected.empresa, selected.ingenio, selected.fecha]);
  
  async function loadEmpresas() {
    const response = await fetch(
      'https://eewlwrgzeypfwjruzshj.supabase.co/rest/v1/productos?select=empresa',
      {
        headers: {
          'apikey': process.env.REACT_APP_SUPABASE_KEY,
          'Authorization': `Bearer ${process.env.REACT_APP_SUPABASE_KEY}`
        }
      }
    );
    const data = await response.json();
    const uniqueEmpresas = [...new Set(data.map(item => item.empresa))];
    setEmpresas(uniqueEmpresas);
  }
  
  async function loadIngenios(empresa) {
    const response = await fetch(
      `https://eewlwrgzeypfwjruzshj.supabase.co/rest/v1/productos?empresa=eq.${empresa}&select=ingenio`,
      {
        headers: {
          'apikey': process.env.REACT_APP_SUPABASE_KEY,
          'Authorization': `Bearer ${process.env.REACT_APP_SUPABASE_KEY}`
        }
      }
    );
    const data = await response.json();
    const uniqueIngenios = [...new Set(data.map(item => item.ingenio))];
    setIngenios(uniqueIngenios);
  }
  
  async function loadFechas(empresa, ingenio) {
    const response = await fetch(
      `https://eewlwrgzeypfwjruzshj.supabase.co/rest/v1/productos?empresa=eq.${empresa}&ingenio=eq.${ingenio}&select=fecha&order=fecha.desc`,
      {
        headers: {
          'apikey': process.env.REACT_APP_SUPABASE_KEY,
          'Authorization': `Bearer ${process.env.REACT_APP_SUPABASE_KEY}`
        }
      }
    );
    const data = await response.json();
    const uniqueFechas = [...new Set(data.map(item => item.fecha))];
    setFechas(uniqueFechas);
  }
  
  async function loadProductos(empresa, ingenio, fecha) {
    const response = await fetch(
      `https://eewlwrgzeypfwjruzshj.supabase.co/rest/v1/productos?empresa=eq.${empresa}&ingenio=eq.${ingenio}&fecha=eq.${fecha}&processing_status=eq.completed&select=producto`,
      {
        headers: {
          'apikey': process.env.REACT_APP_SUPABASE_KEY,
          'Authorization': `Bearer ${process.env.REACT_APP_SUPABASE_KEY}`
        }
      }
    );
    const data = await response.json();
    const uniqueProductos = [...new Set(data.map(item => item.producto))];
    setProductos(uniqueProductos);
  }
  
  function handleChange(field, value) {
    const newSelected = { ...selected, [field]: value };
    setSelected(newSelected);
    
    // Notificar cambio al padre si todos los campos están seleccionados
    if (newSelected.empresa && newSelected.ingenio && newSelected.fecha && newSelected.producto) {
      onProductChange(newSelected);
    }
  }
  
  return (
    <div className="product-selector">
      <select onChange={(e) => handleChange('empresa', e.target.value)}>
        <option value="">Seleccionar Empresa</option>
        {empresas.map(empresa => (
          <option key={empresa} value={empresa}>{empresa}</option>
        ))}
      </select>
      
      <select onChange={(e) => handleChange('ingenio', e.target.value)} disabled={!selected.empresa}>
        <option value="">Seleccionar Ingenio</option>
        {ingenios.map(ingenio => (
          <option key={ingenio} value={ingenio}>{ingenio}</option>
        ))}
      </select>
      
      <select onChange={(e) => handleChange('fecha', e.target.value)} disabled={!selected.ingenio}>
        <option value="">Seleccionar Fecha</option>
        {fechas.map(fecha => (
          <option key={fecha} value={fecha}>{fecha}</option>
        ))}
      </select>
      
      <select onChange={(e) => handleChange('producto', e.target.value)} disabled={!selected.fecha}>
        <option value="">Seleccionar Producto</option>
        {productos.map(producto => (
          <option key={producto} value={producto}>{producto}</option>
        ))}
      </select>
    </div>
  );
}

export default ProductSelector;
```

---

## ⚡ Optimizaciones y Mejores Prácticas

### 1. Caché de Metadata

```javascript
// Implementar caché en memoria para metadata
class MetadataCache {
  constructor(ttl = 3600000) { // 1 hora por defecto
    this.cache = new Map();
    this.ttl = ttl;
  }
  
  getKey(empresa, ingenio, producto, fecha) {
    return `${empresa}:${ingenio}:${producto}:${fecha}`;
  }
  
  get(empresa, ingenio, producto, fecha) {
    const key = this.getKey(empresa, ingenio, producto, fecha);
    const cached = this.cache.get(key);
    
    if (!cached) return null;
    
    // Verificar si expiró
    if (Date.now() - cached.timestamp > this.ttl) {
      this.cache.delete(key);
      return null;
    }
    
    return cached.data;
  }
  
  set(empresa, ingenio, producto, fecha, data) {
    const key = this.getKey(empresa, ingenio, producto, fecha);
    this.cache.set(key, {
      data,
      timestamp: Date.now()
    });
  }
  
  clear() {
    this.cache.clear();
  }
}

// Uso
const metadataCache = new MetadataCache();

async function getProductMetadataWithCache(empresa, ingenio, producto, fecha) {
  // Intentar obtener del caché
  const cached = metadataCache.get(empresa, ingenio, producto, fecha);
  if (cached) {
    console.log('✅ Usando metadata desde caché');
    return cached;
  }
  
  // Si no está en caché, hacer request
  const metadata = await getProductMetadata(empresa, ingenio, producto, fecha);
  
  // Guardar en caché
  if (metadata) {
    metadataCache.set(empresa, ingenio, producto, fecha, metadata);
  }
  
  return metadata;
}
```

### 2. Pre-carga de Tiles

```javascript
// Pre-cargar tiles visibles para mejor UX
function preloadTiles(map, tileUrl, bounds) {
  const zoom = map.getZoom();
  const tileSize = 256;
  
  // Calcular tiles visibles
  const tiles = calculateVisibleTiles(bounds, zoom, tileSize);
  
  // Pre-cargar cada tile
  tiles.forEach(tile => {
    const url = tileUrl
      .replace('{z}', tile.z)
      .replace('{x}', tile.x)
      .replace('{y}', tile.y);
    
    // Crear imagen para forzar carga
    const img = new Image();
    img.src = url;
  });
}

function calculateVisibleTiles(bounds, zoom, tileSize) {
  const tiles = [];
  const n = Math.pow(2, zoom);
  
  // Convertir bounds a tiles
  const minTileX = Math.floor((bounds.west + 180) / 360 * n);
  const maxTileX = Math.floor((bounds.east + 180) / 360 * n);
  const minTileY = Math.floor((1 - Math.log(Math.tan(bounds.north * Math.PI / 180) + 1 / Math.cos(bounds.north * Math.PI / 180)) / Math.PI) / 2 * n);
  const maxTileY = Math.floor((1 - Math.log(Math.tan(bounds.south * Math.PI / 180) + 1 / Math.cos(bounds.south * Math.PI / 180)) / Math.PI) / 2 * n);
  
  for (let x = minTileX; x <= maxTileX; x++) {
    for (let y = minTileY; y <= maxTileY; y++) {
      tiles.push({ z: zoom, x, y });
    }
  }
  
  return tiles;
}
```

### 3. Manejo de Errores Robusto

```javascript
async function loadRasterWithRetry(empresa, ingenio, producto, fecha, maxRetries = 3) {
  let attempt = 0;
  let lastError;
  
  while (attempt < maxRetries) {
    try {
      const metadata = await getProductMetadata(empresa, ingenio, producto, fecha);
      
      if (!metadata || !metadata.cog_url) {
        throw new Error('No hay COG disponible');
      }
      
      // Verificar que TiTiler esté accesible
      const healthCheck = await fetch(
        'https://ta-titiler-service-1087100331392.us-central1.run.app/healthz'
      );
      
      if (!healthCheck.ok) {
        throw new Error('TiTiler no está disponible');
      }
      
      const tileUrl = buildTileUrl(
        metadata.cog_url,
        metadata.colormap,
        metadata.rescale_min,
        metadata.rescale_max
      );
      
      return { success: true, tileUrl, metadata };
      
    } catch (error) {
      lastError = error;
      attempt++;
      
      if (attempt < maxRetries) {
        console.warn(`⚠️ Intento ${attempt} falló, reintentando...`);
        await new Promise(resolve => setTimeout(resolve, 1000 * attempt)); // Backoff exponencial
      }
    }
  }
  
  return { success: false, error: lastError.message };
}
```

### 4. Comparación de Productos (Side-by-Side)

```javascript
// Implementar comparación de dos productos
function createSplitView(mapContainer, product1, product2) {
  const map = L.map(mapContainer);
  
  // Crear dos controles de sync
  const leftPane = L.DomUtil.create('div', 'map-pane left-pane', mapContainer);
  const rightPane = L.DomUtil.create('div', 'map-pane right-pane', mapContainer);
  
  const leftMap = L.map(leftPane).setView([14.6418, -90.5328], 13);
  const rightMap = L.map(rightPane).setView([14.6418, -90.5328], 13);
  
  // Sincronizar movimientos
  leftMap.sync(rightMap);
  rightMap.sync(leftMap);
  
  // Cargar producto 1 (izquierda)
  loadRaster(product1.empresa, product1.ingenio, product1.producto, product1.fecha)
    .then(({ tileUrl }) => {
      L.tileLayer(tileUrl, { maxZoom: 18 }).addTo(leftMap);
    });
  
  // Cargar producto 2 (derecha)
  loadRaster(product2.empresa, product2.ingenio, product2.producto, product2.fecha)
    .then(({ tileUrl }) => {
      L.tileLayer(tileUrl, { maxZoom: 18 }).addTo(rightMap);
    });
}
```

---

## 📈 Consideraciones de Rendimiento

### Tamaño de Tiles y Zoom
```javascript
// Configuración óptima según uso
const tileConfig = {
  // Para visualización rápida
  quick: {
    maxZoom: 15,
    tileSize: 256,
    quality: 'low'
  },
  
  // Para análisis detallado
  detailed: {
    maxZoom: 18,
    tileSize: 512,
    quality: 'high'
  },
  
  // Balance (recomendado)
  balanced: {
    maxZoom: 17,
    tileSize: 256,
    quality: 'medium'
  }
};
```

### Límites de Request
```javascript
// Implementar throttling para evitar sobrecarga
class RequestThrottler {
  constructor(maxRequests = 10, timeWindow = 1000) {
    this.queue = [];
    this.activeRequests = 0;
    this.maxRequests = maxRequests;
    this.timeWindow = timeWindow;
  }
  
  async execute(requestFn) {
    while (this.activeRequests >= this.maxRequests) {
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    
    this.activeRequests++;
    
    try {
      const result = await requestFn();
      return result;
    } finally {
      this.activeRequests--;
      setTimeout(() => {}, this.timeWindow);
    }
  }
}

const throttler = new RequestThrottler(10, 1000);

// Uso
throttler.execute(() => fetch(tileUrl));
```

---

## 🔒 Seguridad

### Variables de Entorno (Recomendado)

```javascript
// .env.local
REACT_APP_SUPABASE_URL=https://eewlwrgzeypfwjruzshj.supabase.co
REACT_APP_SUPABASE_ANON_KEY=tu_clave_publica
REACT_APP_TITILER_BASE_URL=https://ta-titiler-service-1087100331392.us-central1.run.app

// Uso en código
const SUPABASE_URL = process.env.REACT_APP_SUPABASE_URL;
const SUPABASE_KEY = process.env.REACT_APP_SUPABASE_ANON_KEY;
```

### Row Level Security (Supabase)

```sql
-- Habilitar RLS en tabla productos
ALTER TABLE productos ENABLE ROW LEVEL SECURITY;

-- Política para lectura pública
CREATE POLICY "Allow public read for completed products"
ON productos FOR SELECT
USING (processing_status = 'completed');

-- Política para escritura solo por service role
CREATE POLICY "Allow service role full access"
ON productos FOR ALL
USING (auth.role() = 'service_role');
```

---

## 📚 Recursos Adicionales

### Documentación Oficial
- **TiTiler**: https://developmentseed.org/titiler/
- **Supabase**: https://supabase.com/docs
- **Leaflet**: https://leafletjs.com/reference.html
- **Mapbox GL JS**: https://docs.mapbox.com/mapbox-gl-js/

### Endpoints de Testing
```bash
# Health check de TiTiler
curl https://ta-titiler-service-1087100331392.us-central1.run.app/healthz

# Información de un COG
curl "https://ta-titiler-service-1087100331392.us-central1.run.app/cog/info?url=https://storage.googleapis.com/ta-cogs-apicorreo-prod/ndvi_cog.tif"

# Colormaps disponibles
curl https://ta-titiler-service-1087100331392.us-central1.run.app/colormaps

# Query a Supabase
curl "https://eewlwrgzeypfwjruzshj.supabase.co/rest/v1/productos?empresa=eq.pantaleon&select=*" \
  -H "apikey: TU_KEY" \
  -H "Authorization: Bearer TU_KEY"
```

---

## 🎓 Resumen para Replicación

### Checklist Rápido

✅ **Backend Setup**
1. Crear tabla `productos` en Supabase con schema COG
2. Desplegar TiTiler en Cloud Run o servidor propio
3. Configurar Google Cloud Storage o S3
4. Implementar pipeline de ingesta (Python script)

✅ **Frontend Setup (Web)**
1. Elegir librería de mapas (Leaflet/Mapbox)
2. Implementar cliente Supabase REST API
3. Construir URLs de TiTiler dinámicamente
4. Renderizar TileLayer con URLs generadas

✅ **Configuración**
```javascript
const CONFIG = {
  supabase: {
    url: 'https://TU_PROJECT.supabase.co',
    key: 'TU_ANON_KEY'
  },
  titiler: {
    baseUrl: 'https://TU_TITILER_SERVICE.run.app'
  },
  productos: ['ndvi', 'ndwi', 'sg', 'maleza', 'potencial']
};
```

---

## 💡 Ejemplo Mínimo Funcional

```html
<!DOCTYPE html>
<html>
<head>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    #map { height: 100vh; }
  </style>
</head>
<body>
  <div id="map"></div>
  
  <script>
    const map = L.map('map').setView([14.6418, -90.5328], 13);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(map);
    
    // Configuración
    const SUPABASE_URL = 'https://eewlwrgzeypfwjruzshj.supabase.co';
    const SUPABASE_KEY = 'TU_KEY';
    const TITILER_URL = 'https://ta-titiler-service-1087100331392.us-central1.run.app';
    
    // Cargar raster
    fetch(`${SUPABASE_URL}/rest/v1/productos?empresa=eq.pantaleon&ingenio=eq.concepcion&producto=eq.ndvi&fecha=eq.2025-09-03&processing_status=eq.completed&limit=1`, {
      headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
    })
    .then(res => res.json())
    .then(data => {
      if (data[0]) {
        const tileUrl = `${TITILER_URL}/cog/tiles/WebMercatorQuad/{z}/{x}/{y}.png?url=${data[0].cog_url}&rescale=${data[0].rescale_min},${data[0].rescale_max}&colormap_name=${data[0].colormap}`;
        L.tileLayer(tileUrl, { maxZoom: 18, opacity: 0.8 }).addTo(map);
      }
    });
  </script>
</body>
</html>
```

---

**Documento creado:** Octubre 2025  
**Versión:** 1.0  
**Arquitectura:** Cloud-Optimized GeoTIFFs + TiTiler + Supabase
