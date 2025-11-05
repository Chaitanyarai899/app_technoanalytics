import 'package:supabase_flutter/supabase_flutter.dart';


class SupabaseService {
  final supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> getUserInfo(String email) async {
    final response = await supabase
        .from('users')
        .select()
        .eq('email', email)
        .maybeSingle();
    return response;
  }

  Future<List<String>> getCompanies() async {
    final response = await supabase.from('users').select('company');
    return response.map<String>((e) => e['company'].toString()).toSet().toList();
  }

  Future<List<String>> getIngeniosByCompany(String company) async {
    final response = await Supabase.instance.client
        .from('users')
        .select('ingenio')
        .eq('company', company);
    return response.map<String>((e) => e['ingenio'].toString()).toSet().toList();
  }

  // Obtener coordenadas del centroide de un ingenio desde vw_centroide_global
  Future<Map<String, dynamic>?> getIngenioCoordinates(String ingenio) async {
    try {
      print('🎯 Obteniendo centroide para ingenio: $ingenio');
      
      final response = await Supabase.instance.client
          .from('vw_centroide_global')
          .select('latitude, longitude, min_lat, max_lat, min_lng, max_lng, total_parcelas')
          .eq('ingenio', ingenio)
          .maybeSingle();
      
      if (response != null) {
        final latitude = response['latitude'] as double?;
        final longitude = response['longitude'] as double?;
        final minLat = response['min_lat'] as double?;
        final maxLat = response['max_lat'] as double?;
        final minLng = response['min_lng'] as double?;
        final maxLng = response['max_lng'] as double?;
        final totalParcelas = response['total_parcelas'] as int?;
        
        if (latitude != null && longitude != null) {
          // Verificar si los bounds son razonables (no hay outliers extremos)
          bool boundsRazonables = true;
          if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
            double latRange = maxLat - minLat;
            double lngRange = maxLng - minLng;
            
            // Si el rango es mayor a 1 grado (muy amplio), hay posibles outliers
            if (latRange > 1.0 || lngRange > 1.0) {
              boundsRazonables = false;
              print('⚠️ Bounds amplios detectados para $ingenio - posibles outliers');
              print('   Rango lat: ${latRange.toStringAsFixed(4)}°, lng: ${lngRange.toStringAsFixed(4)}°');
            } else {
              print('✅ Bounds razonables para $ingenio');
              print('   Rango lat: ${latRange.toStringAsFixed(4)}°, lng: ${lngRange.toStringAsFixed(4)}°');
            }
          }
          
          print('✅ Centroide encontrado para $ingenio: ($latitude, $longitude) - $totalParcelas parcelas');
          
          return {
            'latitude': latitude,
            'longitude': longitude,
            'min_lat': boundsRazonables ? (minLat ?? latitude) : latitude,
            'max_lat': boundsRazonables ? (maxLat ?? latitude) : latitude,
            'min_lng': boundsRazonables ? (minLng ?? longitude) : longitude,
            'max_lng': boundsRazonables ? (maxLng ?? longitude) : longitude,
            'bounds_validos': boundsRazonables,
          };
        }
      }
      
      // Fallback: coordenadas por defecto si no hay datos
      print('⚠️ No se encontraron coordenadas para $ingenio, usando coordenadas por defecto');
      return {
        'latitude': 14.6418,
        'longitude': -90.5328,
        'min_lat': 14.6418,
        'max_lat': 14.6418,
        'min_lng': -90.5328,
        'max_lng': -90.5328,
        'bounds_validos': false,
      };
    } catch (e) {
      print('❌ Error obteniendo coordenadas del ingenio: $e');
      // Coordenadas por defecto
      return {
        'latitude': 14.6418,
        'longitude': -90.5328,
        'min_lat': 14.6418,
        'max_lat': 14.6418,
        'min_lng': -90.5328,
        'max_lng': -90.5328,
        'bounds_validos': false,
      };
    }
  }

  // Nuevo método para obtener centroide filtrado sin outliers
  Future<Map<String, dynamic>?> getIngenioCoordinatesFiltered(String empresa, String ingenio) async {
    try {
      print('🔍 Calculando centroide filtrado para $ingenio');
      
      // Obtener todas las parcelas y filtrar outliers
      final response = await Supabase.instance.client
          .rpc('get_centroide_filtrado', params: {
            'p_empresa': empresa,
            'p_ingenio': ingenio
          });
      
      if (response != null && response is Map) {
        final latitude = response['centroide_lat'] as double?;
        final longitude = response['centroide_lng'] as double?;
        final minLat = response['min_lat_filtrado'] as double?;
        final maxLat = response['max_lat_filtrado'] as double?;
        final minLng = response['min_lng_filtrado'] as double?;
        final maxLng = response['max_lng_filtrado'] as double?;
        final parcelasValidas = response['parcelas_validas'] as int?;
        final parcelasEliminadas = response['parcelas_eliminadas'] as int?;
        
        if (latitude != null && longitude != null) {
          print('✅ Centroide filtrado: ($latitude, $longitude)');
          print('📊 Parcelas válidas: $parcelasValidas, eliminadas: $parcelasEliminadas');
          
          return {
            'latitude': latitude,
            'longitude': longitude,
            'min_lat': minLat ?? latitude,
            'max_lat': maxLat ?? latitude,
            'min_lng': minLng ?? longitude,
            'max_lng': maxLng ?? longitude,
            'bounds_validos': true,
          };
        }
      }
      
      // Fallback al método normal si la función SQL no existe
      print('⚠️ Función SQL no disponible, usando método normal');
      return await getIngenioCoordinates(ingenio);
      
    } catch (e) {
      print('⚠️ Error en filtrado, usando método normal: $e');
      return await getIngenioCoordinates(ingenio);
    }
  }

  static Future<String?> getPoligonos(String ingenio) async {
    final response = await Supabase.instance.client
        .rpc('get_poligonos_geojson', params: {'ingenio': ingenio});
    return response;
  }

  Future<List<String>> getFechasDisponibles(String empresa, String ingenio) async {
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

  Future<List<String>> getProductosPorFecha(String empresa, String ingenio, String fecha) async {
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

  // Modern COG support methods
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
      print('❌ Error checking modern tiles availability: $e');
      return false;
    }
  }


  Future<List<Map<String, dynamic>>> getInspeccionesUltimoMes(String empresa, String ingenio) async {
  final desde = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
  final hasta = DateTime.now().toIso8601String();

  final response = await Supabase.instance.client
      .from('inspecciones')
      .select()
      .gte('fecha_creacion', desde)
      .lte('fecha_creacion', hasta)
      .eq('company', empresa)
      .eq('ingenio', ingenio)
      .eq('tipo_registro', 'inspeccion');

  return List<Map<String, dynamic>>.from(response);
  }

  // Obtener parcelas activas para mostrar en el mapa
  Future<List<Map<String, dynamic>>> getParcelasActivas(String empresa, String ingenio) async {
    try {
      print('Cargando parcelas para: $empresa - $ingenio');
      print('   Empresa: "$empresa" (len: ${empresa.length}, bytes: ${empresa.codeUnits})');
      print('   Ingenio: "$ingenio" (len: ${ingenio.length}, bytes: ${ingenio.codeUnits})');
      
      // Buscar solo por ingenio (sin filtrar por company, igual que vw_centroide_global)
      print('>>> Query: parcelas_ingenios WHERE ingenio="$ingenio"');
      
      // Consultar TODAS las parcelas del ingenio
      var response = await Supabase.instance.client
          .from('parcelas_ingenios')
          .select('id, id_parcela, ingenio, company, geometry_polygon, area_calculada')
          .eq('ingenio', ingenio)
          .limit(15000); // Aumentar a 15,000
      
      print('>>> Query final: ${response.length} parcelas cargadas');

      if (response.isNotEmpty) {
        // Mostrar info de las primeras parcelas
        print('>>> Muestra de parcelas encontradas:');
        for (var i = 0; i < (response.length > 3 ? 3 : response.length); i++) {
          final p = response[i];
          print('   - Parcela ${i+1}: id=${p['id']}, id_parcela=${p['id_parcela']}, ingenio=${p['ingenio']}, company=${p['company']}');
        }
      }

      print('>>> Total parcelas a retornar: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('ERROR obteniendo parcelas: $e');
      return [];
    }
  }

}
