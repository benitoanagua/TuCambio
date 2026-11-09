# Despliegue del backend en Google Cloud Run

## Decisión MVP

Cloud Run aloja el contenedor JVM de Ktor. Supabase permanece como plataforma de datos y servicios gestionados. No se necesita VM, Kubernetes ni un clúster permanente.

La configuración inicial propuesta para el primer piloto es un punto de partida, no un dimensionamiento definitivo:

- 1 vCPU.
- 512 MiB de memoria.
- mínimo 0 instancias.
- máximo 2 instancias.
- concurrencia inicial 40 solicitudes por instancia.
- puerto HTTP 8080.
- escalado a cero permitido.

Se ajustará con métricas de latencia, uso de memoria, concurrencia y conexiones PostgreSQL. El pool de conexiones deberá dimensionarse considerando el máximo de instancias y los límites del proyecto Supabase.

## Región

Elegir la región de Cloud Run junto con la región del proyecto Supabase, midiendo la latencia entre ambos. No crear recursos hasta confirmar la región y el proyecto de destino. Evitar desplegar Ktor lejos de PostgreSQL porque cada consulta cruzará esa distancia.

## Preparación manual (no ejecutada)

1. Crear/seleccionar un proyecto de Google Cloud y habilitar Cloud Run y Artifact Registry.
2. Configurar facturación y presupuesto/alertas.
3. Elegir región compatible y cercana al proyecto Supabase.
4. Crear repositorio de imágenes en Artifact Registry.
5. Configurar secretos en Secret Manager cuando el backend integre Auth y PostgreSQL.
6. Construir y publicar una imagen versionada.
7. Desplegar la imagen y verificar `/health/live` y `/health/ready`.
8. Configurar dominio, TLS, observabilidad y alertas cuando corresponda.

## Ejemplo de despliegue

Después de crear el proyecto, repositorio de imágenes, secretos y permisos IAM, construir/publicar la imagen y desplegarla con parámetros explícitos. Ejemplo orientativo:

```bash
gcloud run deploy tucambio-api \
  --image REGION-docker.pkg.dev/PROJECT_ID/REPOSITORY/tucambio-api:TAG \
  --region REGION \
  --port 8080 \
  --cpu 1 \
  --memory 512Mi \
  --min 0 \
  --max 2 \
  --concurrency 40
```

Los marcadores `REGION`, `PROJECT_ID`, `REPOSITORY` y `TAG` deben reemplazarse por valores reales. El comando no se ha ejecutado.

## Acceso y seguridad

- No habilitar acceso público a comandos de negocio hasta que Supabase Auth/JWT y autorización por tenant estén implementados y probados.
- Los endpoints de health no contienen datos sensibles.
- Una vez implementado Auth, el servicio podrá aceptar tráfico público y validar JWT de Supabase en Ktor; la autorización de negocio seguirá siendo del backend.
- Las credenciales de PostgreSQL y claves secretas se inyectarán desde Secret Manager, nunca como valores versionados.
- No usar una clave service-role en clientes.
- Configurar timeouts, límites de solicitudes, protección contra abuso y logs sin tokens ni URLs firmadas.

## CI/CD

`.github/workflows/backend-ci.yml` compila, ejecuta pruebas y construye el contenedor en GitHub Actions. No publica la imagen, no crea infraestructura y no despliega. La publicación/despliegue se añadirá cuando existan proyecto, región, IAM y secretos aprobados.
