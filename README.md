# TuCambio

TuCambio es una plataforma libre, abierta, genérica y multimoneda para operadores de cambio. La especificación funcional está en [INDICE_MAESTRO.md](INDICE_MAESTRO.md) y el plan de migración tecnológica en [MIGRACION_TU_PAGO_APP.md](MIGRACION_TU_PAGO_APP.md).

## Backend MVP

La base Kotlin/JVM + Ktor, Docker y guía de Cloud Run está en [backend/README.md](backend/README.md). El backend se conecta progresivamente a Supabase; no se incluyen credenciales ni se despliega infraestructura desde este repositorio.

## Supabase

La arquitectura de PostgreSQL, Auth, Storage, RLS y servicios complementarios está documentada en [supabase/README.md](supabase/README.md).
