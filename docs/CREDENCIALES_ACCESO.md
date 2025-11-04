# 🔐 Credenciales de Acceso - Techno Analytics App

## 📋 Información Importante

La aplicación usa **Supabase Authentication** donde:
- Las contraseñas están encriptadas en `auth.users` (no visibles)
- La tabla pública `users` solo contiene metadata del usuario
- Se requiere crear usuarios desde el Dashboard de Supabase o mediante signup

---

## 👥 Usuarios Disponibles en el Sistema

### Usuarios de Prueba (Bitechno Analytics)

```
📧 Email: erick.santizo@bitechnoanalytics.com
👤 Nombre: Erick
🏢 Empresa: Todos
🏭 Ingenio: Todos
🌎 País: Todos
🔑 Contraseña: [Configurar en Supabase Dashboard]
```

```
📧 Email: jose.lopez@bitechnoanalytics.com
👤 Nombre: José
🏢 Empresa: Todos
🏭 Ingenio: Todos
🌎 País: Todos
🔑 Contraseña: [Configurar en Supabase Dashboard]
```

```
📧 Email: prueba@bitechnoanalytics.com
👤 Nombre: Prueba2
🏢 Empresa: Grupo Porres
🏭 Ingenio: Huixtla
🌎 País: mx
🔑 Contraseña: [Configurar en Supabase Dashboard]
```

```
📧 Email: prueba1@bitechnoanalytics.com
👤 Nombre: Prueba2
🏢 Empresa: Grupo Porres
🏭 Ingenio: San_Pedro
🌎 País: mx
🔑 Contraseña: [Configurar en Supabase Dashboard]
```

```
📧 Email: prueba2@bitechnoanalytics.com
👤 Nombre: Prueba3
🏢 Empresa: Grupo Porres
🏭 Ingenio: San_Pedro
🌎 País: mx
🔑 Contraseña: [Configurar en Supabase Dashboard]
```

```
📧 Email: prueba3@bitechnoanalytics.com
👤 Nombre: Prueba4
🏢 Empresa: Santa Ana
🏭 Ingenio: Todos
🌎 País: mx
🔑 Contraseña: [Configurar en Supabase Dashboard]
```

### Usuarios Grupo Porres

```
📧 Email: ocampos@gporres.com.mx
👤 Nombre: Ocampos
🏢 Empresa: Grupo Porres
🏭 Ingenio: San_Pedro
```

```
📧 Email: mrosado@gporres.com.mx
👤 Nombre: Mildreth Lilian
🏢 Empresa: Grupo Porres
🏭 Ingenio: San_Pedro
```

```
📧 Email: rhernandezg@gporres.com.mx
👤 Nombre: Roberto
🏢 Empresa: Grupo Porres
🏭 Ingenio: Todos
```

```
📧 Email: totoheidy@hotmail.com
👤 Nombre: Heidy
🏢 Empresa: Grupo Porres
🏭 Ingenio: Huixtla
```

### Usuarios Demo

```
📧 Email: agronomoalonzo@gmail.com
👤 Nombre: Manuel
🏢 Empresa: Demo
🏭 Ingenio: Demo
🌎 País: GT
```

```
📧 Email: cfgomez@pantaleon.com
👤 Nombre: Carlos
🏢 Empresa: Demo
🏭 Ingenio: Demo
🌎 País: GT
```

---

## 🔧 Cómo Configurar/Resetear Contraseñas

### Opción 1: Desde Supabase Dashboard (Recomendado)

1. **Acceder al Dashboard**
   ```
   URL: https://supabase.com/dashboard/project/eewlwrgzeypfwjruzshj
   ```

2. **Navegar a Authentication > Users**

3. **Seleccionar un usuario** y hacer clic en "Send magic link" o "Reset password"

4. **O crear nuevo usuario**:
   - Clic en "Add user" → "Create new user"
   - Ingresar email y contraseña
   - Confirmar email automáticamente (toggle "Auto Confirm User")

### Opción 2: Usando SQL (Service Role Key requerida)

```sql
-- Desde SQL Editor en Supabase Dashboard

-- Crear usuario nuevo en auth.users
INSERT INTO auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_user_meta_data,
  is_super_admin,
  created_at,
  updated_at
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(),
  'authenticated',
  'authenticated',
  'nuevo.usuario@ejemplo.com',
  crypt('tu_contraseña_aqui', gen_salt('bf')),
  NOW(),
  '{"name": "Nombre Usuario"}',
  false,
  NOW(),
  NOW()
);

-- Luego crear entrada en public.users
INSERT INTO public.users (
  email,
  name,
  company,
  ingenio,
  country,
  activo
) VALUES (
  'nuevo.usuario@ejemplo.com',
  'Nombre Usuario',
  'Empresa',
  'Ingenio',
  'mx',
  true
);
```

### Opción 3: Usando la API de Supabase Admin (Python)

```python
from supabase import create_client, Client
import os

# Usar SERVICE_ROLE_KEY (no la anon key)
url = "https://eewlwrgzeypfwjruzshj.supabase.co"
service_role_key = "TU_SERVICE_ROLE_KEY_AQUI"  # Desde Dashboard > Settings > API

supabase: Client = create_client(url, service_role_key)

# Crear usuario
response = supabase.auth.admin.create_user({
    "email": "nuevo@ejemplo.com",
    "password": "contraseña_segura",
    "email_confirm": True,
    "user_metadata": {
        "name": "Nombre del Usuario"
    }
})

print(f"Usuario creado: {response.user.id}")

# Luego crear entrada en tabla pública
supabase.table('users').insert({
    "email": "nuevo@ejemplo.com",
    "name": "Nombre del Usuario",
    "company": "Empresa",
    "ingenio": "Ingenio",
    "country": "mx",
    "activo": True
}).execute()
```

### Opción 4: Reset Password Programático

```python
from supabase import create_client

url = "https://eewlwrgzeypfwjruzshj.supabase.co"
service_role_key = "TU_SERVICE_ROLE_KEY"

supabase = create_client(url, service_role_key)

# Enviar email de reset
supabase.auth.admin.generate_link({
    "type": "recovery",
    "email": "usuario@ejemplo.com"
})
```

---

## 🚀 Crear Usuario de Prueba Rápido

### Script Python Completo

Guarda como `create_test_user.py`:

```python
#!/usr/bin/env python3
"""
Script para crear usuario de prueba en Techno Analytics
"""

import os
import sys
from supabase import create_client, Client

# Configuración
SUPABASE_URL = "https://eewlwrgzeypfwjruzshj.supabase.co"
SUPABASE_SERVICE_ROLE_KEY = input("Ingresa tu SERVICE_ROLE_KEY: ").strip()

# Datos del usuario
email = input("Email del nuevo usuario: ").strip()
password = input("Contraseña: ").strip()
name = input("Nombre completo: ").strip()
company = input("Empresa: ").strip()
ingenio = input("Ingenio: ").strip()
country = input("País (mx/gt/sv): ").strip().lower()

try:
    # Conectar con service role
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
    
    # 1. Crear usuario en auth.users
    print("\n🔄 Creando usuario en auth...")
    auth_response = supabase.auth.admin.create_user({
        "email": email,
        "password": password,
        "email_confirm": True,  # Confirmar automáticamente
        "user_metadata": {
            "name": name
        }
    })
    
    if auth_response.user:
        print(f"✅ Usuario creado en auth: {auth_response.user.id}")
    else:
        print("❌ Error creando usuario en auth")
        sys.exit(1)
    
    # 2. Crear entrada en public.users
    print("🔄 Creando entrada en tabla users...")
    user_response = supabase.table('users').insert({
        "email": email,
        "name": name,
        "company": company,
        "ingenio": ingenio,
        "country": country,
        "activo": True
    }).execute()
    
    if user_response.data:
        print(f"✅ Usuario creado en tabla users")
    else:
        print("⚠️  Usuario creado en auth pero falló en tabla users")
    
    print("\n" + "="*50)
    print("✅ USUARIO CREADO EXITOSAMENTE")
    print("="*50)
    print(f"📧 Email: {email}")
    print(f"🔑 Contraseña: {password}")
    print(f"👤 Nombre: {name}")
    print(f"🏢 Empresa: {company}")
    print(f"🏭 Ingenio: {ingenio}")
    print(f"🌎 País: {country}")
    print("="*50)
    
except Exception as e:
    print(f"\n❌ Error: {e}")
    sys.exit(1)
```

### Uso:

```bash
# Instalar dependencia
pip install supabase

# Ejecutar script
python create_test_user.py
```

---

## 🔍 Verificar Usuarios Existentes

### Script para Listar Usuarios

```python
#!/usr/bin/env python3
"""
Listar todos los usuarios registrados
"""

import requests
import json

SUPABASE_URL = "https://eewlwrgzeypfwjruzshj.supabase.co"
SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVld2x3cmd6ZXlwZndqcnV6c2hqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzE2MzQ0MzEsImV4cCI6MjA0NzIxMDQzMX0.Jgk9rwKV07ya4a21QGUjfGbCIgC6b4wWJgPeNZ9jIOo"

headers = {
    'apikey': SUPABASE_ANON_KEY,
    'Authorization': f'Bearer {SUPABASE_ANON_KEY}'
}

response = requests.get(
    f'{SUPABASE_URL}/rest/v1/users?select=email,name,company,ingenio,country,activo&activo=eq.true',
    headers=headers
)

if response.status_code == 200:
    users = response.json()
    print(f"\n📋 USUARIOS ACTIVOS ({len(users)} total)\n")
    print("="*80)
    
    for user in sorted(users, key=lambda x: x['company']):
        print(f"📧 {user['email']:<40} | {user['name']:<20}")
        print(f"   🏢 {user['company']:<20} | 🏭 {user['ingenio']:<20} | 🌎 {user['country']}")
        print("-"*80)
else:
    print(f"❌ Error: {response.status_code}")
    print(response.text)
```

---

## 🔐 Contraseñas Temporales Recomendadas

Para usuarios de prueba, puedes usar estas contraseñas temporales (cambiar después):

```
Nivel 1 (Testing básico):
- Password: Test123456!
- Password: Prueba2024!
- Password: Demo123456!

Nivel 2 (Testing interno):
- Password: TechnoAnalytics2024!
- Password: BiTechno2024!

Nivel 3 (Desarrollo):
- Password: DevTA2024!Secure
```

**⚠️ IMPORTANTE**: 
- Estas son contraseñas temporales SOLO para desarrollo
- En producción, usar contraseñas seguras únicas por usuario
- Implementar política de cambio de contraseña en primer login

---

## 📱 Flujo de Login en la App

1. **Usuario ingresa email y contraseña**
2. **App llama a** `Supabase.auth.signInWithPassword()`
3. **Supabase valida credenciales** contra `auth.users`
4. **Si es exitoso**, retorna token de sesión
5. **App consulta** `public.users` con el email para obtener metadata (company, ingenio, etc.)
6. **Si usuario está activo** (`activo = true`), permite acceso
7. **Si usuario inactivo o no existe** en `public.users`, rechaza acceso

---

## 🛠️ Troubleshooting

### Problema: "Credenciales incorrectas"

**Causas posibles:**
- Contraseña incorrecta
- Usuario no existe en `auth.users`
- Email no confirmado (si `email_confirmed_at` es NULL)

**Solución:**
```sql
-- Verificar si usuario existe en auth
SELECT email, email_confirmed_at, created_at 
FROM auth.users 
WHERE email = 'usuario@ejemplo.com';

-- Confirmar email manualmente si es NULL
UPDATE auth.users 
SET email_confirmed_at = NOW() 
WHERE email = 'usuario@ejemplo.com';
```

### Problema: "Usuario no autorizado"

**Causas posibles:**
- Usuario existe en `auth.users` pero no en `public.users`
- Campo `activo = false` en `public.users`

**Solución:**
```sql
-- Verificar en tabla pública
SELECT email, name, activo, company, ingenio 
FROM public.users 
WHERE email = 'usuario@ejemplo.com';

-- Activar usuario
UPDATE public.users 
SET activo = true 
WHERE email = 'usuario@ejemplo.com';

-- O crear entrada si no existe
INSERT INTO public.users (email, name, company, ingenio, country, activo)
VALUES ('usuario@ejemplo.com', 'Nombre', 'Empresa', 'Ingenio', 'mx', true);
```

### Problema: Usuario creado pero no puede login

**Solución completa:**
```sql
-- 1. Confirmar email en auth
UPDATE auth.users 
SET email_confirmed_at = NOW(),
    confirmed_at = NOW()
WHERE email = 'usuario@ejemplo.com';

-- 2. Verificar que exista en public.users
INSERT INTO public.users (email, name, company, ingenio, country, activo)
VALUES ('usuario@ejemplo.com', 'Nombre Usuario', 'Grupo Porres', 'Huixtla', 'mx', true)
ON CONFLICT (email) DO UPDATE
SET activo = true;
```

---

## 📞 Soporte

Para resetear contraseñas de usuarios existentes:
1. Contactar al administrador del sistema
2. Acceder al Dashboard de Supabase
3. Usar el script `create_test_user.py` con SERVICE_ROLE_KEY

**Dashboard Supabase:**
https://supabase.com/dashboard/project/eewlwrgzeypfwjruzshj

**Documentación Auth:**
https://supabase.com/docs/guides/auth

---

## 🔑 Obtener Service Role Key

1. Ir a: https://supabase.com/dashboard/project/eewlwrgzeypfwjruzshj
2. Settings → API
3. Copiar "service_role" key (⚠️ NUNCA compartir públicamente)
4. Usar solo en scripts de backend/admin

---

**Última actualización:** Octubre 2025
