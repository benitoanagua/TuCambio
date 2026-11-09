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

Firebase/Firestore no ofrece el mismo modelo relacional/transaccional de PostgreSQL para este dominio. Supabase proporciona PostgreSQL real, con transacciones, constraints, claves foráneas, índices, SQL y mecanismos de control de acceso a nivel de fila. La decisión prioriza la base de datos transaccional como núcleo del sistema, no una base documental NoSQL.

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
