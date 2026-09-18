# 36. Concurrencia

Debe asumirse que puede ocurrir:

```text
Operador A confirma
        +
Operador B confirma
        ↓
mismo movimiento
```

Solo una operación debe producir el efecto válido.

Lo mismo para:

- doble clic;
- reintento de red;
- dos comprobantes;
- dos pagos;
- dos operadores.

Todo proceso con efecto económico debe ser **idempotente**.

---

# 37. Identidad de operación

Nunca debe identificarse una operación mediante:

```text
cliente + moneda + monto
```

porque pueden existir dos operaciones idénticas.

Debe existir un identificador único.

```text
OP-001
OP-002
```

aunque ambas sean:

```text
100 USD → BOB
```

---
