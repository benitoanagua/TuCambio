# 27. Multimoneda

La estructura queda:

```text
MONEDAS
   ↓
PARES
   ↓
TASAS
   ↓
OPERACIONES
```

Ejemplo:

```text
Monedas:
ARS
BOB
USD
EUR

Pares habilitados:
ARS/BOB
BOB/ARS
USD/BOB

Pares no habilitados:
EUR/USD
USD/ARS
```

Agregar una moneda **no habilita automáticamente todas sus combinaciones**.

---

# 28. Estados de disponibilidad

Queda una separación muy importante:

### Moneda

¿Está disponible?

### Par

¿Está habilitado?

### Tasa

¿Existe una tasa válida?

### Canal

¿Existe un canal operativo compatible?

### Operación

¿Puede avanzar?

Por tanto, no debemos tener una única bandera genérica tipo:

```text
activo = true
```

para representar todo.

---
