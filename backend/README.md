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
| `POST /api/v1/tenants/{tenantId}/evidence` | Crea metadata pending y devuelve URL firmada de carga |
| `POST /api/v1/tenants/{tenantId}/evidence/{evidenceId}/complete` | Verifica bytes, tamaño, firma MIME y SHA-256; finaliza la evidencia |
| `GET /api/v1/tenants/{tenantId}/evidence/{evidenceId}/download-url` | Emite URL firmada de descarga por 60 segundos para evidencia disponible |

Los endpoints de API requieren Bearer access token válido de Supabase. Sin `SUPABASE_URL`, responden 503.

## Autenticación y autorización

Ktor verifica firma JWT mediante JWKS, issuer, audience, expiración, subject UUID canónico, `role=authenticated` y rechaza identidades anónimas. El actor proviene exclusivamente del subject validado.

La autorización se resuelve en PostgreSQL mediante `public.resolve_tenant_access(actor_user_id, tenant_id)`. Solo devuelve acceso si el tenant y la membresía del actor están activos. Las capacidades se derivan de `membership_roles` y `tenant_role_capabilities`; el tenant ID recibido solo identifica el recurso solicitado, nunca demuestra pertenencia.

La función es `SECURITY DEFINER` con `search_path` fijo y devuelve únicamente membership ID y códigos de capacidad. La migración crea el rol grupal sin login `tucambio_backend`, revoca EXECUTE de PUBLIC/anon/authenticated y concede EXECUTE solo a ese rol. El usuario configurado en `DATABASE_URL` debe ser una credencial privada de servidor miembro de `tucambio_backend`. No se conceden permisos directos de lectura sobre las tablas y el rol no tiene BYPASSRLS.

No se usa `user_metadata`, claims editables ni un tenant ID del cliente como fuente de autorización. El backend crea el registro pending y comprueba membresía/capacidad antes de firmar una URL de carga de ruta única. La clave service-role omite RLS, por lo que solo se usa después de esta autorización explícita y nunca sale del proceso Ktor. La falta de membresía activa deniega el acceso. Los errores de PostgreSQL producen 503, nunca una concesión.

## Configuración

- `SUPABASE_URL`: URL raíz del proyecto Supabase.
- `SUPABASE_JWT_AUDIENCE`: audience JWT; default `authenticated`.
- `DATABASE_URL`: URL PostgreSQL privada `postgres://usuario:contraseña@host:puerto/base?sslmode=require`; el usuario debe pertenecer a `tucambio_backend`.
- `SUPABASE_SERVICE_ROLE_KEY`: clave privilegiada solo del servidor para firmar URLs de carga/descarga y descargar el objeto pendiente para inspección. Nunca se devuelve al cliente ni se registra.
- `SUPABASE_URL`: también se utiliza para las llamadas de Storage. No hace falta exponer una clave Supabase al cliente para estos endpoints.

Las credenciales permanecen en el gestor de secretos del entorno. No se guardan en Git, imagen ni cliente. Crear el usuario login y concederle membresía en el rol grupal es una tarea operativa del entorno.

## Pruebas y contenedor

```bash
gradle test
gradle installDist
docker build -t tucambio-api:local ./backend
```

CI valida migraciones en PostgreSQL 17, ejecuta pruebas Kotlin y construye la imagen. No publica ni despliega automáticamente.


## Evidencias privadas (M1.6)

1. El cliente autenticado solicita `POST /api/v1/tenants/{tenantId}/evidence` con `mimeType` y `sizeBytes`. Ktor valida el JWT, y PostgreSQL crea una fila pending únicamente si el actor tiene membresía activa y `operations.operate`.
2. Ktor firma una URL de carga para la ruta determinista `{tenantId}/{evidenceId}`. La respuesta incluye `uploadMethod=PUT`, `contentType` y `maxSizeBytes`; el cliente debe enviar el MIME indicado en `Content-Type` y respetar el límite. La URL es un bearer token temporal y debe usarse inmediatamente; el cliente no elige bucket, ruta ni puede sobrescribir.
3. El cliente hace PUT del binario a esa URL. El bucket privado impone 10 MiB y PDF/JPEG/PNG/WebP.
4. El cliente llama a `POST .../{evidenceId}/complete`. Ktor recupera el objeto con credenciales de servidor, limita la lectura, comprueba tamaño y firma binaria MIME y calcula SHA-256. Solo entonces llama a la función backend-only que marca la evidencia available.
5. La descarga requiere `GET .../{evidenceId}/download-url`; PostgreSQL vuelve a comprobar tenant, membresía y capacidad, y Ktor emite una URL firmada de 60 segundos.

La clave `SUPABASE_SERVICE_ROLE_KEY` omite las políticas RLS de Storage. Su uso está confinado al backend después de que el caso de uso y la función PostgreSQL hayan autorizado el actor y la ruta. Nunca debe enviarse a apps, registrarse en logs ni incluirse en respuestas. Las URLs firmadas también son credenciales temporales: no registrarlas y no almacenarlas más allá de la operación.

La inspección actual verifica tamaño, firma de archivo y SHA-256; todavía no realiza análisis antivirus/antimalware, extracción de contenido ni asociación con una entidad de operación financiera. Esas tareas deben completarse antes de usar evidencias en procesos financieros productivos.
