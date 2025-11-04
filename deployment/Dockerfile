# Dockerfile para TiTiler optimizado para TechnoAnalytics
FROM ghcr.io/developmentseed/titiler:latest

# Agregar variables de entorno para optimización
ENV GDAL_CACHEMAX=512
ENV GDAL_HTTP_MERGE_CONSECUTIVE_RANGES=YES
ENV GDAL_HTTP_MULTIPLEX=YES
ENV GDAL_HTTP_VERSION=2
ENV VSI_CACHE=TRUE
ENV VSI_CACHE_SIZE=1000000

# Configurar para mejor rendimiento con COG
ENV TITILER_API_ROOT_PATH=""
ENV TITILER_API_CORS_ORIGINS="*"

# Puerto de escucha
EXPOSE 8000

# Comando de inicio
CMD ["uvicorn", "titiler.application.main:app", "--host", "0.0.0.0", "--port", "8000"]
