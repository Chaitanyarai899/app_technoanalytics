import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../constants.dart';
import 'supabase_service.dart';

/// Modern raster service supporting both COG (TiTiler) and legacy WMS
class ModernRasterService {
  final SupabaseService _supabaseService = SupabaseService();
  
  /// Cache for product metadata to avoid repeated requests
  final Map<String, Map<String, dynamic>> _metadataCache = {};
  
  /// Get product metadata including COG URL and visualization parameters
  Future<Map<String, dynamic>?> getProductMetadata(
    String empresa,
    String ingenio, 
    String producto,
    String fecha,
  ) async {
    final cacheKey = '$empresa:$ingenio:$producto:$fecha';
    
    // Check cache first
    if (_metadataCache.containsKey(cacheKey)) {
      return _metadataCache[cacheKey];
    }
    
    try {
      final metadata = await _supabaseService.getProductoInfo(
        empresa, ingenio, producto, fecha
      );
      
      if (metadata != null) {
        _metadataCache[cacheKey] = metadata;
      }
      
      return metadata;
    } catch (e) {
      debugPrint('❌ Error getting product metadata: $e');
      return null;
    }
  }
  
  /// Check if modern tiles (COG) are available for a product
  Future<bool> isModernTilesAvailable(
    String empresa,
    String ingenio,
    String producto, 
    String fecha,
  ) async {
    if (!kUseModernTiles) return false;
    
    try {
      return await _supabaseService.isModernTilesAvailable(
        empresa, ingenio, producto, fecha
      );
    } catch (e) {
      debugPrint('❌ Error checking modern tiles availability: $e');
      return false;
    }
  }
  
  /// Build TiTiler tile URL for COG
  String buildTitilerTileUrl(String cogUrl, {
    String? colormap,
    List<double>? rescale,
    String? algorithm,
    Map<String, dynamic>? algorithmParams,
    double? nodata,
  }) {
    final uri = Uri.parse('$kTitilerBaseUrl$kTitilerTilesEndpoint/{z}/{x}/{y}.$kTileFormat');
    
    final queryParams = <String, String>{
      'url': cogUrl,
    };
    
    if (colormap != null) {
      queryParams['colormap_name'] = colormap;
    }
    
    if (rescale != null && rescale.length == 2) {
      queryParams['rescale'] = '${rescale[0]},${rescale[1]}';
    }
    
    if (algorithm != null) {
      queryParams['algorithm'] = algorithm;
    }
    
    if (algorithmParams != null) {
      queryParams['algorithm_params'] = algorithmParams.entries
          .map((e) => '${e.key}:${e.value}')
          .join(',');
    }
    
    if (nodata != null) {
      queryParams['nodata'] = nodata.toString();
    }
    
    // Add common optimization parameters
    queryParams.addAll({
      'resampling': 'nearest',
      'return_mask': 'false',
    });
    
    final finalUri = uri.replace(queryParameters: queryParams);
    return finalUri.toString();
  }
  
  /// Build legacy WMS tile URL
  String buildLegacyWmsTileUrl(
    String wmsLayer,
    String style,
  ) {
    // This uses the existing WMS pattern from the current implementation
    return kLegacyWmsBaseUrl;
  }
  
  /// Create modern raster tile layer (COG via TiTiler)
  Future<TileLayer?> createModernRasterLayer(
    String empresa,
    String ingenio,
    String producto,
    String fecha, {
    String? overrideColormap,
    List<double>? overrideRescale,
  }) async {
    try {
      final metadata = await getProductMetadata(empresa, ingenio, producto, fecha);
      
      if (metadata == null || metadata['cog_url'] == null) {
        debugPrint('⚠️ No COG URL found for product');
        return null;
      }
      
      final cogUrl = metadata['cog_url'] as String;
      
      // Determine colormap
      final colormap = overrideColormap ?? 
          kProductColormaps[producto.toLowerCase()] ?? 
          'viridis';
      
      // Determine rescale values
      List<double>? rescale = overrideRescale;
      if (rescale == null) {
        // Try to get from metadata
        final minVal = metadata['min_value'] as double?;
        final maxVal = metadata['max_value'] as double?;
        
        if (minVal != null && maxVal != null) {
          rescale = [minVal, maxVal];
        } else {
          // Fallback to defaults
          rescale = kProductRescaleDefaults[producto.toLowerCase()];
        }
      }
      
      final nodata = metadata['nodata'] as double?;
      
      final tileUrl = buildTitilerTileUrl(
        cogUrl,
        colormap: colormap,
        rescale: rescale,
        nodata: nodata,
      );
      
      return TileLayer(
        urlTemplate: tileUrl,
        userAgentPackageName: 'com.example.techno_analytics',
        minZoom: kMinZoomLevel.toDouble(),
        maxZoom: kMaxZoomLevel.toDouble(),
        maxNativeZoom: kMaxZoomLevel,
      );
      
    } catch (e) {
      debugPrint('❌ Error creating modern raster layer: $e');
      return null;
    }
  }
  
  /// Create legacy WMS tile layer (fallback)
  TileLayer createLegacyRasterLayer(
    String wmsLayer,
    String style,
  ) {
    return TileLayer(
      wmsOptions: WMSTileLayerOptions(
        baseUrl: '$kLegacyWmsBaseUrl?',
        layers: [wmsLayer],
        format: kLegacyWmsFormat,
        transparent: true,
        version: kLegacyWmsVersion,
        styles: [style],
        crs: const Epsg3857(),
      ),
    );
  }
  
  /// Create raster layer with automatic fallback
  Future<TileLayer> createRasterLayer(
    String empresa,
    String ingenio,
    String producto,
    String fecha,
    String legacyWmsLayer,
    String legacyStyle, {
    String? overrideColormap,
    List<double>? overrideRescale,
  }) async {
    // Try modern tiles first if enabled
    if (kUseModernTiles) {
      final modernLayer = await createModernRasterLayer(
        empresa, ingenio, producto, fecha,
        overrideColormap: overrideColormap,
        overrideRescale: overrideRescale,
      );
      
      if (modernLayer != null) {
        debugPrint('✅ Using modern COG tiles for $producto');
        return modernLayer;
      }
    }
    
    // Fallback to legacy WMS
    debugPrint('⚡ Falling back to legacy WMS for $producto');
    return createLegacyRasterLayer(legacyWmsLayer, legacyStyle);
  }
  
  /// Clear metadata cache
  void clearCache() {
    _metadataCache.clear();
  }
  
  /// Get cache info for debugging
  Map<String, dynamic> getCacheInfo() {
    return {
      'cached_products': _metadataCache.length,
      'cache_keys': _metadataCache.keys.toList(),
    };
  }
  
  /// Health check for TiTiler service
  Future<bool> checkTitilerHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$kTitilerBaseUrl$kTitilerHealthEndpoint'),
        headers: {'Accept': 'application/json'},
      ).timeout(kRequestTimeout);
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ TiTiler health check failed: $e');
      return false;
    }
  }
  
  /// Get available colormaps from TiTiler
  Future<List<String>> getAvailableColormaps() async {
    try {
      final response = await http.get(
        Uri.parse('$kTitilerBaseUrl$kTitilerColormapsEndpoint'),
        headers: {'Accept': 'application/json'},
      ).timeout(kRequestTimeout);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return (data.keys.toList())..sort();
      }
    } catch (e) {
      debugPrint('❌ Error getting colormaps: $e');
    }
    
    // Return default colormaps
    return kProductColormaps.values.toSet().toList()..sort();
  }
}
