# 24. Destino / liquidación

Se abandona como concepto central:

> `Reembolso`

porque no representa correctamente todos los casos.

El concepto general es:

> **Movimiento de destino**

La liquidación es el **proceso mediante el cual se coordina ese movimiento**.

```text
Operación
   ↓
monto final destino
   ↓
destino/canal
   ↓
movimiento externo
   ↓
evidencia
   ↓
verificación
```

---

# 25. Canal / destino

El sistema necesita un concepto genérico para los datos mediante los cuales se realiza un depósito o pago externo.

Por tanto:

> **Canal/Destino**

es más general que:

- cuenta bancaria;
- QR;
- Mercado Pago;
- una entidad específica.

Un canal puede contener, por ejemplo:

```text
Institución
Moneda soportada
Dirección soportada
Datos de transferencia
QR
Método de verificación
Estado
Vigencia
```

---

# 26. QR

El QR deja de ser un concepto económico independiente.

Es:

> **un mecanismo/atributo de un canal o destino.**

Pero el QR/destino realmente utilizado debe conservarse históricamente.

Así:

```text
Destino actual
     ↓
QR actual cambia
     ↓
operaciones nuevas → QR nuevo

operaciones anteriores → conservan QR/destino utilizado
```

---
