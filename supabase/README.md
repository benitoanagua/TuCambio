# Plataforma Supabase de TuCambio

**Estado:** arquitectura adoptada; implementación progresiva.  
**Fuente de verdad:** `MIGRACION_TU_PAGO_APP.md`, ADR-TC-001, ADR-TC-002 y ADR-TC-003.

## Principio

TuCambio adopta Supabase como plataforma backend integrada, no solo como hosting PostgreSQL. Cada servicio se usa donde aporta valor, pero no se duplica la lógica financiera ni se activa infraestructura sin un caso de uso.

Postgres es el núcleo transaccional. Supabase Auth identifica usuarios. Las membresías y permisos de TuCambio autorizan acciones. Kotlin/Ktor ejecuta los casos de uso de negocio. RLS aplica aislamiento en profundidad.

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
3. Un usuario puede recibir invitaciones y tener membresías en varios tenants.
4. Los permisos de negocio se modelan como capacidades (OPERAR, VERIFICAR, LIQUIDAR, GESTIONAR TASAS, GESTIONAR CONFIGURACIÓN, ADMINISTRAR); los roles son agrupaciones configurables.
5. Ktor valida JWT (firma/JWKS, issuer, audience y expiración), obtiene el actor y consulta la membresía y sus permisos vigentes.
6. No usar `user_metadata` editable como fuente de autorización.
7. RLS protege las tablas expuestas con default deny y tenant membership comprobada.
8. MFA TOTP se recomienda para administradores y acciones sensibles; la exigencia se valida en backend/RLS, no solo en la interfaz.
9. OAuth, SMS y SSO solo se habilitan cuando haya credenciales, dominio, redirect URLs, política y coste aprobados.

**M1.1 implementado en migración versionada:** perfiles, tenants, membresías, roles configurables, catálogo de capacidades, asignaciones, invitaciones y auditoría de seguridad. El detalle del contrato está en [IDENTITY.md](./IDENTITY.md). Las tablas tienen RLS habilitado y no conceden acceso a `anon` ni `authenticated`: el estado inicial es default deny. Las políticas específicas y sus pruebas negativas se incorporan en M1.5; no se habilita acceso directo de clientes todavía.

## Flujos críticos

### Comandos financieros
Cliente → Ktor → autorización Auth/JWT + tenant/capacidad → transacción PostgreSQL → auditoría + outbox → commit.  
El cliente nunca confirma una operación mediante una secuencia de escrituras directas a varias tablas.

### Evidencias
Cliente → Ktor autoriza tenant/operación → Storage privado → validación de contenido → metadatos y hash en PostgreSQL → revisión humana/flujo de negocio.  
Subir un comprobante no confirma el movimiento.

### Actualizaciones en vivo
Postgres confirma el cambio → Realtime notifica/actualiza la vista → cliente recupera estado canónico.  
Realtime no es fuente de verdad ni canal para secretos, comprobantes o datos bancarios completos.

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

- [x] M1.1 Esquema PostgreSQL multi-tenant y modelo de membresías/capacidades (migración versionada y prueba de aislamiento entre tenants).
- [x] M1.2 Ktor: validación de firma/JWKS, issuer, audience, expiración y UUID del actor; sin tenant/capacidades todavía.
- [ ] M1.3 Supabase Auth: registro, login, logout, refresh, verificación y recuperación mediante flujos administrados por Auth.
- [ ] M1.4 Ktor: resolución de membresía activa y autorización por capacidades.
- [ ] M1.5 RLS: políticas y pruebas negativas de aislamiento.
- [ ] M1.6 Storage: metadatos, validación y autorización tenant-aware.
- [ ] M1.7 Operaciones/movimientos/tasas con transacciones e idempotencia.
- [ ] M1.8 Realtime para vistas autorizadas.
- [ ] M1.9 Outbox, Queues y worker.
- [ ] M1.10 Cron, Vault y Edge Functions para integraciones.
- [ ] M1.11 CI, observabilidad, backup/restore y control de costes.

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
