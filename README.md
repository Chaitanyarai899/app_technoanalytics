# 🌾 Techno Analytics - Plataforma de Análisis Agrícola

[![Flutter](https://img.shields.io/badge/Flutter-3.0+-blue.svg)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.0+-blue.svg)](https://dart.dev/)
[![Supabase](https://img.shields.io/badge/Supabase-Backend-green.svg)](https://supabase.com/)
[![TiTiler](https://img.shields.io/badge/TiTiler-Raster%20Service-orange.svg)](https://developmentseed.org/titiler/)

Una aplicación móvil avanzada para análisis de datos agrícolas y visualización de rasters satelitales, desarrollada con Flutter y tecnologías de nube modernas.

## 🎯 Características Principales

### 📱 Aplicación Móvil
- **Dashboard interactivo** con métricas de cosecha en tiempo real
- **Mapas dinámicos** con visualización de rasters (NDVI, NDWI, Suelo, Malezas)
- **Modo comparación** para análisis temporal side-by-side
- **Filtros avanzados** por empresa, ingenio, fecha y producto
- **Autenticación personalizada** con perfiles por empresa

### 🗺️ Visualización de Rasters
- **Arquitectura moderna** basada en Cloud-Optimized GeoTIFFs (COG)
- **Servicio TiTiler** para tiles dinámicos optimizados
- **Paletas de colores personalizadas** para cada tipo de producto
- **Rendering escalable** desde CDN global
- **Soporte multi-zoom** hasta 18 niveles

### 📊 Análisis de Datos
- **Métricas de cosecha**: Ha monitoreadas, cosechadas, TCH, eficiencia
- **Distribuciones por variedad**, división y ciclo de cultivo
- **Gráficos interactivos** con FL Chart
- **Indicadores en tiempo real** con gauges animados
- **Comparaciones temporales** y análisis de tendencias

## 🏗️ Arquitectura Técnica

### Frontend (Flutter)
```
lib/
├── constants.dart              # Configuración global
├── main.dart                  # Punto de entrada
├── services/                  # Servicios de datos
│   ├── supabase_service.dart     # Cliente Supabase
│   ├── modern_raster_service.dart # Gestión de rasters COG
│   └── weather_service.dart      # Datos climáticos
├── views/                     # Pantallas de la app
│   ├── login_page.dart           # Autenticación
│   ├── dashboard.dart            # Dashboard principal
│   ├── explorar_view.dart        # Visualización de mapas
│   └── navigation_view.dart      # Navegación principal
└── widgets/                   # Componentes reutilizables
```

### Backend & Infraestructura
```
Infrastructure/
├── Supabase PostgreSQL        # Base de datos principal
├── TiTiler (Cloud Run)        # Servicio de tiles raster
├── Google Cloud Storage       # Almacenamiento de COGs
├── CDN Global                 # Distribución de tiles
└── Auto-scaling               # 0-10 instancias automáticas
```

### Pipeline de Datos
```
Data Pipeline/
├── ingestion/                 # Scripts de ingesta
│   ├── ingest_rasters.py         # Pipeline principal TIF→COG
│   ├── convert_to_cog.sh         # Conversión GDAL
│   └── upload_to_gcs.sh          # Subida a Cloud Storage
├── migration/                 # Scripts de migración
└── scripts/                   # Herramientas de validación
```

## 🚀 Instalación y Configuración

### Prerrequisitos
- **Flutter SDK** 3.0+
- **Dart SDK** 3.0+
- **Android Studio** / **Xcode** (para builds móviles)
- **Python 3.8+** (para scripts de ingesta)
- **GDAL** (para procesamiento de rasters)

### 1. Clonar el Repositorio
```bash
git clone https://github.com/TU_USUARIO/techno_analytics.git
cd techno_analytics
```

### 2. Instalar Dependencias Flutter
```bash
flutter pub get
```

### 3. Configurar Variables de Entorno
Crear archivo `.env` en la raíz del proyecto:
```env
# Supabase Configuration
SUPABASE_URL=https://tu-proyecto.supabase.co
SUPABASE_ANON_KEY=tu_anon_key
SUPABASE_SERVICE_ROLE_KEY=tu_service_role_key

# Google Cloud Configuration
PROJECT_ID=tu-proyecto-gcp
GCS_BUCKET=tu-bucket-cogs

# TiTiler Service
TITILER_BASE_URL=https://tu-titiler-service.run.app
```

### 4. Ejecutar la Aplicación
```bash
# Desarrollo
flutter run

# Build para Android
flutter build apk --release

# Build para iOS
flutter build ios --release
```

## 📊 Base de Datos

### Esquema Principal
La aplicación utiliza Supabase PostgreSQL con las siguientes tablas clave:

```sql
-- Usuarios y autenticación
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  name TEXT,
  company TEXT,
  ingenio TEXT,
  country TEXT,
  activo BOOLEAN DEFAULT true
);

-- Productos raster con metadata COG
CREATE TABLE productos (
  id UUID PRIMARY KEY,
  empresa TEXT NOT NULL,
  ingenio TEXT NOT NULL,
  producto TEXT NOT NULL,
  fecha DATE NOT NULL,
  cog_url TEXT,                    -- URL del COG en GCS
  bounds JSONB,                    -- Bounding box geográfico
  min_value DECIMAL,               -- Valor mínimo del raster
  max_value DECIMAL,               -- Valor máximo del raster
  colormap TEXT,                   -- Paleta de colores
  rescale_min DECIMAL,             -- Rango de visualización
  rescale_max DECIMAL,
  processing_status TEXT,          -- Estado del procesamiento
  created_at TIMESTAMP DEFAULT NOW()
);

-- Parcelas con geometrías
CREATE TABLE parcelas_ingenios (
  id UUID PRIMARY KEY,
  company TEXT,
  ingenio TEXT,
  geometry_polygon TEXT,           -- Geometría en WKT/GeoJSON
  area_calculada DECIMAL,
  temporada_activa BOOLEAN
);
```

## 🌐 API y Servicios

### Supabase REST API
```dart
// Obtener productos disponibles
final productos = await supabase
  .from('productos')
  .select('*')
  .eq('empresa', empresa)
  .eq('ingenio', ingenio)
  .eq('processing_status', 'completed');

// Obtener metadata de producto específico
final metadata = await supabase
  .from('productos')
  .select('cog_url, colormap, rescale_min, rescale_max')
  .eq('producto', 'ndvi')
  .eq('fecha', '2025-09-03')
  .single();
```

### TiTiler Service
```dart
// Construir URL de tiles dinámicos
String buildTileUrl(String cogUrl, String colormap, double min, double max) {
  return '${TITILER_BASE_URL}/cog/tiles/WebMercatorQuad/{z}/{x}/{y}.png'
         '?url=${cogUrl}&rescale=${min},${max}&colormap=${colormap}';
}

// Usar en Flutter Map
TileLayer(
  urlTemplate: buildTileUrl(cogUrl, 'ndvi', 0.0, 1.0),
  maxZoom: 18,
)
```

## 🛠️ Pipeline de Datos

### Ingesta de Rasters
El sistema incluye un pipeline automatizado para procesar archivos TIF:

```bash
# Procesar archivo individual
python ingestion/ingest_rasters.py archivo.tif

# Procesar directorio completo
python ingestion/ingest_rasters.py /ruta/a/directorio/ --force

# Pipeline completo: TIF → COG → GCS → Supabase
# 1. Detecta tipo de producto (NDVI, NDWI, etc.)
# 2. Extrae metadata espacial
# 3. Convierte a Cloud-Optimized GeoTIFF
# 4. Sube a Google Cloud Storage
# 5. Indexa en base de datos con metadata completa
```

### Formato de Archivos Esperado
```
ndvi_pantaleon_concepcion_20250903.tif
│    │         │           │
│    │         │           └── Fecha (YYYYMMDD)
│    │         └────────────── Ingenio
│    └──────────────────────── Empresa
└───────────────────────────── Tipo de producto
```

## 🤝 Contribuir

1. Fork el repositorio
2. Crear branch de feature (`git checkout -b feature/nueva-funcionalidad`)
3. Commit cambios (`git commit -am 'Agregar nueva funcionalidad'`)
4. Push al branch (`git push origin feature/nueva-funcionalidad`)
5. Crear Pull Request

### Estándares de Código
- **Dart**: Seguir [Effective Dart](https://dart.dev/guides/language/effective-dart)
- **Flutter**: Usar widgets const cuando sea posible
- **Python**: Seguir PEP 8 para scripts de backend
- **Commits**: Usar [Conventional Commits](https://www.conventionalcommits.org/)

## 📄 Licencia

Este proyecto está bajo la Licencia MIT - ver el archivo [LICENSE](LICENSE) para detalles.

## 📞 Soporte

- **Email**: soporte@bitechnoanalytics.com
- **Documentación**: Ver carpeta `/docs` para documentación técnica detallada
- **Issues**: Usar GitHub Issues para reportar bugs o solicitar features

## 🙏 Agradecimientos

- **Flutter Team** por el excelente framework
- **Supabase** por la plataforma backend moderna
- **TiTiler** por el servicio de tiles raster
- **Mapbox** por los mapas base
- **Grupo Porres** por el feedback y testing

---

**Desarrollado con ❤️ por BiTechno Analytics**

*Transformando la agricultura con tecnología de vanguardia*
