# 40. Lo que queda oficialmente fuera del dominio

Después de todas las simulaciones, estos conceptos **no deben formar parte de la nueva especificación funcional**:

| Concepto heredadoDecisión                       |                        |
| ----------------------------------------------- | ---------------------- |
| `MovimientoMP`                                  | ❌ eliminar del dominio |
| Mercado Pago como modelo                        | ❌ no                   |
| `/mp/`                                          | ❌ no                   |
| `SolicitudCobro`                                | ❌ no                   |
| `Reembolso`                                     | ❌ no                   |
| `CuentaReceptora`                               | ❌ no                   |
| `CarrilDeposito`                                | ❌ no                   |
| `PagoBancario`                                  | ❌ no                   |
| `TipoCobro`                                     | ❌ no                   |
| `POR_TRANSACCION`                               | ❌ no                   |
| `ACUMULADO_SOCIO`                               | ❌ no                   |
| Verificador específico como concepto de negocio | ❌ no                   |
| FSM histórico de 14 estados                     | ❌ no                   |
| Entidades distintas para ARS/BOB                | ❌ no                   |
| Lógica específica por moneda                    | ❌ no                   |

Esto es importante: **no estamos diciendo necesariamente que todo eso deba borrarse del código histórico**, sino que **no pertenece a la especificación funcional nueva**.

---

# 41. Matriz de requisitos consolidada

## A. Requisitos funcionales

### RF01

El sistema debe permitir crear operaciones entre monedas configuradas.

### RF02

El sistema debe permitir operar en ambas direcciones de un par habilitado.

### RF03

El sistema debe mostrar la estimación de conversión.

### RF04

El sistema debe registrar movimientos externos.

### RF05

El sistema debe permitir movimientos no asociados inicialmente.

### RF06

El sistema debe gestionar evidencias y comprobantes.

### RF07

El sistema debe permitir múltiples evidencias por operación/movimiento.

### RF08

El sistema debe verificar movimientos.

### RF09

El sistema debe determinar la tasa aplicable.

### RF10

El sistema debe registrar el movimiento de destino.

### RF11

El sistema debe registrar incidencias.

### RF12

El sistema debe mantener historial/auditoría.

### RF13

El sistema debe soportar múltiples monedas.

### RF14

El sistema debe soportar múltiples pares independientes.

### RF15

El sistema debe gestionar canales/destinos.

### RF16

El sistema debe conservar la configuración histórica utilizada.

---

# 42. Invariantes

Estas son especialmente importantes porque **no son configurables libremente**.

### INV01

Tu Cambio no custodia fondos.

### INV02

Tu Cambio no ejecuta transferencias externas.

### INV03

Una evidencia no equivale a un movimiento.

### INV04

Un comprobante no confirma automáticamente un movimiento.

### INV05

Un movimiento confirmado no se sobrescribe.

### INV06

Una tasa aplicada a una operación confirmada no cambia retroactivamente.

### INV07

Una misma operación tiene un identificador único.

### INV08

Un mismo movimiento económico no puede confirmarse dos veces.

### INV09

Las acciones con efecto económico deben ser idempotentes.

### INV10

La configuración posterior no altera la historia.

### INV11

Una incidencia no borra ni reemplaza el hecho económico.

### INV12

No se inventa una tasa cuando no existe una tasa aplicable.

---

# 43. Datos fundamentales

El núcleo de datos queda reducido a:

```text
Usuario
Moneda
Par
Tasa
Operación
Movimiento
Evidencia
Canal/Destino
Institución
Incidencia
Evento
Permiso
```

Esto es considerablemente más limpio que el modelo heredado.

---
