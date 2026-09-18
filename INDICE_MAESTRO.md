# Índice maestro — Tu Cambio

Este índice organiza la especificación funcional y de negocio consolidada de **Tu Cambio**.

La documentación se limita a reglas, conceptos, requisitos, escenarios y decisiones surgidas de la investigación, análisis y simulaciones realizadas. No define tecnologías de implementación.

## Estado documental

- **Consolidado:** contenido que forma parte de la definición actual.
- **Validado / simulado:** resultados y escenarios que fueron contrastados durante el trabajo.
- **Pendiente:** decisiones identificadas pero no cerradas.

## Estructura

- `especificacion/01-fundamentos/principios-y-conceptos.md` — Fundamentos. Se basa en las secciones consolidadas: 1, 2.
- `especificacion/02-operaciones/operacion-compra-venta-y-ciclo.md` — Operaciones. Se basa en las secciones consolidadas: 3, 4.
- `especificacion/03-movimientos/movimientos-y-asociacion.md` — Movimientos. Se basa en las secciones consolidadas: 5, 6, 7.
- `especificacion/04-evidencias/evidencias-comprobantes-y-verificacion.md` — Evidencias. Se basa en las secciones consolidadas: 8, 9, 10, 11, 12, 13, 14.
- `especificacion/05-tasas/tasas-vigencia-y-determinacion.md` — Tasas. Se basa en las secciones consolidadas: 15, 16, 17, 18, 19.
- `especificacion/06-calculo/calculadora-calculo-y-diferencias.md` — Calculo. Se basa en las secciones consolidadas: 20, 21, 22, 23.
- `especificacion/07-destinos/destino-liquidacion-canales-y-qr.md` — Destinos. Se basa en las secciones consolidadas: 24, 25, 26.
- `especificacion/08-multimoneda/multimoneda-y-disponibilidad.md` — Multimoneda. Se basa en las secciones consolidadas: 27, 28.
- `especificacion/09-estados/estados-y-transiciones.md` — Estados. Se basa en las secciones consolidadas: 29, 30, 31, 32.
- `especificacion/10-incidencias/incidencias.md` — Incidencias. Se basa en las secciones consolidadas: 33.
- `especificacion/11-auditoria/eventos-auditoria-e-inmutabilidad.md` — Auditoria. Se basa en las secciones consolidadas: 34, 35.
- `especificacion/12-concurrencia/concurrencia-e-identidad-e-idempotencia.md` — Concurrencia. Se basa en las secciones consolidadas: 36, 37.
- `especificacion/13-configuracion/configuracion-historica.md` — Configuracion. Se basa en las secciones consolidadas: 38.
- `especificacion/14-permisos/actores-capacidades-y-permisos.md` — Permisos. Se basa en las secciones consolidadas: 39.
- `especificacion/15-requisitos/requisitos-invariantes-y-datos.md` — Requisitos. Se basa en las secciones consolidadas: 40, 41, 42, 43.
- `especificacion/16-validacion/validacion-resultados-y-simulaciones.md` — Validacion. Se basa en las secciones consolidadas: 45.
- `especificacion/17-politicas-pendientes/politicas-pendientes.md` — Politicas Pendientes. Se basa en las secciones consolidadas: 44.

## Principio de organización

Cada archivo existe porque contiene una unidad documental con material suficiente y conceptualmente relacionado. No se crean archivos únicamente para completar una estructura. Cuando varios apartados pertenecen al mismo concepto, se mantienen juntos.

## Regla maestra

La especificación distingue entre intención (Operación), hecho económico externo (Movimiento), demostración (Evidencia), cálculo (Tasa y reglas económicas) y coordinación/registro del proceso (Tu Cambio).
