# TuCambio API — Kotlin / Ktor

Backend HTTP inicial de TuCambio. Esta base es deliberadamente pequeña: prepara ejecución local, contenedor y health checks sin anticipar el esquema de dominio ni conectar credenciales remotas.

## Stack fijado para el MVP

- Kotlin 2.4.21
- Ktor 3.6.1
- JDK 21
- Gradle 9.2.1
- Netty
- kotlinx.serialization
- Docker multi-stage, runtime JRE no-root

Las versiones corresponden a las versiones estables consultadas el 9 de noviembre de 2026.

## Ejecutar localmente

Requiere JDK 21 y Gradle 9.2.1 instalado.

```bash
cd backend
gradle run
```

El servidor escucha en `0.0.0.0:8080` por defecto. El puerto puede cambiarse con `PORT`.

## Endpoints iniciales

| Ruta | Propósito |
|---|---|
| `GET /` | Identificación del servicio |
| `GET /health/live` | Liveness para detectar proceso activo |
| `GET /health/ready` | Readiness HTTP |

**Importante:** mientras PostgreSQL, Auth y Storage no estén conectados, readiness solo confirma que Ktor terminó de inicializar. No afirma que dependencias externas estén disponibles.

## Pruebas y distribución

```bash
gradle test
gradle installDist
```

## Construir el contenedor

Desde la raíz del repositorio:

```bash
docker build -t tucambio-api:local ./backend
docker run --rm -p 8080:8080 tucambio-api:local
```

El contenedor ejecuta como usuario no privilegiado y recibe el puerto mediante la variable `PORT`.

## Configuración y secretos

No hay credenciales de Supabase ni conexión PostgreSQL en esta primera iteración. Se incorporarán junto con el esquema, Auth/JWT y el pool de conexiones, usando variables de entorno/Secret Manager. No se deben añadir claves service-role, contraseñas SQL ni secretos al repositorio, a la imagen o al cliente.

## Despliegue

La guía de Cloud Run está en [../cloudrun/README.md](../cloudrun/README.md). El workflow actual compila, prueba y construye la imagen; no publica imágenes ni despliega automáticamente.
