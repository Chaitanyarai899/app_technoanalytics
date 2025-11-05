// ExplorarView extendida con lógica de marcador, confirmación y formulario
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techno_analytics/constants.dart';
import '../services/supabase_service.dart';
import '../widgets/weather_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:ui' as ui;
import 'dart:convert'; // Para jsonEncode del colormap personalizado
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';



final GlobalKey<_ExplorarViewState> explorarViewKey = GlobalKey<_ExplorarViewState>();

class ExplorarView extends StatefulWidget {
  final String nombre;
  final bool modoInspeccionInicial;

  const ExplorarView({
    super.key,
    required this.nombre,
    this.modoInspeccionInicial = false,
  });

  @override
  State<ExplorarView> createState() => _ExplorarViewState();
}

class _LeyendaItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LeyendaItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}


class _ExplorarViewState extends State<ExplorarView> {
  // Coordenadas iniciales dinámicas (se actualizarán cuando se obtengan las coordenadas correctas)
  LatLng? _initialCenter;
  final double initialZoom = 15.0; // Zoom apropiado para vista inicial


  final Map<String, List<Color>> leyendasPorProducto = {
    'ndvi': [
      Color(0xFF000000), Color(0xFF734C00), Color(0xFFFF0000), Color(0xFFE60000),
      Color(0xFFFFAA00), Color(0xFFFFFF73), Color(0xFFD1FF73), Color(0xFF55FF00),
      Color(0xFF38A800), Color(0xFF73DFFF), Color(0xFF0070FF), Color(0xFF002673),
      Color(0xFFC500FF), Color(0xFFA80084),
    ],
    'ndwi': [
      Color(0xFF5C09FC), Color(0xFF6B84FD), Color(0xFF3ADFFE), Color(0xFF89FDCC),
      Color(0xFFD2FD77), Color(0xFFF8E71C), Color(0xFFFF9A0B), Color(0xFFFE230A),
    ],
    'sg': [
      Color(0xFFE60000), Color(0xFFFEE825), Color(0xFF6DCF5A), Color(0xFF35B879),
      Color(0xFF1F9E89), Color(0xFF26838F), Color(0xFF31688E), Color(0xFF3E4A8A),
      Color(0xFF482878), Color(0xFF440154),
    ],
    'maleza': [
      Color(0xFF4CE600), Color(0xFF38A800), Color(0xFFFFFF00),
      Color(0xFFE69800), Color(0xFFFF2B18),
    ],
    'potencial': [
      Color(0xFF734C00), 
      Color(0xFFFF0000), 
      Color(0xFFFFFF00), 
      Color(0xFF00FF00), 
    ],
  };

  final Map<String, List<String>> etiquetasPorProducto = {
    'ndvi': ['0', '0.10', '0.20', '0.30', '0.40', '0.50', '0.55', '0.60', '0.65', '0.7', '0.75', '0.80', '0.85', '0.90','1'],
    'ndwi': ['-0.75', '-0.7', '-0.65', '-0.60', '-0.55', '-0.5', '-0.40', '0.0','0.5'],
    'sg': ['20', '40', '50','55', '60', '70', '80', '90', '95', '100'],
    'maleza': ['1', '2', '3', '4', '5 imagenes'],
    'potencial': ['Muy Bajo', 'Bajo', 'Medio', 'Alto'], 
  };

  late final MapController _mapController;
  List<Marker> _marcadoresInspecciones = [];
  final SupabaseService supabaseService = SupabaseService();
  List<String> empresasDisponibles = [];
  List<String> ingeniosDisponibles = [];
  List<String> fechasDisponibles = [];
  List<String> productosDisponibles = [];
  

  String selectedProducto = '';
  String selectedEmpresa = '';
  String selectedIngenio = '';
  String selectedCountry = '';
  String selectedFecha = '';
  String selectedEstilo = 'ndvi'; 


  bool modoInspeccion = false;
  bool modoVerInspecciones = false;
  LatLng? puntoInspeccion;
  
  // Variables para manejo de ubicación del usuario
  LatLng? ubicacionUsuario;
  bool primeraVezUbicacion = true;
  
  // Variables para menú expandible de botones
  bool menuExpandido = false;
  
  // Variables para modo comparación
  bool modoComparacion = false;
  double valorSwipe = 0.5; // 0.0 = solo capa 1, 1.0 = solo capa 2
  String selectedProductoComparacion = '';
  String selectedFechaComparacion = '';
  String selectedEstiloComparacion = 'ndvi';

  // Variables para clima
  Map<String, dynamic>? _ingenioCoordinates;
  bool _loadingWeather = false;

  // Variables para parcelas
  List<Map<String, dynamic>> _parcelas = [];
  List<Polygon> _parcelasPoligonos = []; // CACHE de polígonos
  bool _mostrarParcelas = true;
  bool _loadingParcelas = false;
  bool _isMapReady = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    modoVerInspecciones = false; 
    
    // Establecer coordenadas por defecto inmediatamente
    _initialCenter = const LatLng(15.083297525301454, -92.62443554604393);
    
    // Inicializar filtros de forma asíncrona
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inicializarFiltros();
      
      if (widget.modoInspeccionInicial) {
        setState(() {
          modoInspeccion = true;
          puntoInspeccion = _initialCenter;
        });
      }
    });
  }

  Future<void> _inicializarFiltros() async {
    if (!mounted) return;
    
    try {
      print('🔄 Inicializando filtros...');
      
      // Verificar autenticación usando SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      final email = prefs.getString('user_email') ?? '';
      
      if (!isLoggedIn || email.isEmpty) {
        print('❌ Usuario no autenticado');
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/');
        }
        return;
      }

      print('✅ Usuario autenticado: $email');

      // Obtener información del usuario desde SharedPreferences
      selectedEmpresa = prefs.getString('user_company') ?? '';
      final userIngenio = prefs.getString('user_ingenio') ?? '';
      selectedCountry = (prefs.getString('user_country') ?? '').toLowerCase();

      print('✅ Información de usuario obtenida: $selectedEmpresa');

      if (selectedEmpresa.isEmpty) {
        print('❌ Empresa vacía');
        _usarValoresPorDefecto();
        return;
      }

      // Actualizar UI inmediatamente con datos básicos
      if (mounted) {
        setState(() {});
      }

      // Ejecutar operaciones pesadas en background
      _cargarDatosEnBackground(userIngenio);

      // Cargar coordenadas del ingenio (no crítico para la UI)
      _loadIngenioCoordinates().then((_) {
        if (_ingenioCoordinates != null && mounted) {
          final newCenter = LatLng(
            _ingenioCoordinates!['latitude']! as double,
            _ingenioCoordinates!['longitude']! as double,
          );
          
          // Solo actualizar si las coordenadas son diferentes
          if (_initialCenter != newCenter) {
            setState(() {
              _initialCenter = newCenter;
            });
            print('✅ Coordenadas actualizadas para $selectedIngenio: $newCenter');
          }
        }
      }).catchError((e) {
        print('⚠️ Error cargando coordenadas del ingenio: $e');
      });

      // Actualizar UI
      if (mounted) {
        setState(() {});
        print('✅ Inicialización completada');
      }

    } catch (e) {
      print('❌ Error crítico en _inicializarFiltros: $e');
      _usarValoresPorDefecto();
    }
  }

  void _usarValoresPorDefecto() {
    print('🔧 Usando valores por defecto');
    selectedEmpresa = '';
    selectedIngenio = '';
    selectedCountry = '';
    selectedFecha = '';
    selectedProducto = '';
    ingeniosDisponibles = [];
    fechasDisponibles = [];
    productosDisponibles = [];
    _initialCenter = const LatLng(15.083297525301454, -92.62443554604393);
    
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al cargar datos. Usando vista básica.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // Método para cargar datos pesados en background sin bloquear la UI
  Future<void> _cargarDatosEnBackground(String userIngenio) async {
    try {
      // Obtener ingenios
      if (userIngenio == 'Todos') {
        ingeniosDisponibles = await Future.any([
          supabaseService.getIngeniosByCompany(selectedEmpresa),
          Future.delayed(const Duration(seconds: 5), () => <String>[]),
        ]);
      } else {
        ingeniosDisponibles = [userIngenio];
      }

      // Seleccionar ingenio válido
      selectedIngenio = ingeniosDisponibles.firstWhere(
        (ingenio) => ingenio != 'Todos' && ingenio.isNotEmpty, 
        orElse: () => ingeniosDisponibles.isNotEmpty ? ingeniosDisponibles.first : ''
      );

      if (selectedIngenio.isEmpty) {
        print('❌ No hay ingenios disponibles');
        return;
      }

      print('✅ Ingenio seleccionado: $selectedIngenio');

      // Actualizar UI con ingenio
      if (mounted) {
        setState(() {});
      }

      // Obtener fechas con timeout reducido
      fechasDisponibles = await Future.any([
        supabaseService.getFechasDisponibles(selectedEmpresa, selectedIngenio),
        Future.delayed(const Duration(seconds: 3), () => <String>[]),
      ]);

      if (fechasDisponibles.isNotEmpty) {
        selectedFecha = fechasDisponibles.last;
        print('✅ Fecha seleccionada: $selectedFecha');

        // Obtener productos con timeout reducido
        try {
          productosDisponibles = await Future.any([
            supabaseService.getProductosPorFecha(selectedEmpresa, selectedIngenio, selectedFecha),
            Future.delayed(const Duration(seconds: 3), () => <String>[]),
          ]);

          selectedProducto = productosDisponibles.isNotEmpty ? productosDisponibles.first : '';
          print('✅ Producto seleccionado: $selectedProducto (${productosDisponibles.length} disponibles)');
        } catch (e) {
          print('❌ Error obteniendo productos: $e');
          productosDisponibles = [];
          selectedProducto = '';
        }
      } else {
        selectedFecha = '';
        productosDisponibles = [];
        selectedProducto = '';
        print('⚠️ No hay fechas disponibles para $selectedEmpresa - $selectedIngenio');
      }

      // Actualizar UI final
      if (mounted) {
        setState(() {});
      }

      // Cargar coordenadas del ingenio en background (no crítico para la UI)
      _loadIngenioCoordinates().then((_) {
        if (_ingenioCoordinates != null && mounted) {
          final newCenter = LatLng(
            _ingenioCoordinates!['latitude']! as double,
            _ingenioCoordinates!['longitude']! as double,
          );
          
          // Solo actualizar si las coordenadas son diferentes
          if (_initialCenter != newCenter) {
            setState(() {
              _initialCenter = newCenter;
            });
            print('✅ Coordenadas actualizadas para $selectedIngenio: $newCenter');
          }
        }
      }).catchError((e) {
        print('⚠️ Error cargando coordenadas del ingenio: $e');
      });

      print('✅ Carga en background completada');

    } catch (e) {
      print('❌ Error crítico en _cargarDatosEnBackground: $e');
    }
  }

  Map<String, String> estilosPorProducto = {
    'ndvi': 'ndvi',
    'ndwi': 'ndwi',
    'potencial_ndvi': 'potencial',
    'potencial_ndwi': 'potencial',
    'sg': 'sg',
    'maleza': 'maleza',
  };

  // Función para crear colormap personalizado con TiTiler usando nuestras paletas exactas
  String buildCustomColormap(String producto) {
    switch (producto) {
      case 'ndvi':
        return 'ndvi_custom';
      case 'ndwi':
        return 'ndwi_custom';
      case 'potencial':
        return 'potencial_custom';
      case 'sg':
        return 'sg_custom';
      case 'maleza':
        return 'maleza_custom';
      default:
        return 'viridis';
    }
  }

  // Nueva función para construir URLs de TiTiler con paletas personalizadas
  String buildTileUrl(String baseUrl, String cogUrl, String colormap, double rescaleMin, double rescaleMax) {
    // Construir URL base con WebMercatorQuad tileMatrixSetId
    String url = '$baseUrl/cog/tiles/WebMercatorQuad/{z}/{x}/{y}.png?url=$cogUrl&rescale=$rescaleMin,$rescaleMax';
    
    // Para todas las paletas personalizadas, usar colormap JSON
    if (colormap.endsWith('_custom')) {
      final customColormapJSON = buildCustomColormapJSON(colormap);
      url += '&colormap=${Uri.encodeComponent(customColormapJSON)}';
    } else {
      // Para colormap predefinido (fallback)
      url += '&colormap_name=$colormap';
    }
    
    return url;
  }

  // Función unificada para crear JSON de colormap personalizado para todos los productos
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
      case 'sg_custom':
        colorsHex = [
          '#E60000', '#FEE825', '#6DCF5A', '#35B879',
          '#1F9E89', '#26838F', '#31688E', '#3E4A8A',
          '#482878', '#440154'
        ];
        break;
      case 'maleza_custom':
        colorsHex = [
          '#4CE600', '#38A800', '#FFFF00',
          '#E69800', '#FF2B18'
        ];
        break;
      case 'potencial_custom':
        colorsHex = [
          '#734C00', '#FF0000', '#FFFF00', '#00FF00'
        ];
        break;
      default:
        // Fallback para NDVI si algo sale mal
        colorsHex = [
          '#000000', '#734C00', '#FF0000', '#E60000',
          '#FFAA00', '#FFFF73', '#D1FF73', '#55FF00',
          '#38A800', '#73DFFF', '#0070FF', '#002673',
          '#C500FF', '#A80084'
        ];
    }
    
    return _createColormapJSON(colorsHex);
  }

  // Función helper para crear el JSON del colormap con interpolación
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
    
    // Crear 256 puntos interpolando entre los colores
    for (int i = 0; i <= 255; i++) {
      // Calcular posición en la paleta original (0.0 a 1.0)
      double position = i / 255.0;
      
      // Calcular índice en la paleta original
      double floatIndex = position * (rgbColors.length - 1);
      int lowerIndex = floatIndex.floor();
      int upperIndex = (lowerIndex + 1).clamp(0, rgbColors.length - 1);
      
      if (lowerIndex == upperIndex) {
        // Usar color exacto
        colormapDict[i.toString()] = List<int>.from(rgbColors[lowerIndex]);
      } else {
        // Interpolar entre dos colores
        double weight = floatIndex - lowerIndex;
        List<int> lowerColor = rgbColors[lowerIndex];
        List<int> upperColor = rgbColors[upperIndex];
        
        int r = (lowerColor[0] + (upperColor[0] - lowerColor[0]) * weight).round();
        int g = (lowerColor[1] + (upperColor[1] - lowerColor[1]) * weight).round();
        int b = (lowerColor[2] + (upperColor[2] - lowerColor[2]) * weight).round();
        
        colormapDict[i.toString()] = [r, g, b];
      }
    }
    
    // Convertir a JSON compacto
    return jsonEncode(colormapDict);
  }

  // Función unificada para crear leyenda con colores exactos para todos los productos
  Widget buildCustomColorLegend(String producto) {
    List<String> colors;
    List<String> labels;
    String title;
    
    switch (producto) {
      case 'ndvi':
        colors = [
          '#000000', '#734C00', '#FF0000', '#E60000',
          '#FFAA00', '#FFFF73', '#D1FF73', '#55FF00',
          '#38A800', '#73DFFF', '#0070FF', '#002673',
          '#C500FF', '#A80084'
        ];
        labels = ['0.0', '0.1', '0.2', '0.3', '0.4', '0.5', '0.55', '0.6', '0.65', '0.7', '0.75', '0.8', '0.85', '0.9'];
        title = 'NDVI';
        break;
      case 'ndwi':
        colors = [
          '#5C09FC', '#6B84FD', '#3ADFFE', '#89FDCC',
          '#D2FD77', '#F8E71C', '#FF9A0B', '#FE230A'
        ];
        labels = ['-0.75', '-0.7', '-0.65', '-0.60', '-0.55', '-0.5', '-0.40', '0.0'];
        title = 'NDWI';
        break;
      case 'sg':
        colors = [
          '#E60000', '#FEE825', '#6DCF5A', '#35B879',
          '#1F9E89', '#26838F', '#31688E', '#3E4A8A',
          '#482878', '#440154'
        ];
        labels = ['20', '40', '50', '55', '60', '70', '80', '90', '95', '100'];
        title = 'Smart Growth Index';
        break;
      case 'maleza':
        colors = [
          '#4CE600', '#38A800', '#FFFF00', '#E69800', '#FF2B18'
        ];
        labels = ['1', '2', '3', '4', '5'];
        title = 'Maleza';
        break;
      case 'potencial':
        colors = [
          '#734C00', '#FF0000', '#FFFF00', '#00FF00'
        ];
        labels = ['Muy Bajo', 'Bajo', 'Medio', 'Alto'];
        title = 'Potencial';
        break;
      default:
        return Container(); // No mostrar leyenda para productos desconocidos
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))
          ),
          const SizedBox(height: 4),
          Container(
            height: 16,
            child: Row(
              children: colors.map((colorHex) {
                final color = Color(int.parse(colorHex.substring(1), radix: 16) + 0xFF000000);
                return Expanded(
                  child: Container(
                    color: color,
                    height: 16,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(labels.first, style: const TextStyle(fontSize: 10)),
              Text(labels.last, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _actualizarFechasYProductos() async {
    fechasDisponibles = await supabaseService.getFechasDisponibles(selectedEmpresa, selectedIngenio);
    if (fechasDisponibles.isNotEmpty) {
      selectedFecha = fechasDisponibles.last;
      productosDisponibles = await supabaseService.getProductosPorFecha(
        selectedEmpresa, selectedIngenio, selectedFecha,
      );
      selectedProducto = productosDisponibles.isNotEmpty ? productosDisponibles.first : '';
    } else {
      selectedFecha = '';
      productosDisponibles = [];
      selectedProducto = '';
    }
    
    // Actualizar coordenadas del clima cuando cambie el ingenio
    await _loadIngenioCoordinates();
    
    // Cargar parcelas del nuevo ingenio
    await _cargarParcelas();
    
    setState(() {});
  }

  // Cargar coordenadas del ingenio para el clima
  Future<void> _loadIngenioCoordinates() async {
    if (selectedIngenio.isEmpty) return;
    
    setState(() => _loadingWeather = true);
    
    try {
      _ingenioCoordinates = await supabaseService.getIngenioCoordinates(selectedIngenio);
    } catch (e) {
      print('ERROR Error cargando coordenadas del ingenio: $e');
      _ingenioCoordinates = null;
    }
    
    setState(() => _loadingWeather = false);
  }

  Future<void> _irALaUbicacionActual() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servicio de ubicación deshabilitado')),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permisos de ubicación denegados permanentemente')),
      );
      return;
    }

    final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    final userLatLng = LatLng(position.latitude, position.longitude);
    
    // Actualizar la ubicación del usuario y mostrar el marcador inmediatamente
    ubicacionUsuario = userLatLng;
    setState(() {}); // Actualizar UI para mostrar el marcador de ubicación inmediatamente

    if (primeraVezUbicacion) {
      // Primera vez: Ajustar zoom para incluir vista actual + ubicación del usuario
      final currentCenter = _mapController.camera.center;
      final currentZoom = _mapController.camera.zoom;
      
      // Calcular bounds que incluyan ambos puntos
      final bounds = LatLngBounds.fromPoints([currentCenter, userLatLng]);
      
      // Ajustar la vista para mostrar ambos puntos con padding
      _mapController.fitCamera(CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50.0),
        maxZoom: currentZoom > 14 ? currentZoom : 14, // Máximo zoom razonable
        minZoom: 8, // Mínimo zoom para no alejarse demasiado
      ));
      
      primeraVezUbicacion = false;
    } else {
      // Segunda vez: Zoom solo a la ubicación del usuario
      _mapController.move(userLatLng, 16);
      primeraVezUbicacion = true; // Reiniciar para próxima vez
    }
  }

  // Función para regresar a la vista inicial
  void _regresarAVistaInicial() {
    // Si hay parcelas cargadas, centrar en ellas; si no, ir a coordenadas por defecto
    if (_parcelas.isNotEmpty) {
      _centrarEnParcelas(_parcelas);
    } else {
      // Usar coordenadas por defecto de Huixtla
      _mapController.move(const LatLng(15.083297525301454, -92.62443554604393), initialZoom);
    }
    // Resetear estado de ubicación para que funcione correctamente el botón de ubicación
    primeraVezUbicacion = true;
  }

  // Función para alternar el menú expandible
  void _toggleMenu() {
    setState(() {
      menuExpandido = !menuExpandido;
    });
  }

  // Función para activar modo comparación
  void _activarModoComparacion() {
    setState(() {
      modoComparacion = true;
      menuExpandido = false; // Cerrar menú
      // Inicializar con valores válidos de los productos disponibles
      if (productosDisponibles.isNotEmpty) {
        if (selectedProductoComparacion.isEmpty || !productosDisponibles.contains(selectedProductoComparacion)) {
          selectedProductoComparacion = productosDisponibles.first;
        }
        if (selectedFechaComparacion.isEmpty || !fechasDisponibles.contains(selectedFechaComparacion)) {
          selectedFechaComparacion = fechasDisponibles.isNotEmpty ? fechasDisponibles.last : selectedFecha;
        }
      }
      selectedEstiloComparacion = selectedEstilo;
    });
  }

  // Función para salir del modo comparación
  void _salirModoComparacion() {
    setState(() {
      modoComparacion = false;
      valorSwipe = 0.5;
    });
  }

  // Función para cargar parcelas del ingenio seleccionado SIN auto-centrado
  Future<void> _cargarParcelasSinCentrar() async {
    // Hacer una pausa pequeña para no bloquear la UI
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (selectedEmpresa.isEmpty || selectedIngenio.isEmpty || !mounted) {
      print('WARNING No se pueden cargar parcelas: empresa o ingenio no seleccionados');
      if (mounted) {
        setState(() {
          _parcelas = [];
          _loadingParcelas = false;
        });
      }
      return;
    }
    
    if (mounted) {
      setState(() => _loadingParcelas = true);
    }
    
    try {
      // Cargar parcelas con timeout más corto para evitar bloqueo
      final parcelas = await Future.any([
        supabaseService.getParcelasActivas(selectedEmpresa, selectedIngenio),
        Future.delayed(const Duration(seconds: 5), () => <Map<String, dynamic>>[]),
      ]);
      
      if (mounted) {
        setState(() {
          _parcelas = parcelas;
          _loadingParcelas = false;
        });
        print('SUCCESS Cargadas ${parcelas.length} parcelas para $selectedIngenio (sin auto-centrado)');
      }
    } catch (e) {
      print('ERROR Error cargando parcelas: $e');
      if (mounted) {
        setState(() {
          _parcelas = [];
          _loadingParcelas = false;
        });
      }
    }
  }

  // Función para cargar parcelas del ingenio seleccionado CON auto-centrado (versión original)
  Future<void> _cargarParcelas() async {
    if (selectedEmpresa.isEmpty || selectedIngenio.isEmpty || !mounted) {
      print('WARNING No se pueden cargar parcelas: empresa o ingenio no seleccionados');
      return;
    }
    
    setState(() => _loadingParcelas = true);
    
    try {
      final parcelas = await supabaseService.getParcelasActivas(selectedEmpresa, selectedIngenio);
      
      // Convertir a polígonos UNA SOLA VEZ
      final poligonos = _convertirParcelasAPoligonos(parcelas);
      
      setState(() {
        _parcelas = parcelas;
        _parcelasPoligonos = poligonos;
        _loadingParcelas = false;
      });
      print('SUCCESS Cargadas ${parcelas.length} parcelas y ${poligonos.length} polígonos para $selectedIngenio');
      
      // Centrar y hacer zoom en las parcelas del ingenio solo si hay parcelas válidas
      if (parcelas.isNotEmpty && mounted) {
        // Añadir un pequeño delay para asegurar que el mapa esté listo
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            _centrarEnParcelas(parcelas);
          }
        });
      }
    } catch (e) {
      print('ERROR Error cargando parcelas: $e');
      if (mounted) {
        setState(() {
          _parcelas = [];
          _parcelasPoligonos = [];
          _loadingParcelas = false;
        });
      }
    }
  }

  // Función para centrar el mapa usando centroides de la base de datos
  void _centrarEnParcelas(List<Map<String, dynamic>> parcelas) async {
    if (!mounted || parcelas.isEmpty) {
      print('⚠️ No se puede centrar: sin parcelas o widget no montado');
      return;
    }

    try {
      // Usar el centroide calculado desde la base de datos para mayor eficiencia
      print('🎯 Centrando mapa usando centroide de vw_centroide_global...');
      
      final coordenadas = await Future.any([
        supabaseService.getIngenioCoordinates(selectedIngenio),
        Future.delayed(const Duration(seconds: 5), () => null),
      ]);
      
      if (coordenadas != null && mounted) {
        final latitude = coordenadas['latitude']! as double;
        final longitude = coordenadas['longitude']! as double;
        
        // Verificar si tenemos bounds disponibles para un centrado más preciso
        final minLat = coordenadas['min_lat'] as double?;
        final maxLat = coordenadas['max_lat'] as double?;
        final minLng = coordenadas['min_lng'] as double?;
        final maxLng = coordenadas['max_lng'] as double?;
        final boundsValidos = coordenadas['bounds_validos'] as bool? ?? true;
        
        // Añadir un pequeño delay para asegurar que el mapa esté listo
        await Future.delayed(const Duration(milliseconds: 300));
        
        if (mounted && _isMapReady) {
          try {
            // Solo usar bounds si son válidos y razonables
            if (boundsValidos && minLat != null && maxLat != null && minLng != null && maxLng != null &&
                minLat != latitude && maxLat != latitude && minLng != longitude && maxLng != longitude) {
              
              // Verificar que los bounds no sean extremos (outliers)
              double latRange = maxLat - minLat;
              double lngRange = maxLng - minLng;
              
              print('📏 Rango de bounds - Lat: $latRange°, Lng: $lngRange°');
              
              // Si el rango es menor a 1 grado, usar bounds; si es mayor, usar punto central
              if (latRange < 1.0 && lngRange < 1.0) {
                final bounds = LatLngBounds(
                  LatLng(minLat, minLng), // southwest
                  LatLng(maxLat, maxLng), // northeast
                );
                
                _mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(30), // Padding moderado para zoom óptimo
                  ),
                );
                
                print('✅ Centrado usando bounds filtrados: ($minLat, $minLng) a ($maxLat, $maxLng)');
              } else {
                // Bounds muy amplios, usar punto central con zoom fijo
                print('⚠️ Bounds amplios detectados (lat: $latRange, lng: $lngRange), usando punto central');
                _mapController.move(LatLng(latitude, longitude), 15.0);
                print('✅ Centrado en punto específico: ($latitude, $longitude)');
              }
            } else {
              // Sin bounds válidos, usar punto central con zoom apropiado
              _mapController.move(LatLng(latitude, longitude), 15.0);
              print('✅ Centrado en punto específico: ($latitude, $longitude)');
            }
            
          } catch (e) {
            print('⚠️ Error al centrar el mapa, usando fallback: $e');
            // Fallback silencioso: mover a las coordenadas básicas con zoom muy cercano
            if (mounted && _isMapReady) {
              _mapController.move(LatLng(latitude, longitude), 15.0);
            }
          }
        }
        
        print('✅ Mapa centrado exitosamente en $selectedIngenio');
      } else {
        print('⚠️ No se pudieron obtener coordenadas, usando centrado manual fallback');
        _centrarEnParcelasFallback(parcelas);
      }
    } catch (e) {
      print('❌ Error obteniendo centroide de la BD: $e');
      // Fallback al método manual si hay error con la BD
      _centrarEnParcelasFallback(parcelas);
    }
  }

  // Método fallback para centrado manual (método anterior como respaldo)
  void _centrarEnParcelasFallback(List<Map<String, dynamic>> parcelas) async {
    if (parcelas.isEmpty || !mounted) return;

    try {
      print('🔄 Usando centrado manual fallback...');
      
      double minLat = double.infinity;
      double maxLat = -double.infinity;
      double minLon = double.infinity;
      double maxLon = -double.infinity;
      
      int parcelasValidas = 0;

      // Calcular el bounding box de todas las parcelas
      for (var parcela in parcelas) {
        try {
          dynamic geometryData = parcela['geometry_polygon'];
          Map<String, dynamic> geometry;
          
          if (geometryData is String) {
            geometry = jsonDecode(geometryData);
          } else if (geometryData is Map<String, dynamic>) {
            geometry = geometryData;
          } else {
            continue;
          }
          
          if (geometry['type'] == 'Polygon' && geometry['coordinates'] != null) {
            final coordenadas = geometry['coordinates'][0] as List;
            parcelasValidas++;
            
            for (var coord in coordenadas) {
              if (coord is List && coord.length >= 2) {
                double lon = coord[0].toDouble();
                double lat = coord[1].toDouble();
                
                if (lat < minLat) minLat = lat;
                if (lat > maxLat) maxLat = lat;
                if (lon < minLon) minLon = lon;
                if (lon > maxLon) maxLon = lon;
              }
            }
          }
        } catch (e) {
          print('⚠️ Error procesando parcela para centrado: $e');
          continue;
        }
      }

      // Verificar que tenemos coordenadas válidas
      if (parcelasValidas > 0 && minLat != double.infinity && maxLat != -double.infinity && 
          minLon != double.infinity && maxLon != -double.infinity && mounted) {
        
        final bounds = LatLngBounds(
          LatLng(minLat, minLon),
          LatLng(maxLat, maxLon),
        );
        
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (mounted && _isMapReady) {
          try {
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.all(10), // Padding muy reducido para zoom muy cercano
              ),
            );
          } catch (e) {
            print('⚠️ Error al centrar el mapa en fallback: $e');
          }
        }
        
        final centerLat = (minLat + maxLat) / 2;
        final centerLon = (minLon + maxLon) / 2;
        print('✅ Centrado fallback completado: ($centerLat, $centerLon)');
        print('📊 Procesadas $parcelasValidas parcelas válidas');
      }
    } catch (e) {
      print('❌ Error general en centrado fallback: $e');
    }
  }

  // Función para alternar la visualización de parcelas
  void _toggleParcelas() {
    setState(() {
      _mostrarParcelas = !_mostrarParcelas;
    });
  }

  // Función para convertir GeoJSON de Supabase a polígonos de Flutter Map
  List<Polygon> _convertirParcelasAPoligonos([List<Map<String, dynamic>>? parcelas]) {
    final parcelasAConvertir = parcelas ?? _parcelas;
    if (parcelasAConvertir.isEmpty) {
      return [];
    }
    
    List<Polygon> poligonos = [];
    int parcelasExitosas = 0;
    int parcelasConError = 0;
    
    // Procesar TODAS las parcelas sin límite
    print('>>> Convirtiendo ${parcelasAConvertir.length} parcelas a polígonos...');
    
    for (var parcela in parcelasAConvertir) {
      try {
        final geometryJson = parcela['geometry_polygon'];
        if (geometryJson == null) continue;
        
        // Parsear el GeoJSON de forma segura
        Map<String, dynamic> geometry;
        if (geometryJson is String) {
          if (geometryJson.trim().isEmpty) continue;
          geometry = jsonDecode(geometryJson);
        } else if (geometryJson is Map<String, dynamic>) {
          geometry = geometryJson;
        } else {
          continue;
        }
        
        if (geometry['type'] == 'Polygon' && geometry['coordinates'] != null) {
          final coordinates = geometry['coordinates'] as List;
          
          // El primer array son las coordenadas del polígono exterior
          if (coordinates.isNotEmpty) {
            final exteriorRing = coordinates[0] as List;
            List<LatLng> puntos = [];
            
            // Limitar también el número de puntos por polígono
            final puntosLimitados = exteriorRing.take(100).toList(); // Máximo 100 puntos por polígono
            
            for (var coord in puntosLimitados) {
              if (coord is List && coord.length >= 2) {
                try {
                  // GeoJSON usa [longitud, latitud]
                  double lng = (coord[0] as num).toDouble();
                  double lat = (coord[1] as num).toDouble();
                  
                  // Validar coordenadas razonables
                  if (lat.abs() <= 90 && lng.abs() <= 180) {
                    puntos.add(LatLng(lat, lng));
                  }
                } catch (e) {
                  // Saltar coordenada inválida
                  continue;
                }
              }
            }
            
            // Solo crear polígono si tenemos al menos 3 puntos válidos
            if (puntos.length >= 3) {
              poligonos.add(
                Polygon(
                  points: puntos,
                  color: Colors.transparent, // Sin relleno
                  borderColor: Colors.blue.withOpacity(0.7), // Azul semi-transparente
                  borderStrokeWidth: 1.0, // Línea delgada
                  isFilled: false,
                ),
              );
              parcelasExitosas++;
            }
          }
        }
      } catch (e) {
        parcelasConError++;
        // Solo mostrar los primeros errores para no saturar logs
        if (parcelasConError <= 5) {
          print('ERROR Error procesando parcela ${parcela['id'] ?? 'unknown'}: $e');
        }
      }
    }
    
    print('>>> Poligonos creados: $parcelasExitosas exitosos, $parcelasConError errores de ${parcelasAConvertir.length} parcelas');
    return poligonos;
  }


  Future<void> _mostrarFormularioInspeccion(LatLng punto) async {
    String tipoRegistro = 'inspeccion';
    String hallazgo = '';
    String recomendacion = '';
    String grupoLabor = '';
    String actividad = '';
    String dosis = '';
    String productoLabor = '';
    DateTime? fechaResolucion;
    XFile? imagenEvidencia;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) => SingleChildScrollView(
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: tipoRegistro,
                    decoration: const InputDecoration(labelText: 'Tipo de registro'),
                    items: const [
                      DropdownMenuItem(value: 'inspeccion', child: Text('Inspección')),
                      DropdownMenuItem(value: 'labor', child: Text('Labor')),
                    ],
                    onChanged: (val) => setModalState(() => tipoRegistro = val!),
                  ),
                  if (tipoRegistro == 'inspeccion') ...[
                    DropdownButtonFormField<String>(
                      value: hallazgo.isNotEmpty ? hallazgo : null,
                      decoration: const InputDecoration(labelText: 'Hallazgo'),
                      items: const [
                        'Daño por plaga',
                        'Daño mecanico',
                        'Uniformidad por resiembra',
                        'Despoblacion',
                        'Estres Hidrico',
                        'Inundacion por drenaje',
                        'Daño por Herbicida',
                        'Daño por dosis de Fertilizacion',
                        'Topografia',
                        'Error de dibujo',
                        'Daño por Madurante',
                        'Malezas',
                      ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (val) => setModalState(() => hallazgo = val!),
                    ),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Recomendación'),
                      onChanged: (val) => recomendacion = val,
                    ),
                    ListTile(
                      leading: const Icon(Icons.calendar_today),
                      title: Text(
                        fechaResolucion == null
                            ? 'Fecha de resolución'
                            : 'Resolución: ${fechaResolucion!.toLocal().toString().split(' ')[0]}',
                      ),
                      onTap: () async {
                        final now = DateTime.now();
                        final selectedDate = await showDatePicker(
                          context: context,
                          initialDate: now,
                          firstDate: now,
                          lastDate: now.add(const Duration(days: 60)),
                        );
                        if (selectedDate != null) {
                          setModalState(() => fechaResolucion = selectedDate);
                        }
                      },
                    ),
                  ] else ...[
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Grupo de labor'),
                      onChanged: (val) => grupoLabor = val,
                    ),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Actividad'),
                      onChanged: (val) => actividad = val,
                    ),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Dosis'),
                      onChanged: (val) => dosis = val,
                    ),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Producto'),
                      onChanged: (val) => productoLabor = val,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.camera_alt),
                        tooltip: 'Tomar foto',
                        onPressed: () async {
                          final picked = await ImagePicker().pickImage(source: ImageSource.camera);
                          if (picked != null) setModalState(() => imagenEvidencia = picked);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.photo_library),
                        tooltip: 'Desde galería',
                        onPressed: () async {
                          final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
                          if (picked != null) setModalState(() => imagenEvidencia = picked);
                        },
                      ),
                      if (imagenEvidencia != null)
                        Expanded(child: Text(imagenEvidencia!.name, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () async {
                      // Validaciones básicas
                      if (tipoRegistro == 'inspeccion' && hallazgo.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Por favor selecciona un hallazgo')),
                        );
                        return;
                      }
                      
                      if (tipoRegistro == 'labor' && (grupoLabor.isEmpty || actividad.isEmpty)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Por favor completa los campos de labor')),
                        );
                        return;
                      }

                      try {
                        String? imageUrl;
                        if (imagenEvidencia != null) {
                          final bytes = await imagenEvidencia!.readAsBytes();
                          final user = Supabase.instance.client.auth.currentUser;
                          if (user == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Sesión expirada. Por favor vuelve a iniciar sesión.')),
                            );
                            return;
                          }
                          final fileName = 'inspecciones/${DateTime.now().millisecondsSinceEpoch}_${imagenEvidencia!.name}';
                          try {
                            await Supabase.instance.client.storage
                              .from('evidencias')
                              .uploadBinary(fileName, bytes, fileOptions: const FileOptions(upsert: true));
                            imageUrl = Supabase.instance.client.storage
                              .from('evidencias')
                              .getPublicUrl(fileName);
                          } catch (e) {
                            print('ERROR Error al subir imagen: $e');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('No se pudo subir la imagen: $e')),
                            );
                            return; // detener el flujo si no se pudo subir
                          }
                        }

                        // Obtener información del usuario actual
                        final user = Supabase.instance.client.auth.currentUser;
                        final userName = user?.email ?? 'Usuario desconocido';

                        final datos = {
                          'latitud': punto.latitude,
                          'longitud': punto.longitude,
                          'company': selectedEmpresa,
                          'ingenio': selectedIngenio,
                          'producto': selectedProducto,
                          'fecha_mapa': selectedFecha,
                          'fecha_creacion': DateTime.now().toIso8601String(),
                          'fecha_ultima_modificacion': DateTime.now().toIso8601String(),
                          'usuario': userName,
                          'tipo_registro': tipoRegistro,
                          'estatus_inspeccion': 'pendiente',
                          'fecha_posible_resolucion': fechaResolucion?.toIso8601String(),
                          if (imageUrl != null) 'evidencia_labor': [imageUrl],
                        };

                        if (tipoRegistro == 'inspeccion') {
                          datos['hallazgo'] = hallazgo;
                          datos['recomendacion'] = recomendacion;
                        } else {
                          datos['grupo_labor'] = grupoLabor;
                          datos['actividad'] = actividad;
                          datos['dosis'] = dosis;
                          datos['producto_labor'] = productoLabor;
                        }

                        await Supabase.instance.client.from('inspecciones').insert(datos);

                        if (mounted) {
                          Navigator.pop(context);
                          setState(() {
                            modoInspeccion = false;
                            puntoInspeccion = null;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Inspección enviada exitosamente')),
                          );
                        }
                      } catch (e) {
                        print('ERROR Error al guardar inspeccion: $e');
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error al guardar inspección: $e')),
                        );
                      }
                    },
                    child: const Text('Enviar inspección'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _cargarInspeccionesEnMapa() async {
    final inspecciones = await supabaseService.getInspeccionesUltimoMes(
      selectedEmpresa,
      selectedIngenio,
    );

    final nuevosMarcadores = inspecciones.map((inspeccion) {
      final estatus = inspeccion['estatus_inspeccion'];
      final color = estatus == 'pendiente'
          ? Colors.orange
          : estatus == 'en proceso'
              ? Colors.blue
              : Colors.green;

      return Marker(
        width: 40,
        height: 40,
        point: LatLng(
          (inspeccion['latitud'] as num).toDouble(),
          (inspeccion['longitud'] as num).toDouble(),
        ),
        child: GestureDetector(
          onTap: () => _mostrarFormularioEdicion(inspeccion),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.location_on, color: Colors.white, size: 38), // borde blanco
              Icon(Icons.location_on, color: color, size: 30),         // marcador real
            ],
          ),
        ),
      );
    }).toList();

    setState(() {
      _marcadoresInspecciones = nuevosMarcadores;
    });

  }

  void _mostrarFormularioEdicion(Map<String, dynamic> inspeccion) {
    if (inspeccion['tipo_registro'] != 'inspeccion') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solo se pueden editar inspecciones, no labores')),
      );
      return;
    }

    String hallazgo = inspeccion['hallazgo'] ?? '';
    String recomendacion = inspeccion['recomendacion'] ?? '';
    String estatus = inspeccion['estatus_inspeccion'] ?? 'pendiente';
    DateTime? fechaResolucion = inspeccion['fecha_posible_resolucion'] != null
        ? DateTime.tryParse(inspeccion['fecha_posible_resolucion'])
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: hallazgo.isNotEmpty ? hallazgo : null,
                    decoration: const InputDecoration(labelText: 'Hallazgo'),
                    items: const [
                      'Daño por plaga',
                      'Daño mecanico',
                      'Uniformidad por resiembra',
                      'Despoblacion',
                      'Estres Hidrico',
                      'Inundacion por drenaje',
                      'Daño por Herbicida',
                      'Daño por dosis de Fertilizacion',
                      'Topografia',
                      'Error de dibujo',
                      'Daño por Madurante',
                    ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (val) => setModalState(() => hallazgo = val ?? ''),
                  ),
                  TextFormField(
                    initialValue: recomendacion,
                    decoration: const InputDecoration(labelText: 'Recomendación'),
                    onChanged: (val) => recomendacion = val,
                  ),
                  DropdownButtonFormField<String>(
                    value: estatus,
                    decoration: const InputDecoration(labelText: 'Estatus de inspección'),
                    items: const [
                      DropdownMenuItem(value: 'pendiente', child: Text('Pendiente')),
                      DropdownMenuItem(value: 'en proceso', child: Text('En proceso')),
                      DropdownMenuItem(value: 'resuelto', child: Text('Resuelto')),
                    ],
                    onChanged: (val) => setModalState(() => estatus = val ?? 'pendiente'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: Text(
                      fechaResolucion == null
                          ? 'Fecha de resolución'
                          : 'Resolución: ${fechaResolucion!.toLocal().toIso8601String().split('T')[0]}',
                    ),
                    onTap: () async {
                      final now = DateTime.now();
                      final selectedDate = await showDatePicker(
                        context: context,
                        initialDate: fechaResolucion ?? now,
                        firstDate: now.subtract(const Duration(days: 30)),
                        lastDate: now.add(const Duration(days: 90)),
                      );
                      if (selectedDate != null) {
                        setModalState(() => fechaResolucion = selectedDate);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('Aplicar cambios'),
                    onPressed: () async {
                      try {
                        await Supabase.instance.client
                            .from('inspecciones')
                            .update({
                              'hallazgo': hallazgo,
                              'recomendacion': recomendacion,
                              'estatus_inspeccion': estatus,
                              'fecha_posible_resolucion': fechaResolucion?.toIso8601String(),
                              'fecha_ultima_modificacion': DateTime.now().toIso8601String(),
                            })
                            .eq('id', inspeccion['id']);

                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Inspección actualizada')),
                          );
                          _cargarInspeccionesEnMapa(); // refrescar puntos
                        }
                      } catch (e) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error al actualizar inspección: $e')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    // Solo mostrar loading si realmente no tenemos coordenadas iniciales
    if (_initialCenter == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                color: Color(0xFF52AA5E),
              ),
              const SizedBox(height: 16),
              Text(
                'Cargando mapa...',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Si no hay datos de empresa/ingenio, mostrar el mapa básico
    if (selectedEmpresa.isEmpty || selectedIngenio.isEmpty) {
      print('⚠️ Mostrando mapa básico - Empresa: $selectedEmpresa, Ingenio: $selectedIngenio');
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter!,
              initialZoom: initialZoom,
              onMapReady: () {
                try {
                  // Marcar el mapa como listo
                  setState(() {
                    _isMapReady = true;
                  });
                  // Cargar parcelas cuando el mapa esté listo (pero sin centrar automáticamente)
                  print('INFO Mapa listo, cargando parcelas sin auto-centrado...');
                  _cargarParcelasSinCentrar().catchError((e) {
                    print('ERROR en _cargarParcelasSinCentrar desde onMapReady: $e');
                  });
                } catch (e) {
                  print('ERROR crítico en onMapReady: $e');
                }
              },
              onPositionChanged: (pos, hasGesture) {
                try {
                  if (modoInspeccion) {
                    setState(() => puntoInspeccion = pos.center);
                  }
                  // Actualizar la UI cuando cambie el zoom para mostrar/ocultar parcelas
                  if (mounted) {
                    setState(() {});
                  }
                } catch (e) {
                  print('ERROR en onPositionChanged: $e');
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/satellite-v9/tiles/{z}/{x}/{y}?access_token=$mapboxAccessToken',
                userAgentPackageName: 'com.example.techno_analytics',
                minZoom: 1,
                maxZoom: 30,
                tileProvider: CancellableNetworkTileProvider(
                  silenceExceptions: true, // Silenciar errores 404 de tiles base
                ),
              ),
              if (selectedEmpresa.isNotEmpty && selectedIngenio.isNotEmpty && selectedProducto.isNotEmpty && selectedFecha.isNotEmpty && !modoComparacion)
                FutureBuilder<Map<String, dynamic>?>(
                  future: supabaseService.getProductoInfo(selectedEmpresa, selectedIngenio, selectedProducto, selectedFecha),
                  builder: (context, snapshot) {
                    // Manejo de errores silencioso
                    if (snapshot.hasError) {
                      print('⚠️ Error cargando producto info: ${snapshot.error}');
                      return Container(); // No mostrar capa si hay error
                    }
                    if (snapshot.hasData && snapshot.data != null) {
                      final producto = snapshot.data!;
                      final cogUrl = producto['cog_url'] as String?;
                      final processingStatus = producto['processing_status'] as String?;
                      
                      if (cogUrl != null && processingStatus == 'completed') {
                        // Usar TiTiler moderno con paletas predefinidas para evitar URLs largas
                        final titilerBaseUrl = 'https://ta-titiler-service-1087100331392.us-central1.run.app';
                        final estilo = estilosPorProducto[selectedProducto] ?? 'ndvi';
                        final customColormap = buildCustomColormap(estilo);
                        final rescaleMin = producto['rescale_min'] ?? 0.0;
                        final rescaleMax = producto['rescale_max'] ?? 1.0;
                        
                        return TileLayer(
                          urlTemplate: buildTileUrl(titilerBaseUrl, cogUrl, customColormap, rescaleMin, rescaleMax),
                          userAgentPackageName: 'com.example.techno_analytics',
                          minZoom: 8,
                          maxZoom: 18,
                          maxNativeZoom: 18,
                          tileProvider: CancellableNetworkTileProvider(
                            silenceExceptions: true, // Silenciar errores 404 cuando no hay productos
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
                    
                    // No hay COG disponible - mostrar mensaje
                    return Container();
                  },
                ),

              // Capas para modo comparación
              if (modoComparacion && selectedEmpresa.isNotEmpty && selectedIngenio.isNotEmpty) ...[
                // Capa base (lado izquierdo)
                FutureBuilder<Map<String, dynamic>?>(
                  future: supabaseService.getProductoInfo(selectedEmpresa, selectedIngenio, selectedProducto, selectedFecha),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      final producto = snapshot.data!;
                      final cogUrl = producto['cog_url'] as String?;
                      final processingStatus = producto['processing_status'] as String?;
                      
                      if (cogUrl != null && processingStatus == 'completed') {
                        // Usar TiTiler moderno con paletas predefinidas para evitar URLs largas
                        final titilerBaseUrl = 'https://ta-titiler-service-1087100331392.us-central1.run.app';
                        final estilo = estilosPorProducto[selectedProducto] ?? 'ndvi';
                        final customColormap = buildCustomColormap(estilo);
                        final rescaleMin = producto['rescale_min'] ?? 0.0;
                        final rescaleMax = producto['rescale_max'] ?? 1.0;
                        
                        return ClipPath(
                          clipper: LeftSideClipper(valorSwipe),
                          child: TileLayer(
                            urlTemplate: buildTileUrl(titilerBaseUrl, cogUrl, customColormap, rescaleMin, rescaleMax),
                            userAgentPackageName: 'com.example.techno_analytics',
                            minZoom: 8,
                            maxZoom: 18,
                            maxNativeZoom: 18,
                            tileProvider: CancellableNetworkTileProvider(
                              silenceExceptions: true, // Silenciar errores 404 cuando no hay productos
                            ),
                            tileBuilder: (context, widget, tile) {
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                child: widget,
                              );
                            },
                          ),
                        );
                      }
                    }
                    
                    // No hay COG disponible
                    return Container();
                  },
                ),
                // Capa de comparación (lado derecho)
                FutureBuilder<Map<String, dynamic>?>(
                  future: supabaseService.getProductoInfo(
                    selectedEmpresa, 
                    selectedIngenio, 
                    selectedProductoComparacion.isNotEmpty ? selectedProductoComparacion : selectedProducto, 
                    selectedFechaComparacion.isNotEmpty ? selectedFechaComparacion : selectedFecha
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      final producto = snapshot.data!;
                      final cogUrl = producto['cog_url'] as String?;
                      final processingStatus = producto['processing_status'] as String?;
                      
                      if (cogUrl != null && processingStatus == 'completed') {
                        // Usar TiTiler moderno con paletas predefinidas para evitar URLs largas
                        final titilerBaseUrl = 'https://ta-titiler-service-1087100331392.us-central1.run.app';
                        final productoComparacion = selectedProductoComparacion.isNotEmpty ? selectedProductoComparacion : selectedProducto;
                        final estilo = estilosPorProducto[productoComparacion] ?? 'ndvi';
                        final customColormap = buildCustomColormap(estilo);
                        final rescaleMin = producto['rescale_min'] ?? 0.0;
                        final rescaleMax = producto['rescale_max'] ?? 1.0;
                        
                        return ClipPath(
                          clipper: RightSideClipper(valorSwipe),
                          child: TileLayer(
                            urlTemplate: buildTileUrl(titilerBaseUrl, cogUrl, customColormap, rescaleMin, rescaleMax),
                            userAgentPackageName: 'com.example.techno_analytics',
                            minZoom: 8,
                            maxZoom: 18,
                            maxNativeZoom: 18,
                            tileProvider: CancellableNetworkTileProvider(
                              silenceExceptions: true, // Silenciar errores 404 cuando no hay productos
                            ),
                            tileBuilder: (context, widget, tile) {
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                child: widget,
                              );
                            },
                          ),
                        );
                      }
                    }
                    
                    // No hay COG disponible
                    return Container();
                  },
                ),
              ],

              // Capa de polígonos de parcelas (visible con zoom >= 10)
              if (_mostrarParcelas && _parcelasPoligonos.isNotEmpty && _isMapReady && _mapController.camera.zoom >= 10.0)
                PolygonLayer(polygons: _parcelasPoligonos),

              if (_marcadoresInspecciones.isNotEmpty)
                MarkerClusterLayerWidget(
                  options: MarkerClusterLayerOptions(
                    maxClusterRadius: 45,
                    size: const Size(40, 40),
                    markers: _marcadoresInspecciones,
                    polygonOptions: PolygonOptions(
                      borderColor: Colors.blueAccent,
                      color: Colors.black12,
                      borderStrokeWidth: 2,
                    ),
                    builder: (context, cluster) {
                      final estatuses = (cluster.children ?? []).map((m) {
                        final icon = (m.child as GestureDetector).child as Icon;
                        return icon.color;
                      }).toSet();

                      Color clusterColor;

                      if (estatuses.length == 1) {
                        final unicoColor = estatuses.first;
                        clusterColor = unicoColor!;
                      } else {
                        clusterColor = const Color.fromARGB(255, 41, 173, 79);
                      }

                      return Container(
                        width: 45,
                        height: 45,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: clusterColor.withOpacity(0.8),
                          boxShadow: [
                            BoxShadow(
                              color: clusterColor.withOpacity(0.5),
                              blurRadius: 15,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            cluster.length.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      );
                    }
                  ),
                ),

              if (modoInspeccion && puntoInspeccion != null)
                MarkerLayer(markers: [
                  Marker(
                    point: puntoInspeccion!,
                    width: 50,
                    height: 50,
                    child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                  )
                ]),
              
              // Marcador de ubicación del usuario
              if (ubicacionUsuario != null)
                MarkerLayer(markers: [
                  Marker(
                    point: ubicacionUsuario!,
                    width: 60,
                    height: 60,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Círculo exterior animado (pulso)
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                        ),
                        // Punto central de ubicación
                        Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 3,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        // Borde blanco interno
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        // Punto azul central
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  )
                ]),
              _buildBarLegend(),
              
              // Leyenda de comparación (solo visible en modo comparación)
              if (modoComparacion) _buildBarLegendComparacion(),
            ],
          ),

          if (modoInspeccion && puntoInspeccion != null)
            Positioned(
              bottom: 100,
              left: 16,
              child: Row(
                children: [
                  FloatingActionButton.extended(
                    heroTag: "cancelar_inspeccion",
                    onPressed: () {
                      setState(() {
                        modoInspeccion = false;
                        puntoInspeccion = null;
                      });
                    },
                    label: const Text("Cancelar", style: TextStyle(color: Colors.white)),
                    icon: const Icon(Icons.close, color: Colors.white),
                    backgroundColor: Colors.red[600],
                  ),
                  const SizedBox(width: 16),
                  FloatingActionButton.extended(
                    heroTag: "confirmar_inspeccion",
                    onPressed: () => _mostrarFormularioInspeccion(puntoInspeccion!),
                    label: const Text("Confirmar ubicación", style: TextStyle(color: Colors.white)),
                    icon: const Icon(Icons.check, color: Colors.white),
                    backgroundColor: const Color(0xFF52AA5E),
                  ),
                ],
              ),
            ),

          // Indicador de estado de parcelas
          if (_mostrarParcelas)
            Positioned(
              top: 135,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 4)
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.crop_free, 
                      color: _loadingParcelas 
                        ? Colors.orange 
                        : (_isMapReady && _mapController.camera.zoom < 12.0)
                          ? Colors.grey
                          : Colors.green,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _loadingParcelas 
                        ? 'Cargando...' 
                        : (_isMapReady && _mapController.camera.zoom < 12.0)
                          ? '${_parcelas.length} parcelas (zoom >12 para ver)'
                          : '${_parcelas.length} parcelas',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),

          if (modoVerInspecciones)
            Positioned(
              top: 160,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 4)
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _LeyendaItem(color: Colors.orange, label: 'Pendiente'),
                    SizedBox(height: 4),
                    _LeyendaItem(color: Colors.green, label: 'En proceso'),
                    SizedBox(height: 4),
                    _LeyendaItem(color: Colors.blue, label: 'Resuelto'),
                    SizedBox(height: 4),
                    _LeyendaItem(color: Colors.grey, label: 'Mixto'),
                  ],
                ),
              ),
            ),
          if (modoVerInspecciones)
            Positioned(
              top: 50,
              right: 16,
              child: FloatingActionButton.small(
                heroTag: 'cerrar_inspecciones',
                backgroundColor: Colors.red[400],
                tooltip: 'Cerrar inspecciones',
                onPressed: () {
                  setState(() {
                    modoVerInspecciones = false;
                    _marcadoresInspecciones.clear();
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Visualización de inspecciones desactivada'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),


          // Filtros superiores
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: _buildDropdown(
                    'Empresa', empresasDisponibles, selectedEmpresa, (value) async {
                      if (value == null) return;
                      selectedEmpresa = value;
                      ingeniosDisponibles = await supabaseService.getIngeniosByCompany(selectedEmpresa);
                      // Seleccionar el primer ingenio que no sea "Todos"
                      selectedIngenio = ingeniosDisponibles.firstWhere(
                        (ingenio) => ingenio != 'Todos', 
                        orElse: () => ingeniosDisponibles.isNotEmpty ? ingeniosDisponibles.first : ''
                      );
                      await _actualizarFechasYProductos();
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildDropdown(
                    'Ingenio', ingeniosDisponibles, selectedIngenio, (value) async{
                      if (value == null) return;
                      selectedIngenio = value;
                      await _actualizarFechasYProductos();
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),

          // Filtros inferiores
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black12)],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Fecha con ícono y calendario
                  GestureDetector(
                    onTap: () async {
                      if (fechasDisponibles.isEmpty || selectedEmpresa.isEmpty || selectedIngenio.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('No hay fechas disponibles')),
                        );
                        return;
                      }

                      try {
                        DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.parse(fechasDisponibles.last),
                          firstDate: DateTime.parse(fechasDisponibles.first),
                          lastDate: DateTime.parse(fechasDisponibles.last),
                          selectableDayPredicate: (day) {
                            final formatted = DateFormat('yyyy-MM-dd').format(day);
                            return fechasDisponibles.contains(formatted);
                          },
                        );

                        if (picked != null) {
                          final formatted = DateFormat('yyyy-MM-dd').format(picked);
                          selectedFecha = formatted;
                          productosDisponibles = await supabaseService.getProductosPorFecha(
                            selectedEmpresa, selectedIngenio, selectedFecha);
                          selectedProducto = productosDisponibles.isNotEmpty ? productosDisponibles.first : '';
                          setState(() {});
                        }
                      } catch (e) {
                        print('Error seleccionando fecha: $e');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Error seleccionando fecha')),
                        );
                      }
                    },
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today, 
                          size: 20,
                          color: fechasDisponibles.isEmpty ? Colors.grey : null,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          selectedFecha.isEmpty
                              ? (fechasDisponibles.isEmpty ? 'Sin fechas' : 'Fecha')
                              : DateFormat('dd/MM/yyyy').format(DateTime.parse(selectedFecha)),
                          style: TextStyle(
                            fontSize: 14,
                            color: fechasDisponibles.isEmpty ? Colors.grey : null,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Dropdown de productos
                  Row(
                    children: [
                      Icon(
                        Icons.agriculture_outlined, 
                        size: 20,
                        color: productosDisponibles.isEmpty ? Colors.grey : null,
                      ),
                      const SizedBox(width: 6),
                      DropdownButton<String>(
                        value: (selectedProducto.isNotEmpty && productosDisponibles.contains(selectedProducto)) 
                            ? selectedProducto 
                            : null,
                        hint: Text(
                          productosDisponibles.isEmpty ? 'Sin productos' : 'Producto',
                          style: TextStyle(
                            color: productosDisponibles.isEmpty ? Colors.grey : Colors.black54,
                          ),
                        ),
                        underline: const SizedBox(),
                        style: const TextStyle(color: Colors.black),
                        items: productosDisponibles.map((p) {
                          return DropdownMenuItem(value: p, child: Text(p));
                        }).toList(),
                        onChanged: productosDisponibles.isEmpty ? null : (p) {
                          if (p != null) {
                            setState(() {
                              selectedProducto = p;
                              selectedEstilo = estilosPorProducto[p] ?? 'ndvi';
                            });
                          }
                        },
                      ),
                    ],
                  ),

                  const SizedBox(width: 8),

                  // Widget de clima dinámico
                  _ingenioCoordinates != null 
                    ? WeatherWidget(
                        latitude: (_ingenioCoordinates!['latitude'] as double?) ?? 0.0,
                        longitude: (_ingenioCoordinates!['longitude'] as double?) ?? 0.0,
                        compact: true,
                      )
                    : _loadingWeather 
                      ? Container(
                          width: 60,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                              ),
                            ),
                          ),
                        )
                      : const Icon(Icons.wb_cloudy_outlined, size: 20, color: Colors.grey),
                ],
              ),
            ),
          ),

          // Controles de modo comparación
          if (modoComparacion) ...[
            // Línea divisoria vertical arrastrable (solo en el área de la línea)
            Positioned(
              left: MediaQuery.of(context).size.width * valorSwipe - 20,
              top: 0,
              bottom: 0,
              width: 40,
              child: GestureDetector(
                onPanUpdate: (details) {
                  final RenderBox renderBox = context.findRenderObject() as RenderBox;
                  final localPosition = renderBox.globalToLocal(details.globalPosition);
                  final newPosition = localPosition.dx / renderBox.size.width;
                  setState(() {
                    valorSwipe = newPosition.clamp(0.0, 1.0);
                  });
                },
                child: Container(
                  width: 40,
                  color: Colors.transparent,
                ),
              ),
            ),
            
            // Línea visual
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: DividerLinePainter(valorSwipe),
                ),
              ),
            ),
            
            // Control de swipe - compacto y a nivel de botones flotantes
            Positioned(
              bottom: 100,
              left: 16,
              right: 88, // Dejar espacio para los botones flotantes
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.97),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header con título y botón cerrar
                    SizedBox(
                      height: 32,
                      child: Row(
                        children: [
                          const Icon(Icons.compare_arrows, color: Color(0xFF52AA5E), size: 16),
                          const SizedBox(width: 6),
                          const Text(
                            'Comparación',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF52AA5E),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: _salirModoComparacion,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          ),
                        ],
                      ),
                    ),
                    
                    // Selectores de producto y fecha
                    Row(
                      children: [
                        // Lado izquierdo
                        Expanded(
                          child: Column(
                            children: [
                              Text('Izquierda', style: TextStyle(fontSize: 9, color: Colors.grey[600])),
                              const SizedBox(height: 2),
                              SizedBox(
                                height: 28,
                                child: DropdownButtonFormField<String>(
                                  value: productosDisponibles.contains(selectedProducto) ? selectedProducto : null,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 10),
                                  items: productosDisponibles.map((String value) {
                                    return DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(value, style: const TextStyle(fontSize: 10)),
                                    );
                                  }).toList(),
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      selectedProducto = newValue ?? '';
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(height: 2),
                              InkWell(
                                onTap: () async {
                                  if (fechasDisponibles.isEmpty) return;
                                  final DateTime? picked = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.parse(selectedFecha.isNotEmpty ? selectedFecha : fechasDisponibles.last),
                                    firstDate: DateTime.parse(fechasDisponibles.first),
                                    lastDate: DateTime.parse(fechasDisponibles.last),
                                    selectableDayPredicate: (DateTime day) {
                                      final String dayString = "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";
                                      return fechasDisponibles.contains(dayString);
                                    },
                                  );
                                  if (picked != null) {
                                    String nuevaFecha = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                                    if (fechasDisponibles.contains(nuevaFecha)) {
                                      setState(() {
                                        selectedFecha = nuevaFecha;
                                      });
                                    }
                                  }
                                },
                                child: Container(
                                  height: 20,
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey[300]!, width: 1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.calendar_today, size: 8, color: Colors.grey[600]),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          selectedFecha.isNotEmpty ? selectedFecha : 'Fecha',
                                          style: TextStyle(fontSize: 8, color: Colors.grey[700]),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(width: 8),
                        
                        // Lado derecho
                        Expanded(
                          child: Column(
                            children: [
                              Text('Derecha', style: TextStyle(fontSize: 9, color: Colors.grey[600])),
                              const SizedBox(height: 2),
                              SizedBox(
                                height: 28,
                                child: DropdownButtonFormField<String>(
                                  value: productosDisponibles.contains(selectedProductoComparacion) ? selectedProductoComparacion : null,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 10),
                                  items: productosDisponibles.map((String value) {
                                    return DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(value, style: const TextStyle(fontSize: 10)),
                                    );
                                  }).toList(),
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      selectedProductoComparacion = newValue ?? '';
                                      // Actualizar el estilo de comparación basado en el producto seleccionado
                                      if (selectedProductoComparacion.isNotEmpty) {
                                        selectedEstiloComparacion = selectedProductoComparacion;
                                      }
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(height: 2),
                              InkWell(
                                onTap: () async {
                                  if (fechasDisponibles.isEmpty) return;
                                  final DateTime? picked = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.parse(selectedFechaComparacion.isNotEmpty ? selectedFechaComparacion : fechasDisponibles.last),
                                    firstDate: DateTime.parse(fechasDisponibles.first),
                                    lastDate: DateTime.parse(fechasDisponibles.last),
                                    selectableDayPredicate: (DateTime day) {
                                      final String dayString = "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";
                                      return fechasDisponibles.contains(dayString);
                                    },
                                  );
                                  if (picked != null) {
                                    String nuevaFecha = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                                    if (fechasDisponibles.contains(nuevaFecha)) {
                                      setState(() {
                                        selectedFechaComparacion = nuevaFecha;
                                      });
                                    }
                                  }
                                },
                                child: Container(
                                  height: 20,
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey[300]!, width: 1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.calendar_today, size: 8, color: Colors.grey[600]),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          selectedFechaComparacion.isNotEmpty ? selectedFechaComparacion : 'Fecha',
                                          style: TextStyle(fontSize: 8, color: Colors.grey[700]),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          ],

          // Sistema de botones flotantes expandible con scroll elegante
          Positioned(
            bottom: 100,
            right: 16,
            top: 200, // Limitar la altura máxima disponible
            child: _buildExpandableFloatingButtons(),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    List<String> items,
    String? selected,
    void Function(String?)? onChanged,
  ) {
    // Filtrar "Todos" del dropdown de Ingenio
    List<String> filteredItems = items;
    if (label == 'Ingenio') {
      filteredItems = items.where((item) => item != 'Todos').toList();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0), // menos padding
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 8),
          border: InputBorder.none,
          isCollapsed: true, // compacta verticalmente
          contentPadding: const EdgeInsets.fromLTRB(0, 5, 0, 5),
        ),
        isDense: true, // aún más compacto
        value: selected,
        items: filteredItems.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildBarLegend() {
    // Usar la función unificada para todos los productos
    final estilo = estilosPorProducto[selectedProducto] ?? selectedProducto;
    return Positioned(
      top: 60,
      left: 16,
      right: 70,
      child: buildCustomColorLegend(estilo),
    );
  }

  Widget _buildBarLegendComparacion() {
    // Usar el producto de comparación correcto
    final String productoLeyenda = selectedProductoComparacion.isNotEmpty ? selectedProductoComparacion : selectedProducto;
    final estilo = estilosPorProducto[productoLeyenda] ?? productoLeyenda;

    // Calcular la posición para que esté en el lado derecho de forma segura
    final screenWidth = MediaQuery.of(context).size.width;
    final splitPosition = valorSwipe.clamp(0.0, 1.0);
    final rightSideStart = screenWidth * splitPosition;
    final legendWidth = 200.0;
    
    // Asegurar que siempre haya espacio mínimo para la leyenda
    final minSpaceNeeded = legendWidth + 20;
    final availableRightWidth = screenWidth - rightSideStart;
    
    double finalLeft;
    if (availableRightWidth >= minSpaceNeeded) {
      // Hay suficiente espacio, centrar en el lado derecho
      finalLeft = rightSideStart + (availableRightWidth - legendWidth) / 2;
    } else {
      // Poco espacio, posicionar cerca del borde derecho
      finalLeft = screenWidth - legendWidth - 10;
    }
    
    // Asegurar que esté dentro de límites válidos
    final minLeft = rightSideStart + 10;
    final maxLeft = screenWidth - legendWidth - 10;
    
    if (minLeft <= maxLeft) {
      finalLeft = finalLeft.clamp(minLeft, maxLeft);
    } else {
      finalLeft = maxLeft > 0 ? maxLeft : 10;
    }

    return Positioned(
      top: 60,
      left: finalLeft,
      child: buildCustomColorLegend(estilo),
    );
  }

  void activarModoInspeccion() {
    setState(() {
      modoInspeccion = true;
      puntoInspeccion = _mapController.camera.center;
    });
  }

  void activarModoVerInspecciones() {
    setState(() {
      modoVerInspecciones = true;
    });
    _cargarInspeccionesEnMapa();
  }

  void desactivarModoVerInspecciones() {
    setState(() {
      modoVerInspecciones = false;
      _marcadoresInspecciones.clear(); // limpia los puntos
    });
  }

  // Sistema de botones flotantes expandible con animaciones elegantes
  Widget _buildExpandableFloatingButtons() {
    return SingleChildScrollView(
      reverse: true, // Los elementos más importantes (botones principales) estarán al final
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Botones secundarios con animación
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            height: menuExpandido ? null : 0,
            child: menuExpandido
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Zoom Out
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 400),
                        opacity: menuExpandido ? 1.0 : 0.0,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 350),
                          offset: menuExpandido ? Offset.zero : const Offset(1, 0),
                          child: _buildElegantButton(
                            icon: Icons.zoom_out,
                            tooltip: 'Alejar',
                            onPressed: () => _mapController.move(
                              _mapController.camera.center,
                              _mapController.camera.zoom - 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Zoom In
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 450),
                        opacity: menuExpandido ? 1.0 : 0.0,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 400),
                          offset: menuExpandido ? Offset.zero : const Offset(1, 0),
                          child: _buildElegantButton(
                            icon: Icons.zoom_in,
                            tooltip: 'Acercar',
                            onPressed: () => _mapController.move(
                              _mapController.camera.center,
                              _mapController.camera.zoom + 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Leyenda
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 500),
                        opacity: menuExpandido ? 1.0 : 0.0,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 450),
                          offset: menuExpandido ? Offset.zero : const Offset(1, 0),
                          child: _buildElegantButton(
                            icon: Icons.filter_alt,
                            tooltip: 'Leyenda',
                            onPressed: () {},
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Capas
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 550),
                        opacity: menuExpandido ? 1.0 : 0.0,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 500),
                          offset: menuExpandido ? Offset.zero : const Offset(1, 0),
                          child: _buildElegantButton(
                            icon: Icons.compare,
                            tooltip: 'Comparar',
                            onPressed: _activarModoComparacion,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Parcelas
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 575),
                        opacity: menuExpandido ? 1.0 : 0.0,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 525),
                          offset: menuExpandido ? Offset.zero : const Offset(1, 0),
                          child: _buildElegantButton(
                            icon: _mostrarParcelas ? Icons.crop_free : Icons.crop_original,
                            tooltip: _mostrarParcelas ? 'Ocultar parcelas' : 'Mostrar parcelas',
                            onPressed: () {
                              _toggleParcelas();
                              _toggleMenu(); // Cerrar menú después de activar
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Nueva Inspección
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 600),
                        opacity: menuExpandido ? 1.0 : 0.0,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 550),
                          offset: menuExpandido ? Offset.zero : const Offset(1, 0),
                          child: _buildElegantButton(
                            icon: modoInspeccion ? Icons.close : Icons.add_location,
                            tooltip: modoInspeccion ? 'Cancelar inspección' : 'Nueva inspección',
                            onPressed: () {
                              if (modoInspeccion) {
                                setState(() {
                                  modoInspeccion = false;
                                  puntoInspeccion = null;
                                });
                              } else {
                                activarModoInspeccion();
                              }
                              _toggleMenu(); // Cerrar menú después de activar
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Ver Inspecciones
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 650),
                        opacity: menuExpandido ? 1.0 : 0.0,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 600),
                          offset: menuExpandido ? Offset.zero : const Offset(1, 0),
                          child: _buildElegantButton(
                            icon: modoVerInspecciones ? Icons.visibility_off : Icons.visibility,
                            tooltip: modoVerInspecciones ? 'Ocultar inspecciones' : 'Ver inspecciones',
                            onPressed: () {
                              if (modoVerInspecciones) {
                                desactivarModoVerInspecciones();
                              } else {
                                activarModoVerInspecciones();
                              }
                              _toggleMenu(); // Cerrar menú después de activar
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  )
                : null,
          ),
          
          // Botones principales siempre visibles
          _buildElegantButton(
            icon: Icons.location_searching,
            tooltip: 'Mi Ubicación',
            onPressed: _irALaUbicacionActual,
            isPrimary: true,
          ),
          const SizedBox(height: 12),
          
          _buildElegantButton(
            icon: Icons.home_rounded,
            tooltip: 'Inicio',
            onPressed: _regresarAVistaInicial,
            isPrimary: true,
          ),
          const SizedBox(height: 12),
          
          // Botón de menú con rotación elegante
          AnimatedRotation(
            duration: const Duration(milliseconds: 300),
            turns: menuExpandido ? 0.125 : 0, // 45 grados cuando está expandido
            child: _buildElegantButton(
              icon: menuExpandido ? Icons.close : Icons.menu,
              tooltip: menuExpandido ? 'Cerrar menú' : 'Más opciones',
              onPressed: _toggleMenu,
              isPrimary: true,
              isMenuButton: true,
            ),
          ),
        ],
      ),
    );
  }

  // Botón flotante elegante con diseño profesional
  Widget _buildElegantButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    bool isPrimary = false,
    bool isMenuButton = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: isPrimary 
            ? (isMenuButton 
                ? (menuExpandido ? Colors.red[600] : const Color(0xFF52AA5E))
                : const Color(0xFF52AA5E))
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Container(
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(12),
            child: Icon(
              icon,
              color: isPrimary ? Colors.white : const Color(0xFF52AA5E),
              size: 24,
            ),
          ),
        ),
      ),
    );
  }



}

// Clipper para el lado izquierdo en modo comparación
class LeftSideClipper extends CustomClipper<ui.Path> {
  final double splitPosition;

  LeftSideClipper(this.splitPosition);

  @override
  ui.Path getClip(Size size) {
    final path = ui.Path();
    final splitX = size.width * splitPosition;
    
    path.addRect(Rect.fromLTRB(0, 0, splitX, size.height));
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<ui.Path> oldClipper) => true;
}

// Clipper para el lado derecho en modo comparación
class RightSideClipper extends CustomClipper<ui.Path> {
  final double splitPosition;

  RightSideClipper(this.splitPosition);

  @override
  ui.Path getClip(Size size) {
    final path = ui.Path();
    final splitX = size.width * splitPosition;
    
    path.addRect(Rect.fromLTRB(splitX, 0, size.width, size.height));
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<ui.Path> oldClipper) => true;
}

// CustomPainter para la línea divisoria
class DividerLinePainter extends CustomPainter {
  final double splitPosition;

  DividerLinePainter(this.splitPosition);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;

    final x = size.width * splitPosition;

    // Sombra
    canvas.drawLine(
      Offset(x + 1, 0),
      Offset(x + 1, size.height),
      shadowPaint,
    );

    // Línea principal
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

extension on List<Marker> {
  get children => null;
}
