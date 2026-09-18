# 8. Evidencia y comprobante

## Regla E01

**Evidencia ≠ Movimiento**

Una evidencia demuestra o intenta demostrar un hecho.

Un comprobante es simplemente un tipo de evidencia documental.

```text
Evidencia
 ├── comprobante bancario
 ├── comprobante QR
 ├── captura
 ├── documento
 └── otra evidencia admitida
```

---

# 9. Una operación puede tener múltiples evidencias

Por ejemplo:

```text
Operación
 ├── comprobante original
 ├── comprobante corregido
 ├── comprobante adicional
 └── comprobante de destino
```

No se debe sobrescribir el anterior.

La corrección significa:

```text
Evidencia 1 → OBSERVADA
Evidencia 2 → PRESENTADA
Evidencia 2 → VÁLIDA
```

No:

```text
Evidencia 1 → reemplazada/eliminada
```

---

# 10. Evidencia presentada antes de la operación

También queda permitido conceptualmente:

```text
Comprobante recibido
       ↓
sin operación asociada
       ↓
Evidencia pendiente de asociación
```

Después puede vincularse.

Esto es especialmente útil para depósitos que llegan antes de que el operador encuentre o cree la solicitud correspondiente.

---

# 11. Un comprobante no confirma automáticamente un movimiento

Regla fundamental:

> **Subir un comprobante nunca equivale por sí mismo a confirmar el movimiento.**

Flujo:

```text
Usuario presenta comprobante
          ↓
Evidencia PRESENTADA
          ↓
Revisión
          ↓
¿corresponde al movimiento?
          ↓
       sí / no
```

Esto evita que una captura manipulada o equivocada produzca un efecto económico automático.

---

# 12. Comprobante incorrecto

Si el comprobante está:

- equivocado;
- incompleto;
- ilegible;
- inconsistente;
- no corresponde al movimiento;

la consecuencia inicial es:

> **Evidencia OBSERVADA**

No necesariamente:

> Operación RECHAZADA.

Esto queda como una distinción fundamental.

---

# 13. Movimiento y comprobante pueden divergir

Escenario:

```text
Comprobante incorrecto
        ↓
operador lo observa
        ↓
se presenta otro comprobante
        ↓
el movimiento real se verifica
```

La existencia de un comprobante incorrecto no significa que el movimiento externo nunca ocurrió.

Por eso:

```text
MOVIMIENTO = hecho económico
EVIDENCIA = prueba del hecho
```

---

# 14. Reutilización de comprobantes

El mismo comprobante no debe poder utilizarse silenciosamente para confirmar dos movimientos distintos.

Si se detecta:

```text
Comprobante A
   ↓
Movimiento 1 confirmado
   ↓
intento de usar A nuevamente
```

Debe generarse una:

> **INCIDENCIA**

y pasar a revisión.

---
