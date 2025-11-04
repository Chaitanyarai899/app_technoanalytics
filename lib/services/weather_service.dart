import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class WeatherData {
  final double temperature;
  final int humidity;
  final double precipitationProbability;
  final String weatherCode;
  final DateTime timestamp;

  WeatherData({
    required this.temperature,
    required this.humidity,
    required this.precipitationProbability,
    required this.weatherCode,
    required this.timestamp,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      temperature: json['temperature']?.toDouble() ?? 0.0,
      humidity: json['humidity']?.toInt() ?? 0,
      precipitationProbability: json['precipitation_probability']?.toDouble() ?? 0.0,
      weatherCode: json['weather_code']?.toString() ?? '0',
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'temperature': temperature,
      'humidity': humidity,
      'precipitation_probability': precipitationProbability,
      'weather_code': weatherCode,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  // Determinar el icono basado en el código del clima
  String get weatherIcon {
    final code = int.tryParse(weatherCode) ?? 0;
    if (code == 0) return '☀️';
    if (code <= 3) return '⛅';
    if (code <= 48) return '☁️';
    if (code <= 67) return '🌧️';
    if (code <= 77) return '🌨️';
    if (code <= 82) return '🌦️';
    if (code <= 99) return '⛈️';
    return '🌤️';
  }

  String get description {
    final code = int.tryParse(weatherCode) ?? 0;
    if (code == 0) return 'Despejado';
    if (code <= 3) return 'Parcialmente nublado';
    if (code <= 48) return 'Nublado';
    if (code <= 67) return 'Lluvia';
    if (code <= 77) return 'Nieve';
    if (code <= 82) return 'Chubascos';
    if (code <= 99) return 'Tormenta';
    return 'Variable';
  }
}

class WeatherService {
  static const String _baseUrl = 'https://api.open-meteo.com/v1/forecast';
  static const Duration _cacheExpiration = Duration(hours: 1); // Cache por 1 hora

  // Obtener clima actual para coordenadas específicas
  Future<WeatherData?> getCurrentWeather(double latitude, double longitude) async {
    try {
      // Verificar cache primero
      final cachedData = await _getCachedWeather(latitude, longitude);
      if (cachedData != null) {
        print('🔄 Usando datos de clima desde cache');
        return cachedData;
      }

      // Hacer llamada al API
      final url = Uri.parse(
        '$_baseUrl?latitude=$latitude&longitude=$longitude&current=temperature_2m,relative_humidity_2m,precipitation_probability,weather_code&timezone=America/Guatemala&forecast_days=1'
      );

      print('🌦️ Obteniendo clima para: $latitude, $longitude');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current'];
        
        final weatherData = WeatherData(
          temperature: current['temperature_2m']?.toDouble() ?? 0.0,
          humidity: current['relative_humidity_2m']?.toInt() ?? 0,
          precipitationProbability: current['precipitation_probability']?.toDouble() ?? 0.0,
          weatherCode: current['weather_code']?.toString() ?? '0',
          timestamp: DateTime.now(),
        );

        // Guardar en cache
        await _cacheWeather(latitude, longitude, weatherData);
        
        return weatherData;
      } else {
        print('❌ Error en API del clima: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Error obteniendo clima: $e');
      return null;
    }
  }

  // Verificar si hay datos en cache válidos
  Future<WeatherData?> _getCachedWeather(double latitude, double longitude) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'weather_${latitude.toStringAsFixed(2)}_${longitude.toStringAsFixed(2)}';
      
      final cachedJson = prefs.getString(key);
      if (cachedJson == null) return null;

      final weatherData = WeatherData.fromJson(json.decode(cachedJson));
      
      // Verificar si el cache ha expirado
      if (DateTime.now().difference(weatherData.timestamp) > _cacheExpiration) {
        await prefs.remove(key); // Limpiar cache expirado
        return null;
      }

      return weatherData;
    } catch (e) {
      print('❌ Error leyendo cache del clima: $e');
      return null;
    }
  }

  // Guardar datos del clima en cache
  Future<void> _cacheWeather(double latitude, double longitude, WeatherData weatherData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'weather_${latitude.toStringAsFixed(2)}_${longitude.toStringAsFixed(2)}';
      
      await prefs.setString(key, json.encode(weatherData.toJson()));
    } catch (e) {
      print('❌ Error guardando cache del clima: $e');
    }
  }

  // Limpiar cache antiguo (llamar ocasionalmente)
  Future<void> clearExpiredCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.startsWith('weather_'));
      
      for (final key in keys) {
        final cachedJson = prefs.getString(key);
        if (cachedJson != null) {
          final weatherData = WeatherData.fromJson(json.decode(cachedJson));
          if (DateTime.now().difference(weatherData.timestamp) > _cacheExpiration) {
            await prefs.remove(key);
          }
        }
      }
    } catch (e) {
      print('❌ Error limpiando cache del clima: $e');
    }
  }
}
