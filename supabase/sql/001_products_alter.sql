-- =============================================================================
-- Supabase Migration: Modern Raster Architecture
-- Add COG support and metadata to productos table
-- =============================================================================

-- Add new columns for COG support and metadata
ALTER TABLE productos 
  ADD COLUMN IF NOT EXISTS cog_url TEXT,
  ADD COLUMN IF NOT EXISTS bounds JSONB,
  ADD COLUMN IF NOT EXISTS epsg INTEGER DEFAULT 3857,
  ADD COLUMN IF NOT EXISTS nodata DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS min_value DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS max_value DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS palette TEXT,
  ADD COLUMN IF NOT EXISTS sha256 TEXT,
  ADD COLUMN IF NOT EXISTS file_size_bytes BIGINT,
  ADD COLUMN IF NOT EXISTS processing_status TEXT DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS error_message TEXT,
  ADD COLUMN IF NOT EXISTS cog_created_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- Add comments for documentation
COMMENT ON COLUMN productos.cog_url IS 'Public URL to the Cloud Optimized GeoTIFF in Google Cloud Storage';
COMMENT ON COLUMN productos.bounds IS 'Bounding box as [west, south, east, north] in WGS84';
COMMENT ON COLUMN productos.epsg IS 'EPSG code of the raster CRS (default: 3857 Web Mercator)';
COMMENT ON COLUMN productos.nodata IS 'NoData value for the raster';
COMMENT ON COLUMN productos.min_value IS 'Minimum pixel value in the raster';
COMMENT ON COLUMN productos.max_value IS 'Maximum pixel value in the raster';
COMMENT ON COLUMN productos.palette IS 'Color palette name for visualization (ndvi, ndwi, etc.)';
COMMENT ON COLUMN productos.sha256 IS 'SHA256 hash of the COG file for integrity verification';
COMMENT ON COLUMN productos.file_size_bytes IS 'File size in bytes';
COMMENT ON COLUMN productos.processing_status IS 'Status: pending, processing, completed, error';
COMMENT ON COLUMN productos.error_message IS 'Error message if processing failed';

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_productos_location 
  ON productos (empresa, ingenio, producto, fecha);

CREATE INDEX IF NOT EXISTS idx_productos_full_location 
  ON productos (id, empresa, ingenio, producto, fecha);

CREATE INDEX IF NOT EXISTS idx_productos_processing_status 
  ON productos (processing_status);

CREATE INDEX IF NOT EXISTS idx_productos_cog_url 
  ON productos (cog_url) 
  WHERE cog_url IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_productos_updated_at 
  ON productos (updated_at DESC);

-- Create unique constraint to prevent duplicates
-- This will help maintain data integrity
ALTER TABLE productos 
  ADD CONSTRAINT uk_productos_unique_product 
  UNIQUE (empresa, ingenio, producto, fecha);

-- Create a function to automatically update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_productos_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for automatic timestamp updates
DROP TRIGGER IF EXISTS trigger_productos_updated_at ON productos;
CREATE TRIGGER trigger_productos_updated_at
  BEFORE UPDATE ON productos
  FOR EACH ROW
  EXECUTE FUNCTION update_productos_updated_at();

-- Create a function to validate bounds format
CREATE OR REPLACE FUNCTION validate_bounds(bounds_json JSONB)
RETURNS BOOLEAN AS $$
BEGIN
  -- Check if bounds is an array with exactly 4 numeric elements
  IF jsonb_typeof(bounds_json) != 'array' THEN
    RETURN FALSE;
  END IF;
  
  IF jsonb_array_length(bounds_json) != 4 THEN
    RETURN FALSE;
  END IF;
  
  -- Check if all elements are numeric
  FOR i IN 0..3 LOOP
    IF jsonb_typeof(bounds_json->i) NOT IN ('number') THEN
      RETURN FALSE;
    END IF;
  END LOOP;
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Add check constraint for bounds validation
ALTER TABLE productos 
  ADD CONSTRAINT check_bounds_format 
  CHECK (bounds IS NULL OR validate_bounds(bounds));

-- Add check constraint for processing status
ALTER TABLE productos 
  ADD CONSTRAINT check_processing_status 
  CHECK (processing_status IN ('pending', 'processing', 'completed', 'error'));

-- Create a view for active/completed products only
CREATE OR REPLACE VIEW v_productos_active AS
SELECT 
  id,
  producto,
  fecha,
  empresa,
  ingenio,
  cog_url,
  bounds,
  epsg,
  nodata,
  min_value,
  max_value,
  palette,
  processing_status,
  cog_created_at,
  updated_at
FROM productos
WHERE processing_status = 'completed' 
  AND cog_url IS NOT NULL;

COMMENT ON VIEW v_productos_active IS 'View showing only successfully processed products with COG URLs';

-- Grant appropriate permissions
GRANT SELECT ON v_productos_active TO anon;
GRANT SELECT ON v_productos_active TO authenticated;

-- Create function to get product info for Flutter app
CREATE OR REPLACE FUNCTION get_producto_info(
  p_empresa TEXT,
  p_ingenio TEXT, 
  p_producto TEXT,
  p_fecha DATE
)
RETURNS TABLE (
  id UUID,
  cog_url TEXT,
  bounds JSONB,
  epsg INTEGER,
  nodata DOUBLE PRECISION,
  min_value DOUBLE PRECISION,
  max_value DOUBLE PRECISION,
  palette TEXT,
  processing_status TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.cog_url,
    p.bounds,
    p.epsg,
    p.nodata,
    p.min_value,
    p.max_value,
    p.palette,
    p.processing_status
  FROM productos p
  WHERE p.empresa = p_empresa
    AND p.ingenio = p_ingenio
    AND p.producto = p_producto
    AND p.fecha = p_fecha
    AND p.processing_status = 'completed'
    AND p.cog_url IS NOT NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_producto_info IS 'Get COG information for a specific product to use in Flutter app';

-- Grant execute permission to anon and authenticated users
GRANT EXECUTE ON FUNCTION get_producto_info TO anon;
GRANT EXECUTE ON FUNCTION get_producto_info TO authenticated;

-- Create migration status tracking
CREATE TABLE IF NOT EXISTS migration_status (
  id SERIAL PRIMARY KEY,
  migration_name TEXT NOT NULL UNIQUE,
  applied_at TIMESTAMPTZ DEFAULT now(),
  description TEXT
);

INSERT INTO migration_status (migration_name, description) 
VALUES ('001_products_cog_support', 'Added COG support and metadata columns to productos table')
ON CONFLICT (migration_name) DO NOTHING;

-- Show migration summary
DO $$
DECLARE
  total_products INTEGER;
  cog_products INTEGER;
BEGIN
  SELECT COUNT(*) INTO total_products FROM productos;
  SELECT COUNT(*) INTO cog_products FROM productos WHERE cog_url IS NOT NULL;
  
  RAISE NOTICE '📊 Migration Summary:';
  RAISE NOTICE '   Total products: %', total_products;
  RAISE NOTICE '   Products with COG: %', cog_products;
  RAISE NOTICE '   Products to migrate: %', (total_products - cog_products);
  RAISE NOTICE '✅ Migration 001_products_cog_support completed successfully!';
END
$$;
