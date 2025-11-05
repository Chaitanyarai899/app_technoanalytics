import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'explorar_view.dart';
import 'dashboard.dart'; 

class MainNavigationView extends StatefulWidget {
  final String nombre;

  const MainNavigationView({
    super.key,
    required this.nombre,
  });

  @override
  State<MainNavigationView> createState() => _MainNavigationViewState();
}

class _MainNavigationViewState extends State<MainNavigationView> {
  int _selectedIndex = 0;

  void _cerrarSesion() async {
    try {
      // Limpiar SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      print('Error al cerrar sesión: $e');
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    }
  }

  void _onMenuSeleccionado(String opcion) {
    if (opcion == 'Cerrar sesión') {
      _cerrarSesion();
    } else if (opcion == 'Configuración') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Abrir configuración...')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromRGBO(82, 170, 94, 1.0),
        title: const Text(
          'Techno Analytics',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(
                'Hola, ${widget.nombre}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.person, color: Colors.white),
            onSelected: _onMenuSeleccionado,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'Configuración', child: Text('Configuración')),
              PopupMenuItem(value: 'Cerrar sesión', child: Text('Cerrar sesión')),
            ],
          ),
        ],
      ),
      body: _selectedIndex == 0
          ? ExplorarView(
              key: explorarViewKey,
              nombre: widget.nombre,
            )
          : const DashboardView(), // Aquí integramos el nuevo dashboard
      floatingActionButtonLocation: const CustomFABLocation(),
      floatingActionButton: SizedBox(
        height: 70,
        width: 70,
        child: FloatingActionButton(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (context) => _buildInspeccionesModal(context),
            );
          },
          backgroundColor: const Color.fromRGBO(82, 170, 94, 1.0),
          elevation: 8,
          shape: const CircleBorder(),
          child: const Icon(Icons.add_location_alt_outlined, size: 36, color: Colors.white),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6.0,
        elevation: 10,
        child: SafeArea(
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildBottomNavItem(icon: Icons.map, label: 'Explorar', index: 0),
                const SizedBox(width: 56),
                _buildBottomNavItem(icon: Icons.dashboard_customize_outlined, label: 'Dashboard', index: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = _selectedIndex == index;
    final color = isSelected ? const Color.fromRGBO(82, 170, 94, 1.0) : Colors.grey;

    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildInspeccionesModal(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.map),
            title: const Text('Ver inspecciones'),
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _selectedIndex = 0;
              });
              Future.delayed(const Duration(milliseconds: 300), () {
                explorarViewKey.currentState?.activarModoVerInspecciones();
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_location_alt),
            title: const Text('Crear nueva inspección'),
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _selectedIndex = 0;
              });
              Future.delayed(const Duration(milliseconds: 300), () {
                explorarViewKey.currentState?.activarModoInspeccion();
              });
            },
          ),
        ],
      ),
    );
  }
}

class CustomFABLocation extends FloatingActionButtonLocation {
  const CustomFABLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final double fabX = (scaffoldGeometry.scaffoldSize.width - scaffoldGeometry.floatingActionButtonSize.width) / 2;
    final double fabY = scaffoldGeometry.scaffoldSize.height
        - 56 // altura real del BottomAppBar
        - (scaffoldGeometry.floatingActionButtonSize.height * 0.5); // 80% incrustado

    return Offset(fabX, fabY);
  }
}
