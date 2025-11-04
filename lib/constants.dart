// lib/constants.dart
const supabaseUrl = 'https://eewlwrgzeypfwjruzshj.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVld2x3cmd6ZXlwZndqcnV6c2hqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzE2MzQ0MzEsImV4cCI6MjA0NzIxMDQzMX0.Jgk9rwKV07ya4a21QGUjfGbCIgC6b4wWJgPeNZ9jIOo'; // tu anon key
const String mapboxAccessToken = 'pk.eyJ1IjoiZXJpY2thbG9uem9zYW50aXpvIiwiYSI6ImNrNGNzdm94YTBycHkzbnJxNXBlbnJidGQifQ.oKgLer033Bi8XNHIScq41g';
const String geoJsonUrl ="https://eewlwrgzeypfwjruzshj.supabase.co/storage/v1/object/sign/Grupo_Porres/gp_poligonos_huixtla.geojson?token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1cmwiOiJHcnVwb19Qb3JyZXMvZ3BfcG9saWdvbm9zX2h1aXh0bGEuZ2VvanNvbiIsImlhdCI6MTczNDg5MzgyMSwiZXhwIjoxNzY2NDI5ODIxfQ.YPMFdYz-7kwwg14uVAaKI1zH2WW71T9tkokXhe2z7n4&t=2024-12-22T18%3A57%3A04.058Z";

// =============================================================================
// MODERN RASTER ARCHITECTURE CONFIGURATION
// =============================================================================

// Feature flags
const bool kUseModernTiles = true; // Set to false to use legacy WMS
const bool kEnableHybridMode = true; // Allow fallback to WMS if COG not available

// TiTiler Configuration
const String kTitilerBaseUrl = 'https://ta-titiler-service-1087100331392.us-central1.run.app'; // Updated with Cloud Run URL
const String kTitilerHealthEndpoint = '/healthz';
const String kTitilerInfoEndpoint = '/cog/info';
const String kTitilerTilesEndpoint = '/cog/tiles';
const String kTitilerColormapsEndpoint = '/colormaps';

// Legacy WMS Configuration (fallback)
const String kLegacyWmsBaseUrl = 'https://geoserver.bitechnoanalytics.com/geoserver/raster/wms';
const String kLegacyWmsVersion = '1.1.1';
const String kLegacyWmsFormat = 'image/png';

// Colormap mappings for TiTiler
const Map<String, String> kProductColormaps = {
  'ndvi': 'ndvi',
  'ndwi': 'ndwi',
  'sg': 'sg', 
  'maleza': 'maleza',
  'potencial': 'potencial',
  'potencial_ndvi': 'potencial',
  'potencial_ndwi': 'potencial',
};

// Default rescale values for products (min,max)
const Map<String, List<double>> kProductRescaleDefaults = {
  'ndvi': [0.0, 1.0],
  'ndwi': [-0.75, 0.5],
  'sg': [20.0, 100.0],
  'maleza': [1.0, 5.0],
  'potencial': [0.0, 4.0],
};

// Tile configuration
const int kDefaultTileSize = 256;
const int kMaxZoomLevel = 18;
const int kMinZoomLevel = 1;
const String kTileFormat = 'png';

// Cache configuration
const Duration kTileCacheDuration = Duration(hours: 24);
const Duration kMetadataCacheDuration = Duration(hours: 1);

// Error handling
const int kMaxRetries = 3;
const Duration kRetryDelay = Duration(seconds: 2);
const Duration kRequestTimeout = Duration(seconds: 30);
