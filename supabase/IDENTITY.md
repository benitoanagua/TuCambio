# Esquema de identidad y autorización multi-tenant

**Milestone:** M1.1 / M1.4 / M1.5 / M1.6  
**Estado:** implementado como migración SQL; pendiente aplicar y validar en un proyecto Supabase real.  
**Migración:** `20261109000200_identity_multitenant_schema.sql`

## Modelo

- `auth.users` es la identidad externa administrada por Supabase Auth. TuCambio no replica contraseñas ni usa `user_metadata` para autorizar.
- `profiles` contiene preferencias y datos de presentación de la persona; no concede acceso a ningún tenant.
- `tenants` representa una casa de cambio u organización independiente.
- `tenant_memberships` relaciona una identidad con un tenant. Una identidad puede pertenecer a varios tenants. La pertenencia tiene estado propio y no se infiere del perfil.
- `capabilities` es el catálogo estable de capacidades de negocio.
- `tenant_roles` permite que cada tenant cree sus agrupaciones de permisos.
- `tenant_role_capabilities` asigna capacidades a roles.
- `membership_roles` asigna roles a una membresía concreta.
- `tenant_invitations` registra invitaciones por email. Solo se almacena el hash SHA-256 del token, nunca el token en claro.
- `tenant_invitation_roles` define los roles propuestos al aceptar una invitación.
- `tenant_security_audit_events` conserva eventos de administración de acceso vinculados al actor y a su membresía en el tenant.

## Catálogo inicial de capacidades

| Código | Capacidad funcional |
|---|---|
| `operations.operate` | OPERAR |
| `movements.verify` | VERIFICAR |
| `operations.settle` | LIQUIDAR |
| `rates.manage` | GESTIONAR TASAS |
| `settings.manage` | GESTIONAR CONFIGURACIÓN |
| `tenant.administer` | ADMINISTRAR miembros, invitaciones y permisos |

Los roles son agrupaciones configurables por tenant; los códigos de capacidad son el vocabulario estable que evalúa el backend. No se importan nombres ni privilegios rígidos de roles históricos.

## Invariantes de integridad

1. La identidad Auth y la membresía de negocio son conceptos distintos.
2. La unicidad `(tenant_id, user_id)` evita membresías duplicadas en un mismo tenant.
3. Las claves foráneas compuestas obligan a que una asignación de rol, invitación o evento de auditoría pertenezca al mismo tenant de sus referencias.
4. Una membresía revocada o suspendida no se elimina para conservar trazabilidad; su estado impide autorizar nuevas acciones.
5. Una invitación guarda un hash de 32 bytes, expira y puede aceptarse o revocarse, pero no ambas cosas.
6. La aceptación de invitaciones debe comprobar token, expiración, email verificado y estado del tenant en una transacción del backend; la migración no crea un endpoint ni un trigger que acepte invitaciones automáticamente.
7. La creación inicial de un tenant debe crear su primera membresía y el rol administrativo en un flujo controlado. No se permite que cualquier usuario se autoasigne `tenant.administer`.
8. Los eventos de seguridad enlazan el usuario actor con su membresía dentro del tenant.

## Seguridad en esta etapa

- RLS queda habilitado en todas las tablas del esquema.
- No se crean políticas permisivas todavía. El comportamiento es **default deny**.
- Se revocan privilegios de tabla de `anon` y `authenticated`.
- M1.5 concede únicamente SELECT a authenticated y lo filtra mediante políticas RLS. No se concede DML directo al cliente; las escrituras siguen en Ktor. La función de resolución M1.4 queda reservada al rol backend.
- Ktor consultará la identidad validada y las membresías/roles vigentes. La selección de tenant solicitada por el cliente se valida contra esa membresía; nunca se acepta como autoridad.
- Las credenciales administrativas de base de datos permanecen exclusivamente en el entorno servidor.
- No hay triggers automáticos de perfil, invitación, timestamps o auditoría en esta migración. Los cambios de seguridad deben entrar por casos de uso explícitos de Ktor y registrar su evento en la misma transacción.

## Decisiones diferidas

- Flujo de bootstrap del primer tenant/administrador.
- Política de invitaciones, expiración y reenvío.
- Mapeo exacto de capacidades a cada caso de uso del dominio.
- Políticas RLS por tabla y por operación (SELECT/INSERT/UPDATE/DELETE).
- Contexto de tenant de la conexión backend y estrategia de conexión/pooling.
- Borrado/anonimización de cuentas sujeto a conservación de historial financiero.
- MFA obligatorio para administradores y operaciones sensibles.

No se inventan estas políticas dentro de M1.1. Se cierran antes de exponer las tablas por Data API o habilitar flujos de alta reales.

## Políticas RLS de lectura (M1.5)

- `profiles`: cada usuario solo puede leer su propio perfil.
- `tenants`, `tenant_memberships`, `tenant_roles`, `tenant_role_capabilities` y `membership_roles`: solo miembros activos de un tenant activo pueden leer filas de ese tenant.
- `capabilities`: catálogo global de solo lectura para usuarios autenticados.
- `tenant_invitations`, `tenant_invitation_roles` y `tenant_security_audit_events`: solo miembros con `tenant.administer` pueden leer estos datos.
- Los helpers `is_tenant_member` y `has_tenant_capability` son `SECURITY DEFINER`, con `search_path` fijo, y solo ejecutables por `authenticated`; no se concede acceso anónimo.
- `authenticated` recibe SELECT, pero no INSERT/UPDATE/DELETE/TRUNCATE. `anon` no recibe privilegios. No hay políticas de escritura.

## Pruebas

`supabase/tests/bootstrap.sql` crea los objetos mínimos equivalentes a Supabase Auth/Storage para validar migraciones en PostgreSQL limpio. `assert_identity_schema.sql` comprueba catálogo, RLS, ausencia de privilegios de cliente y rechazo de asignaciones de roles cruzadas entre tenants. El workflow ejecuta todas las migraciones versionadas en PostgreSQL 17 antes de construir el backend y el contenedor.

Esta prueba no reemplaza una validación en un proyecto Supabase administrado ni pruebas completas de políticas RLS; estas pertenecen al siguiente hito.


## Evidencias privadas (M1.6)

- `tenant_evidence` conserva tenant, creador, bucket, ruta determinista, MIME declarado, tamaño esperado, SHA-256 y estado (`pending`, `available`, `rejected`).
- La ruta es `<tenant_uuid>/<evidence_uuid>`; el cliente no selecciona bucket ni ruta arbitraria.
- El bucket `operation-evidence` es privado. Límite por archivo: 10 MiB. Tipos declarados admitidos: PDF, JPEG, PNG y WebP.
- Solo `tucambio_backend` puede ejecutar `create_tenant_evidence` y `complete_tenant_evidence`. No tiene grants directos de tabla ni `BYPASSRLS`.
- Storage permite INSERT únicamente para una fila `pending` creada por el backend, por el mismo usuario y con MIME/tamaño coincidentes. SELECT solo para evidencia `available` y con capacidad vigente. No hay UPDATE/DELETE para clientes.
- Ktor debe verificar los bytes reales, MIME detectado, tamaño real y SHA-256 antes de finalizar. La función de finalización comprueba que el objeto correspondiente exista y coincida con el tamaño/tipo declarados, pero no sustituye la inspección de contenido.
- Esta etapa no añade aún endpoints Ktor ni finge URLs firmadas; el adaptador HTTP de carga/descarga se implementará después del contrato de seguridad.
