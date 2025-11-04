# 🔧 Troubleshooting Guide - Modern Raster Architecture

Esta guía cubre los problemas más comunes que puedes encontrar durante la implementación y operación de la arquitectura moderna de rasters.

## 🚀 Setup y Deployment

### Error: "Project not found" durante setup
```bash
# Verificar autenticación
gcloud auth list

# Configurar proyecto por defecto
gcloud config set project YOUR_PROJECT_ID

# Verificar permisos
gcloud projects get-iam-policy YOUR_PROJECT_ID
```

### Error: "Bucket already exists"
```bash
# El nombre del bucket debe ser globalmente único
# Cambiar GCS_BUCKET en .env a un nombre único:
GCS_BUCKET=ta-cogs-your-company-prod
```

### TiTiler deployment falla
```bash
# Verificar APIs habilitadas
gcloud services list --enabled | grep -E "(run|storage|cloudbuild)"

# Habilitar APIs faltantes
gcloud services enable run.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable cloudbuild.googleapis.com

# Verificar limits de cuota
gcloud compute project-info describe --project=YOUR_PROJECT_ID
```

## 🗄️ Problemas de Base de Datos

### Error: "relation productos does not exist"
```sql
-- Verificar que la tabla existe
\dt public.productos

-- Si no existe, crear tabla base primero
CREATE TABLE IF NOT EXISTS productos (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(255) NOT NULL,
    descripcion TEXT,
    fecha_creacion TIMESTAMP DEFAULT NOW()
);

-- Luego ejecutar la migración
\i supabase/sql/001_products_alter.sql
```

### Error de conexión a Supabase
```bash
# Verificar URL y keys en .env
echo $SUPABASE_URL
echo $SUPABASE_SERVICE_ROLE_KEY

# Probar conexión
curl -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
     "$SUPABASE_URL/rest/v1/productos?select=id"
```

## 📁 Problemas de Ingesta de Datos

### Error: "Not a valid raster file"
```bash
# Verificar que GDAL puede leer el archivo
gdalinfo your_file.tif

# Verificar formato del archivo
file your_file.tif

# Si es un raster válido pero corrupto, intentar reparar
gdal_translate -of GTiff your_file.tif repaired_file.tif
```

### COG conversion fails
```bash
# Verificar espacio en disco
df -h

# Aumentar memoria para archivos grandes
export GDAL_CACHEMAX=2048

# Usar compresión más agresiva para archivos muy grandes
gdal_translate -of COG \
  -co COMPRESS=JPEG \
  -co JPEG_QUALITY=75 \
  -co BLOCKSIZE=1024 \
  input.tif output_cog.tif
```

### Upload a GCS falla
```bash
# Verificar permisos del bucket
gsutil iam get gs://YOUR_BUCKET_NAME

# Verificar autenticación
gcloud auth application-default print-access-token

# Subir archivo manualmente para probar
gsutil cp test_file.tif gs://YOUR_BUCKET_NAME/test/
```

## 🌐 Problemas de TiTiler

### TiTiler retorna 404 para COG files
```bash
# Verificar que el archivo está en GCS
gsutil ls gs://YOUR_BUCKET_NAME/cogs/

# Probar acceso directo al COG
curl -I "https://storage.googleapis.com/YOUR_BUCKET_NAME/cogs/your_file.tif"

# Verificar permisos públicos del bucket
gsutil iam ch allUsers:objectViewer gs://YOUR_BUCKET_NAME
```

### TiTiler retorna error 500
```bash
# Verificar logs de Cloud Run
gcloud run services logs read titiler-service --region=us-central1

# Verificar memory limits
gcloud run services describe titiler-service --region=us-central1

# Aumentar memoria si es necesario
gcloud run services update titiler-service \
  --memory=4Gi \
  --region=us-central1
```

### Tiles no cargan en Flutter
```dart
// Verificar URL en constants.dart
const String kTitilerBaseUrl = 'https://your-actual-domain.com';

// Probar URL directamente en browser
// https://your-domain.com/cog/tiles/WebMercatorQuad/{z}/{x}/{y}?url=gs://bucket/file.tif

// Verificar CORS en browser console
// Agregar CORS policy al bucket si es necesario
```

## 🚀 Problemas de Performance

### Tiles cargan muy lento
```bash
# Verificar cache headers
curl -I "https://your-domain.com/cog/tiles/WebMercatorQuad/10/500/400?url=gs://bucket/file.tif"

# Verificar si CDN está funcionando
curl -H "Cache-Control: no-cache" "https://your-domain.com/healthz"

# Monitorear Cloud Run
gcloud run services describe titiler-service --region=us-central1
```

### High memory usage en TiTiler
```bash
# Revisar tamaño de archivos COG
gsutil du -sh gs://YOUR_BUCKET_NAME/cogs/

# Optimizar COGs existentes
gdal_translate -of COG \
  -co COMPRESS=LZW \
  -co BLOCKSIZE=512 \
  -co OVERVIEW_RESAMPLING=AVERAGE \
  input_cog.tif optimized_cog.tif

# Configurar overviews más agresivos
gdaladdo -r average file.tif 2 4 8 16 32 64
```

## 📱 Problemas en Flutter

### Modern tiles no aparecen
```dart
// Verificar feature flag
const bool kUseModernTiles = true;

// Debug en ModernRasterService
print('Using modern tiles: $kUseModernTiles');
print('TiTiler URL: $kTitilerBaseUrl');

// Verificar fallback a WMS
if (!success) {
  print('Falling back to WMS');
}
```

### Error de certificado SSL
```bash
# Verificar estado del certificado
gcloud compute ssl-certificates describe titiler-ssl-cert

# El certificado puede tardar hasta 60 minutos en provisionar
# Mientras tanto, usar HTTP en desarrollo:
const String kTitilerBaseUrl = 'http://your-ip-address';
```

## 🔍 Debugging Tools

### Verificar estado general
```bash
# Script de health check
./scripts/health_check.sh

# Status de todos los servicios
gcloud run services list --region=us-central1

# Status del CDN
gcloud compute backend-services list
```

### Logs centralizados
```bash
# TiTiler logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=titiler-service" --limit=50

# Load Balancer logs  
gcloud logging read "resource.type=http_load_balancer" --limit=50
```

### Métricas de performance
```bash
# Cloud Run metrics
gcloud run services describe titiler-service --region=us-central1 --format="value(status.traffic[0].percent)"

# Storage usage
gsutil du -sh gs://YOUR_BUCKET_NAME/

# CDN hit rate
gcloud monitoring metrics list --filter="metric.type=loadbalancing.googleapis.com/https/cache_hit_rate"
```

## 📞 Contacto y Soporte

Si los problemas persisten:

1. **Revisa la documentación**: `docs/README.md`
2. **Consulta los logs**: Usa los comandos de debugging arriba
3. **Verifica la configuración**: `.env` y `constants.dart`
4. **Prueba componentes individualmente**: GCS → TiTiler → CDN → Flutter

### Información útil para reportar problemas:
- Versión de GDAL: `gdalinfo --version`
- Versión de gcloud: `gcloud version`
- Logs de error específicos
- Configuración de .env (sin secrets)
- Tamaño y formato de archivos problemáticos

## 🔄 Recovery Procedures

### Rollback a WMS legacy
```dart
// En constants.dart
const bool kUseModernTiles = false;

// Esto automáticamente usará WMS como fallback
```

### Restore desde backup
```bash
# Si tienes backups de la DB
pg_restore -h your-db-host -d postgres backup_file.dump

# Restaurar archivos desde backup
gsutil cp -r gs://backup-bucket/* gs://production-bucket/
```

---

💡 **Tip**: Mantén siempre el modo de fallback a WMS habilitado durante la migración inicial para asegurar continuidad del servicio.
