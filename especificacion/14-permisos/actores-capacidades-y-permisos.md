# 39. Permisos

Ya no necesitamos convertir necesariamente los roles históricos en reglas de negocio rígidas.

El modelo conceptual más limpio es:

```text
USUARIO
   ↓
PERMISOS
```

Capacidades principales:

- OPERAR
- VERIFICAR
- LIQUIDAR
- GESTIONAR TASAS
- GESTIONAR CONFIGURACIÓN
- ADMINISTRAR

Los roles pueden ser agrupaciones de permisos.

Así no atamos el negocio a:

> ADMINISTRADOR / OPERADORA\_TASAS / OPERADORA\_OPERACIONES / SOCIO

como si fueran conceptos inmutables.

---
