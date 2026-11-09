# TuCambio API — Kotlin / Ktor

Backend HTTP inicial de TuCambio. Esta base es deliberadamente pequeña: prepara ejecución local, contenedor y health checks sin anticipar el esquema de dominio ni conectar credenciales remotas.

## Stack fijado para el MVP

- Kotlin 2.4.21
- Ktor 3.6.1
- JDK 21
- Gradle 9.2.1
- Netty
- kotlinx.serialization
- Docker multi-stage, runtime JRE no-root

Las versiones corresponden a las versiones estables consultadas el 9 de noviembre de 2026.

## Ejecutar localmente

Requiere JDK 21 y Gradle 9.2.1 instalado.

```bash
cd backend
gradle run
```

El servidor escucha en `0.0.0.0:8080` por defecto. El puerto puede cambiarse con `PORT`.

## Endpoints iniciales

| Ruta | Propósito |
|---|---|
| `GET /` | Identificación del servicio |
| `GET /health/live` | Liveness para detectar proceso activo |
| `GET /health/ready` | Readiness HTTP |

**Importante:** mientras PostgreSQL, Auth y Storage no estén conectados, readiness solo confirma que Ktor terminó de inicializar. No afirma que dependencias externas estén disponibles.

## Supabase Auth y contexto de identidad

Cuando SUPABASE_URL está configurada, Ktor valida Bearer access tokens usando el JWKS público de `/auth/v1/.well-known/jwks.json`, issuer `/auth/v1`, audience `authenticated` (configurable), expiración y firma. El proveedor JWKS mantiene caché y límite de solicitudes para no consultar Auth en cada request.

`GET /api/v1/me` devuelve únicamente el UUID del sujeto autenticado. Se rechazan sujetos que no sean UUID, tokens con rol distinto de `authenticated` y sesiones anónimas. Sin SUPABASE_URL, el endpoint responde 503; el resto del servidor y los health checks siguen disponibles.

Esta etapa no implementa registro/login/refresh/logout ni recuperación de contraseña: esos flujos deben delegarse a Supabase Auth desde un cliente o integrarse después mediante un contrato explícito. Tampoco resuelve tenant ni capacidades. El claim `user_metadata` y otros datos editables del token nunca autorizan acciones de negocio. La membresía activa y las capacidades deberán consultarse en PostgreSQL antes de habilitar endpoints de dominio.

## Pruebas y distribución

```bash
gradle test
gradle installDist
```

## Construir el contenedor

Desde la raíz del repositorio:

```bash
docker build -t tucambio-api:local ./backend
docker run --rm -p 8080:8080 tucambio-api:local
```

El contenedor ejecuta como usuario no privilegiado y recibe el puerto mediante la variable `PORT`.

## Configuración y secretos

La verificación JWT se configura con `SUPABASE_URL` y `SUPABASE_JWT_AUDIENCE`. No se almacena ni se necesita una clave service-role para verificar firmas asimétricas mediante JWKS. Las credenciales administrativas de PostgreSQL y cualquier clave secreta permanecen fuera del repositorio, de la imagen y del cliente.

## Despliegue

La guía de Cloud Run está en [../cloudrun/README.md](../cloudrun/README.md). El workflow actual compila, prueba y construye la imagen; no publica imágenes ni despliega automáticamente.
