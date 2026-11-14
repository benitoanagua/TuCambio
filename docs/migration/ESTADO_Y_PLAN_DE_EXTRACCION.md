# Estado de migración: Tu-Pago-App → TuCambio

**Fecha de corte:** 2026-11-14  
**Rama de trabajo:** `migration/m1-13-destination-snapshot-isolation`  
**Base:** `main` en `b9eb1a966e5cc84af6db623d9702ad0c41193c8e`

## 1. Propósito

TuCambio es la plataforma libre, abierta, genérica y multimoneda para cualquier persona u organización que compre y venda monedas. Tu-Pago-App es una implementación de referencia y fuente de experiencia funcional; no es una plantilla que deba copiarse literalmente.

La migración extrae contratos, reglas y pruebas que sean aplicables después de generalizarlos. La especificación funcional de TuCambio tiene precedencia sobre el comportamiento particular del producto de origen.

## 2. Estado verificado del destino

En la revisión del repositorio `benitoanagua/TuCambio` se verificó:

- Rama principal `main`, commit `19460cbb709f5814c82cb643ffd311ca0236397d`.
- Backend Kotlin/JVM + Ktor.
- PostgreSQL 17 como base de validación de migraciones y Supabase como plataforma destino.
- Autenticación JWT de Supabase y resolución de membresía/capacidades por tenant.
- RLS, almacenamiento privado de evidencias y funciones PostgreSQL backend-only.
- Alta de monedas, pares, tasas, operaciones y movimientos con claves de idempotencia.
- Asociación explícita de movimientos a operaciones con rol de origen o destino.
- Verificación de movimientos externos y resolución de tasa desde el instante efectivo del movimiento de origen confirmado.
- Snapshot inmutable del movimiento e importe de origen verificados.
- Snapshot inmutable del movimiento, importe e instante efectivo de destino confirmados, expuesto en consultas financieras.
- Cálculo monetario genérico con precisión configurada por moneda y modo de redondeo explícito.
- Asociaciones de evidencias, consultas financieras e historial de auditoría.

La ejecución más reciente observada de `backend-ci` para el commit base terminó correctamente: migraciones PostgreSQL, pruebas Kotlin y construcción Docker.

## 3. Límites actuales que deben respetarse

La implementación existente no debe interpretarse como un flujo financiero completo. En particular:

- Crear una operación no confirma que haya ingresado dinero.
- Registrar un movimiento no equivale a verificarlo.
- Subir o asociar evidencia no confirma el movimiento.
- Confirmar el movimiento de origen puede fijar la tasa y el snapshot de origen, pero no autoriza por sí mismo a liquidar.
- El cálculo de destino no debe inventar una política de redondeo ni resolver diferencias/comisiones por defecto.
- TuCambio no custodia fondos ni ejecuta transferencias; registra y coordina hechos externos.

Las políticas P01–P22 de `especificacion/17-politicas-pendientes/politicas-pendientes.md` siguen abiertas. No codificar resultados automáticos para diferencias de depósito, comisiones, redondeo, límites, expiraciones, tasas especiales, pagos de destino insuficientes/excesivos, cancelaciones o devoluciones hasta contar con decisiones aprobadas.

## 4. Inventario de capacidades de origen a generalizar

| Capacidad de Tu-Pago-App | Tratamiento en TuCambio | Estado de revisión |
|---|---|---|
| Dinero exacto y calculadoras | Importe con moneda explícita, precisión configurable y política de redondeo explícita | Contrato destino presente; extracción de código/pruebas del origen pendiente |
| Catálogo de monedas y pares | Catálogo extensible y pares por tenant | Modelo destino presente; contraste de origen pendiente |
| Compra/venta bidireccional | Operación genérica moneda origen → moneda destino | Especificación destino presente; contraste de FSM pendiente |
| Cotizaciones temporales | Historial inmutable, vigencia semiabierta y resolución por instante efectivo | Base destino presente; revisar reglas de origen y huecos temporales |
| Cuentas de cobro y destinos | Canales/destinos configurables por moneda, país, dirección y proveedor | Generalización conceptual definida; modelo operativo completo pendiente |
| Movimientos y conciliación | Hechos externos independientes, asociables y verificables | Base destino presente; ciclo completo pendiente |
| Comprobantes | Evidencias múltiples, privadas, trazables y asociadas explícitamente | Storage y asociaciones presentes; antimalware/retención pendientes |
| Auditoría | Eventos append-only con actor, tenant, instante y correlación | Lectura y escritura base presentes; revisar cobertura de eventos |
| Caja, arqueo y cierre | Módulos opcionales con saldos separados por moneda | No portar hasta revisar contratos e invariantes |
| Roles y permisos | Capacidades y roles configurables por tenant | Base destino presente; revisar matriz de origen sin copiar privilegios |
| Notificaciones | Adaptadores desacoplados y eventos/outbox | Pendiente |
| Aplicaciones Android/UI | Experiencia de referencia, sin marca ni supuestos particulares | Pendiente; no bloquear el núcleo backend |

## 5. Secuencia de trabajo

### M0 — Inventario y contratos

- [x] Confirmar el estado de la rama principal y el CI del destino.
- [x] Verificar la estructura del backend, migraciones SQL, pruebas y especificación funcional del destino.
- [x] Identificar las políticas económicas que continúan abiertas.
- [ ] Inspeccionar los módulos y pruebas equivalentes de Tu-Pago-App.
- [ ] Completar la matriz archivo/contrato origen → regla destino → prueba destino.
- [ ] Registrar explícitamente qué código no se porta por dependencia de Firebase, Android, proveedor, moneda, país o marca.

### M1 — Núcleo monetario

- [x] Verificar la existencia del modelo de importe, par y calculadora con precisión por moneda.
- [ ] Contrastar fórmulas, dirección, precisión y casos límite con el origen.
- [ ] Ampliar pruebas de pares invertidos, escalas 0–18, divisiones no exactas y entradas inválidas.
- [ ] Mantener el redondeo como parámetro explícito hasta aprobar P04.

### M2 — Ciclo operativo

- [x] Verificar creación de operación y registro de movimientos externos.
- [x] Verificar asociación origen/destino, verificación y snapshot de origen.
- [x] Verificar asociación de evidencias.
- [x] Capturar en la operación el snapshot inmutable del movimiento de destino confirmado, validando tenant, asociación y moneda.
- [x] Probar importe/instante exactos, rechazo de moneda destino incompatible y protección contra mutación.
- [x] Exponer el snapshot de destino en consultas de lectura.
- [x] Añadir una prueba negativa que impide a un actor sin membresía leer el snapshot de destino de otro tenant.
- [ ] Completar el contrato de incidencias y transiciones posteriores sin inventar reglas de liquidación.
- [ ] Asegurar que diferencias, incidencias y estados no se resuelvan automáticamente.

### M3 — Operador, seguridad y auditoría

- [x] Verificar membresías, capacidades, aislamiento tenant y RLS en la base actual.
- [x] Cubrir el aislamiento cross-tenant en comandos y consultas financieras, incluido el snapshot de destino.
- [ ] Completar auditoría sistemática de pruebas negativas para cada nuevo comando/consulta.
- [ ] Completar revisión de eventos de auditoría y recuperación ante fallos.

### M4/M5 — Aplicaciones, integración y publicación

- [ ] Diseñar UI genérica para operadores individuales y organizaciones/sucursales.
- [ ] Integrar ciclo de sesión del cliente con Supabase Auth.
- [ ] Implementar outbox/worker y notificaciones desacopladas.
- [ ] Revisar retención y análisis antimalware de evidencias.
- [ ] Completar E2E y guías de despliegue/contribución.

## 6. Próximo bloque de implementación

**M1.12 está integrado en `main` mediante el PR #28.** Captura el movimiento de destino confirmado como hecho externo inmutable y lo expone en consultas financieras. M1.13 refuerza la prueba de aislamiento tenant de esa lectura. El siguiente bloque es la auditoría sistemática de autorización y auditoría de comandos/consultas; las reglas de incidencias y transiciones económicas siguen bloqueadas hasta aprobar las políticas pendientes.

Este bloque no debe:
- transferir fondos ni llamar a bancos;
- inventar un monto final cuando falte una política económica;
- convertir una evidencia en confirmación automática;
- introducir cuentas o proveedores específicos en el dominio;
- marcar una operación como liquidada solo por registrar un movimiento.

Antes de implementar reglas económicas nuevas, contrastar el contrato con las secciones 24–26 y 29–35 de la especificación y con los módulos equivalentes de Tu-Pago-App. No resolver P13/P14 ni otras políticas pendientes por inferencia.

## 7. Criterio de avance

Cada bloque se entrega con:
1. contrato y alcance explícitos;
2. migración SQL reversible o estrategia documentada de evolución;
3. pruebas PostgreSQL de autorización, aislamiento, idempotencia y concurrencia;
4. pruebas Kotlin de validación y manejo de errores;
5. documentación actualizada;
6. CI verde antes de continuar.

No desplegar Supabase remoto ni infraestructura, no copiar datos reales ni secretos y no fusionar cambios sin validación.
