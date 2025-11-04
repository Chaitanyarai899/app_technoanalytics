// lib/widgets/floating_button.dart
import 'package:flutter/material.dart';

class FloatingButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const FloatingButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: tooltip,
      backgroundColor: Colors.green[700],
      onPressed: onPressed,
      tooltip: tooltip,
      child: Icon(icon, color: Colors.white),
    );
  }
}
