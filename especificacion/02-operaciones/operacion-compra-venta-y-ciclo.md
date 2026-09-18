# 3. Operación

## Regla O01 — Definición

Una operación representa la intención de realizar una conversión:

**moneda origen → moneda destino**

Ejemplos:

- ARS → BOB
- BOB → ARS
- USD → BOB
- BOB → USD
- EUR → USD

No deben existir operaciones separadas conceptualmente para cada combinación.

### Modelo conceptual

```text
Operación
 ├── dirección
 ├── monedaOrigen
 ├── monedaDestino
 ├── montoSolicitado
 ├── tasa aplicable
 ├── cálculo
 ├── movimiento de origen
 ├── movimiento de destino
 ├── evidencias
 ├── incidencias
 └── eventos
```

---

# 4. COMPRA y VENTA

Se mantienen como **terminología de usuario**, no como dos modelos diferentes.

### COMPRA

El usuario entrega la moneda origen y recibe la moneda destino.

### VENTA

El usuario entrega la otra moneda y recibe la primera.

Por tanto:

```text
COMPRA / VENTA
       ↓
Operación genérica
       ↓
monedaOrigen + monedaDestino
```

Esto elimina una futura duplicación del modelo.

---
