import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({Key? key}) : super(key: key);

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  final SupabaseService supabaseService = SupabaseService();
  List<String> empresasDisponibles = [];
  List<String> ingeniosDisponibles = [];
  List<dynamic> parcelas = [];
  bool isLoading = false;
  String selectedEmpresa = '';
  String selectedIngenio = '';
  String selectedCountry = '';

  final List<String> secciones = [
    'Overview',
    'Cosecha',
    'Smart Index',
    'NDVI+',
    'HIDRO+',
    'Malezas',
    'TCH',
    'Pol Caña',
  ];

  int selectedSeccion = 0;

  @override
  void initState() {
    super.initState();
    cargarFiltrosEmpresaIngenio();
  }

  Future<void> cargarFiltrosEmpresaIngenio() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    if (!isLoggedIn) return;
    
    final userCompany = prefs.getString('user_company') ?? '';
    final userIngenio = prefs.getString('user_ingenio') ?? '';
    
    if (userCompany == 'Todos') {
      empresasDisponibles = await supabaseService.getCompanies();
      empresasDisponibles.removeWhere((e) => e.trim().toLowerCase() == 'todos');
    } else {
      empresasDisponibles = [userCompany];
    }
    selectedEmpresa = empresasDisponibles.isNotEmpty ? empresasDisponibles.first : '';

    if (userIngenio == 'Todos') {
      ingeniosDisponibles = await supabaseService.getIngeniosByCompany(selectedEmpresa);
      // Filtrar "Todos" de la lista de ingenios disponibles
      ingeniosDisponibles.removeWhere((ingenio) => ingenio == 'Todos');
    } else {
      ingeniosDisponibles = [userIngenio];
    }
    
    // Seleccionar el primer ingenio disponible
    if (ingeniosDisponibles.isNotEmpty) {
      selectedIngenio = ingeniosDisponibles.first;
    }
    selectedCountry = (prefs.getString('user_country') ?? '').toLowerCase();
    
    if (mounted) {
      setState(() {});
      cargarDatosParcelas();
    }
  }

  Future<void> cargarDatosParcelas() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final response = await Supabase.instance.client
          .from('parcelas_ingenios')
          .select()
          .eq('ingenio', selectedIngenio); // Sin filtro de company (por RLS)

      print('Dashboard: Consultadas ${response.length} parcelas para $selectedIngenio');
      
      // Filtrar temporada_activa en el cliente
      final parcelasActivas = response.where((p) => p['temporada_activa'] == true).toList();
      
      print('Dashboard: ${parcelasActivas.length} parcelas activas de ${response.length} totales');

      if (mounted) {
        setState(() {
          parcelas = parcelasActivas;
          isLoading = false;
        });
      }
    } catch (e) {
      print('ERROR Dashboard: $e');
      if (mounted) {
        setState(() {
          parcelas = [];
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildFiltros(),
          _buildCarrusel(),
          Expanded(child: _buildSeccionActual()),
        ],
      ),
    );
  }

  Widget _buildFiltros() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: selectedEmpresa,
              decoration: const InputDecoration(labelText: 'Empresa'),
              items: empresasDisponibles.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (value) async {
                if (!mounted) return;
                setState(() {
                  selectedEmpresa = value!;
                });
                
                // Actualizar ingenios disponibles para la nueva empresa
                final email = Supabase.instance.client.auth.currentUser?.email;
                if (email != null) {
                  final userInfo = await supabaseService.getUserInfo(email);
                  if (userInfo != null && mounted) {
                    final userIngenio = userInfo['ingenio'];
                    if (userIngenio == 'Todos') {
                      ingeniosDisponibles = await supabaseService.getIngeniosByCompany(selectedEmpresa);
                      // Filtrar "Todos" de la lista de ingenios disponibles
                      ingeniosDisponibles.removeWhere((ingenio) => ingenio == 'Todos');
                    } else {
                      ingeniosDisponibles = [userIngenio];
                    }
                    
                    // Seleccionar el primer ingenio disponible
                    if (ingeniosDisponibles.isNotEmpty) {
                      selectedIngenio = ingeniosDisponibles.first;
                    }
                    if (mounted) setState(() {});
                  }
                }
                
                cargarDatosParcelas();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: selectedIngenio,
              decoration: const InputDecoration(labelText: 'Ingenio'),
              items: ingeniosDisponibles.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (value) {
                if (!mounted) return;
                setState(() {
                  selectedIngenio = value!;
                });
                cargarDatosParcelas();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarrusel() {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: secciones.length,
        itemBuilder: (context, index) {
          final isSelected = index == selectedSeccion;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ChoiceChip(
              label: Text(secciones[index]),
              selected: isSelected,
              onSelected: (_) {
                if (mounted) setState(() => selectedSeccion = index);
              },
              selectedColor: Colors.green[300],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSeccionActual() {
    switch (secciones[selectedSeccion]) {
      case 'Overview':
        return _buildOverview();
      case 'Cosecha':
        return _buildCosecha();
      default:
        return const Center(child: Text('Sección en construcción...'));
    }
  }

  Widget _buildOverview() {
    return isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIndicadoresResumen(),
                const SizedBox(height: 20),
                CustomHorizontalStackedBar(data: agruparAreaTop7('variedad'), titulo: 'Distribución por Variedad'),
                CustomHorizontalStackedBar(data: agruparAreaTop7('division_01'), titulo: 'Distribución por División'),
                CustomHorizontalStackedBar(data: agruparAreaTop7('ciclo'), titulo: 'Distribución por Ciclo'),
              ],
            ),
          );
  }

  Widget _buildIndicadoresResumen() {
    double haMonitoreo = 0;
    double haCosechadas = 0;
    double toneladasIndustrializadas = 0;
    double toneladasPotencial = 0;

    for (var parcela in parcelas) {
      // Usar area_calculada para Ha Monitoreo
      final area = (parcela['area_calculada'] ?? 0).toDouble();
      haMonitoreo += area;

      // Ha cosechadas: usar area_cosechada o verificar si tiene fecha_fin
      final areaCosechada = (parcela['area_cosechada'] ?? 0).toDouble();
      final fechaFin = parcela['fecha_fin'];
      
      if (areaCosechada > 0 || fechaFin != null) {
        haCosechadas += areaCosechada > 0 ? areaCosechada : area;
        
        // Usar ton_real si está disponible, sino ton_cosechadas
        final tonReal = (parcela['ton_real'] ?? 0).toDouble();
        final tonCosechadas = (parcela['ton_cosechadas'] ?? 0).toDouble();
        toneladasIndustrializadas += tonReal > 0 ? tonReal : tonCosechadas;
        
        // Usar ton_potencial para el potencial
        toneladasPotencial += (parcela['ton_potencial'] ?? 0).toDouble();
      }
    }

    double tchActual = haCosechadas > 0 ? toneladasIndustrializadas / haCosechadas : 0;
    double porcentajeCumplimiento = toneladasPotencial > 0 ? (toneladasIndustrializadas / toneladasPotencial) : 0;
    final Color colorTch = porcentajeCumplimiento >= 0.95 ? Colors.green : Colors.red;

    final formatter = NumberFormat('#,##0', 'en_US');
    final formatterDecimal = NumberFormat('#,##0.00', 'en_US');

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildCardIndicador('Ha Monitoreo', formatter.format(haMonitoreo), Colors.green[300]!, titleFontSize: 12, valueFontSize: 22),
        _buildCardIndicador('Ha Cosechadas', formatter.format(haCosechadas), Colors.green[300]!, titleFontSize: 10, valueFontSize: 22),
        _buildCardIndicador('TCH Actual', formatterDecimal.format(tchActual), colorTch,
            subtitulo: '(${(porcentajeCumplimiento * 100).toStringAsFixed(1)}% del potencial)', titleFontSize: 12, valueFontSize: 22, refFontSize: 8),
      ],
    );
  }

  Widget _buildCardIndicador(String titulo, String valor, Color color, {String? subtitulo, double titleFontSize = 13, double valueFontSize = 20, double refFontSize = 10}) {
    return SizedBox(
      height: 140,
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: const Color(0xFFF9F9F9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(titulo, 
                   style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w600), 
                   textAlign: TextAlign.center,
                   maxLines: 2,
                   overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(valor, 
                   style: TextStyle(fontSize: valueFontSize, fontWeight: FontWeight.bold, color: color),
                   textAlign: TextAlign.center,
                   maxLines: 1,
                   overflow: TextOverflow.ellipsis,
              ),
              if (subtitulo != null) ...[
                const SizedBox(height: 4),
                Text(subtitulo, 
                     style: TextStyle(fontSize: refFontSize, color: Colors.grey), 
                     textAlign: TextAlign.center,
                     maxLines: 2,
                     overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Map<String, double> agruparAreaTop7(String campo) {
    final Map<String, double> agrupado = {};

    for (var parcela in parcelas) {
      final key = parcela[campo]?.toString() ?? 'Sin dato';
      final area = (parcela['area_calculada'] ?? 0).toDouble();
      agrupado.update(key, (value) => value + area, ifAbsent: () => area);
    }

    final entries = agrupado.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top7 = entries.take(7);
    final otros = entries.skip(7).map((e) => e.value).fold(0.0, (a, b) => a + b);

    final Map<String, double> resultado = {
      for (var e in top7) e.key: e.value,
    };
    if (otros > 0) resultado['Otros'] = otros;

    return resultado;
  }

  Widget _buildCosecha() {
    double haMonitoreo = 0;
    double haCosechadas = 0;
    double toneladasIndustrializadas = 0;
    double toneladasPotencial = 0;
    Map<int, double> haPorSemana = {};
    Map<int, double> tchPorSemana = {};
    Map<String, double> tipoCosecha = {};
    Map<String, List<double>> rendimientoPorZona = {};
    Map<String, double> variedadesCosechadas = {};

    for (var parcela in parcelas) {
      final area = (parcela['area_calculada'] ?? 0).toDouble();
      haMonitoreo += area;

      // Verificar si la parcela está cosechada usando fecha_fin o area_cosechada
      final fechaFin = parcela['fecha_fin'];
      final areaCosechada = (parcela['area_cosechada'] ?? 0).toDouble();
      
      if (fechaFin != null || areaCosechada > 0) {
        final areaUsada = areaCosechada > 0 ? areaCosechada : area;
        haCosechadas += areaUsada;
        
        // Usar ton_real si está disponible, sino ton_cosechadas
        final tonReal = (parcela['ton_real'] ?? 0).toDouble();
        final tonCosechadas = (parcela['ton_cosechadas'] ?? 0).toDouble();
        final toneladas = tonReal > 0 ? tonReal : tonCosechadas;
        toneladasIndustrializadas += toneladas;
        
        // Acumular toneladas potencial
        toneladasPotencial += (parcela['ton_potencial'] ?? 0).toDouble();

        if (fechaFin != null) {
          try {
            final fechaFinDate = DateTime.parse(fechaFin);
            final semana = ((fechaFinDate.difference(DateTime(fechaFinDate.year, 1, 1)).inDays) / 7).ceil();
            haPorSemana.update(semana, (value) => value + areaUsada, ifAbsent: () => areaUsada);
            
            // TCH por semana
            final tch = areaUsada > 0 ? toneladas / areaUsada : 0;
            if (tchPorSemana.containsKey(semana)) {
              // Promedio ponderado
              final haExistente = haPorSemana[semana]! - areaUsada;
              final tchExistente = tchPorSemana[semana]!;
              tchPorSemana[semana] = ((tchExistente * haExistente) + (tch * areaUsada)) / haPorSemana[semana]!;
            } else {
              tchPorSemana[semana] = tch;
            }
          } catch (e) {
            // Si hay error parseando la fecha, ignorar para el gráfico por semana
          }
        }

        // Usar tipo_cosecha_real si está disponible, sino tipo_cosecha_estimado
        final tipoReal = parcela['tipo_cosecha_real']?.toString();
        final tipoEstimado = parcela['tipo_cosecha_estimado']?.toString();
        final tipo = tipoReal ?? tipoEstimado ?? 'Otro';
        tipoCosecha.update(tipo, (value) => value + areaUsada, ifAbsent: () => areaUsada);

        // Usar division_01 como zona para el rendimiento
        final zona = (parcela['division_01'] ?? 'Sin división').toString();
        if (!rendimientoPorZona.containsKey(zona)) {
          rendimientoPorZona[zona] = [0, 0];
        }
        rendimientoPorZona[zona]![0] += toneladas;
        rendimientoPorZona[zona]![1] += areaUsada;
        
        // Variedades cosechadas
        final variedad = (parcela['variedad'] ?? 'Sin variedad').toString();
        variedadesCosechadas.update(variedad, (value) => value + areaUsada, ifAbsent: () => areaUsada);
      }
    }

    double avance = haMonitoreo > 0 ? haCosechadas / haMonitoreo : 0;
    double rendimientoPromedio = haCosechadas > 0 ? toneladasIndustrializadas / haCosechadas : 0;
    double eficienciaToneladas = toneladasPotencial > 0 ? (toneladasIndustrializadas / toneladasPotencial) : 0;

    final zonasOrdenadas = rendimientoPorZona.entries
        .map((e) => MapEntry<String, double>(e.key, e.value[1] > 0 ? e.value[0] / e.value[1] : 0))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topZonas = zonasOrdenadas.take(5).toList();
    
    final variedadesOrdenadas = variedadesCosechadas.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topVariedades = variedadesOrdenadas.take(3).toList();

    final formatter = NumberFormat('#,##0', 'en_US');
    final formatterDecimal = NumberFormat('#,##0.00', 'en_US');

    return isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Indicadores principales
                _buildIndicadoresPrincipalesCosecha(
                  avance, haCosechadas, toneladasIndustrializadas, 
                  rendimientoPromedio, eficienciaToneladas, formatter, formatterDecimal
                ),
                const SizedBox(height: 20),
                
                // Tipo de cosecha
                _buildTipoCosechaLineal(tipoCosecha),
                const SizedBox(height: 20),
                
                // Gráficos de rendimiento - en filas separadas para mejor visualización
                _buildBarrasPorSemana(haPorSemana, "Ha Cosechadas por Semana"),
                const SizedBox(height: 16),
                
                _buildTCHPorSemana(tchPorSemana),
                const SizedBox(height: 20),
                
                // Rankings lado a lado
                Row(
                  children: [
                    Expanded(child: _buildTopZonas(topZonas)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildTopVariedades(topVariedades)),
                  ],
                ),
              ],
            ),
          );
  }

  // Nuevos widgets para la sección de cosecha mejorada
  Widget _buildIndicadoresPrincipalesCosecha(
    double avance, double haCosechadas, double toneladasIndustrializadas,
    double rendimientoPromedio, double eficienciaToneladas,
    NumberFormat formatter, NumberFormat formatterDecimal
  ) {
    return Column(
      children: [
        // Primera fila: Avance grande + 2 indicadores
        Row(
          children: [
            Expanded(flex: 2, child: _buildGaugeAvanceMejorado(avance)),
            const SizedBox(width: 12),
            Expanded(child: _buildCardIndicador('Ha Cosechadas', formatter.format(haCosechadas), Colors.green[400]!, titleFontSize: 12, valueFontSize: 18)),
            const SizedBox(width: 12),
            Expanded(child: _buildCardIndicador('Toneladas', formatter.format(toneladasIndustrializadas), Colors.blue[400]!, titleFontSize: 12, valueFontSize: 18)),
          ],
        ),
        const SizedBox(height: 12),
        // Segunda fila: 2 indicadores centrados
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SizedBox(
              width: 170,
              child: _buildCardIndicador('TCH Promedio', formatterDecimal.format(rendimientoPromedio), Colors.orange[400]!, titleFontSize: 12, valueFontSize: 18)
            ),
            SizedBox(
              width: 170,
              child: _buildCardIndicador('Eficiencia', '${(eficienciaToneladas * 100).toStringAsFixed(1)}%', eficienciaToneladas >= 0.9 ? Colors.green[400]! : Colors.red[400]!, titleFontSize: 12, valueFontSize: 18)
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGaugeAvanceMejorado(double avance) {
    final porcentaje = (avance * 100).clamp(0, 100);
    final Color colorGauge = porcentaje >= 90 ? Colors.green : porcentaje >= 70 ? Colors.orange : Colors.red;

    return SizedBox(
      height: 140,
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: const Color(0xFFF9F9F9),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Avance de Cosecha', 
                       style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: SfRadialGauge(
                  axes: <RadialAxis>[
                    RadialAxis(
                      minimum: 0,
                      maximum: 100,
                      startAngle: 180,
                      endAngle: 0,
                      showLabels: false,
                      showTicks: false,
                      radiusFactor: 0.85,
                      axisLineStyle: AxisLineStyle(
                        thickness: 0.2,
                        thicknessUnit: GaugeSizeUnit.factor,
                        color: const Color.fromARGB(30, 0, 169, 181),
                        cornerStyle: CornerStyle.startCurve,
                      ),
                      pointers: <GaugePointer>[
                        RangePointer(
                          value: porcentaje.toDouble(),
                          width: 0.2,
                          sizeUnit: GaugeSizeUnit.factor,
                          color: colorGauge,
                          cornerStyle: CornerStyle.bothCurve,
                        ),
                      ],
                      annotations: <GaugeAnnotation>[
                        GaugeAnnotation(
                          angle: 90,
                          positionFactor: 0.1,
                          widget: Text(
                            '${porcentaje.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 28, 
                              fontWeight: FontWeight.bold, 
                              color: colorGauge
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTipoCosechaLineal(Map<String, double> tipoCosecha) {
    if (tipoCosecha.isEmpty) return const SizedBox.shrink();
    
    final total = tipoCosecha.values.fold(0.0, (a, b) => a + b);
    final List<Color> colores = [Colors.green[400]!, Colors.blue[400]!, Colors.orange[400]!, Colors.purple[400]!];
    
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tipo de Cosecha', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            // Barra horizontal
            Container(
              height: 40,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: tipoCosecha.entries.map((entry) {
                  final porcentaje = (entry.value / total);
                  final color = colores[tipoCosecha.keys.toList().indexOf(entry.key) % colores.length];
                  return Expanded(
                    flex: (porcentaje * 100).round().clamp(1, 100),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: porcentaje > 0.2 ? Text(
                          '${(porcentaje * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ) : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            // Leyenda horizontal
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: tipoCosecha.entries.map((entry) {
                final porcentaje = (entry.value / total) * 100;
                final color = colores[tipoCosecha.keys.toList().indexOf(entry.key) % colores.length];
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text('${entry.key} (${porcentaje.toStringAsFixed(0)}%)', 
                         style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTCHPorSemana(Map<int, double> tchPorSemana) {
    if (tchPorSemana.isEmpty) return const SizedBox.shrink();
    
    final semanasOrdenadas = tchPorSemana.keys.toList()..sort();
    final maxTCH = tchPorSemana.values.fold(0.0, (prev, curr) => curr > prev ? curr : prev);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TCH por Semana', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  barGroups: semanasOrdenadas.map((semana) {
                    final tch = tchPorSemana[semana]!;
                    return BarChartGroupData(
                      x: semana,
                      barRods: [
                        BarChartRodData(
                          toY: tch,
                          color: tch >= 80 ? Colors.green : tch >= 60 ? Colors.orange : Colors.red,
                          width: 12,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, _) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) => Text('S${value.toInt()}', style: const TextStyle(fontSize: 10)),
                        reservedSize: 25,
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  maxY: maxTCH + (maxTCH * 0.2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopVariedades(List<MapEntry<String, double>> topVariedades) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top Variedades Cosechadas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...topVariedades.map((variedad) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(variedad.key, style: const TextStyle(fontSize: 14))),
                  Text('${variedad.value.toStringAsFixed(0)} ha', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildBarrasPorSemana(Map<int, double> haPorSemana, [String? titulo]) {
    if (haPorSemana.isEmpty) return const SizedBox.shrink();
    
    final semanasOrdenadas = haPorSemana.keys.toList()..sort();
    final maxHa = haPorSemana.values.fold(0.0, (prev, curr) => curr > prev ? curr : prev);
    final tituloFinal = titulo ?? 'Ha Cosechadas por Semana';

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tituloFinal, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  barGroups: semanasOrdenadas.map((semana) {
                    return BarChartGroupData(
                      x: semana,
                      barRods: [
                        BarChartRodData(
                          toY: haPorSemana[semana]!,
                          color: Colors.green,
                          width: 12,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true, 
                        reservedSize: 40,
                        getTitlesWidget: (value, _) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) => Text('S${value.toInt()}', style: const TextStyle(fontSize: 10)),
                        reservedSize: 25,
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  maxY: maxHa + (maxHa * 0.2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopZonas(List<MapEntry<String, double>> topZonas) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top Zonas por Rendimiento (TCH)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...topZonas.map((zona) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(zona.key, style: const TextStyle(fontSize: 14)),
                  Text(zona.value.toStringAsFixed(2), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class CustomHorizontalStackedBar extends StatelessWidget {
  final Map<String, double> data;
  final String titulo;

  const CustomHorizontalStackedBar({Key? key, required this.data, required this.titulo}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold(0.0, (a, b) => a + b);
    final List<Color> tonosVerdes = [
      const Color(0xFF81C784),
      const Color(0xFF66BB6A),
      const Color(0xFF4CAF50),
      const Color(0xFF43A047),
      const Color(0xFF388E3C),
      const Color(0xFF2E7D32),
      const Color(0xFF1B5E20),
    ];

    final List<BarChartRodStackItem> stackItems = [];
    final List<Widget> porcentajes = [];
    final List<Widget> nombres = [];

    double start = 0;
    int colorIndex = 0;

    for (var entry in data.entries) {
      final porcentaje = (entry.value / total) * 100;
      final end = start + porcentaje;
      final color = tonosVerdes[colorIndex % tonosVerdes.length];

      stackItems.add(BarChartRodStackItem(start, end, color));

      porcentajes.add(Expanded(
        flex: (porcentaje * 10).toInt().clamp(1, 100),
        child: Center(
          child: porcentaje >= 2 ? Text('${porcentaje.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)) : const SizedBox.shrink(),
        ),
      ));

      nombres.add(Expanded(
        flex: (porcentaje * 10).toInt().clamp(1, 100),
        child: Center(
          child: Text(
            entry.key,
            style: TextStyle(fontSize: porcentaje >= 5 ? 10 : 8, fontWeight: FontWeight.w500, color: porcentaje >= 5 ? Colors.black : Colors.grey),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ));

      start = end;
      colorIndex++;
    }

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: const Color(0xFFF9F9F9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 6,
              child: RotatedBox(
                quarterTurns: 1,
                child: BarChart(
                  BarChartData(
                    barGroups: [
                      BarChartGroupData(
                        x: 0,
                        barRods: [
                          BarChartRodData(
                            toY: 100,
                            rodStackItems: stackItems,
                            width: 22,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ],
                      ),
                    ],
                    titlesData: FlTitlesData(show: false),
                    gridData: FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(enabled: false),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(children: porcentajes),
            const SizedBox(height: 4),
            Row(children: nombres),
          ],
        ),
      ),
    );
  }
}
