# Contrato técnico del dominio financiero (M1.7)

**Estado:** contrato de implementación inicial; no sustituye ni modifica la especificación funcional.  
**Base normativa:** `INDICE_MAESTRO.md` y `especificacion/`.  
**Regla de precedencia:** ante cualquier diferencia, prevalece la especificación funcional aprobada.

## 1. Objetivo y límites

M1.7 incorpora el núcleo transaccional de operaciones, movimientos externos y tasas. La implementación debe preservar la separación entre intención comercial, hecho económico externo, evidencia y coordinación del proceso.

TuCambio:
- registra y coordina operaciones;
- registra movimientos que ocurrieron fuera de TuCambio;
- permite movimientos todavía no asociados a una operación;
- conserva evidencias y asociaciones sin convertirlas en confirmaciones automáticas;
- calcula el importe autoritativo únicamente cuando existan los datos normativamente requeridos;
- no custodia fondos ni ejecuta transferencias.

No se incorporan modelos heredados específicos de proveedores, bancos, países o monedas.

## 2. Entidades y responsabilidades

### Moneda y par

- Moneda: código identificador, nombre y precisión configurada.
- Par: dos monedas distintas, dentro de un tenant, con estado/configuración propios.
- No se fija una moneda base global ni se codifican combinaciones de monedas en enums.
- La precisión se almacena como configuración explícita por moneda; las reglas de redondeo siguen pendientes.

### Tasa

- Pertenece a un par y tenant.
- Conserva valores de compra y venta, vigencia `[valid_from, valid_until)`, autor y timestamps.
- Las tasas son históricas e inmutables una vez utilizadas; las correcciones se registran como nuevas versiones/eventos, no sobrescribiendo una tasa aplicada.
- No se crea una tasa implícita ni se extrapola cuando no existe una tasa vigente.
- La tasa aplicable a la operación se determina por el instante efectivo del movimiento de origen verificado, no por creación de operación ni hora del dispositivo.
- La zona horaria se normaliza a un instante absoluto; no se almacena como desplazamiento manual.

### Operación

- Es la intención de convertir una moneda origen en una moneda destino.
- Tiene identidad propia, tenant, actor creador, par/dirección, monto solicitado y estado de operación.
- Puede existir sin movimientos y puede tener movimientos de origen y destino asociados.
- Los valores de estimación no congelan la tasa ni sustituyen el cálculo económico autoritativo.
- La operación no se identifica por usuario, moneda y monto: utiliza UUID propio.

### Movimiento

- Representa un hecho económico externo ya ocurrido o declarado, nunca una transferencia ejecutada por TuCambio.
- Conserva tenant, moneda, importe, instante efectivo reportado, datos de referencia externos permitidos, actor registrador y estado propio.
- Puede crearse sin operación asociada.
- La asociación a operación es explícita y auditable.
- Un movimiento confirmado no se sobrescribe ni se confirma dos veces.
- La evidencia es independiente: puede haber múltiples evidencias por movimiento y/o operación; subir evidencia no confirma movimiento.

### Evidencia, incidencia y eventos

- Se reutiliza `tenant_evidence` de M1.6; la asociación al dominio financiero se hará mediante relaciones explícitas tenant-scoped, sin mover objetos ni cambiar el contrato Storage.
- Una evidencia observada no implica rechazar la operación ni negar que el movimiento ocurrió.
- Las incidencias registran diferencias y anomalías sin borrar ni reemplazar el hecho económico.
- Los eventos de dominio/auditoría registran actor, tenant, entidad, acción, instante y correlación; no almacenan secretos ni URLs firmadas.

## 3. Límites transaccionales e idempotencia

- Toda escritura de dominio se ejecuta en Ktor y PostgreSQL dentro de una única transacción ACID.
- Cada comando con efecto debe aceptar una clave de idempotencia vinculada al tenant, actor/ámbito y tipo de comando.
- La misma clave con el mismo contenido devuelve el resultado original; la misma clave con contenido distinto se rechaza como conflicto.
- La unicidad de la identidad de operación y la prevención de doble confirmación de movimiento se refuerzan con constraints/índices, no solo con comprobaciones previas en Kotlin.
- La asociación y confirmación concurrente de un mismo movimiento debe producir como máximo un efecto válido.
- Eventos/auditoría del cambio se escriben en la misma transacción que el cambio de estado.
- No se usa Realtime como mecanismo de escritura ni de exclusión mutua.

## 4. Estados separados

No se crea un único estado que mezcle operación, movimiento, evidencia e incidencia.

- Operación: BORRADOR, PENDIENTE, EN VERIFICACIÓN, PENDIENTE DE LIQUIDACIÓN, EN LIQUIDACIÓN, FINALIZADA, CANCELADA, EXPIRADA o RECHAZADA, sujetos a transiciones aprobadas.
- Movimiento: DECLARADO, EN VERIFICACIÓN, CONFIRMADO o NO CONFIRMADO.
- Evidencia: PRESENTADA, EN REVISIÓN, VÁLIDA u OBSERVADA (M1.6 Storage conserva además su estado técnico pending/available/rejected; no confundir ambos ciclos).
- Liquidación/destino: se representa mediante el movimiento de destino y su coordinación, no mediante una entidad económica duplicada.

Las transiciones permitidas, actores autorizados y precondiciones deben quedar especificados antes de habilitar comandos productivos.

## 5. Políticas que NO se deben codificar por inferencia

Permanecen abiertas en `especificacion/17-politicas-pendientes/politicas-pendientes.md`: diferencias inferiores/superiores, comisiones, redondeo, mínimos/máximos, límites acumulados, expiraciones, tasas especiales, movimientos no asociados, pagos de destino insuficientes/excesivos, cancelación/devolución tras depósito, requisitos de comprobantes, depósitos durante suspensión o ausencia de tasa y huecos entre tasas.

M1.7 puede crear estructuras neutrales para conservar datos y trazabilidad, pero no debe asignar resultados automáticos ni valores por defecto que resuelvan esas políticas.

## 6. Orden de implementación propuesto

1. Catálogo tenant-scoped de monedas y pares, constraints y capacidades.
2. Tasas versionadas con vigencia semiabierta y consulta determinista por instante.
3. Operaciones: creación idempotente y estados iniciales, sin fijar una tasa definitiva antes del movimiento origen verificado.
4. Movimientos: registro asociado/no asociado, asociación explícita y protección contra doble confirmación.
5. Asociaciones de evidencias e incidencias, historial append-only.
6. Cálculo autoritativo solo cuando las reglas aprobadas estén disponibles; mientras falten políticas, devolver estado explícito de pendiente en vez de inventar un importe final.

## 7. Criterios de aceptación

- Pruebas SQL en PostgreSQL 17 desde base limpia y pruebas Kotlin.
- Aislamiento tenant en todas las claves foráneas, funciones y consultas.
- Tests negativos de cross-tenant, idempotencia repetida/con payload distinto, concurrencia de confirmación, tasa en límites exactos de vigencia y ausencia de tasa.
- Pruebas que demuestren que evidencia no confirma movimiento, movimiento no asociado es válido y movimiento confirmado no se sobrescribe.
- Docker build verde.
- Ningún secreto, service-role key ni credencial en cliente, Git o logs.
- Ninguna migración se aplica a un proyecto Supabase remoto ni se despliega infraestructura desde CI.


## 8. Consultas financieras de lectura (M1.9.1)

Las primeras consultas de lectura se exponen como funciones PostgreSQL SECURITY DEFINER de solo lectura, invocables exclusivamente por `tucambio_backend`. No se concede `SELECT` directo sobre las tablas financieras.

- `financial.read` es la capacidad explícita requerida para consultar información financiera dentro del tenant.
- La autorización se vuelve a resolver en PostgreSQL con actor y tenant; el identificador del tenant recibido no concede acceso por sí mismo.
- `query_financial_operations` lista operaciones con nombres y precisión de las monedas origen/destino.
- `query_external_movements` lista movimientos con metadatos de moneda y, cuando existe, operación/rol de asociación.
- Ambas consultas aceptan filtro exacto por estado y paginación por `page_size` (1–100) y `offset` (0–10000).
- El orden es determinista: `created_at DESC, id DESC`. La respuesta incluye `items`, `total`, `pageSize` y `offset`.
- Los filtros no alteran estados ni ejecutan comandos. No se calculan saldos, tasas aplicadas ni importes finales.
- La suite SQL verifica privilegios, autorización cross-tenant, metadatos y rechazo de ventanas de paginación fuera de límites.

La capacidad debe asignarse explícitamente a los roles que deban consultar finanzas; no se infiere de `operations.operate`, `movements.verify` ni de la administración del tenant.


## 9. Resolución de tasa desde el movimiento de origen (M1.8.2)

Al pasar a `CONFIRMED` un movimiento asociado a una operación con rol `ORIGIN`, el comando de verificación:
- bloquea el movimiento y la operación en la misma transacción;
- toma `external_movements.effective_at` como instante de referencia;
- busca una tasa del mismo tenant y par cuya vigencia semiabierta `[valid_from, valid_until)` contenga ese instante;
- selecciona `buy_rate` cuando el cliente entrega la moneda base (el operador compra la moneda base) y `sell_rate` cuando entrega la moneda cotizada (el operador vende la moneda base);
- fija `source_effective_at`, `applied_rate_id` y `applied_rate` una sola vez y registra el evento de operación dentro de la misma transacción.

La confirmación del movimiento externo no se revierte por falta de tasa. En ese caso se conserva el instante efectivo, se deja la tasa sin asignar y se registra `OPERATION_SOURCE_RATE_NOT_FOUND`. Si la moneda del movimiento no coincide con la moneda origen declarada en la operación, no se asigna tasa y se registra `OPERATION_SOURCE_CURRENCY_MISMATCH`. Movimientos sin asociación ORIGIN no disparan resolución de tasa.

Esta resolución no determina importes finales, comisiones, redondeos ni transiciones de liquidación. Las políticas P01–P22 permanecen fuera de este comando.


## 10. Snapshot del importe de origen verificado (M1.8.4)

Al confirmar un movimiento asociado con rol `ORIGIN`, si la moneda coincide con la moneda origen de la operación, PostgreSQL conserva en la operación:
- `verified_source_movement_id`: movimiento externo confirmado que respalda el dato;
- `verified_source_amount`: copia exacta del importe registrado en ese movimiento;
- `source_effective_at`: instante efectivo del mismo movimiento.

El snapshot se conserva incluso si no existe una tasa vigente. Si la moneda no coincide, no se copia el importe ni se aplica una tasa. La base de datos comprueba que el movimiento esté confirmado, asociado como `ORIGIN`, pertenezca al mismo tenant y coincida en moneda, importe e instante. Una vez asignado, el snapshot es inmutable.

Este dato no sustituye `requested_amount`: ambos pueden diferir y la diferencia no se corrige automáticamente. Tampoco constituye el importe calculado de destino. El cálculo final permanece pendiente de la política de redondeo P04 y de las políticas económicas aplicables; esta migración no inventa ni congela esas decisiones.
