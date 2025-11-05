# 📍 Data Transformation & Calculation Files - Location Guide

This document maps every data transformation and calculation to its exact file location.

---

## 📊 1. PARCELAS → CALCULATIONS

### File: `lib/views/dashboard.dart`

All harvest calculations, metrics, and aggregations happen in the dashboard view.

#### **A. Basic Metrics Calculation**

**Location**: `lib/views/dashboard.dart:250-277`

```dart
// FUNCTION: _buildIndicadoresResumen()
// Line 244-288

for (var parcela in parcelas) {
  // Sum area_calculada → haMonitoreo
  final area = (parcela['area_calculada'] ?? 0).toDouble();  // Line 252
  haMonitoreo += area;                                        // Line 253

  // Filter by fecha_fin → haCosechadas
  final areaCosechada = (parcela['area_cosechada'] ?? 0).toDouble();  // Line 256
  final fechaFin = parcela['fecha_fin'];                               // Line 257

  if (areaCosechada > 0 || fechaFin != null) {                        // Line 259
    haCosechadas += areaCosechada > 0 ? areaCosechada : area;         // Line 260

    // Sum ton_real → toneladasIndustrializadas
    final tonReal = (parcela['ton_real'] ?? 0).toDouble();            // Line 263
    final tonCosechadas = (parcela['ton_cosechadas'] ?? 0).toDouble();// Line 264
    toneladasIndustrializadas += tonReal > 0 ? tonReal : tonCosechadas; // Line 265

    toneladasPotencial += (parcela['ton_potencial'] ?? 0).toDouble(); // Line 268
  }
}

// Calculate TCH
double tchActual = haCosechadas > 0
  ? toneladasIndustrializadas / haCosechadas
  : 0;  // Line 272-273

// Calculate efficiency percentage
double porcentajeCumplimiento = toneladasPotencial > 0
  ? (toneladasIndustrializadas / toneladasPotencial)
  : 0;  // Line 275-277
```

**What it does:**
- ✅ Sums `area_calculada` from all parcels → `haMonitoreo`
- ✅ Filters parcels with `fecha_fin` or `area_cosechada > 0` → `haCosechadas`
- ✅ Sums `ton_real` (or `ton_cosechadas`) → `toneladasIndustrializadas`
- ✅ Calculates TCH (Tons per Hectare)
- ✅ Calculates efficiency vs potential

---

#### **B. Weekly Aggregation**

**Location**: `lib/views/dashboard.dart:357-404`

```dart
// FUNCTION: _construirCarruselDatos()
// Initialize aggregation maps

Map<int, double> haPorSemana = {};       // Line 357 - Weekly hectares
Map<int, double> tchPorSemana = {};      // Line 358 - Weekly TCH
Map<String, double> tipoCosecha = {};    // Line 359 - Harvest type distribution

for (var parcela in parcelas) {
  final area = (parcela['area_calculada'] ?? 0).toDouble();  // Line 364
  haMonitoreo += area;                                        // Line 365

  final fechaFin = parcela['fecha_fin'];                      // Line 368
  final areaCosechada = (parcela['area_cosechada'] ?? 0).toDouble();  // Line 369

  if (fechaFin != null || areaCosechada > 0) {                // Line 371
    final areaUsada = areaCosechada > 0 ? areaCosechada : area;  // Line 372
    haCosechadas += areaUsada;                                   // Line 373

    final toneladas = /* calculation */;                         // Line 378
    toneladasIndustrializadas += toneladas;                      // Line 379

    if (fechaFin != null) {
      try {
        // Parse date and calculate week number
        final fechaFinDate = DateTime.parse(fechaFin);          // Line 386

        // Calculate week of year: (days since Jan 1) / 7
        final semana = ((fechaFinDate.difference(
          DateTime(fechaFinDate.year, 1, 1)).inDays) / 7).ceil();  // Line 387

        // Group by week → haPorSemana: Map<int, double>
        haPorSemana.update(semana,
          (value) => value + areaUsada,
          ifAbsent: () => areaUsada);                           // Line 388

        // Calculate TCH for this parcel
        final tch = areaUsada > 0 ? toneladas / areaUsada : 0;  // Line 391

        // Calculate TCH → tchPorSemana: Map<int, double> with weighted average
        if (tchPorSemana.containsKey(semana)) {                 // Line 392
          // Weighted average: (TCH1 × Ha1 + TCH2 × Ha2) / (Ha1 + Ha2)
          final haExistente = haPorSemana[semana]! - areaUsada;     // Line 394
          final tchExistente = tchPorSemana[semana]!;               // Line 395
          tchPorSemana[semana] = ((tchExistente * haExistente)
            + (tch * areaUsada)) / haPorSemana[semana]!;            // Line 396
        } else {
          tchPorSemana[semana] = tch;                               // Line 398
        }
      } catch (e) {
        // Error handling
      }
    }
  }
}
```

**What it does:**
- ✅ Parses `fecha_fin` string to DateTime
- ✅ Calculates week number from date
- ✅ Groups hectares by week → `haPorSemana: Map<int, double>`
- ✅ Calculates weighted average TCH per week → `tchPorSemana: Map<int, double>`

**Formula Used:**
```dart
// Week number
week = (days_since_jan_1) / 7  (rounded up)

// Weighted TCH average
TCH_week = (TCH_existing × Ha_existing + TCH_new × Ha_new) / Ha_total
```

---

#### **C. Top-N Area Aggregation**

**Location**: `lib/views/dashboard.dart:331-350`

```dart
// FUNCTION: agruparAreaTop7()
// Groups areas by field (variety, division, etc.) and returns top 7

Map<String, double> agruparAreaTop7(String campo) {
  final Map<String, double> agrupado = {};

  // Aggregate by field
  for (var parcela in parcelas) {                                   // Line 335
    final key = parcela[campo]?.toString() ?? 'Sin dato';           // Line 336
    final area = (parcela['area_calculada'] ?? 0).toDouble();       // Line 337

    // Sum areas for each category
    agrupado.update(key,
      (value) => value + area,
      ifAbsent: () => area);                                        // Line 338
  }

  // Sort descending and take top 7
  final entries = agrupado.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));                   // Line 342
  final top7 = entries.take(7);                                     // Line 343

  // Group remaining as "Otros"
  final otros = entries.skip(7)
    .map((e) => e.value)
    .fold(0.0, (a, b) => a + b);                                    // Line 344

  final Map<String, double> resultado = {
    for (var e in top7) e.key: e.value,                             // Line 347
  };
  if (otros > 0) resultado['Otros'] = otros;                        // Line 349

  return resultado;
}
```

**What it does:**
- ✅ Groups parcels by any field (variety, division, harvest type)
- ✅ Sums areas for each category
- ✅ Sorts descending by area
- ✅ Returns top 7 + "Otros" category

**Used for:**
- Variety distribution charts
- Division analysis
- Harvest cycle breakdown

---

#### **D. Zone Yield Ranking**

**Location**: `lib/views/dashboard.dart:405-434`

```dart
// Inside _construirCarruselDatos() loop

Map<String, List<double>> rendimientoPorZona = {};  // Line 360 - [totalTons, totalHa]

// Accumulate tons and hectares by zone
final zona = (parcela['division_01'] ?? 'Sin división').toString();  // Line 407
if (!rendimientoPorZona.containsKey(zona)) {
  rendimientoPorZona[zona] = [0, 0];                                  // Line 409
}
rendimientoPorZona[zona]![0] += toneladas;  // Total tons              // Line 411
rendimientoPorZona[zona]![1] += areaUsada;  // Total ha                // Line 412

// After loop: Calculate yield per zone and sort
final zonasOrdenadas = rendimientoPorZona.entries
  .map((e) => MapEntry<String, double>(
      e.key,
      e.value[1] > 0 ? e.value[0] / e.value[1] : 0  // Tons/Ha per zone
  ))
  .toList()
  ..sort((a, b) => b.value.compareTo(a.value));  // Sort descending    // Line 429-433

final topZonas = zonasOrdenadas.take(5).toList();                      // Line 434
```

**What it does:**
- ✅ Accumulates tons and hectares by zone (division_01)
- ✅ Calculates yield (Tons/Ha) per zone
- ✅ Ranks zones by yield (top 5)

---

## 🗺️ 2. GEOJSON → POLYGONS

### File: `lib/views/explorar_view.dart`

All GeoJSON parsing and polygon rendering happens in the map exploration view.

#### **A. Main Conversion Function**

**Location**: `lib/views/explorar_view.dart:1003-1087`

```dart
// FUNCTION: _convertirParcelasAPoligonos()
// Converts GeoJSON geometry to Flutter Map Polygons

List<Polygon> _convertirParcelasAPoligonos([List<Map<String, dynamic>>? parcelas]) {
  final parcelasAConvertir = parcelas ?? _parcelas;      // Line 1004
  if (parcelasAConvertir.isEmpty) return [];             // Line 1005

  List<Polygon> poligonos = [];                          // Line 1009

  for (var parcela in parcelasAConvertir) {              // Line 1016
    try {
      // Extract geometry_polygon field
      final geometryJson = parcela['geometry_polygon'];   // Line 1018
      if (geometryJson == null) continue;                 // Line 1019

      // Parse GeoJSON safely (handle both String and Map)
      Map<String, dynamic> geometry;
      if (geometryJson is String) {
        if (geometryJson.trim().isEmpty) continue;
        geometry = jsonDecode(geometryJson);              // Line 1025 - JSON parsing
      } else if (geometryJson is Map<String, dynamic>) {
        geometry = geometryJson;                          // Line 1027
      } else {
        continue;
      }

      // Extract Polygon coordinates
      if (geometry['type'] == 'Polygon' && geometry['coordinates'] != null) {  // Line 1032
        final coordinates = geometry['coordinates'] as List;                   // Line 1033

        // First array is exterior ring
        if (coordinates.isNotEmpty) {                                          // Line 1036
          final exteriorRing = coordinates[0] as List;                         // Line 1037
          List<LatLng> puntos = [];                                            // Line 1038

          // Limit to 100 points per polygon (performance optimization)
          final puntosLimitados = exteriorRing.take(100).toList();             // Line 1041

          for (var coord in puntosLimitados) {                                 // Line 1043
            if (coord is List && coord.length >= 2) {
              try {
                // GeoJSON format: [longitude, latitude]
                double lng = (coord[0] as num).toDouble();  // Line 1046
                double lat = (coord[1] as num).toDouble();  // Line 1047

                // Validate coordinates
                if (lat.abs() <= 90 && lng.abs() <= 180) {  // Line 1049
                  // Convert to LatLng (latitude, longitude) - note the swap!
                  puntos.add(LatLng(lat, lng));              // Line 1050
                }
              } catch (e) {
                continue;  // Skip invalid coordinates
              }
            }
          }

          // Create polygon if we have at least 3 valid points
          if (puntos.length >= 3) {                          // Line 1058
            poligonos.add(
              Polygon(
                points: puntos,                              // Line 1061
                color: Colors.transparent,                   // Line 1062
                borderColor: Colors.blue.withOpacity(0.7),   // Line 1063
                borderStrokeWidth: 1.0,                      // Line 1064
                isFilled: false,                             // Line 1065
              ),
            );
          }
        }
      }
    } catch (e) {
      parcelasConError++;  // Line 1069 - Error counting
    }
  }

  return poligonos;  // Line 1084
}
```

**What it does:**
- ✅ Extracts `geometry_polygon` from parcel data
- ✅ Parses GeoJSON string (handles both String and Map types)
- ✅ Extracts coordinate arrays: `[[lng, lat], [lng, lat], ...]`
- ✅ Converts to LatLng objects (swaps from [lng, lat] to LatLng(lat, lng))
- ✅ Validates coordinates (lat ≤ 90, lng ≤ 180)
- ✅ Creates Flutter Map Polygon widgets
- ✅ Limits to 100 points per polygon (performance)

**Data Flow:**
```
Database JSON → Parse String → Extract coordinates → Validate → Create LatLng → Build Polygon Widget
```

---

#### **B. Usage in Map Rendering**

**Location**: `lib/views/explorar_view.dart:1729-1734`

```dart
// In FlutterMap widget children:

// Render parcels only when zoomed in (zoom >= 10)
if (_mostrarParcelas &&
    _parcelasPoligonos.isNotEmpty &&
    _isMapReady &&
    _mapController.camera.zoom >= 10.0)
  PolygonLayer(polygons: _parcelasPoligonos),  // Line 1732
```

**Performance Optimization:**
- Only renders when `_mostrarParcelas` is true
- Only renders when zoom level ≥ 10
- Polygons limited to 100 points each

---

#### **C. Data Loading**

**Location**: `lib/views/explorar_view.dart:785-807`

```dart
// FUNCTION: _cargarParcelas()
// Loads parcel data from Supabase

Future<void> _cargarParcelas() async {
  if (selectedEmpresa.isEmpty || selectedIngenio.isEmpty) return;

  try {
    // Fetch from Supabase
    final parcelas = await supabaseService.getParcelasActivas(
      selectedEmpresa,
      selectedIngenio
    );  // Line 789

    // Convert to polygons
    final poligonos = _convertirParcelasAPoligonos(parcelas);  // Line 791

    if (mounted) {
      setState(() {
        _parcelas = parcelas;                    // Line 794
        _parcelasPoligonos = poligonos;          // Line 795
      });
    }
  } catch (e) {
    print('Error cargando parcelas: $e');  // Line 801
  }
}
```

---

## 🎨 3. PRODUCT METADATA → TILE URLS

### Files: `lib/services/modern_raster_service.dart` + `lib/views/explorar_view.dart`

Tile URL generation happens in the service layer, usage happens in the view.

#### **A. Tile URL Builder**

**Location**: `lib/services/modern_raster_service.dart:66-110`

```dart
// FUNCTION: buildTitilerTileUrl()
// Builds TiTiler URL with COG URL, colormap, and rescale parameters

String buildTitilerTileUrl(String cogUrl, {
  String? colormap,                    // Line 67
  List<double>? rescale,               // Line 68
  String? algorithm,                   // Line 69
  Map<String, dynamic>? algorithmParams,  // Line 70
  double? nodata,                      // Line 71
}) {
  // Base URL pattern with {z}/{x}/{y} placeholders
  final uri = Uri.parse('$kTitilerBaseUrl$kTitilerTilesEndpoint/{z}/{x}/{y}.$kTileFormat');  // Line 73

  final queryParams = <String, String>{
    'url': cogUrl,  // COG file URL in GCS  // Line 76
  };

  // Apply colormap from constants
  if (colormap != null) {
    queryParams['colormap_name'] = colormap;  // Line 80
  }

  // Apply rescale values (min, max)
  if (rescale != null && rescale.length == 2) {
    queryParams['rescale'] = '${rescale[0]},${rescale[1]}';  // Line 84
  }

  if (algorithm != null) {
    queryParams['algorithm'] = algorithm;      // Line 88
  }

  if (algorithmParams != null) {
    queryParams['algorithm_params'] = algorithmParams.entries
        .map((e) => '${e.key}:${e.value}')
        .join(',');                            // Line 92-94
  }

  if (nodata != null) {
    queryParams['nodata'] = nodata.toString();  // Line 98
  }

  // Add optimization parameters
  queryParams.addAll({
    'resampling': 'nearest',                   // Line 103
    'return_mask': 'false',                    // Line 104
  });

  final finalUri = uri.replace(queryParameters: queryParams);  // Line 107
  return finalUri.toString();                  // Line 108
}
```

**What it does:**
- ✅ Gets COG URL from productos table via function parameter
- ✅ Applies colormap from constants (ndvi, ndwi, sg, etc.)
- ✅ Builds TiTiler URL with rescale params (min/max values)
- ✅ Adds optimization flags (resampling, return_mask)
- ✅ Returns complete tile URL pattern

**Example Output:**
```
https://ta-titiler-service-xxxxx.run.app/cog/tiles/{z}/{x}/{y}.png
  ?url=gs://bucket/ndvi_2024-01-15.cog.tif
  &colormap_name=ndvi
  &rescale=0.0,1.0
  &resampling=nearest
  &return_mask=false
```

---

#### **B. Complete Tile URL Generation**

**Location**: `lib/services/modern_raster_service.dart:126-177`

```dart
// FUNCTION: buildCompleteTileUrl()
// Gets product metadata and builds complete tile URL

Future<String?> buildCompleteTileUrl({
  required String empresa,
  required String ingenio,
  required String producto,
  required String fecha,
  String? overrideColormap,
  List<double>? overrideRescale,
}) async {
  try {
    // Get product metadata from Supabase
    final metadata = await _supabaseService.getProductoInfo(
      empresa, ingenio, producto, fecha
    );  // Line 129-131

    if (metadata == null || metadata['cog_url'] == null) {
      return null;  // Line 132
    }

    // Extract COG URL from metadata
    final cogUrl = metadata['cog_url'] as String;  // Line 137

    // Get colormap (override > metadata > default)
    final colormap = overrideColormap
        ?? metadata['colormap']
        ?? kProductColormaps[producto.toLowerCase()];  // Line 139-141

    // Determine rescale values
    List<double>? rescale = overrideRescale;  // Line 145
    if (rescale == null) {
      // Try from metadata
      final minVal = metadata['rescale_min'];  // Line 148
      final maxVal = metadata['rescale_max'];  // Line 149

      if (minVal != null && maxVal != null) {
        rescale = [minVal, maxVal];  // Line 152
      } else {
        // Use defaults from constants
        rescale = kProductRescaleDefaults[producto.toLowerCase()];  // Line 155
      }
    }

    // Build the tile URL
    final tileUrl = buildTitilerTileUrl(
      cogUrl,
      colormap: colormap,
      rescale: rescale,          // Line 164
      nodata: metadata['nodata_value'],
    );  // Line 161-165

    return tileUrl;  // Line 167
  } catch (e) {
    return null;
  }
}
```

**What it does:**
- ✅ Fetches product metadata from Supabase (including `cog_url`)
- ✅ Extracts COG URL from database
- ✅ Determines colormap (priority: override > metadata > defaults)
- ✅ Determines rescale values (priority: override > metadata > defaults)
- ✅ Calls `buildTitilerTileUrl()` with all parameters
- ✅ Returns complete tile URL

---

#### **C. Usage in Flutter Map**

**Location**: `lib/views/explorar_view.dart:1587-1659`

```dart
// In FlutterMap widget children:

// COG raster layer with TiTiler
if (selectedEmpresa.isNotEmpty &&
    selectedIngenio.isNotEmpty &&
    selectedProducto.isNotEmpty &&
    selectedFecha.isNotEmpty)
  FutureBuilder<Map<String, dynamic>?>(
    future: supabaseService.getProductoInfo(
      selectedEmpresa, selectedIngenio, selectedProducto, selectedFecha
    ),  // Line 1593-1595
    builder: (context, snapshot) {
      if (snapshot.hasData && snapshot.data != null) {
        final producto = snapshot.data!;
        final cogUrl = producto['cog_url'] as String?;                // Line 1599 - Get COG URL
        final processingStatus = producto['processing_status'] as String?;  // Line 1600

        if (cogUrl != null && processingStatus == 'completed') {      // Line 1602
          // Get configuration
          final titilerBaseUrl = 'https://ta-titiler-service-xxxxx.run.app';  // Line 1603
          final estilo = estilosPorProducto[selectedProducto] ?? 'ndvi';       // Line 1604
          final customColormap = buildCustomColormap(estilo);                  // Line 1605
          final rescaleMin = producto['rescale_min'] ?? 0.0;                   // Line 1606
          final rescaleMax = producto['rescale_max'] ?? 1.0;                   // Line 1607

          return TileLayer(
            urlTemplate: buildTileUrl(
              titilerBaseUrl, cogUrl, customColormap, rescaleMin, rescaleMax
            ),  // Line 1610-1612 - Build complete tile URL
            userAgentPackageName: 'com.example.techno_analytics',    // Line 1613
            minZoom: 8,                                               // Line 1614
            maxZoom: 18,                                              // Line 1615
            maxNativeZoom: 18,                                        // Line 1616
            tileProvider: CancellableNetworkTileProvider(
              silenceExceptions: true,
            ),  // Line 1617
            tileBuilder: (context, widget, tile) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                child: widget,
              );
            },  // Line 1620-1625
          );
        }
      }
      return Container();  // Line 1628
    },
  ),
```

**What it does:**
- ✅ Uses FutureBuilder to fetch product metadata asynchronously
- ✅ Extracts `cog_url` from metadata
- ✅ Checks `processing_status == 'completed'`
- ✅ Gets colormap style from `estilosPorProducto` map
- ✅ Builds custom colormap JSON (256-color gradient)
- ✅ Gets rescale min/max from metadata or defaults
- ✅ Builds complete tile URL
- ✅ Passes to TileLayer widget for rendering

---

## 📁 Summary Table

| Transformation | File | Function | Lines |
|---------------|------|----------|-------|
| **Sum area_calculada → haMonitoreo** | `lib/views/dashboard.dart` | `_buildIndicadoresResumen()` | 252-253 |
| **Filter by fecha_fin → haCosechadas** | `lib/views/dashboard.dart` | `_buildIndicadoresResumen()` | 256-260 |
| **Sum ton_real → toneladasIndustrializadas** | `lib/views/dashboard.dart` | `_buildIndicadoresResumen()` | 263-265 |
| **Calculate TCH** | `lib/views/dashboard.dart` | `_buildIndicadoresResumen()` | 272-273 |
| **Calculate efficiency** | `lib/views/dashboard.dart` | `_buildIndicadoresResumen()` | 275-277 |
| **Group by week → haPorSemana** | `lib/views/dashboard.dart` | `_construirCarruselDatos()` | 387-388 |
| **Calculate TCH per week** | `lib/views/dashboard.dart` | `_construirCarruselDatos()` | 391-399 |
| **Week number calculation** | `lib/views/dashboard.dart` | `_construirCarruselDatos()` | 387 |
| **Top-N aggregation** | `lib/views/dashboard.dart` | `agruparAreaTop7()` | 331-350 |
| **Zone yield ranking** | `lib/views/dashboard.dart` | `_construirCarruselDatos()` | 407-434 |
| **Parse GeoJSON geometry** | `lib/views/explorar_view.dart` | `_convertirParcelasAPoligonos()` | 1018-1030 |
| **Extract coordinates** | `lib/views/explorar_view.dart` | `_convertirParcelasAPoligonos()` | 1032-1041 |
| **Convert to LatLng** | `lib/views/explorar_view.dart` | `_convertirParcelasAPoligonos()` | 1046-1050 |
| **Create Polygon widgets** | `lib/views/explorar_view.dart` | `_convertirParcelasAPoligonos()` | 1058-1067 |
| **Build TiTiler URL** | `lib/services/modern_raster_service.dart` | `buildTitilerTileUrl()` | 66-110 |
| **Apply colormap** | `lib/services/modern_raster_service.dart` | `buildTitilerTileUrl()` | 79-81 |
| **Apply rescale params** | `lib/services/modern_raster_service.dart` | `buildTitilerTileUrl()` | 83-85 |
| **Get product metadata** | `lib/services/modern_raster_service.dart` | `buildCompleteTileUrl()` | 129-141 |
| **Extract cog_url** | `lib/services/modern_raster_service.dart` | `buildCompleteTileUrl()` | 137 |
| **Render tiles in map** | `lib/views/explorar_view.dart` | FlutterMap builder | 1587-1659 |

---

## 🔍 Quick Reference

**calculations**
- Harvest metrics → `lib/views/dashboard.dart:244-288`
- Weekly aggregation → `lib/views/dashboard.dart:357-404`
- Top-N grouping → `lib/views/dashboard.dart:331-350`

**map rendering**
- GeoJSON parsing → `lib/views/explorar_view.dart:1003-1087`
- Polygon display → `lib/views/explorar_view.dart:1729-1734`
- Parcel loading → `lib/views/explorar_view.dart:785-807`

**tile generation**
- URL builder → `lib/services/modern_raster_service.dart:66-110`
- Metadata fetching → `lib/services/modern_raster_service.dart:126-177`
- Map integration → `lib/views/explorar_view.dart:1587-1659`

---

**Document Version**: 1.0
**Last Updated**: 2024
**Total Transformation Points Mapped**: 20+
