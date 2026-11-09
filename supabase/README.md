# Plataforma Supabase de TuCambio

**Estado:** arquitectura adoptada; implementación progresiva.  
**Fuente de verdad:** `MIGRACION_TU_PAGO_APP.md`, ADR-TC-001, ADR-TC-002 y ADR-TC-003.

## Principio

Supabase es la plataforma backend integrada, no solo hosting PostgreSQL. Postgres es el núcleo transaccional; Supabase Auth identifica usuarios; las membresías y permisos de TuCambio autorizan acciones; Kotlin/Ktor ejecuta los casos de uso de negocio; RLS aplica aislamiento en profundidad.

## Mapa de servicios

| Componente | Uso |
|---|---|
| PostgreSQL | Datos financieros, configuración, auditoría, outbox y restricciones ACID |
| Auth | Identidad, sesiones, email, OTP/magic link, OAuth según configuración, MFA |
| RLS | Aislamiento por tenant y control de acceso a filas |
| Storage | Evidencias en buckets privados |
| Realtime | Refresco de vistas y notificaciones de cambios confirmados |
| Edge Functions | Webhooks e integraciones pequeñas, auxiliares y de baja latencia |
| Queues | Procesamiento asíncrono durable y reintentos |
| Cron | Trabajos programados y disparo de procesos |
| Vault | Secretos usados por funciones SQL/Cron |
| Data API / PostgREST | Lecturas autorizadas y operaciones simples sujetas a RLS; no reemplaza Ktor para comandos financieros |
| GraphQL | Opcional; no habilitado inicialmente |
| pgvector / AI | Futuro opcional para búsqueda documental, nunca decisiones financieras |
| CLI / Studio / Management API | Desarrollo, migraciones, administración y despliegue |
| Logs / métricas | Observabilidad de plataforma y correlación con auditoría propia |

## Autenticación y autorización

1. Supabase Auth mantiene la identidad; TuCambio no almacena contraseñas.
2. `auth.users.id` referencia el perfil interno. La identidad no implica automáticamente pertenencia a un operador.
3. Un usuario puede tener membresías en varios tenants.
4. Los permisos de negocio se modelan como capacidades estables; los roles son agrupaciones configurables por tenant.
5. Ktor valida JWT (firma/JWKS, issuer, audience y expiración), obtiene el actor y consulta membresía/capacidades vigentes.
6. No usar `user_metadata` editable como fuente de autorización.
7. RLS protege tablas expuestas con default deny y membresía comprobada.
8. MFA para administradores y acciones sensibles se exige en backend/RLS, no solo en interfaz.
9. OAuth, SMS y SSO solo se habilitan con credenciales, dominio, redirect URLs, política y coste aprobados.

**M1.1–M1.5 implementados en migraciones versionadas:** identidad multi-tenant, JWT Ktor, resolución de membresía/capacidades y políticas RLS de lectura.  
**M1.6 implementado:** metadata y políticas Storage privadas, junto con endpoints Ktor para iniciar carga, verificar bytes/tamaño/firma MIME/SHA-256, finalizar y emitir URL de descarga temporal. La clave service-role permanece exclusivamente en Ktor y se usa después de autorización PostgreSQL. El detalle está en [IDENTITY.md](./IDENTITY.md) y [backend/README.md](../backend/README.md).

## Flujos críticos

### Comandos financieros

Cliente → Ktor → JWT + autorización tenant/capacidad → transacción PostgreSQL → auditoría + outbox → commit. El cliente nunca confirma una operación mediante escrituras directas a varias tablas.

### Evidencias

Cliente → Ktor autoriza tenant → Storage privado → inspección de contenido → metadata/hash en PostgreSQL → asociación/revisión del flujo de negocio. Subir un comprobante no confirma el movimiento. M1.6 valida tamaño, firma de archivo y SHA-256; análisis antimalware y asociación al dominio se mantienen como trabajo pendiente antes de producción.

### Actualizaciones en vivo

Postgres confirma el cambio → Realtime notifica/actualiza la vista → cliente recupera estado canónico. Realtime no es fuente de verdad ni canal para secretos, comprobantes o datos bancarios completos.

### Procesamiento asíncrono

Transacción de negocio escribe outbox → worker/Queues procesa → reintentos idempotentes → estado y resultado auditados. Cron programa trabajos; no sustituye a una cola.

### Integraciones externas

Webhook/Edge Function verifica firma, timestamp y deduplicación → registra evento/outbox → worker/backend procesa. Ninguna llamada externa bloquea la transacción financiera.

## Seguridad obligatoria

- No publicar service-role/secret keys ni credenciales SQL.
- Buckets privados; URLs firmadas de corta duración y nunca registradas completas.
- RLS y grants mínimos en todo esquema expuesto por Data API.
- El tenant se deriva de membresía autenticada, nunca del tenant_id libre enviado por el cliente.
- No confiar en claims personalizados hasta definir cómo se emiten y refrescan; consultar membresías vigentes para permisos revocables.
- MFA para cuentas/acciones de riesgo.
- Rate limits y protección anti-abuso para Auth, endpoints públicos y webhooks.
- Cifrado TLS en tránsito y secretos en gestores apropiados.
- Auditoría append-only para cambios de permisos, identidad, operación, movimiento y evidencia.
- Restauración PostgreSQL y recuperación de objetos Storage se prueban por separado.

## Planes, límites y costes

El plan Free sirve para desarrollo y pilotos de bajo riesgo, no como compromiso de disponibilidad productiva. Vigilar MAU de Auth, almacenamiento/egress, Realtime, invocaciones Edge, cómputo DB, backups, logs y límites de conexiones. Revisar precios y cuotas oficiales antes de dimensionar producción.

## Secuencia

- [x] M1.1 Esquema PostgreSQL multi-tenant y modelo de membresías/capacidades.
- [x] M1.2 Ktor: validación de firma/JWKS, issuer, audience, expiración y UUID del actor.
- [ ] M1.3 Supabase Auth cliente: registro, login, logout, refresh, verificación y recuperación (integración de cliente pendiente).
- [x] M1.4 Ktor: resolución de membresía activa y capacidades vigentes desde PostgreSQL.
- [x] M1.5 RLS: políticas de lectura autenticada por tenant, helpers y pruebas negativas de aislamiento.
- [x] M1.6 Storage: bucket privado, metadata, límites, funciones backend-only, políticas tenant-aware y adaptador HTTP Ktor de carga/inspección/descarga.
- [ ] M1.7 Dominio financiero: monedas/pares, tasas, operaciones y movimientos con transacciones e idempotencia. Contrato técnico inicial: [FINANCIAL_DOMAIN.md](./FINANCIAL_DOMAIN.md). No codificar políticas de negocio todavía abiertas.
- [ ] M1.8 Realtime para vistas autorizadas.
- [ ] M1.9 Outbox, Queues y worker.
- [ ] M1.10 Cron, Vault y Edge Functions para integraciones.
- [ ] M1.11 Observabilidad, backup/restore y control de costes.

## Pendientes previos a producción

- Análisis antimalware/antivirus y política de retención de evidencias.
- Asociación de evidencias a operaciones/movimientos con auditoría.
- Integración de ciclo de sesión del cliente con Supabase Auth (M1.3).
- Validación administrada en un proyecto Supabase real, después de disponer de configuración y aprobación.
- Provisionamiento de secretos, IAM, Cloud Run, backup/restore y monitorización; no automatizar ni ejecutar sin autorización operativa.

## Documentación oficial

- https://supabase.com/docs/guides/platform
- https://supabase.com/docs/guides/getting-started/architecture
- https://supabase.com/docs/guides/auth
- https://supabase.com/docs/guides/auth/auth-mfa
- https://supabase.com/docs/guides/database/secure-data
- https://supabase.com/docs/guides/functions
- https://supabase.com/docs/guides/queues
- https://supabase.com/docs/guides/cron
- https://supabase.com/docs/guides/database/vault
- https://supabase.com/docs/guides/cli
