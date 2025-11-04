-- =============================================================================
-- SCRIPT SQL: Actualizar centroides de ingenios en vw_centroide_global
-- =============================================================================

-- Paso 1: Crear tabla para almacenar centroides si no existe
CREATE TABLE IF NOT EXISTS centroides_ingenios (
    id SERIAL PRIMARY KEY,
    ingenio VARCHAR(100) UNIQUE NOT NULL,
    centroide_lat DOUBLE PRECISION NOT NULL,
    centroide_lng DOUBLE PRECISION NOT NULL,
    min_lat DOUBLE PRECISION,
    max_lat DOUBLE PRECISION,
    min_lng DOUBLE PRECISION,
    max_lng DOUBLE PRECISION,
    total_parcelas INTEGER,
    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Crear índice si no existe
CREATE INDEX IF NOT EXISTS idx_centroides_ingenio ON centroides_ingenios(ingenio);

-- Paso 2: Calcular y insertar/actualizar centroides desde parcelas
INSERT INTO centroides_ingenios 
(ingenio, centroide_lat, centroide_lng, min_lat, max_lat, min_lng, max_lng, total_parcelas, fecha_actualizacion, updated_at)
SELECT 
    ingenio,
    ST_Y(ST_Centroid(ST_Union(geometry_polygon))) as centroide_lat,
    ST_X(ST_Centroid(ST_Union(geometry_polygon))) as centroide_lng,
    ST_YMin(ST_Union(geometry_polygon)) as min_lat,
    ST_YMax(ST_Union(geometry_polygon)) as max_lat,
    ST_XMin(ST_Union(geometry_polygon)) as min_lng,
    ST_XMax(ST_Union(geometry_polygon)) as max_lng,
    COUNT(*) as total_parcelas,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM parcelas_ingenios 
WHERE activo = true 
AND geometry_polygon IS NOT NULL
GROUP BY ingenio
ON CONFLICT (ingenio) 
DO UPDATE SET 
    centroide_lat = EXCLUDED.centroide_lat,
    centroide_lng = EXCLUDED.centroide_lng,
    min_lat = EXCLUDED.min_lat,
    max_lat = EXCLUDED.max_lat,
    min_lng = EXCLUDED.min_lng,
    max_lng = EXCLUDED.max_lng,
    total_parcelas = EXCLUDED.total_parcelas,
    fecha_actualizacion = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP;

-- Paso 3: Recrear la vista vw_centroide_global
DROP VIEW IF EXISTS vw_centroide_global;

CREATE VIEW vw_centroide_global AS
SELECT 
    ingenio,
    centroide_lat as latitude,
    centroide_lng as longitude,
    min_lat,
    max_lat,
    min_lng,
    max_lng,
    total_parcelas,
    fecha_actualizacion
FROM centroides_ingenios
ORDER BY ingenio;

-- Paso 4: Verificar resultados
SELECT 
    'RESULTADOS FINALES' as info,
    ingenio,
    ROUND(latitude::numeric, 6) as latitude,
    ROUND(longitude::numeric, 6) as longitude,
    total_parcelas
FROM vw_centroide_global 
ORDER BY ingenio;

-- Mostrar comparación con los valores que calculó la app
SELECT 
    'COMPARACION CON VALORES DE LA APP' as info,
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
    CASE 
        WHEN ingenio = 'Huixtla' THEN ABS(latitude - 16.712136) < 0.001
        WHEN ingenio = 'Modelo' THEN ABS(latitude - 19.178353) < 0.001
        WHEN ingenio = 'Santa_Clara' THEN ABS(latitude - 19.307709) < 0.001
        ELSE NULL
    END as lat_match,
    CASE 
        WHEN ingenio = 'Huixtla' THEN ABS(longitude - (-93.825052)) < 0.001
        WHEN ingenio = 'Modelo' THEN ABS(longitude - (-96.433022)) < 0.001  
        WHEN ingenio = 'Santa_Clara' THEN ABS(longitude - (-99.225468)) < 0.001
        ELSE NULL
    END as lng_match
FROM vw_centroide_global 
ORDER BY ingenio;
