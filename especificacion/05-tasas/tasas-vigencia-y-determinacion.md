# 15. Tasa

La tasa es temporal.

Conceptualmente:

```text
Tasa
 ├── par de monedas
 ├── valor compra
 ├── valor venta
 ├── desde
 └── hasta
```

La validez temporal se define mediante:

```text
[desde, hasta)
```

---

# 16. Regla temporal de tasa

Si:

```text
Tasa A
10:00 ───────── 11:00

Tasa B
11:00 ───────── 12:00
```

Entonces:

- 10:59:59 → Tasa A
- 11:00:00 → Tasa B

Nunca hay ambigüedad.

---

# 17. ¿Qué determina la tasa?

Queda establecida esta jerarquía:

### NO determina la tasa:

- creación de la operación;
- apertura de la pantalla;
- cálculo de la calculadora;
- subida del comprobante;
- revisión del operador;
- hora del teléfono del usuario.

### Sí determina la tasa:

> **El instante efectivo del movimiento de origen verificado.**

Esto es particularmente importante para operaciones que atraviesan un cambio de tasa.

---

# 18. Conversión horaria

Los timestamps recibidos desde comprobantes deben convertirse a un instante absoluto.

Para las operaciones históricas:

- Argentina → `America/Argentina/Buenos_Aires`
- Bolivia → `America/La_Paz`

No se debe resolver mediante:

> “sumar/restar X horas”.

La zona horaria forma parte de la interpretación del dato.

---

# 19. Ausencia de tasa

Si en el momento correspondiente no existe una tasa aplicable:

> **Tu Cambio no inventa una tasa.**

La operación debe quedar sujeta a la política correspondiente.

Esto nos lleva a una distinción importante:

```text
No hay tasa
≠
Par suspendido
≠
Canal cerrado
≠
Sistema fuera de servicio
```

Son situaciones diferentes.

---
