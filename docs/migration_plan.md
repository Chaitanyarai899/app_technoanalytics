# 🚀 PLAN DE MIGRACIÓN COMPLETA - APROVECHANDO FLUJOS EXISTENTES

## ✅ ESTADO ACTUAL
- [x] TiTiler service desplegado: `https://ta-titiler-service-1087100331392.us-central1.run.app`
- [x] Colormap personalizado NDVI implementado y funcionando
- [x] Flujos de ingesta existentes: `ingest_production.py`, `upload_batch.py`
- [x] Scripts de verificación: `scripts/verify_*.py`
- [x] Leyendas optimizadas sin superposición

## 📋 MIGRACIÓN SIMPLIFICADA (45 min total)

### OPCIÓN A: MIGRACIÓN AUTOMÁTICA COMPLETA (45 min)
```bash
# 1. Procesar todos los rasters existentes con nuevo colormap (30 min)
python ingest_production.py test_files/ --force

# 2. Verificar migración (5 min)
python scripts/verify_database.py

# 3. Test final en Flutter (10 min)
flutter run -d chrome
```

### OPCIÓN B: MIGRACIÓN POR LOTES (Control granular)
```bash
# 1. Migrar solo NDVI primero (15 min)
python ingest_production.py test_files/ --force --limit 5

# 2. Verificar NDVI funciona correctamente
python scripts/verify_supabase.py

# 3. Migrar resto de productos (20 min)
python ingest_production.py test_files/ --force

# 4. Verificación final
python scripts/verify_database.py
```

## 🆕 SCRIPTS NUEVOS NECESARIOS (Solo 3 scripts)

### 1. Script de inventario rápido
```bash
python migration/quick_inventory.py
# Listar todos los rasters pendientes de migrar
```

### 2. Script de validación masiva
```bash
python migration/validate_migration.py
# Verificar que todos los COGs son accesibles vía TiTiler
```

### 3. Script de rollback
```bash
python migration/rollback.py
# En caso de problemas, revertir a configuración anterior
```

## 🎯 VENTAJAS DEL ENFOQUE ACTUAL
✅ **Reutiliza tus flujos probados**: `ingest_production.py` ya hace todo
✅ **Conversión COG automática**: Ya implementada con rasterio
✅ **Upload GCS automático**: Ya configurado con gsutil
✅ **Metadata en Supabase**: Ya actualiza la DB correctamente
✅ **Detección de productos**: Ya detecta NDVI, NDWI, etc.
✅ **Configuración de colormaps**: Ya asigna rescale y colormap por tipo

## 📊 TIEMPO ESTIMADO REAL
- **Migración con scripts existentes**: 30 min
- **Verificación**: 5 min  
- **Testing**: 10 min
- **TOTAL**: ~45 min (¡3x más rápido!)

## � COMANDO ÚNICO PARA MIGRACIÓN COMPLETA
```bash
# Un solo comando migra todo
python ingest_production.py test_files/ --force --verbose
```

## 🔧 MODIFICACIONES MÍNIMAS NECESARIAS
1. Actualizar `ingest_production.py` para usar nuevo TiTiler (ya está hecho)
2. Verificar que colormap personalizado NDVI se aplique automáticamente (ya está)
3. Crear scripts de validación (simples)

## � FLUJO FUTURO AUTOMATIZADO
```bash
# Para nuevos rasters, simplemente:
python ingest_production.py nuevo_archivo.tif
# ¡Y ya está disponible con colormap personalizado!
```
