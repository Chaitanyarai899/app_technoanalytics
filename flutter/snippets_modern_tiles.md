# Modern Raster Tiles Integration - Flutter Snippets

Esta guía muestra cómo integrar el nuevo sistema de tiles COG/TiTiler en tu aplicación Flutter existente.

## 1. Importaciones Necesarias

```dart
import '../services/modern_raster_service.dart';
import '../constants.dart';
```

## 2. Integración en ExplorarView

### Agregar el servicio moderno

En la clase `_ExplorarViewState`, agrega:

```dart
class _ExplorarViewState extends State<ExplorarView> {
  // ... código existente ...
  
  // Nuevo: Servicio moderno de raster
  final ModernRasterService _modernRasterService = ModernRasterService();
  
  // ... resto del código ...
}
```

### Modificar el método build()

Reemplaza la sección de TileLayer existente:

```dart
// ANTES (WMS existente):
if (selectedEmpresa.isNotEmpty && selectedIngenio.isNotEmpty && !modoComparacion)
  TileLayer(
    wmsOptions: WMSTileLayerOptions(
      baseUrl: 'https://geoserver.bitechnoanalytics.com/geoserver/raster/wms?',
      layers: [wmsLayer],
      format: 'image/png',
      transparent: true,
      version: '1.1.1',
      styles: [selectedEstilo],
      crs: const Epsg3857(),
    ),
  ),

// DESPUÉS (Moderno con fallback):
if (selectedEmpresa.isNotEmpty && selectedIngenio.isNotEmpty && !modoComparacion)
  FutureBuilder<TileLayer>(
    future: _modernRasterService.createRasterLayer(
      selectedEmpresa,
      selectedIngenio, 
      selectedProducto,
      selectedFecha,
      wmsLayer, // Para fallback WMS
      selectedEstilo, // Para fallback WMS
    ),
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return snapshot.data!;
      }
      // Mostrar capa de carga mientras se resuelve
      return TileLayer(
        urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/satellite-v9/tiles/{z}/{x}/{y}?access_token=$mapboxAccessToken',
        userAgentPackageName: 'com.example.techno_analytics',
        opacity: 0.3, // Transparente mientras carga
      );
    },
  ),
```

### Modificar modo comparación

Para el modo comparación, actualiza ambas capas:

```dart
// Capas para modo comparación
if (modoComparacion && selectedEmpresa.isNotEmpty && selectedIngenio.isNotEmpty) ...[
  // Capa base (lado izquierdo)
  ClipPath(
    clipper: LeftSideClipper(valorSwipe),
    child: FutureBuilder<TileLayer>(
      future: _modernRasterService.createRasterLayer(
        selectedEmpresa,
        selectedIngenio,
        selectedProducto,
        selectedFecha,
        wmsLayer,
        selectedEstilo,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return snapshot.data!;
        }
        return const SizedBox.shrink();
      },
    ),
  ),
  // Capa de comparación (lado derecho)
  ClipPath(
    clipper: RightSideClipper(valorSwipe),
    child: FutureBuilder<TileLayer>(
      future: _modernRasterService.createRasterLayer(
        selectedEmpresa,
        selectedIngenio,
        selectedProductoComparacion.isNotEmpty ? selectedProductoComparacion : selectedProducto,
        selectedFechaComparacion.isNotEmpty ? selectedFechaComparacion : selectedFecha,
        buildWMSLayerName(
          selectedCountry, 
          selectedEmpresa, 
          selectedProductoComparacion.isNotEmpty ? selectedProductoComparacion : selectedProducto, 
          selectedIngenio, 
          selectedFechaComparacion.isNotEmpty 
            ? selectedFechaComparacion.replaceAll('-', '') 
            : selectedFecha
        ),
        selectedEstiloComparacion,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return snapshot.data!;
        }
        return const SizedBox.shrink();
      },
    ),
  ),
],
```

## 3. Actualización de constantes

Asegúrate de que `constants.dart` tenga la URL correcta de TiTiler:

```dart
// En constants.dart, actualiza:
const String kTitilerBaseUrl = 'https://tu-dominio-titiler.com'; // Reemplaza con tu dominio real
```

## 4. Indicador de estado de tiles modernos

Agrega un indicador visual para mostrar qué tipo de tiles se están usando:

```dart
// En el widget build(), después de los filtros superiores:
if (kUseModernTiles && selectedEmpresa.isNotEmpty && selectedIngenio.isNotEmpty)
  Positioned(
    top: 120,
    right: 16,
    child: FutureBuilder<bool>(
      future: _modernRasterService.isModernTilesAvailable(
        selectedEmpresa, selectedIngenio, selectedProducto, selectedFecha
      ),
      builder: (context, snapshot) {
        final isModern = snapshot.data ?? false;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isModern ? Colors.green.withOpacity(0.9) : Colors.orange.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isModern ? Icons.cloud_done : Icons.warning,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                isModern ? 'COG' : 'WMS',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    ),
  ),
```

## 5. Manejo de errores y estados de carga

Agrega un método para manejar errores:

```dart
// En _ExplorarViewState:
void _showTileLoadError() {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Error cargando tiles. Intentando con servidor de respaldo...'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}
```

## 6. Control de cache (opcional)

Agrega un botón para limpiar cache en el menú de desarrollo:

```dart
// En el menú expandible de botones flotantes:
if (kDebugMode)
  _buildElegantButton(
    icon: Icons.clear_all,
    tooltip: 'Limpiar cache de tiles',
    onPressed: () {
      _modernRasterService.clearCache();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache de tiles limpiado')),
      );
    },
  ),
```

## 7. Verificación de conectividad (opcional)

Agrega verificación de salud del servicio TiTiler:

```dart
// Método para verificar conectividad
Future<void> _checkTitilerHealth() async {
  final isHealthy = await _modernRasterService.checkTitilerHealth();
  
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isHealthy 
            ? 'Servicio de tiles moderno disponible ✅' 
            : 'Servicio de tiles moderno no disponible. Usando WMS de respaldo ⚠️'
        ),
        backgroundColor: isHealthy ? Colors.green : Colors.orange,
      ),
    );
  }
}

// Llamar en initState():
@override
void initState() {
  super.initState();
  // ... código existente ...
  
  if (kUseModernTiles) {
    _checkTitilerHealth();
  }
}
```

## 8. Testing y Debugging

Para testing, puedes cambiar temporalmente la constante:

```dart
// En constants.dart, para probar WMS:
const bool kUseModernTiles = false;

// Para probar COG:
const bool kUseModernTiles = true;
```

## 9. Personalización de colormaps

Si necesitas colormaps personalizados para productos específicos:

```dart
// En la llamada a createRasterLayer:
await _modernRasterService.createRasterLayer(
  selectedEmpresa,
  selectedIngenio, 
  selectedProducto,
  selectedFecha,
  wmsLayer,
  selectedEstilo,
  overrideColormap: 'custom_ndvi', // Colormap personalizado
  overrideRescale: [0.0, 0.8], // Rango personalizado
)
```

## 10. Migración gradual

Para una migración gradual, puedes usar productos específicos:

```dart
// En constants.dart:
const List<String> kModernTileProducts = ['ndvi', 'ndwi']; // Solo estos productos usan COG

// En la lógica:
final useModernForProduct = kUseModernTiles && kModernTileProducts.contains(selectedProducto.toLowerCase());
```

Esta implementación mantiene compatibilidad total con el código existente mientras agrega soporte para la nueva arquitectura COG/TiTiler.
