-- =============================================================================
-- MODERN RASTER ARCHITECTURE - Database Migration
-- Actualización de tabla productos para soporte COG
-- =============================================================================

BEGIN;

-- Agregar columnas para COG metadata
ALTER TABLE public.productos 
ADD COLUMN IF NOT EXISTS cog_url TEXT,
ADD COLUMN IF NOT EXISTS cog_filename TEXT,
ADD COLUMN IF NOT EXISTS original_filename TEXT,
ADD COLUMN IF NOT EXISTS file_size_mb DECIMAL(10,2),
ADD COLUMN IF NOT EXISTS bounds JSONB,
ADD COLUMN IF NOT EXISTS epsg INTEGER DEFAULT 4326,
ADD COLUMN IF NOT EXISTS width INTEGER,
ADD COLUMN IF NOT EXISTS height INTEGER,
ADD COLUMN IF NOT EXISTS bands INTEGER DEFAULT 1,
ADD COLUMN IF NOT EXISTS min_value DECIMAL(10,6),
ADD COLUMN IF NOT EXISTS max_value DECIMAL(10,6),
ADD COLUMN IF NOT EXISTS nodata_value DECIMAL(10,6),
ADD COLUMN IF NOT EXISTS processing_status TEXT DEFAULT 'pending',
ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
ADD COLUMN IF NOT EXISTS processing_log TEXT,
ADD COLUMN IF NOT EXISTS colormap TEXT,
ADD COLUMN IF NOT EXISTS rescale_min DECIMAL(10,6),
ADD COLUMN IF NOT EXISTS rescale_max DECIMAL(10,6);

-- Agregar comentarios para documentación
COMMENT ON COLUMN public.productos.cog_url IS 'URL del archivo COG en Google Cloud Storage';
COMMENT ON COLUMN public.productos.cog_filename IS 'Nombre del archivo COG en el bucket';
COMMENT ON COLUMN public.productos.original_filename IS 'Nombre del archivo original TIF';
COMMENT ON COLUMN public.productos.file_size_mb IS 'Tamaño del archivo en MB';
COMMENT ON COLUMN public.productos.bounds IS 'Bounding box en formato [minx, miny, maxx, maxy]';
COMMENT ON COLUMN public.productos.epsg IS 'Código EPSG del sistema de coordenadas';
COMMENT ON COLUMN public.productos.width IS 'Ancho en píxeles';
COMMENT ON COLUMN public.productos.height IS 'Alto en píxeles';
COMMENT ON COLUMN public.productos.bands IS 'Número de bandas del raster';
COMMENT ON COLUMN public.productos.min_value IS 'Valor mínimo del raster';
COMMENT ON COLUMN public.productos.max_value IS 'Valor máximo del raster';
COMMENT ON COLUMN public.productos.nodata_value IS 'Valor NoData del raster';
COMMENT ON COLUMN public.productos.processing_status IS 'Estado: pending, processing, completed, failed';
COMMENT ON COLUMN public.productos.processing_log IS 'Log del procesamiento';
COMMENT ON COLUMN public.productos.colormap IS 'Colormap a usar en TiTiler';
COMMENT ON COLUMN public.productos.rescale_min IS 'Valor mínimo para rescaling';
COMMENT ON COLUMN public.productos.rescale_max IS 'Valor máximo para rescaling';

-- Crear índices para mejorar performance
CREATE INDEX IF NOT EXISTS productos_producto_idx ON public.productos USING btree (producto);
CREATE INDEX IF NOT EXISTS productos_empresa_idx ON public.productos USING btree (empresa);
CREATE INDEX IF NOT EXISTS productos_ingenio_idx ON public.productos USING btree (ingenio);
CREATE INDEX IF NOT EXISTS productos_processing_status_idx ON public.productos USING btree (processing_status);
CREATE INDEX IF NOT EXISTS productos_created_at_idx ON public.productos USING btree (created_at);
CREATE INDEX IF NOT EXISTS productos_bounds_idx ON public.productos USING gin (bounds);

-- Agregar constraints para validación
DO $$
BEGIN
    -- Add processing_status constraint if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'productos_processing_status_check'
        AND table_name = 'productos'
    ) THEN
        ALTER TABLE public.productos 
        ADD CONSTRAINT productos_processing_status_check 
        CHECK (processing_status IN ('pending', 'processing', 'completed', 'failed'));
    END IF;

    -- Add epsg constraint if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'productos_epsg_check'
        AND table_name = 'productos'
    ) THEN
        ALTER TABLE public.productos 
        ADD CONSTRAINT productos_epsg_check 
        CHECK (epsg > 0);
    END IF;

    -- Add dimensions constraint if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'productos_dimensions_check'
        AND table_name = 'productos'
    ) THEN
        ALTER TABLE public.productos 
        ADD CONSTRAINT productos_dimensions_check 
        CHECK (width > 0 AND height > 0);
    END IF;
END $$;

-- Función para actualizar updated_at automáticamente
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear trigger para updated_at
DROP TRIGGER IF EXISTS update_productos_updated_at ON public.productos;
CREATE TRIGGER update_productos_updated_at
    BEFORE UPDATE ON public.productos
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- Funciones útiles para la aplicación
-- =============================================================================

-- Función para obtener productos con COG disponible
CREATE OR REPLACE FUNCTION get_products_with_cog()
RETURNS TABLE (
    id UUID,
    producto TEXT,
    fecha DATE,
    empresa TEXT,
    ingenio TEXT,
    cog_url TEXT,
    bounds JSONB,
    colormap TEXT,
    rescale_min DECIMAL,
    rescale_max DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.producto,
        p.fecha,
        p.empresa,
        p.ingenio,
        p.cog_url,
        p.bounds,
        p.colormap,
        p.rescale_min,
        p.rescale_max
    FROM public.productos p
    WHERE p.processing_status = 'completed'
    AND p.cog_url IS NOT NULL
    ORDER BY p.fecha DESC, p.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Función para buscar producto por archivo
CREATE OR REPLACE FUNCTION find_product_by_filename(filename TEXT)
RETURNS TABLE (
    id UUID,
    producto TEXT,
    processing_status TEXT,
    cog_url TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.producto,
        p.processing_status,
        p.cog_url
    FROM public.productos p
    WHERE p.original_filename = filename 
    OR p.cog_filename = filename;
END;
$$ LANGUAGE plpgsql;

-- Función para obtener estadísticas de procesamiento
CREATE OR REPLACE FUNCTION get_processing_stats()
RETURNS TABLE (
    total_products BIGINT,
    completed BIGINT,
    failed BIGINT,
    pending BIGINT,
    processing BIGINT,
    total_size_gb DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*) as total_products,
        COUNT(*) FILTER (WHERE processing_status = 'completed') as completed,
        COUNT(*) FILTER (WHERE processing_status = 'failed') as failed,
        COUNT(*) FILTER (WHERE processing_status = 'pending') as pending,
        COUNT(*) FILTER (WHERE processing_status = 'processing') as processing,
        ROUND(SUM(file_size_mb) / 1024.0, 2) as total_size_gb
    FROM public.productos;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- Políticas RLS (Row Level Security) - Opcional
-- =============================================================================

-- Habilitar RLS si no está habilitado
-- ALTER TABLE public.productos ENABLE ROW LEVEL SECURITY;

-- Política para permitir lectura a usuarios autenticados
-- CREATE POLICY IF NOT EXISTS "Allow read access to authenticated users" ON public.productos
--     FOR SELECT USING (auth.role() = 'authenticated');

-- Política para permitir inserción/actualización a service role
-- CREATE POLICY IF NOT EXISTS "Allow full access to service role" ON public.productos
--     FOR ALL USING (auth.role() = 'service_role');

-- =============================================================================
-- Datos de ejemplo / migración de datos existentes
-- =============================================================================

-- Si tienes datos existentes sin las nuevas columnas, puedes actualizarlos:
-- UPDATE public.productos 
-- SET 
--     processing_status = 'pending',
--     created_at = NOW(),
--     updated_at = NOW()
-- WHERE processing_status IS NULL;

-- =============================================================================
-- Verificación de la estructura
-- =============================================================================

-- Ver todas las columnas de la tabla
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns 
-- WHERE table_name = 'productos' AND table_schema = 'public'
-- ORDER BY ordinal_position;

COMMIT;
