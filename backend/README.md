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
| `POST /api/v1/tenants/{tenantId}/currencies` | Alta idempotente de moneda del tenant |
| `POST /api/v1/tenants/{tenantId}/currency-pairs` | Alta idempotente de par de monedas |
| `POST /api/v1/tenants/{tenantId}/currency-rates` | Alta idempotente de tasa con vigencia |
| `POST /api/v1/tenants/{tenantId}/operations` | Crea operación financiera en estado inicial |
| `POST /api/v1/tenants/{tenantId}/movements` | Registra movimiento externo declarado |
| `POST /api/v1/tenants/{tenantId}/movement-associations` | Asocia un movimiento a una operación con rol ORIGIN o DESTINATION |
| `POST /api/v1/tenants/{tenantId}/evidence-links` | Asocia una evidencia disponible a una operación o movimiento |
| `POST /api/v1/tenants/{tenantId}/movements/{movementId}/transitions` | Avanza el ciclo de verificación de un movimiento externo |
| `GET /api/v1/tenants/{tenantId}/operations` | Consulta operaciones financieras del tenant |
| `GET /api/v1/tenants/{tenantId}/movements` | Consulta movimientos externos del tenant |
| `GET /api/v1/tenants/{tenantId}/currency-rates` | Consulta historial de tasas del tenant, opcionalmente por par |

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

## Comandos financieros (M1.7.3)

Todos los seis comandos requieren JWT Supabase y el header `Idempotency-Key` (1–200 caracteres). El actor siempre se toma del subject del JWT; el tenant se toma de la ruta y se vuelve a autorizar dentro de la función PostgreSQL. El cuerpo nunca puede elegir actor ni membership.

Los cuerpos JSON son:
- `currencies`: `code`, `name`, `decimalPlaces` (0–18).
- `currency-pairs`: `baseCurrencyCode`, `quoteCurrencyCode`.
- `currency-rates`: `pairId`, `buyRate`, `sellRate`, `validFrom`, `validUntil` opcional. Importes decimales se envían como cadenas; fechas como ISO-8601 con offset.
- `operations`: `pairId`, `sourceCurrencyCode`, `targetCurrencyCode`, `requestedAmount`.
- `movements`: `currencyCode`, `amount`, `effectiveAt`, `externalReference` y `description` opcionales.
- `movement-associations`: `operationId`, `movementId`, `movementRole` (`ORIGIN` o `DESTINATION`).

La API calcula SHA-256 del DTO serializado y lo envía junto con la clave de idempotencia a PostgreSQL. Misma clave y mismo hash devuelven el recurso anterior (HTTP 200); mismo ámbito y clave con cuerpo distinto produce HTTP 409. Una creación nueva responde HTTP 201. Los errores de autorización responden 403; referencias o conflictos de dominio 409; validaciones de dominio 422; indisponibilidad de base de datos 503. No se exponen mensajes SQL.

La conexión `DATABASE_URL` debe usar una credencial privada de servidor miembro de `tucambio_backend`. Ese rol recibe EXECUTE únicamente sobre las funciones de comando; no obtiene DML directo sobre las tablas financieras ni BYPASSRLS. Los eventos de dominio y la idempotencia se persisten en la misma transacción PostgreSQL que la escritura.

Estos endpoints no confirman movimientos, no aplican tasas automáticamente, no calculan importes finales ni liquidan operaciones. Esas transiciones y reglas requieren especificación aprobada; no se infieren desde el alta o la asociación.


## Verificación de movimientos (M1.8.1)

El endpoint de transición recibe `{"targetStatus":"IN_VERIFICATION"}`, `{"targetStatus":"CONFIRMED"}` o `{"targetStatus":"NOT_CONFIRMED"}` y exige `Idempotency-Key`. Las únicas transiciones válidas son:

- `DECLARED → IN_VERIFICATION`
- `IN_VERIFICATION → CONFIRMED`
- `IN_VERIFICATION → NOT_CONFIRMED`

El actor debe tener la capacidad `movements.verify` en el tenant. La función PostgreSQL bloquea la fila del movimiento durante la transición, persiste el nuevo estado, registra el evento de auditoría con estado anterior/nuevo, actor y timestamp, y guarda la clave idempotente en la misma transacción. Los reintentos con la misma clave y cuerpo devuelven el recurso original; una clave reutilizada con otro cuerpo produce conflicto. No hay transiciones inversas ni salida desde un estado terminal. Un movimiento confirmado permanece inmutable.

Esta etapa no aplica tasas ni calcula importes. La tasa se resolverá en M1.8.2 usando el instante efectivo del movimiento de origen una vez confirmado.


## Consultas financieras de lectura (M1.9.2)

Las rutas `GET /api/v1/tenants/{tenantId}/operations` y `GET /api/v1/tenants/{tenantId}/movements` requieren Bearer JWT válido y capacidad explícita `financial.read` en el tenant. La API deriva el actor del subject JWT; nunca acepta actor o membership en query/body.

Parámetros opcionales:
- `status`: filtro exacto por estado.
- `pageSize`: 1–100, default 25.
- `offset`: 0–10000, default 0.

La respuesta contiene `items`, `total`, `pageSize` y `offset`; el orden es determinista (`created_at DESC, id DESC`). Las funciones PostgreSQL vuelven a validar actor, tenant y capacidad. Ktor utiliza únicamente las funciones backend-only; no realiza SELECT directo sobre tablas financieras. La falta de capacidad responde 403, parámetros inválidos 400 y errores de base de datos 503. Las rutas responden 503 si la autenticación no está configurada.

Estas consultas no calculan saldos, tasa aplicada ni importes finales y no cambian estados de negocio.


## Historial de tasas de cambio (M1.10.1)

`GET /api/v1/tenants/{tenantId}/currency-rates` requiere JWT válido y la capacidad `financial.read`. Admite `pairId` opcional para filtrar por un par configurado, además de `pageSize` (1–100, default 25) y `offset` (0–10000, default 0).

La respuesta incluye historial inmutable ordenado por `valid_from DESC, id DESC`, tasas de compra/venta, intervalo de vigencia y códigos de moneda del par. El actor se deriva del subject JWT; PostgreSQL revalida tenant y capacidad. El rol backend solo ejecuta la función de lectura y no recibe SELECT directo sobre tablas financieras. No se publica ni modifica una tasa desde esta ruta.


## Historial de auditoría financiera (M1.10.2)

La ruta `GET /api/v1/tenants/{tenantId}/events` requiere JWT válido y capacidad `financial.read`. Acepta `entityType` (CURRENCY, CURRENCY_PAIR, RATE, OPERATION, MOVEMENT o EVIDENCE_LINK), `entityId`, `pageSize` (1–100, default 25) y `offset` (0–10000, default 0). El orden es determinista por `occurred_at DESC, id DESC`.

La consulta PostgreSQL vuelve a validar actor, tenant y capacidad, y solo es ejecutable por `tucambio_backend`. Devuelve ID del evento, actor usuario, entidad, tipo de evento, correlación y timestamp; excluye deliberadamente `payload` y membership IDs. No permite modificar ni reproducir eventos.


## Asociación financiera de evidencias (M1.11.1)

`POST /api/v1/tenants/{tenantId}/evidence-links` requiere Bearer JWT válido y `Idempotency-Key`. El cuerpo contiene `evidenceId`, `targetType` (`OPERATION` o `MOVEMENT`) y `targetId`.

La evidencia debe existir en el mismo tenant y tener integridad de almacenamiento `available`. Para asociar a una operación se exige `operations.operate`; para asociar a un movimiento se exige `movements.verify`. PostgreSQL vuelve a comprobar actor, tenant y capacidad dentro del comando transaccional.

Una evidencia puede documentar una operación y un movimiento relacionado. No puede vincularse a dos movimientos distintos, evitando su reutilización silenciosa para respaldar hechos externos incompatibles. Las asociaciones son append-only y generan eventos de auditoría. Los reintentos con la misma clave y contenido son idempotentes.

La asociación no modifica `status`, `review_status`, ni el estado del movimiento. Vincular un comprobante no lo valida ni confirma un movimiento. La revisión documental y la verificación del hecho externo siguen siendo procesos separados.
