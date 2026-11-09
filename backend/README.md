# TuCambio API — Kotlin / Ktor

Backend HTTP de TuCambio. La API valida identidad con Supabase Auth y resuelve autorización multi-tenant desde PostgreSQL.

## Stack

- Kotlin 2.4.21, Ktor 3.6.1, JDK 21, Gradle 9.2.1
- Netty, HikariCP, PostgreSQL JDBC y kotlinx.serialization
- Docker multi-stage con runtime JRE no-root

## Ejecutar localmente

Requiere JDK 21 y Gradle 9.2.1.

```bash
cd backend
gradle run
```

Puerto por defecto: `8080`, configurable mediante `PORT`.

## Endpoints

| Ruta | Propósito |
|---|---|
| `GET /` | Identificación del servicio |
| `GET /health/live` | Liveness del proceso |
| `GET /health/ready` | Readiness HTTP; aún no verifica dependencias |
| `GET /api/v1/me` | Identidad autenticada |
| `GET /api/v1/tenants/{tenantId}/authorization` | Membresía activa y capacidades del actor |

Los endpoints de API requieren Bearer access token válido de Supabase. Sin `SUPABASE_URL`, responden 503.

## Autenticación y autorización

Ktor verifica firma JWT mediante JWKS, issuer, audience, expiración, subject UUID canónico, `role=authenticated` y rechaza identidades anónimas. El actor proviene exclusivamente del subject validado.

La autorización se resuelve en PostgreSQL mediante `public.resolve_tenant_access(actor_user_id, tenant_id)`. Solo devuelve acceso si el tenant y la membresía del actor están activos. Las capacidades se derivan de `membership_roles` y `tenant_role_capabilities`; el tenant ID recibido solo identifica el recurso solicitado, nunca demuestra pertenencia.

La función es `SECURITY DEFINER` con `search_path` fijo y devuelve únicamente membership ID y códigos de capacidad. La migración crea el rol grupal sin login `tucambio_backend`, revoca EXECUTE de PUBLIC/anon/authenticated y concede EXECUTE solo a ese rol. El usuario configurado en `DATABASE_URL` debe ser una credencial privada de servidor miembro de `tucambio_backend`. No se conceden permisos directos de lectura sobre las tablas y el rol no tiene BYPASSRLS.

No se usa `user_metadata`, claims editables ni un tenant ID del cliente como fuente de autorización. La falta de membresía activa deniega el acceso. Los errores de PostgreSQL producen 503, nunca una concesión.

## Configuración

- `SUPABASE_URL`: URL raíz del proyecto Supabase.
- `SUPABASE_JWT_AUDIENCE`: audience JWT; default `authenticated`.
- `DATABASE_URL`: URL PostgreSQL privada `postgres://usuario:contraseña@host:puerto/base?sslmode=require`; el usuario debe pertenecer a `tucambio_backend`.

Las credenciales permanecen en el gestor de secretos del entorno. No se guardan en Git, imagen ni cliente. Crear el usuario login y concederle membresía en el rol grupal es una tarea operativa del entorno.

## Pruebas y contenedor

```bash
gradle test
gradle installDist
docker build -t tucambio-api:local ./backend
```

CI valida migraciones en PostgreSQL 17, ejecuta pruebas Kotlin y construye la imagen. No publica ni despliega automáticamente.
