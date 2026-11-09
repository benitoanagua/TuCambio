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

---

# 38. Verificación de concurrencia en PostgreSQL

Las pruebas de concurrencia deben usar sesiones PostgreSQL independientes. Una secuencia de llamadas dentro de una sola transacción no demuestra serialización entre operadores.

La suite de integración coordina sesiones competidoras y comprueba:

- Dos operadores deciden estados finales opuestos para el mismo movimiento: solo una transición puede persistir y producir su evento final.
- Dos operadores intentan iniciar la revisión de la misma evidencia: solo una transición y un evento de revisión pueden persistir.
- Dos solicitudes simultáneas con el mismo actor, clave de idempotencia y contenido: ambas reciben el mismo resultado lógico, una como ejecución original y otra como repetición, sin duplicar auditoría.

Las pruebas mantienen los comandos y reglas de dominio existentes. No introducen prioridades entre operadores ni resuelven empates por orden de llegada; el ganador depende de la serialización efectiva de PostgreSQL. La otra solicitud debe releer el estado comprometido y ser rechazada si su transición quedó obsoleta.

La suite se ejecuta en CI contra PostgreSQL 17, después de aplicar todas las migraciones y las aserciones SQL de dominio.
