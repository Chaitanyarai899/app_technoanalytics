# 📁 Estructura del Proyecto - Techno Analytics

## 🗂️ Organización de Carpetas

### 📱 **Aplicación Principal**
- `lib/` - Código fuente Flutter (vistas, servicios, widgets)
- `assets/` - Recursos (imágenes, iconos)
- `android/`, `ios/`, `web/`, `windows/`, `linux/`, `macos/` - Configuraciones por plataforma

### 🧪 **Testing y Pruebas**
- `testing/` - Todos los archivos de prueba organizados
  - `dart/` - Pruebas en Dart/Flutter
  - `python/` - Scripts de prueba Python
  - `scripts/` - Scripts PowerShell/Bash para testing
- `test/` - Pruebas unitarias Flutter (generadas automáticamente)

### 🔧 **Configuración y Despliegue**
- `config/` - Archivos de configuración (API keys, CORS, etc.)
- `deployment/` - Scripts de instalación y despliegue
- `supabase/` - Configuración y SQL de base de datos

### 🛠️ **Herramientas y Utilidades**
- `tools/` - Scripts Python para mantenimiento
- `sql/` - Scripts SQL utilitarios
- `scripts/` - Scripts de automatización general
- `infra/` - Configuración de infraestructura cloud

### 📊 **Datos y Procesamiento**
- `ingestion/` - Pipeline de ingesta de rasters
- `migration/` - Scripts de migración de datos
- `rasters_to_migrate/` - Datos temporales para migración
- `test_files/` - Archivos de prueba para testing

### 📚 **Documentación**
- `docs/` - Documentación técnica detallada
- `flutter/` - Documentación específica de Flutter
- `README.md` - Documentación principal del proyecto

### 🔨 **Build y Temporales**
- `build/` - Archivos compilados (ignorado por git)
- `temp/` - Archivos temporales de procesamiento
- `.dart_tool/` - Herramientas Dart (ignorado por git)

## 🚀 Archivos Importantes en la Raíz

- `pubspec.yaml` - Dependencias Flutter
- `analysis_options.yaml` - Configuración de análisis Dart
- `.gitignore` - Archivos ignorados por Git
- `.env` - Variables de entorno (no versionado)
- `CREDENCIALES_LOGIN.md` - Guía de acceso al sistema

## 📋 Comandos Rápidos

```bash
# Instalar dependencias
flutter pub get

# Ejecutar app
flutter run

# Ejecutar pruebas
flutter test

# Build para producción
flutter build apk --release
```

## 🎯 Estructura Limpia y Organizada

Todos los archivos están organizados por propósito y tipo, facilitando:
- ✅ Navegación rápida
- ✅ Mantenimiento eficiente  
- ✅ Colaboración en equipo
- ✅ Despliegue automatizado