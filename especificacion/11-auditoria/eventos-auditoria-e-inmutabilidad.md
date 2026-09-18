# 34. Eventos y auditoría

`createdAt` y `updatedAt` no son suficientes.

Debe existir una historia de eventos capaz de reconstruir:

```text
quién
qué hizo
cuándo
sobre qué
qué cambió
por qué
```

Ejemplo:

```text
Operación creada
↓
Comprobante presentado
↓
Comprobante observado
↓
Nuevo comprobante presentado
↓
Movimiento verificado
↓
Tasa aplicada
↓
Destino seleccionado
↓
Liquidación registrada
↓
Operación finalizada
```

---

# 35. Inmutabilidad

Regla de oro:

> **Ningún dato derivado, comprobante, cambio de estado, acción de operador o configuración posterior debe modificar silenciosamente un hecho económico ya verificado.**

Por tanto:

### No se modifica

- movimiento confirmado;
- tasa aplicada;
- monto económico final;
- evidencia validada;
- destino histórico utilizado.

### Se agrega

- evento;
- nueva evidencia;
- incidencia;
- corrección documentada;
- nueva asociación.

---
