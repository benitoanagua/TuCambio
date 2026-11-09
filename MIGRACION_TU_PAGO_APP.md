# Migración de Tu-Pago-App hacia TuCambio

**Estado:** Fase de análisis y extracción de contratos  
**Origen:** `benitoanagua/Tu-Pago-App` (privado)  
**Destino:** `benitoanagua/TuCambio` (público)  
**Rama de trabajo:** `migration/tu-pago-core-extraction`

## 1. Objetivo de producto

TuCambio es la edición libre, abierta y genérica de la plataforma. Debe servir a cualquier persona u organización que compre y venda monedas, sin presuponer país, moneda base, institución financiera, proveedor de pagos ni una única casa de cambio.

Tu-Pago-App se considera una implementación de referencia y fuente de experiencia funcional. No es el molde que deba copiarse sin cambios: las reglas de negocio particulares de su operación se generalizan antes de incorporarse.

## 2. Inventario preliminar de capacidades reutilizables

| Capacidad de origen | Evidencia localizada | Decisión para TuCambio |
|---|---|---|
| Dinero decimal y cálculos exactos | `Money`, `ExchangeCalculator`, `ExchangeRateConverter` | Extraer concepto y pruebas; usar precisión/escala configurada por moneda, nunca escala fija de dos decimales global. |
| Catálogo de monedas | `CatalogoMonedas`, `Moneda` | Generalizar a códigos ISO 4217 y metadatos configurables; admitir monedas sin recompilar cuando sea razonable. |
| Par de monedas | `ParMonedas` | Conservar identidad canónica sin dirección; compra/venta se define respecto al operador y al par publicado. |
| Configuración por par | `ConfiguracionParMonedas` | Reutilizar: habilitación independiente, intervalos y disponibilidad por par/operador. |
| Cotización y vigencia | `Cotizacion`, `CotizacionesRoutes` | Reutilizar ventanas `[desde, hasta)`, historial inmutable y ausencia de solapamientos incompatibles; incorporar origen de tasa, spread y autor. |
| Calculadora | `ExchangeCalculator`, `OperacionCotizacionCalculator` | Reutilizar reglas matemáticas como base; parametrizar par, dirección, precisión y redondeo. |
| Zona horaria de transferencias | `TransferTimeZone` | Generalizar: cada movimiento declara zona/offset de origen y se normaliza a instante; no codificar ARS/BOB. |
| Ciclo de operación | FSM de solicitud y eventos | Reutilizar estados como referencia, conciliándolos con la especificación vigente de TuCambio. |
| Evidencias y comprobantes | solicitud, carga y reemplazo de comprobantes | Reutilizar múltiples evidencias, trazabilidad, validación y asociación a movimientos. |
| Movimientos y conciliación | movimientos ingreso/egreso vinculados a operaciones | Reutilizar como libro de movimientos por moneda y cuenta; no exigir cuentas pre-registradas. |
| Auditoría | `AuditoriaService`, eventos de dominio | Extraer eventos inmutables con actor, instante, entidad, acción, correlación y cambios relevantes. |
| Roles y permisos | `Rol`, `Permiso`, `RolPermisos` | Adoptar mínimo privilegio y matriz configurable por organización; no conservar roles con nombres o privilegios del producto original sin revisión. |
| Cierre y arqueo | módulos de cierre, arqueo y reportes | Reutilizar como módulos opcionales de caja/operación; diseñar saldos separados por moneda. |
| Cuentas de cobro y destinos | `CuentaCobro`, QR, datos de transferencia | Generalizar a instrumentos/canales/destinos configurables por moneda, país y proveedor. |
| Notificaciones | FCM y eventos de solicitud | Adoptar patrón basado en eventos con canales intercambiables; FCM no debe ser dependencia del dominio. |
| UI y sistema visual | Compose, componentes y guías de diseño | Referencia visual, no copiar marca, etiquetas o términos propios; mantener presentación desacoplada del dominio. |
| Tests y E2E | suites en shared/core/app/backend | Migrar como estrategia y casos, no copiar ciegamente fakes, fixtures ni dependencias. |

## 3. Reglas de generalización obligatorias

### 3.1 Monedas
- No asumir ARS, BOB, USD ni ninguna moneda como predeterminada.
- Una moneda contiene código, nombre, símbolo, precisión decimal y reglas de presentación.
- Los importes llevan moneda explícita; no se suman importes de monedas distintas sin conversión expresa.
- La precisión decimal no es universal: respetar los dígitos fraccionarios configurados para cada moneda.

### 3.2 Pares y dirección comercial
- Un par identifica dos monedas distintas y se almacena de forma canónica.
- Compra y venta se expresan desde la perspectiva del operador que publica la cotización.
- La cotización debe especificar qué moneda se entrega y cuál se recibe, o definir formalmente compra/venta respecto al par.
- No codificar fórmulas de un solo par; las fórmulas deben derivarse de la dirección y la unidad de la tasa.
- No usar defaults silenciosos para moneda de entrega, recepción, tasa o cuenta de destino.

### 3.3 Operadores y organizaciones
- La entidad principal configurable es el operador (persona o entidad) y, opcionalmente, una organización con sucursales/cajas.
- Cada operador administra sus pares habilitados, tasas, spread, horarios, límites, canales, cuentas/destinos, usuarios y permisos.
- El catálogo de monedas disponibles es global o extensible; la habilitación de un par y su tasa son configuración del operador.
- Los datos de un operador deben estar aislados de los demás (multi-tenancy).

### 3.4 Tasas
- Cada tasa define par, dirección/unidad, valor decimal, fuente, vigencia, autor y contexto del operador.
- Las tasas publicadas son históricas e inmutables; las correcciones se registran como nuevos eventos/versiones.
- La ventana de vigencia es explícita y no ambigua.
- El cálculo conserva la tasa aplicada en la operación, aunque después se publique otra.
- Redondeo, escala y tolerancia deben ser políticas visibles y versionadas.

### 3.5 Operaciones, movimientos y conciliación
- Separar intención de operación, movimiento económico real, evidencia y conciliación.
- La creación de una operación no debe simular que el dinero ya fue recibido o entregado.
- Registrar movimientos por moneda y dirección (ingreso/egreso), con cuenta/instrumento opcional o externo.
- Una conciliación debe enlazar evidencia, movimiento, monto, moneda, fecha/hora y tasa aplicada.
- Permitir múltiples evidencias y registrar reemplazos sin borrar el historial.

### 3.6 País, zona horaria e instituciones
- El país y la zona horaria pertenecen al operador, sucursal, cuenta o movimiento según corresponda.
- No derivar zona horaria del código de moneda.
- Bancos, billeteras, canales y proveedores son catálogos opcionales o texto estructurado extensible; evitar dependencias de un solo proveedor.
- Formateo local no debe alterar el valor monetario almacenado.

## 4. Qué no copiar directamente desde Tu-Pago-App

- Credenciales, tokens, claves, certificados, secretos, archivos de service account o valores de configuración de Firebase/GCP.
- Identificadores de proyectos, buckets, dominios, cuentas de despliegue, URLs privadas o referencias de producción.
- Datos reales de socios, usuarios, casas, clientes, cuentas, transferencias, comprobantes, QRs o movimientos.
- Marca Tu-Pago, logotipos, nombres de paquete `com.tupago`, textos comerciales y etiquetas de un negocio concreto.
- Defaults de ARS/BOB, zonas horarias asociadas a esas monedas, rutas y colecciones con semántica específica del negocio de origen.
- Integraciones y conceptos legacy retirados o ya no soportados.
- Configuraciones de CI/CD o despliegue antes de diseñar el pipeline independiente de TuCambio.

Los archivos de infraestructura del origen deben revisarse uno a uno. No copiar `.firebaserc`, `firebase.json`, `cloudbuild.yaml`, manifiestos de despliegue, reglas o índices sin reconstruirlos para el entorno de TuCambio.

## 5. Arquitectura destino sugerida

La arquitectura definitiva se debe decidir después de revisar los archivos completos y validar compatibilidad de dependencias. Como separación conceptual:

1. **domain**: Money/Amount, Currency, CurrencyPair, ExchangeQuote, ExchangeOperation, Movement, Evidence, Reconciliation, AuditEvent, Operator/Organization.
2. **application**: casos de uso para catálogo, pares, cotización, cálculo, operación, conciliación, liquidación, caja y reportes.
3. **ports**: repositorios, reloj, almacenamiento de evidencias, notificaciones, identidad y proveedores externos.
4. **adapters**: API/backend, persistencia, autenticación, storage, notificaciones, UI Android/web y herramientas de importación.
5. **shared contracts**: contratos serializables únicamente cuando sean verdaderamente compartidos entre clientes y backend.

El dominio no debe depender de Firebase, Ktor, Android, FCM, Compose ni un proveedor de pagos específico.

## 6. Secuencia de migración

### M0 — Inventario y saneamiento
- Enumerar árboles completos de código, documentación, pruebas y recursos del origen.
- Identificar archivos sensibles y dependencias específicas.
- Relacionar cada feature del origen con la especificación vigente de TuCambio.
- Registrar incompatibilidades sin modificar las reglas consolidadas de TuCambio.

### M1 — Núcleo monetario genérico
- Modelo de moneda configurable.
- Importe exacto con moneda/escala.
- Pares canónicos.
- Cotizaciones orientadas por dirección.
- Calculadora y políticas de redondeo.
- Pruebas unitarias de precisión, inversión, límites y pares sin defaults.

### M2 — Dominio operativo
- Operaciones compra/venta genéricas.
- Movimientos multi-cuenta y multi-moneda.
- Evidencias múltiples.
- Conciliación y tasa aplicada inmutable.
- Estados, transiciones, idempotencia y concurrencia.

### M3 — Operador, seguridad y auditoría
- Multi-tenancy.
- Usuarios/roles/permisos configurables.
- Auditoría append-only.
- Configuración por operador/sucursal/caja.
- Aislamiento y pruebas negativas de acceso.

### M4 — Aplicaciones e integraciones
- UI genérica para operador de cambio.
- Gestión de tasas, operaciones, caja, conciliación y reportes.
- Canales de pago/destino enchufables.
- Notificaciones desacopladas.
- Importación/exportación y documentación de despliegue propia.

### M5 — Validación y publicación
- Tests de dominio, integración y E2E por cada dirección y moneda.
- CI limpio desde el entorno de TuCambio.
- Revisión de secretos y datos privados.
- Licencia OSS explícita y aviso de atribución/origen cuando corresponda.
- Guías de contribución, configuración local y despliegue.

## 7. Criterios de aceptación de la migración

- Ninguna ruta crítica requiere una moneda concreta compilada.
- No existen defaults financieros silenciosos.
- Se pueden configurar al menos dos operadores aislados con catálogos/parámetros distintos.
- Se pueden crear pares arbitrarios entre monedas activas y publicar tasas para cada par.
- Los cálculos son exactos y respetan precisión y redondeo de cada moneda.
- Una operación conserva el par, dirección, cotización y política de redondeo aplicados.
- No se confunde operación, movimiento, evidencia ni conciliación.
- Los eventos de auditoría permiten reconstruir cambios relevantes.
- Los tests prueban tanto caminos válidos como intentos de cruce entre operadores.
- El repositorio público no contiene secretos, datos personales, datos bancarios ni configuraciones productivas del origen.

## 8. Observación de estado

Este documento es el mapa inicial de migración basado en el inventario y contratos visibles. No afirma que se hayan copiado o ejecutado módulos de Tu-Pago-App. Antes de trasladar código fuente, cada archivo debe pasar revisión de dependencias, sensibilidad, licencia, nombres, supuestos monetarios y cobertura de pruebas.

## 9. Decisión tecnológica: PostgreSQL administrado por Supabase (ADR-TC-001)

**Estado:** Decisión arquitectónica adoptada para el diseño destino.  
**Fecha:** 2026-11-09  
**Decisión:** Firebase deja de ser la plataforma de persistencia/backend de TuCambio. La fuente de verdad transaccional será PostgreSQL, operado mediante Supabase. Se conserva Kotlin/Ktor como backend de aplicación cuando corresponda; Supabase no obliga a trasladar la lógica de dominio a JavaScript ni a exponer escrituras financieras desde el cliente.

### 9.1 Motivo

TuCambio administra cotizaciones, operaciones de compra/venta, movimientos de dinero, saldos, conciliaciones y auditoría. Estas entidades requieren integridad referencial, restricciones consistentes, aislamiento de concurrencia y transacciones ACID en una única base relacional.

Precisión técnica: Firestore sí ofrece transacciones ACID dentro de sus límites y alcance documentados; el motivo del cambio no es afirmar que carezca por completo de atomicidad. Para el dominio de TuCambio, PostgreSQL resulta más adecuado porque ofrece un modelo relacional con foreign keys, unique/check constraints, joins, bloqueos, aislamiento transaccional configurable y funciones SQL para expresar invariantes entre múltiples entidades. Supabase proporciona PostgreSQL real y administra servicios complementarios alrededor de esa base. La decisión prioriza la integridad relacional y la capacidad de ejecutar operaciones financieras multi-entidad en una transacción SQL.

### 9.2 Componentes destino

| Necesidad | Tecnología / responsabilidad |
|---|---|
| Persistencia principal | Supabase PostgreSQL. Fuente de verdad de todo dato financiero y operativo. |
| Autenticación | Supabase Auth como proveedor de identidad, integrado con el backend. |
| API de negocio | Kotlin/Ktor como capa de aplicación y autorización de casos de uso; no duplicar reglas críticas en clientes. |
| Acceso SQL | Backend confiable conectado a PostgreSQL mediante JDBC/driver PostgreSQL y pool de conexiones. |
| Archivos y comprobantes | Supabase Storage en buckets privados; PostgreSQL guarda metadatos, hash, propietario, relación y estado. |
| Cambios en vivo | Supabase Realtime solo para notificaciones/actualización de vistas, nunca como mecanismo de consistencia financiera. |
| Tareas asíncronas | Worker/backend y patrón transactional outbox en PostgreSQL. |
| Migraciones | Migraciones SQL versionadas en Git, revisadas en PR y aplicadas de forma reproducible. |
| Observabilidad | Logs estructurados, métricas, trazas, auditoría de negocio y alertas operativas. |

### 9.3 Límites ACID y regla de oro

ACID aplica a transacciones ejecutadas dentro de PostgreSQL. No se debe afirmar que una operación distribuida entre PostgreSQL, Storage, Auth, correo, push o servicios externos sea una sola transacción ACID.

- Todo cambio que afecte operación, movimiento, saldo, cotización aplicada, conciliación o auditoría debe persistirse en una transacción PostgreSQL.
- Las invariantes críticas deben reforzarse en la base de datos con foreign keys, unique constraints, check constraints, índices y, cuando proceda, funciones SQL/PLpgSQL.
- Las escrituras que cambien varias tablas financieras deben ocurrir en una única transacción; preferir una función/caso de uso del backend que delimite explícitamente esa transacción.
- No implementar secuencias críticas como varias llamadas HTTP independientes desde el cliente.
- El saldo no debe ser un número editable sin trazabilidad: definir libro de movimientos inmutable y estrategia transaccional para proyecciones/saldos.
- Usar idempotency keys con restricciones únicas para comandos reintentables.
- Aplicar bloqueos/aislamiento adecuados ante concurrencia; documentar y probar los niveles de aislamiento y los conflictos esperados.
- Auditoría y outbox deben escribirse en la misma transacción que el cambio de negocio que describen.
- Para efectos externos, usar outbox + reintentos idempotentes/saga y estados explícitos; nunca simular atomicidad entre sistemas.

### 9.4 Seguridad y multi-tenancy

- Toda tabla de negocio que pertenezca a un operador/organización debe incluir tenant_id (o clave equivalente) y claves/relaciones que impidan referencias cruzadas entre tenants.
- Activar RLS en todas las tablas expuestas por Data API; las políticas deben denegar por defecto y filtrar por tenant y pertenencia/rol.
- El backend no debe confiar en un tenant_id enviado libremente por el cliente: debe derivarlo de la identidad y membresía autenticadas.
- El cliente móvil/web nunca recibe la service_role key ni credenciales de PostgreSQL.
- Las escrituras financieras se canalizan por casos de uso autorizados del backend. No conceder DML directo indiscriminado a clientes.
- RLS es defensa en profundidad, no reemplazo de autorización de negocio ni de constraints.
- Storage usa buckets privados y políticas de acceso por tenant; las rutas y metadatos se validan desde backend.
- Separar roles de migración, runtime y administración; runtime con privilegio mínimo.
- Probar explícitamente que un usuario de un tenant no puede leer, modificar, relacionar ni descargar datos de otro tenant.

### 9.5 Conectividad y operación

- Para un backend persistente Kotlin/Ktor, preferir conexión PostgreSQL directa cuando la red del despliegue soporte IPv6; si no, usar Supavisor en modo sesión.
- Reservar el pooler en modo transacción para cargas serverless/funciones de corta duración y verificar las limitaciones del driver (por ejemplo, prepared statements y estado de sesión).
- Ejecutar migraciones y tareas administrativas con conexión directa, no a través del pooler transaccional.
- Exigir TLS/SSL, límites de pool explícitos, timeouts y manejo de fallos/reintentos.
- Configurar backups y probar restauraciones. La recuperación point-in-time y retención dependen del plan contratado; verificarlo antes de producción.
- Los objetos de Storage requieren estrategia de backup independiente: no asumir que el backup de PostgreSQL incluye los archivos.
- Separar proyectos/entornos dev, staging y producción. Ningún secreto ni dato real de Tu-Pago-App se reutiliza.

### 9.6 Consecuencias y trabajo requerido

1. Retirar Firebase/Firestore como persistencia del dominio de TuCambio; no migrar sus colecciones como modelo final.
2. Diseñar primero el esquema relacional y sus invariantes a partir de la especificación de TuCambio.
3. Crear migraciones SQL desde cero, con datos de prueba sintéticos.
4. Mantener Auth, Storage y Realtime como servicios auxiliares de Supabase, no como fuente de verdad financiera.
5. Definir contratos Kotlin para repositorios y transacciones; mantener el dominio independiente del SDK de Supabase.
6. Implementar pruebas de integración reales contra PostgreSQL para atomicidad, rollback, restricciones, idempotencia, concurrencia y aislamiento multi-tenant.
7. Añadir pruebas de políticas RLS y Storage antes de habilitar acceso de clientes.
8. Documentar RPO/RTO, backups, restore drill, rotación de secretos y plan de recuperación.

### 9.7 Criterios de aceptación tecnológicos

- Una operación completa con sus movimientos y auditoría se confirma o revierte como unidad PostgreSQL.
- No se producen saldos negativos/duplicados ni movimientos duplicados bajo reintentos o concurrencia, salvo que una política explícita lo permita.
- Las restricciones críticas viven en PostgreSQL, no solo en validaciones de UI.
- El aislamiento entre tenants está probado en backend, SQL/RLS y Storage.
- No hay claves administrativas ni credenciales de base de datos en el cliente.
- Las migraciones reconstruyen el esquema desde una base vacía y se pueden aplicar en CI.
- Se ha probado backup y restauración de base de datos y se documentó la estrategia separada de archivos.
- Realtime y notificaciones pueden fallar temporalmente sin dejar inconsistentes las operaciones financieras.

### 9.8 Referencias oficiales

- Supabase Database overview: https://supabase.com/docs/guides/database/overview
- Connecting to Postgres (direct connection y poolers): https://supabase.com/docs/guides/database/connecting-to-postgres
- Securing your data / RLS: https://supabase.com/docs/guides/database/secure-data
- Connection pooling and limits: https://supabase.com/docs/guides/database/connecting-to-postgres/connection-pooling


## 10. Archivos y comprobantes: Supabase Storage (ADR-TC-002)

**Estado:** Decisión adoptada para el diseño e implementación inicial de infraestructura como código.  
**Fecha:** 2026-11-09

### 10.1 Servicio y capa gratuita confirmados

Supabase ofrece Supabase Storage como servicio administrado de objetos, integrado con PostgreSQL y políticas RLS. Según la tabla oficial de planes consultada el 9 de noviembre de 2026, el plan Free incluye:

| Concepto | Cuota Free |
|---|---:|
| Almacenamiento de archivos | 1 GB |
| Egress total | 5 GB |
| Tamaño máximo por archivo | 50 MB |
| Proyectos gratuitos activos | 2 por cuenta/organización según las reglas de elegibilidad |

Las cuotas de almacenamiento y egress se contabilizan a nivel de organización y se agregan entre sus proyectos. El plan Free no debe considerarse una garantía de disponibilidad para producción: los proyectos con poca actividad pueden pausarse tras 7 días; además, el plan no incluye las mismas garantías/funciones operativas de los planes pagos. El límite de 50 MB es el máximo global permitido en Free, no una recomendación para los comprobantes de TuCambio.

Referencias oficiales:
- Planes y cuotas: https://supabase.com/pricing
- Cuotas y facturación: https://supabase.com/docs/guides/platform/billing-faq
- Precio/cupo de Storage: https://supabase.com/docs/guides/storage/pricing
- Límites de carga: https://supabase.com/docs/guides/storage/uploads/file-limits
- Buckets privados: https://supabase.com/docs/guides/storage/buckets/fundamentals
- Control de acceso: https://supabase.com/docs/guides/storage/security/access-control
- Pausa por inactividad: https://supabase.com/docs/guides/platform/free-project-pausing

### 10.2 Decisión de uso

- Supabase Storage será el almacén de objetos para comprobantes y evidencias; PostgreSQL seguirá siendo la fuente de verdad de metadatos, relaciones, estados, hash y auditoría.
- Los archivos de operaciones se guardarán en el bucket privado `operation-evidence`; nunca en un bucket público.
- La migración inicial crea el bucket privado con límite de 10 MiB por archivo y MIME permitidos: PDF, JPEG, PNG y WebP. Es un límite de aplicación deliberadamente menor al máximo del plan; podrá revisarse con métricas y requisitos reales.
- No guardar binarios en columnas PostgreSQL ni confiar en nombres originales como identificadores.
- La ruta de objeto debe ser opaca y generada por el servidor, con separación por tenant y operación; no incluir nombres, correos, números de cuenta ni otros datos personales.
- El cliente no recibe `service_role`, claves secretas ni credenciales PostgreSQL.
- El backend Kotlin/Ktor autoriza la operación y la pertenencia al tenant antes de emitir una URL firmada de carga/descarga de vida corta o ejecutar la transferencia del archivo.
- La URL firmada es una credencial temporal: no registrarla en logs, analítica ni auditoría en texto completo; evitar persistirla.
- Para descargas, preferir autorización del backend y URL firmada de corta duración. No hacer públicos los comprobantes.
- Las políticas RLS de `storage.objects` deben vincularse a la tabla real de membresías/tenants cuando el esquema de identidad de TuCambio esté definido. No se crea ahora una política genérica basada en claims o rutas no verificadas. Hasta entonces, el acceso directo de clientes permanece denegado y las operaciones pasan por backend confiable.
- Los registros de metadatos deben guardar como mínimo: tenant_id, operation_id, bucket_id, object_key, MIME detectado, tamaño, SHA-256, usuario que subió, fecha, estado de validación y fecha de eliminación lógica.
- Validar contenido real del archivo, MIME detectado, tamaño, extensión permitida y malware antes de marcar una evidencia como válida. La extensión y el Content-Type enviados por el cliente no son prueba suficiente.
- La eliminación de un objeto debe ser un flujo explícito y auditado, coordinado con el estado del registro de metadatos; no borrar evidencia financiera por una sustitución silenciosa.
- Storage requiere backup/retención independiente de PostgreSQL. La recuperación de la base no restaura automáticamente los objetos. Definir exportación/replicación, retención y simulacros de restauración antes de producción.

### 10.3 Criterios de aceptación

- El bucket se crea reproduciblemente mediante migración versionada y queda privado.
- La migración limita tamaño y tipos MIME a los valores definidos.
- Ningún cliente puede listar, leer, sobrescribir o eliminar comprobantes de otro tenant.
- Ninguna clave administrativa aparece en apps móviles/web, repositorio ni logs.
- Las URLs firmadas expiran y no sustituyen la autorización del caso de uso.
- La base conserva metadatos, hash y auditoría; los objetos tienen estrategia independiente de respaldo y restauración.
- El plan Free solo se usa para desarrollo, pruebas o piloto de bajo riesgo. Antes de producción se revisan cuota, egress, pausa, backups, RPO/RTO y costo del plan elegido.


## 11. Supabase como plataforma backend completa (ADR-TC-003)

**Estado:** Decisión arquitectónica adoptada.  
**Fecha:** 2026-11-09  
**Alcance:** Adoptar los servicios Supabase que aportan valor al producto, sin convertir cada servicio disponible en una dependencia obligatoria ni duplicar la lógica financiera.

TuCambio utilizará Supabase como plataforma backend integrada. PostgreSQL será el núcleo; Auth, RLS, Storage, Realtime, Edge Functions, Cron, Queues y Vault se incorporarán según las responsabilidades descritas en este ADR. Kotlin/Ktor se conserva como backend principal de los casos de uso financieros y de autorización.

### 11.1 Catálogo de servicios y decisión

| Servicio Supabase | Decisión en TuCambio | Responsabilidad |
|---|---|---|
| Postgres Database | **Base obligatoria** | Fuente de verdad relacional; constraints, transacciones, índices, funciones, auditoría y outbox. |
| Supabase Auth | **Adoptar** | Registro, inicio/cierre de sesión, recuperación, verificación de email, OTP/magic link, OAuth según configuración y gestión de sesiones. |
| JWT + RLS | **Adoptar obligatoriamente** | Identidad autenticada y aislamiento de filas por tenant; políticas de mínimo privilegio. |
| Storage | **Adoptar** | Evidencias y comprobantes en buckets privados. |
| Realtime | **Adoptar selectivamente** | Actualización de vistas, avisos de cambios y presencia operativa no crítica; nunca confirmar dinero ni reemplazar lecturas consistentes. |
| Edge Functions | **Adoptar para tareas acotadas** | Webhooks, callbacks, integraciones externas pequeñas, endpoints auxiliares y tareas cercanas al usuario. No alojar el núcleo de operaciones financieras si requiere transacciones largas o lógica compartida Kotlin. |
| Supabase Queues | **Adoptar cuando se active procesamiento asíncrono** | Cola durable basada en Postgres para trabajos, reintentos y consumidores; usar junto con outbox/idempotencia. |
| Supabase Cron | **Adoptar para programación** | Expiración de cotizaciones, limpieza lógica/retención, recordatorios, conciliaciones programadas y disparo de workers; cada tarea idempotente y auditable. |
| Supabase Vault | **Adoptar para secretos usados dentro de Postgres** | Guardar secretos de integraciones y credenciales que necesiten funciones SQL/Cron; no sustituye el gestor de secretos del backend ni permite exponer secretos al cliente. |
| Data API / PostgREST | **Disponible, uso restringido** | Consultas autorizadas y operaciones simples protegidas por RLS. No publicar escrituras financieras sensibles ni conceder DML general al cliente. |
| GraphQL | **Opcional, no inicial** | Evaluar solo si aparece un consumidor que lo justifique; no duplicar contratos Ktor sin necesidad. |
| Database Webhooks / pg_net | **Opcional y acotado** | Disparar integraciones no críticas mediante outbox o eventos; nunca dentro de la ruta de confirmación financiera. |
| Database Extensions | **Adoptar según necesidad** | Extensiones oficiales/soportadas para UUID, criptografía, scheduling, búsqueda u observabilidad, verificando compatibilidad y coste. |
| AI / pgvector | **No activar en el núcleo** | Futuro uso opcional para búsqueda semántica de documentos/ayuda; jamás para decidir tasas, verificar comprobantes o autorizar movimientos. |
| Supabase Studio / CLI / Management API | **Adoptar para operación** | Administración, desarrollo local, migraciones, configuración y despliegue reproducible. Management API requiere credenciales administrativas solo en CI/operaciones seguras. |
| Logs, métricas y plataforma | **Adoptar** | Observabilidad de DB, Auth, Storage, Edge Functions y servicios; correlación con request_id y audit events propios. |

### 11.2 Supabase Auth: identidad de toda la plataforma

Supabase Auth será el proveedor de identidad para aplicaciones web/móvil y usuarios del backend.

Métodos previstos, habilitados por etapa:
- Email + contraseña con verificación.
- Magic link y OTP por email para acceso passwordless.
- OAuth (por ejemplo Google o Apple) cuando se configuren credenciales y redirect URLs propias.
- Teléfono/SMS solo si el producto y el coste del proveedor lo justifican; no activarlo por defecto.
- MFA con TOTP para administradores y operadores con capacidades sensibles; definir obligatoriedad por política y nivel de riesgo.

Reglas:
1. `auth.users.id` es el identificador externo de identidad; no guardar contraseñas ni replicar credenciales en tablas propias.
2. Crear un perfil de aplicación separado y una relación explícita usuario–tenant–permisos. Un usuario puede pertenecer a más de un operador/organización si la política del producto lo permite.
3. No convertir `user_metadata` editable por el usuario en fuente de autorización. Los permisos y la pertenencia se resuelven desde tablas controladas por backend/DB y claims confiables.
4. Validar JWT, emisor, audiencia, expiración y firma en Kotlin/Ktor usando el mecanismo/JWKS recomendado por Supabase; nunca aceptar un UUID de usuario enviado en el body como prueba de identidad.
5. El backend deriva actor y tenant de la sesión autenticada y consulta membresías/roles vigentes.
6. RLS debe usar identidad y membresía verificadas; las políticas deben cubrir SELECT/INSERT/UPDATE/DELETE por separado y aplicar default deny.
7. Revocación, cierre de sesión, expiración y refresh de sesiones se deben contemplar en backend y clientes.
8. La cuenta Auth no equivale a un operador comercial: una persona puede tener identidad y luego recibir una invitación a uno o más tenants.
9. Invitaciones, altas, bajas y cambios de permisos deben generar eventos de auditoría.
10. MFA UI no basta: las operaciones sensibles deben exigir AAL apropiado también en backend/RLS según la política adoptada.

No se fija todavía el esquema SQL de perfiles, tenants, membresías e invitaciones: se definirá junto con el modelo relacional de M1/M3 para que las claves compuestas, pertenencia multi-tenant y capacidades de la especificación funcional queden coherentes.

### 11.3 Autorización y límites de API

- Kotlin/Ktor es el punto de entrada canónico para los comandos de negocio: crear operación, registrar movimiento, verificar, aplicar tasa, asociar evidencia, liquidar y resolver incidencias.
- La Data API de Supabase no es una autorización implícita. Toda tabla expuesta requiere grants mínimos y RLS probada.
- Para clientes, se permiten lecturas directas únicamente donde simplifiquen la experiencia y la política RLS sea suficiente y comprobada.
- Las operaciones que cambian hechos económicos se ejecutan en una transacción PostgreSQL única, iniciada por Ktor o por una función SQL explícita llamada por Ktor.
- No usar Edge Functions para eludir la autorización del backend ni para crear una segunda implementación de las reglas de dominio.
- Las claves publishable/anon pueden estar en clientes según el modelo de Supabase; las secret/service-role keys, claves SQL y credenciales administrativas solo en entornos confiables. Las claves privilegiadas pueden omitir RLS.
- No exponer el esquema `auth` ni tablas internas del proveedor a través de vistas o APIs públicas.

### 11.4 Eventos en vivo, colas y programación

- Realtime se limita a refrescar listas/estados y notificar cambios ya confirmados en Postgres. El cliente debe poder recuperar el estado canónico con una consulta HTTP/SQL posterior.
- No enviar comprobantes, tokens, datos bancarios completos ni payloads sensibles en canales Broadcast/Presence.
- Para trabajo asíncrono, escribir el evento/outbox en la misma transacción del negocio y procesarlo con Queues/worker. Los consumidores son idempotentes y registran intentos, errores y resultado.
- Cron programa tareas; no es una cola ni un mecanismo de exclusión mutua. Cada job debe ser reentrante, con límites, lock/idempotency key y registro de ejecución.
- Los webhooks externos se verifican criptográficamente, se deduplican y se procesan fuera de la transacción original.

### 11.5 Secretos, configuración y despliegue

- Vault guarda secretos que deban ser leídos desde funciones SQL/pg_cron; controlar acceso y rotación.
- Secretos de Ktor se inyectan desde el gestor de secretos del entorno de ejecución (no desde código ni tablas públicas).
- Separar proyectos Supabase para desarrollo, staging y producción.
- Supabase CLI y migraciones SQL versionadas son la fuente reproducible de schema/configuración; los cambios de Dashboard se reflejan luego en Git.
- CI aplica migraciones en base efímera/local y ejecuta pruebas de RLS, Auth, Storage y transacciones. Despliegue productivo requiere aprobación y secretos protegidos.
- Backups de PostgreSQL y backups/exportaciones de Storage se diseñan y prueban por separado.
- Medir cuotas y límites del plan: Auth MAU, Storage, egress, Realtime, Edge Function invocations, base de datos, compute, backups y logs. No asumir que todos los servicios o add-ons tienen cuota gratuita ilimitada.

### 11.6 Orden de implementación

1. **M1.1** PostgreSQL: esquema base, tenants, usuarios/perfiles, membresías, capacidades, constraints e índices.
2. **M1.2** Auth: flujos de sesión, validación JWT Ktor, verificación email, recuperación, invitaciones y políticas de sesión.
3. **M1.3** RLS: aislamiento tenant, permisos por capacidad y pruebas negativas por cada tabla.
4. **M1.4** Storage: metadatos de evidencias, rutas privadas, URLs firmadas y autorización tenant-aware.
5. **M1.5** Dominio financiero: operaciones, movimientos, tasas, idempotencia, auditoría y transacciones.
6. **M1.6** Realtime: suscripciones solo a cambios autorizados y recuperación de estado canónico.
7. **M1.7** Outbox + Queues + worker: procesamiento fiable de tareas asíncronas.
8. **M1.8** Cron + Vault + Edge Functions: automatizaciones, secretos de integraciones y webhooks.
9. **M1.9** Observabilidad, backups, restore drills, límites y optimización de costes.

### 11.7 Criterios de aceptación de plataforma

- El usuario se autentica con Supabase Auth y Ktor valida el JWT antes de ejecutar cualquier caso de uso protegido.
- La autorización de tenant/permiso proviene de membresías vigentes, no de metadata editable del cliente.
- Las políticas RLS impiden lectura/escritura cruzada incluso si un cliente manipula IDs.
- Un usuario puede tener membresías diferenciadas sin duplicar identidad.
- MFA se aplica a las acciones/cuentas de alto riesgo en backend, no solo en UI.
- Realtime no puede cambiar el estado financiero y su caída no afecta integridad.
- Todo trabajo asíncrono tiene outbox, idempotencia, reintentos y trazabilidad.
- Cron y Edge Functions no contienen lógica financiera duplicada ni secretos expuestos.
- No hay service-role/secret keys en artefactos públicos o clientes.
- Migraciones y configuración se reproducen desde Git en entorno limpio.
- Los límites/costes de cada servicio están monitorizados antes de producción.

### 11.8 Referencias oficiales

- Plataforma Supabase: https://supabase.com/docs/guides/platform
- Arquitectura: https://supabase.com/docs/guides/getting-started/architecture
- Auth: https://supabase.com/docs/guides/auth
- MFA: https://supabase.com/docs/guides/auth/auth-mfa
- RLS y seguridad: https://supabase.com/docs/guides/database/secure-data
- Edge Functions: https://supabase.com/docs/guides/functions
- Cron: https://supabase.com/docs/guides/cron
- Programar Edge Functions: https://supabase.com/docs/guides/functions/schedule-functions
- Queues: https://supabase.com/docs/guides/queues
- Vault: https://supabase.com/docs/guides/database/vault
- Supabase CLI: https://supabase.com/docs/guides/cli


## 12. Backend Kotlin/Ktor y alojamiento MVP (ADR-TC-004)

**Estado:** decisión adoptada para la base técnica del MVP; despliegue remoto pendiente.  
**Fecha:** 2026-11-09

### 12.1 Decisión

- Backend de aplicación: Kotlin/JVM + Ktor 3.6.1.
- Runtime: JDK 21.
- Build: Gradle 9.2.1.
- Servidor HTTP: Ktor Netty.
- Empaquetado: distribución JVM dentro de imagen Docker multi-stage.
- Hosting del backend: Google Cloud Run.
- Plataforma de datos: Supabase (PostgreSQL, Auth, Storage y servicios seleccionados).
- CI: GitHub Actions compila, ejecuta pruebas y construye el contenedor. No publica ni despliega automáticamente en esta etapa.

Versiones elegidas según releases estables consultadas el 9 de noviembre de 2026. Referencias:
- Ktor releases: https://ktor.io/docs/releases.html
- Kotlin releases: https://kotlinlang.org/docs/releases.html
- Cloud Run container deployment: https://docs.cloud.google.com/run/docs/deploying

### 12.2 Responsabilidades

Cloud Run ejecuta el proceso Ktor como contenedor stateless. Supabase no aloja el proceso JVM; proporciona PostgreSQL y servicios backend administrados. Ktor es la entrada canónica de los comandos financieros, valida JWT de Supabase, resuelve tenant/capacidades y delimita transacciones PostgreSQL.

No se adopta microservicios, Kubernetes, VM permanente ni Edge Functions como sustituto del backend Kotlin para el MVP.

### 12.3 Perfil inicial Cloud Run

Parámetros iniciales sujetos a medición y revisión:
- CPU: 1 vCPU.
- Memoria: 512 MiB.
- Instancias mínimas: 0.
- Instancias máximas: 2.
- Concurrencia: 40 solicitudes por instancia.
- Puerto: 8080.

El máximo de instancias debe considerarse junto con el tamaño del pool PostgreSQL y los límites de conexiones de Supabase. La escala a cero reduce coste en inactividad, pero introduce latencia de arranque en la primera solicitud.

La región de Cloud Run se decide junto con la región de Supabase y se valida midiendo latencia real entre servicio y base de datos. No se fija una región sin conocer el proyecto de destino.

### 12.4 Base de aplicación entregada

Se incorpora el esqueleto en `backend/`:
- aplicación Ktor con rutas `/`, `/health/live` y `/health/ready`;
- pruebas HTTP para esos endpoints;
- configuración Gradle con toolchain JDK 21;
- Dockerfile multi-stage y runtime no-root;
- ejemplo de variables sin secretos;
- guía de ejecución y despliegue Cloud Run.

Mientras no se conecten PostgreSQL y Auth, `/health/ready` confirma únicamente que el proceso HTTP está inicializado; no representa una comprobación de disponibilidad de dependencias externas.

### 12.5 CI y límites de automatización

El workflow `.github/workflows/backend-ci.yml` ejecuta tests, genera la distribución e intenta construir la imagen Docker en pull requests y pushes relevantes. No necesita secretos cloud.

Fuera de alcance automático por ahora:
- publicar imágenes en Artifact Registry;
- crear proyecto, repositorio de imágenes o recursos Cloud Run;
- desplegar revisiones;
- crear/configurar proyecto Supabase;
- crear secretos o asignar IAM;
- habilitar acceso público.

Estas acciones requieren proyecto, región, facturación, IAM, secretos y configuración de seguridad reales. Se harán en una fase posterior, con valores explícitos y aprobación operativa.

### 12.6 Criterios de aceptación

- La aplicación arranca en local con JDK 21 y escucha en el puerto `PORT`.
- Health checks responden HTTP 200 y no revelan información sensible.
- Los tests HTTP corren en CI.
- La imagen se construye con runtime JRE y usuario no privilegiado.
- El contenedor escucha en 8080 y respeta `PORT`.
- Ningún secreto ni credencial real aparece en archivos, workflow, logs o imagen.
- El pipeline no despliega infraestructura ni publica imágenes.
- La conexión a PostgreSQL/Auth se añade después de definir esquema, membresías y validación JWT.
