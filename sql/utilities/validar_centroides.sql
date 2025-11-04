-- =============================================================================
-- VALIDACIÓN: Verificar centroides actualizados en vw_centroide_global
-- =============================================================================

-- Ver todos los centroides disponibles
SELECT 
    '=== CENTROIDES ACTUALES EN vw_centroide_global ===' as info,
    ingenio,
    ROUND(latitude::numeric, 6) as latitude,
    ROUND(longitude::numeric, 6) as longitude,
    total_parcelas,
    fecha_actualizacion
FROM vw_centroide_global 
ORDER BY ingenio;

-- Comparar con los valores calculados por la aplicación Flutter
SELECT 
    '=== COMPARACIÓN CON VALORES DE LA APP FLUTTER ===' as info,
    ingenio,
    ROUND(latitude::numeric, 6) as db_lat,
    ROUND(longitude::numeric, 6) as db_lng,
    CASE 
        WHEN ingenio = 'Huixtla' THEN 16.712136
        WHEN ingenio = 'Modelo' THEN 19.178353
        WHEN ingenio = 'Santa_Clara' THEN 19.307709
        ELSE NULL
    END as app_lat,
    CASE 
        WHEN ingenio = 'Huixtla' THEN -93.825052
        WHEN ingenio = 'Modelo' THEN -96.433022
        WHEN ingenio = 'Santa_Clara' THEN -99.225468
        ELSE NULL
    END as app_lng,
    -- Verificar si coinciden (tolerancia de 0.001 grados)
    CASE 
        WHEN ingenio = 'Huixtla' THEN 
            CASE WHEN ABS(latitude - 16.712136) < 0.001 AND ABS(longitude - (-93.825052)) < 0.001 
                 THEN '✅ COINCIDE' ELSE '❌ DIFERENTE' END
        WHEN ingenio = 'Modelo' THEN 
            CASE WHEN ABS(latitude - 19.178353) < 0.001 AND ABS(longitude - (-96.433022)) < 0.001 
                 THEN '✅ COINCIDE' ELSE '❌ DIFERENTE' END
        WHEN ingenio = 'Santa_Clara' THEN 
            CASE WHEN ABS(latitude - 19.307709) < 0.001 AND ABS(longitude - (-99.225468)) < 0.001 
                 THEN '✅ COINCIDE' ELSE '❌ DIFERENTE' END
        ELSE '🔍 NUEVO INGENIO'
    END as validacion
FROM vw_centroide_global 
ORDER BY ingenio;

-- Verificar que la tabla base tiene los datos correctos
SELECT 
    '=== DATOS EN TABLA CENTROIDES_INGENIOS ===' as info,
    ingenio,
    ROUND(centroide_lat::numeric, 6) as centroide_lat,
    ROUND(centroide_lng::numeric, 6) as centroide_lng,
    total_parcelas,
    fecha_actualizacion
FROM centroides_ingenios 
ORDER BY ingenio;

-- Estadísticas de parcelas por ingenio
SELECT 
    '=== ESTADÍSTICAS DE PARCELAS ACTIVAS ===' as info,
    ingenio,
    COUNT(*) as parcelas_activas,
    MIN(ST_Y(ST_Centroid(geometry_polygon))) as min_lat,
    MAX(ST_Y(ST_Centroid(geometry_polygon))) as max_lat,
    MIN(ST_X(ST_Centroid(geometry_polygon))) as min_lng,
    MAX(ST_X(ST_Centroid(geometry_polygon))) as max_lng
FROM parcelas_ingenios 
WHERE activo = true 
AND geometry_polygon IS NOT NULL
GROUP BY ingenio
ORDER BY ingenio;
