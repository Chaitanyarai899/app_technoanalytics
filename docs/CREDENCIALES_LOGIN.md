# 🔐 CREDENCIALES DE PRUEBA - AUTENTICACIÓN DIRECTA

## ✅ Sistema de Autenticación Actualizado

La aplicación ahora usa **autenticación directa** desde la tabla `public.users`:
- ✅ No requiere Supabase Auth
- ✅ Valida contra `password_hash` en tabla users
- ✅ Acceso inmediato con credenciales existentes

---

## 👥 USUARIOS DISPONIBLES PARA LOGIN

### 🏢 Grupo Porres - Usuarios Activos

#### Usuario 1: Ocampos
```
📧 Email: ocampos@gporres.com.mx
🔑 Contraseña: Inicio2025!
👤 Nombre: Ocampos
🏢 Empresa: Grupo Porres
🏭 Ingenio: San_Pedro
🌎 País: mx
```

#### Usuario 2: Mildreth Lilian
```
📧 Email: mrosado@gporres.com.mx
🔑 Contraseña: Inicio2025!
👤 Nombre: Mildreth Lilian
🏢 Empresa: Grupo Porres
🏭 Ingenio: San_Pedro
🌎 País: mx
```

#### Usuario 3: Katia Marlen
```
📧 Email: kchavez@gporres.com.mx
🔑 Contraseña: Inicio2025!
👤 Nombre: Katia Marlen
🏢 Empresa: Grupo Porres
🏭 Ingenio: Santa_Clara
🌎 País: mx
```

---

## 🧪 USUARIOS DE PRUEBA RECOMENDADOS

### Para Desarrollo y Testing

```
📧 Email: ocampos@gporres.com.mx
🔑 Contraseña: Inicio2025!
✨ Recomendado para: Pruebas generales
```

```
📧 Email: mrosado@gporres.com.mx
🔑 Contraseña: Inicio2025!
✨ Recomendado para: Pruebas de ingenio San_Pedro
```

---

## 📱 Cómo Usar las Credenciales

1. **Abrir la aplicación**
2. **Ingresar email** (copiar exactamente como se muestra)
3. **Ingresar contraseña**: `Inicio2025!`
4. **Hacer clic en "Iniciar sesión"**

---

## 🔍 Verificar Más Usuarios

Si necesitas ver todos los usuarios disponibles, ejecuta:

```bash
cd c:\BUSINESS_INTELLIGENCE\TA\Proyectos\app_movil\techno_analytics

python -c "import requests; import json; r = requests.get('https://eewlwrgzeypfwjruzshj.supabase.co/rest/v1/users?select=email,name,password_hash,company,ingenio,activo&activo=eq.true', headers={'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVld2x3cmd6ZXlwZndqcnV6c2hqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzE2MzQ0MzEsImV4cCI6MjA0NzIxMDQzMX0.Jgk9rwKV07ya4a21QGUjfGbCIgC6b4wWJgPeNZ9jIOo', 'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVld2x3cmd6ZXlwZndqcnV6c2hqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzE2MzQ0MzEsImV4cCI6MjA0NzIxMDQzMX0.Jgk9rwKV07ya4a21QGUjfGbCIgC6b4wWJgPeNZ9jIOo'}); users = r.json(); print(f'\n📋 USUARIOS ACTIVOS: {len(users)}\n'); [print(f\"📧 {u['email']:<40} 🔑 {u['password_hash']:<15} 🏢 {u['company']:<20} 👤 {u['name']}\") for u in sorted(users, key=lambda x: x['company'])]"
```

---

## 🛠️ Cambios Realizados en el Código

### `lib/views/login_page.dart`
- ✅ Eliminado `signInWithPassword` de Supabase Auth
- ✅ Consulta directa a tabla `users`
- ✅ Validación de `password_hash` en texto plano
- ✅ Verificación de campo `activo = true`

### `lib/views/splash_screen.dart`
- ✅ Eliminada verificación de sesión de Supabase Auth
- ✅ Redirige directamente a login
- ✅ Simplificado para autenticación custom

---

## 🔒 Seguridad (Mejoras Futuras)

⚠️ **IMPORTANTE**: El sistema actual almacena contraseñas en texto plano (`password_hash`).

### Recomendaciones para Producción:

1. **Implementar hashing real**:
```sql
-- Migrar a bcrypt
ALTER TABLE users 
ADD COLUMN password_bcrypt TEXT;

-- Usar función de hash
CREATE EXTENSION IF NOT EXISTS pgcrypto;

UPDATE users 
SET password_bcrypt = crypt(password_hash, gen_salt('bf'))
WHERE password_hash IS NOT NULL;
```

2. **Actualizar lógica de login** para usar:
```dart
// En Flutter, usar package: bcrypt
import 'package:bcrypt/bcrypt.dart';

// Validar
final isValid = BCrypt.checkpw(password, usuario['password_bcrypt']);
```

3. **Implementar sesiones persistentes**:
```dart
import 'package:shared_preferences/shared_preferences.dart';

// Guardar sesión
final prefs = await SharedPreferences.getInstance();
await prefs.setString('user_email', email);
await prefs.setString('session_token', generateToken());

// Verificar en splash_screen
final email = prefs.getString('user_email');
if (email != null) {
  // Auto-login
}
```

---

## 📊 Estructura de Tabla Users

```sql
CREATE TABLE public.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  name TEXT,
  password_hash TEXT,  -- Actualmente en texto plano
  company TEXT,
  ingenio TEXT,
  country TEXT,
  activo BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW()
);
```

---

## ✅ Verificación Rápida

Para probar que funciona:

1. **Ejecutar la app**: `flutter run`
2. **Usar estas credenciales**:
   - Email: `ocampos@gporres.com.mx`
   - Contraseña: `Inicio2025!`
3. **Debería entrar directamente** al dashboard

---

## 🐛 Troubleshooting

### "Usuario no encontrado o inactivo"
- Verifica que el email esté escrito correctamente
- Verifica que `activo = true` en la base de datos

### "Contraseña incorrecta"
- La contraseña es **case-sensitive**
- Copia exactamente: `Inicio2025!`

### "Error al iniciar sesión"
- Verifica conexión a internet
- Verifica que Supabase esté disponible
- Revisa logs en consola de Flutter

---

## 📞 Contacto

Si necesitas agregar más usuarios o cambiar contraseñas:

```sql
-- Agregar nuevo usuario
INSERT INTO public.users (email, name, password_hash, company, ingenio, country, activo)
VALUES ('nuevo@ejemplo.com', 'Nombre', 'ContraseñaAqui', 'Empresa', 'Ingenio', 'mx', true);

-- Cambiar contraseña
UPDATE public.users 
SET password_hash = 'NuevaContraseña' 
WHERE email = 'usuario@ejemplo.com';

-- Activar/desactivar usuario
UPDATE public.users 
SET activo = true 
WHERE email = 'usuario@ejemplo.com';
```

---

**Última actualización:** Octubre 2025  
**Sistema:** Autenticación Custom desde public.users
