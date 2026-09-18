# 5. Movimiento

## Regla M01

Un movimiento es un **hecho económico ocurrido externamente a Tu Cambio**.

Tu Cambio no genera el dinero ni ejecuta la transferencia.

Ejemplo:

```text
Banco externo
     ↓
transferencia realizada
     ↓
Movimiento
     ↓
Tu Cambio registra/verifica
```

## Regla M02

Una operación puede tener:

- movimiento de origen;
- movimiento de destino.

Conceptualmente:

```text
                 OPERACIÓN
                    │
          ┌─────────┴─────────┐
          ↓                   ↓
 Movimiento origen     Movimiento destino
   usuario entrega       usuario recibe
```

---

# 6. Movimiento sin operación

Esta regla es importante.

Puede ocurrir:

```text
Movimiento externo
       ↓
Tu Cambio todavía no tiene operación
```

Por tanto, el sistema debe poder registrar:

> **Movimiento no asociado**

Posteriormente podrá asociarse a una operación.

Esto evita perder hechos económicos simplemente porque alguien realizó el depósito antes de registrar la solicitud.

---

# 7. Operación sin movimiento

También es válido:

```text
Operación creada
      ↓
esperando depósito
```

Por tanto:

> **Operación y movimiento no son la misma cosa.**

Esta separación queda definitivamente establecida.

---
