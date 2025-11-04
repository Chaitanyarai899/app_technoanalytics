# 🧪 Testing - Archivos de Prueba

Esta carpeta contiene todos los archivos de prueba organizados por tipo.

## 📁 Estructura

### `dart/`
Archivos de prueba en Dart/Flutter:
- `test_connection.dart` - Pruebas de conectividad básica
- `test_supabase.dart` - Pruebas de conexión a Supabase

### `python/`
Scripts de prueba en Python:
- `test_ingestion_simple.py` - Pruebas del pipeline de ingesta
- `test_integration.py` - Pruebas de integración completas

### `scripts/`
Scripts de prueba en PowerShell y Bash:
- `test_integration_full.ps1` - Suite completa de pruebas
- `test_simple.ps1` - Pruebas básicas
- `test_supabase.ps1` - Pruebas de Supabase
- `test_titiler.ps1` - Pruebas del servicio TiTiler
- `test_titiler.sh` - Pruebas TiTiler (Bash)

## 🚀 Cómo Usar

### Pruebas Dart
```bash
dart testing/dart/test_connection.dart
dart testing/dart/test_supabase.dart
```

### Pruebas Python
```bash
python testing/python/test_ingestion_simple.py
python testing/python/test_integration.py
```

### Scripts de Prueba
```bash
# PowerShell
.\testing\scripts\test_simple.ps1
.\testing\scripts\test_integration_full.ps1

# Bash (Linux/macOS)  
bash testing/scripts/test_titiler.sh
```