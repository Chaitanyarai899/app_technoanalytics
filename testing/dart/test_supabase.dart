import 'package:supabase_flutter/supabase_flutter.dart';
import 'lib/constants.dart';
import 'lib/services/supabase_service.dart';

Future<void> main() async {
  print('🔧 Iniciando prueba de conexión a Supabase...');
  
  try {
    // Inicializar Supabase
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    print('✅ Supabase inicializado correctamente');
    
    // Probar el servicio
    final service = SupabaseService();
    
    // Prueba 1: Obtener información de usuario
    print('🔍 Probando obtener información de usuario...');
    try {
      final userInfo = await service.getUserInfo('test@example.com');
      print('📊 Respuesta getUserInfo: $userInfo');
    } catch (e) {
      print('❌ Error en getUserInfo: $e');
    }
    
    // Prueba 2: Obtener empresas
    print('🔍 Probando obtener empresas...');
    try {
      final companies = await service.getCompanies();
      print('🏢 Empresas encontradas: $companies');
    } catch (e) {
      print('❌ Error en getCompanies: $e');
    }
    
    // Prueba 3: Probar conexión directa
    print('🔍 Probando conexión directa a Supabase...');
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('count')
          .limit(1);
      print('📊 Respuesta directa: $response');
    } catch (e) {
      print('❌ Error en conexión directa: $e');
    }
    
    print('✅ Prueba completada');
    
  } catch (e) {
    print('❌ Error inicializando Supabase: $e');
  }
}
