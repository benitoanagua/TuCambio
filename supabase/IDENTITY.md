# Esquema de identidad y autorización multi-tenant

**Milestone:** M1.1 / M1.4 / M1.5 / M1.6  
**Estado:** implementado en migraciones SQL y backend Ktor; pendiente aplicar y validar en un proyecto Supabase real.

## Modelo

- `auth.users` es la identidad externa administrada por Supabase Auth. TuCambio no replica contraseñas ni usa `user_metadata` para autorizar.
- `profiles` contiene preferencias y datos de presentación; no concede acceso a ningún tenant.
- `tenants` representa una casa de cambio u organización independiente.
- `tenant_memberships` relaciona identidad y tenant; una identidad puede pertenecer a varios tenants.
- `capabilities` es el catálogo estable de capacidades de negocio.
- `tenant_roles` permite que cada tenant cree agrupaciones de permisos.
- `tenant_role_capabilities` asigna capacidades a roles.
- `membership_roles` asigna roles a una membresía concreta.
- `tenant_invitations` registra invitaciones por email y almacena solo hash SHA-256 del token.
- `tenant_invitation_roles` define los roles propuestos al aceptar una invitación.
- `tenant_security_audit_events` conserva eventos de administración de acceso.

## Catálogo inicial de capacidades

| Código | Capacidad funcional |
|---|---|
| `operations.operate` | OPERAR |
| `movements.verify` | VERIFICAR |
| `operations.settle` | LIQUIDAR |
| `rates.manage` | GESTIONAR TASAS |
| `settings.manage` | GESTIONAR CONFIGURACIÓN |
| `tenant.administer` | ADMINISTRAR miembros, invitaciones y permisos |

Los roles son agrupaciones configurables por tenant; los códigos de capacidad son el vocabulario estable que evalúa el backend.

## Invariantes de integridad

1. La identidad Auth y la membresía de negocio son conceptos distintos.
2. La unicidad `(tenant_id, user_id)` evita membresías duplicadas en un tenant.
3. Las claves foráneas compuestas impiden referencias y asignaciones cruzadas entre tenants.
4. Una membresía revocada o suspendida se conserva para trazabilidad y no autoriza nuevas acciones.
5. Una invitación guarda un hash de 32 bytes, expira y puede aceptarse o revocarse, pero no ambas cosas.
6. La aceptación de invitaciones comprueba token, expiración, email verificado y estado del tenant en una transacción backend.
7. La creación inicial de tenant debe crear primera membresía y rol administrativo en un flujo controlado.
8. Los eventos de seguridad enlazan el actor con su membresía dentro del tenant.

## Seguridad

- RLS habilitado en las tablas de identidad.
- `anon` no recibe acceso.
- `authenticated` recibe solo SELECT filtrado por RLS; no DML directo.
- Ktor valida JWT y consulta membresías/roles vigentes. El tenant ID solicitado nunca demuestra pertenencia.
- Credenciales administrativas de base de datos permanecen exclusivamente en servidor.
- La función de resolución de autorización es `SECURITY DEFINER`, con `search_path` fijo y EXECUTE reservado al rol backend.
- No hay BYPASSRLS ni grants directos de tablas al rol grupal `tucambio_backend`.

## Evidencias privadas (M1.6 completado)

- `tenant_evidence` conserva tenant, creador, bucket, ruta determinista, MIME declarado, tamaño esperado, SHA-256 y estado técnico (`pending`, `available`, `rejected`).
- La ruta es `<tenant_uuid>/<evidence_uuid>`; el cliente no selecciona bucket ni ruta arbitraria.
- El bucket `operation-evidence` es privado. Límite por archivo: 10 MiB. Tipos admitidos: PDF, JPEG, PNG y WebP.
- Solo `tucambio_backend` puede ejecutar funciones de creación/finalización. No tiene grants directos de tabla ni BYPASSRLS.
- Storage permite INSERT únicamente para metadata pending creada por backend, por el mismo usuario y con MIME/tamaño coincidentes. SELECT solo para evidencia available y miembros con capacidad vigente.
- Ktor ofrece endpoints para crear metadata y URL de carga, completar tras inspección binaria y emitir URL de descarga temporal.
- Ktor verifica tamaño real, firma binaria MIME y SHA-256 antes de finalizar. Las URLs firmadas son bearer tokens: no registrarlas ni persistirlas innecesariamente.
- `SUPABASE_SERVICE_ROLE_KEY` omite RLS y queda exclusivamente en Ktor, después de autorización explícita en PostgreSQL.
- El análisis antivirus/antimalware, extracción de contenido, retención y asociación financiera siguen pendientes antes de producción.

## Pruebas y límites operativos

El workflow valida migraciones en PostgreSQL 17, pruebas SQL de privilegios/aislamiento, pruebas Kotlin y construcción Docker. Esto no sustituye una validación en proyecto Supabase administrado.

No se han aplicado migraciones a Supabase remoto ni desplegado infraestructura. El ciclo de registro/login/logout/refresh/verificación/recuperación del cliente (M1.3) continúa pendiente.
