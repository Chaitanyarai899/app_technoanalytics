#!/usr/bin/env python3
"""
Script simplificado para corregir registros en Supabase usando requests
"""

import os
import sys
import logging
import re
import requests
import json
from datetime import datetime

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)

def load_env():
    """Cargar variables de entorno desde .env"""
    env_vars = {}
    try:
        with open('.env', 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key] = value
    except FileNotFoundError:
        logging.error("❌ Archivo .env no encontrado")
        return None
    return env_vars

class SimpleDatabaseFixer:
    def __init__(self):
        """Inicializar configuración de Supabase"""
        # Leer variables de entorno desde .env
        env_vars = load_env()
        if not env_vars:
            logging.error("❌ No se pudo cargar configuración desde .env")
            sys.exit(1)
            
        self.supabase_url = env_vars.get('SUPABASE_URL')
        self.supabase_key = env_vars.get('SUPABASE_SERVICE_ROLE_KEY')
        
        if not self.supabase_url or not self.supabase_key:
            logging.error("❌ Faltan credenciales de Supabase en .env")
            sys.exit(1)
            
        self.headers = {
            "Authorization": f"Bearer {self.supabase_key}",
            "apikey": self.supabase_key,
            "Content-Type": "application/json",
            "Prefer": "return=minimal"
        }
        logging.info("✅ Configuración Supabase inicializada")
    
    def get_mx_gp_records(self):
        """Obtener todos los registros de mx_gp"""
        try:
            url = f"{self.supabase_url}/rest/v1/productos"
            params = {'empresa': 'eq.mx_gp'}
            
            response = requests.get(url, headers=self.headers, params=params)
            response.raise_for_status()
            
            records = response.json()
            logging.info(f"📊 Encontrados {len(records)} registros de mx_gp")
            return records
            
        except Exception as e:
            logging.error(f"❌ Error obteniendo registros: {e}")
            return []
    
    def update_record(self, record_id, updates):
        """Actualizar un registro específico"""
        try:
            url = f"{self.supabase_url}/rest/v1/productos"
            params = {'id': f'eq.{record_id}'}
            
            response = requests.patch(url, headers=self.headers, params=params, json=updates)
            response.raise_for_status()
            return True
            
        except Exception as e:
            logging.error(f"❌ Error actualizando registro {record_id}: {e}")
            return False
    
    def fix_empresa_name(self, records):
        """Corregir empresa de 'mx_gp' a 'Grupo Porres'"""
        count = 0
        for record in records:
            if record['empresa'] == 'mx_gp':
                if self.update_record(record['id'], {'empresa': 'Grupo Porres'}):
                    count += 1
        
        logging.info(f"✅ Empresa corregida en {count} registros")
        return count
    
    def fix_ingenio_names(self, records):
        """Corregir nombres de ingenios"""
        count = 0
        for record in records:
            new_ingenio = None
            filename = record.get('original_filename', '')
            
            # Santa_Clara o Santa -> Santa Clara
            if record['ingenio'] in ['Santa', 'Santa_Clara'] or 'Santa_Clara' in filename:
                new_ingenio = 'Santa Clara'
            
            # potencial -> corregir basado en el filename
            elif record['ingenio'] == 'potencial':
                if 'potencial_ndvi' in filename or 'potencial_ndwi' in filename:
                    # Extraer el ingenio real del filename
                    match = re.search(r'mx_gp_potencial_n[dw][vw]i_([^_]+)_', filename)
                    if match:
                        ingenio_name = match.group(1)
                        if ingenio_name in ['Santa', 'Santa_Clara']:
                            new_ingenio = 'Santa Clara'
                        else:
                            new_ingenio = ingenio_name
            
            if new_ingenio and new_ingenio != record['ingenio']:
                if self.update_record(record['id'], {'ingenio': new_ingenio}):
                    count += 1
                    logging.info(f"🔧 Ingenio '{record['ingenio']}' -> '{new_ingenio}' para {filename}")
        
        logging.info(f"✅ Ingenio corregido en {count} registros")
        return count
    
    def fix_product_names(self, records):
        """Corregir nombres de productos"""
        count = 0
        for record in records:
            new_product = None
            filename = record.get('original_filename', '')
            
            # Detectar productos que se parsearon mal
            if record['producto'] == 'potencial':
                if 'potencial_ndvi' in filename:
                    new_product = 'potencial_ndvi'
                elif 'potencial_ndwi' in filename:
                    new_product = 'potencial_ndwi'
            
            if new_product and new_product != record['producto']:
                if self.update_record(record['id'], {'producto': new_product}):
                    count += 1
                    logging.info(f"🔧 Producto '{record['producto']}' -> '{new_product}' para {filename}")
        
        logging.info(f"✅ Producto corregido en {count} registros")
        return count
    
    def analyze_records(self, records):
        """Analizar registros para mostrar qué necesita corrección"""
        logging.info("🔍 ANÁLISIS DE REGISTROS:")
        
        empresa_count = sum(1 for r in records if r['empresa'] == 'mx_gp')
        santa_count = sum(1 for r in records if r['ingenio'] in ['Santa', 'Santa_Clara'] or 'Santa_Clara' in r.get('original_filename', ''))
        potencial_ingenio = sum(1 for r in records if r['ingenio'] == 'potencial')
        potencial_producto = sum(1 for r in records if r['producto'] == 'potencial')
        missing_metadata = sum(1 for r in records if not r.get('file_size_mb') or not r.get('bounds'))
        
        logging.info(f"   📊 Empresa 'mx_gp' a corregir: {empresa_count}")
        logging.info(f"   📊 Ingenios 'Santa*' a corregir: {santa_count}")
        logging.info(f"   📊 Ingenios 'potencial' a corregir: {potencial_ingenio}")
        logging.info(f"   📊 Productos 'potencial' a corregir: {potencial_producto}")
        logging.info(f"   📊 Registros sin metadatos: {missing_metadata}")
    
    def run_fixes(self, dry_run=False):
        """Ejecutar todas las correcciones"""
        logging.info("🚀 Iniciando corrección de base de datos")
        
        # Obtener registros
        records = self.get_mx_gp_records()
        if not records:
            logging.error("❌ No se encontraron registros para corregir")
            return
        
        # Analizar primero
        self.analyze_records(records)
        
        if dry_run:
            logging.info("🔍 MODO DRY-RUN: No se realizaron cambios")
            return
        
        # Aplicar correcciones
        empresa_fixes = self.fix_empresa_name(records)
        ingenio_fixes = self.fix_ingenio_names(records)
        product_fixes = self.fix_product_names(records)
        
        # Resumen
        logging.info("🎯 RESUMEN DE CORRECCIONES:")
        logging.info(f"   ✅ Empresa corregida: {empresa_fixes}")
        logging.info(f"   ✅ Ingenio corregido: {ingenio_fixes}")
        logging.info(f"   ✅ Producto corregido: {product_fixes}")
        logging.info(f"   📊 Total registros procesados: {len(records)}")

def main():
    """Función principal"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Corregir registros en Supabase')
    parser.add_argument('--dry-run', action='store_true',
                       help='Solo mostrar qué se corregiría sin hacer cambios')
    
    args = parser.parse_args()
    
    fixer = SimpleDatabaseFixer()
    fixer.run_fixes(dry_run=args.dry_run)

if __name__ == "__main__":
    main()
