import 'dart:convert';
import 'package:http/http.dart' as http;

const supabaseUrl = 'https://eewlwrgzeypfwjruzshj.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVld2x3cmd6ZXlwZndqcnV6c2hqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzE2MzQ0MzEsImV4cCI6MjA0NzIxMDQzMX0.Jgk9rwKV07ya4a21QGUjfGbCIgC6b4wWJgPeNZ9jIOo';

Future<void> main() async {
  print('🔧 Probando conexión directa a Supabase...');
  
  try {
    // Prueba 1: Obtener información de usuarios
    print('🔍 Probando consulta a tabla users...');
    final usersResponse = await http.get(
      Uri.parse('$supabaseUrl/rest/v1/users?select=*&limit=5'),
      headers: {
        'apikey': supabaseAnonKey,
        'Authorization': 'Bearer $supabaseAnonKey',
        'Content-Type': 'application/json',
      },
    );
    
    print('📊 Status users: ${usersResponse.statusCode}');
    if (usersResponse.statusCode == 200) {
      final usersData = json.decode(usersResponse.body);
      print('✅ Usuarios encontrados: ${usersData.length}');
      if (usersData.length > 0) {
        print('📋 Primer usuario: ${usersData[0]}');
      }
    } else {
      print('❌ Error en users: ${usersResponse.body}');
    }
    
    // Prueba 2: Obtener vista de centroide
    print('🔍 Probando consulta a vw_centroide_global...');
    final centroideResponse = await http.get(
      Uri.parse('$supabaseUrl/rest/v1/vw_centroide_global?select=*&limit=5'),
      headers: {
        'apikey': supabaseAnonKey,
        'Authorization': 'Bearer $supabaseAnonKey',
        'Content-Type': 'application/json',
      },
    );
    
    print('📊 Status centroide: ${centroideResponse.statusCode}');
    if (centroideResponse.statusCode == 200) {
      final centroideData = json.decode(centroideResponse.body);
      print('✅ Registros centroide encontrados: ${centroideData.length}');
      if (centroideData.length > 0) {
        print('📋 Primer centroide: ${centroideData[0]}');
      }
    } else {
      print('❌ Error en centroide: ${centroideResponse.body}');
    }
    
    // Prueba 3: Obtener productos
    print('🔍 Probando consulta a productos...');
    final productosResponse = await http.get(
      Uri.parse('$supabaseUrl/rest/v1/productos?select=*&limit=5'),
      headers: {
        'apikey': supabaseAnonKey,
        'Authorization': 'Bearer $supabaseAnonKey',
        'Content-Type': 'application/json',
      },
    );
    
    print('📊 Status productos: ${productosResponse.statusCode}');
    if (productosResponse.statusCode == 200) {
      final productosData = json.decode(productosResponse.body);
      print('✅ Productos encontrados: ${productosData.length}');
      if (productosData.length > 0) {
        print('📋 Primer producto: ${productosData[0]}');
      }
    } else {
      print('❌ Error en productos: ${productosResponse.body}');
    }
    
  } catch (e) {
    print('❌ Error general: $e');
  }
  
  print('✅ Prueba de conexión completada');
}
