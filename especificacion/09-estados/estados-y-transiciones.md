# 29. Estados de operación

El modelo simplificado provisional queda:

```text
BORRADOR
PENDIENTE
EN VERIFICACIÓN
PENDIENTE DE LIQUIDACIÓN
EN LIQUIDACIÓN
FINALIZADA
CANCELADA
EXPIRADA
RECHAZADA
```

Pero estos estados deben convivir con estados propios de:

- evidencia;
- movimiento;
- incidencia.

No debemos meter todo dentro del estado de operación.

---

# 30. Estados de evidencia

```text
PRESENTADA
      ↓
EN REVISIÓN
      ↓
VÁLIDA
   o
OBSERVADA
```

---

# 31. Estados de movimiento

```text
DECLARADO
    ↓
EN VERIFICACIÓN
    ↓
CONFIRMADO
    o
NO CONFIRMADO
```

---

# 32. Liquidación / destino

Conceptualmente:

```text
PENDIENTE
   ↓
SOLICITADA
   ↓
REALIZADA
   o
INCIDENCIA
```

No es necesario convertir esto en una nueva entidad económica separada si el movimiento de destino ya representa el hecho.

---
