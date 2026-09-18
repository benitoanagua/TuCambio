# 45. Lo que hemos conseguido

Después de las simulaciones, el modelo se puede reducir a esta arquitectura conceptual:

```text
                    ┌─────────────┐
                    │   USUARIO   │
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────┐
                    │  OPERACIÓN  │
                    └──────┬──────┘
                           │
             ┌─────────────┼─────────────┐
             ▼             ▼             ▼
        MOVIMIENTO      EVIDENCIA      TASA
             │             │
             │             │
             └──────┬──────┘
                    ▼
               VERIFICACIÓN
                    │
                    ▼
               CALCULACIÓN
                    │
                    ▼
             MOVIMIENTO DESTINO
                    │
                    ▼
                FINALIZACIÓN

        ┌─────────────────────────┐
        │       INCIDENCIAS       │
        └─────────────────────────┘

        ┌─────────────────────────┐
        │         EVENTOS         │
        │       AUDITORÍA         │
        └─────────────────────────┘
```

Y alrededor:

```text
Monedas
   ↓
Pares
   ↓
Tasas

Canales / Destinos
   ↓
Instituciones

Usuarios
   ↓
Permisos
```

---
