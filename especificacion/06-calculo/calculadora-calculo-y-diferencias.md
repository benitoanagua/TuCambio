# 20. Calculadora

La calculadora queda definida como:

> **herramienta de estimación previa.**

No congela necesariamente la tasa.

Debe indicar claramente que el resultado es una:

**ESTIMACIÓN**

hasta que exista una operación y un movimiento verificado.

---

# 21. Cálculo económico

Se separan claramente:

```text
montoSolicitado
        ↓
montoOrigenVerificado
        ↓
tasaAplicada
        ↓
montoCalculadoBruto
        ↓
comisiones / ajustes
        ↓
redondeo
        ↓
montoFinalDestino
```

El sistema debe tener **un único cálculo económico autoritativo**.

No debe existir:

> “lo que calculó la pantalla A”
> frente a
> “lo que calculó la pantalla B”.

---

# 22. Precisión monetaria

Cada moneda debe poder definir su propia precisión.

No se debe asumir universalmente:

```text
2 decimales
```

porque la configuración puede variar según moneda.

El cálculo interno debe conservar precisión suficiente y el resultado final debe respetar la precisión de la moneda destino.

---

# 23. Diferencias de monto

La regla conceptual ya está clara:

> **El monto recibido no se modifica automáticamente para hacer que la operación cuadre.**

Si se esperaba:

```text
100 ARS
```

y se verifica:

```text
98 ARS
```

no se recalcula silenciosamente como si hubieran sido 100.

Se genera:

> **INCIDENCIA — diferencia de monto**

La política exacta de resolución todavía queda pendiente.

Lo mismo aplica a un exceso.

---
