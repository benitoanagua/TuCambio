# Supabase Storage

## Bucket inicial

La migración `20261109000100_storage_private_evidence_bucket.sql` crea el bucket privado `operation-evidence`.

- Privado: no hay lectura pública.
- Tamaño máximo inicial: 10 MiB por objeto.
- MIME admitidos: PDF, JPEG, PNG y WebP.
- No se agregan políticas RLS permisivas hasta que exista el esquema canónico de tenants y membresías.
- En esta fase, las operaciones deben pasar por el backend Kotlin/Ktor, que valida identidad, tenant, operación y permisos antes de emitir URLs firmadas de corta duración o manipular objetos con credenciales exclusivamente de servidor.

## Capa gratuita (verificada 2026-11-09)

El plan Free de Supabase incluye 1 GB de Storage, 5 GB de egress y un máximo global de 50 MB por archivo. El cupo de organización se comparte entre proyectos. Los proyectos Free con baja actividad pueden pausarse después de 7 días. Estas condiciones hacen que Free sea adecuado para desarrollo, pruebas y pilotos pequeños, no una garantía de disponibilidad para producción.

Consultar siempre la página oficial antes de estimar costos:
- https://supabase.com/pricing
- https://supabase.com/docs/guides/storage/pricing
- https://supabase.com/docs/guides/platform/billing-faq
- https://supabase.com/docs/guides/platform/free-project-pausing

## Contrato de metadatos pendiente del esquema

Cuando se implemente el modelo de operaciones/tenants, el registro PostgreSQL de cada archivo deberá relacionar al menos tenant, operación, bucket, object key, MIME detectado, tamaño, SHA-256, actor, timestamps y estado de validación. Los binarios no se guardan en PostgreSQL.

## Seguridad y operación

- Nunca incluir `service_role` ni credenciales PostgreSQL en clientes.
- No usar buckets públicos para comprobantes.
- No registrar URLs firmadas completas.
- Validar bytes/MIME real, tamaño y malware en backend/worker antes de aceptar la evidencia.
- Definir borrado lógico y retención auditada.
- Respaldar Storage por separado: el backup PostgreSQL no incluye los objetos.
- Antes de producción, definir RPO/RTO, exportación/replicación de objetos y pruebas de restauración.
