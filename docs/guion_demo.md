# Guion de la demo (Tarea 9.4 — P2)

## Preparación (5 minutos antes de la demo)

1. **Aiven activo:** verificar que la base no esté pausada por inactividad. Si lo está, encender desde la consola de Aiven y esperar a que esté disponible.
2. **API corriendo:** `GET /salud` debe responder 200.
3. **Front accesible:** abrir la URL del front y verificar que carga el catálogo.
4. **Backup previo:** tener un `pg_dump` reciente por si algo sale mal.
5. **Datos de prueba:** verificar con `db/seed/controles.sql` que no hay errores.

## Guion paso a paso (15 minutos)

### 1. Introducción (2 min)

> "Bodegas del Atuel es un sistema de gestión y distribución vitivinícola. La base de datos es el corazón: modelo relacional, constraints, funciones, triggers, procedimientos almacenados, índices y consultas analíticas. Está desplegada en Aiven con la API accediendo por SSL y roles diferenciados."

### 2. Modelo de datos (2 min)

- Mostrar el DER o el diagrama del esquema.
- Explicar las 29 tablas y las 34 FK.
- Destacar la normalización a 3FN (`docs/normalizacion.md`).
- Mencionar los tipos: `NUMERIC(12,2)` para dinero, `cuit_dom` para CUIT, `estado_documento` para estados.

### 3. Integridad y reglas de negocio (3 min)

Demostrar en `psql` o desde la API:

| Regla | Demostración |
|---|---|
| RN-05 | Insertar composición 60+30 → `COMMIT` falla con `[RN-05]` |
| RN-06 | `SELECT fn_descuento_cliente('socio')` → 10.00 |
| RN-08 | Insertar renglon_comprobante → trigger calcula precio, descuento y subtotal |
| RN-09 | Vender con stock insuficiente → `[RN-09] Stock insuficiente` |
| RN-10 | `UPDATE ingreso SET estado='procesado'` desde `en_confeccion` → `[RN-10]` |
| RN-11 | `UPDATE transferencia SET fecha_confeccion = ...` → `[RN-11] fecha inmutable` |
| RN-12 | Editar renglón de documento terminado → `[RN-12]` |
| RN-13 | `UPDATE vino SET precio_venta=...` → registro en `auditoria_precio` |

### 4. Concurrencia (2 min)

- Mostrar `docs/informe/03-concurrencia.md`.
- Explicar el lost update sin `FOR UPDATE` (escenario 1).
- Mostrar cómo RN-09 serializa con `SELECT ... FOR UPDATE` (escenario 2).
- Mencionar `test_004_concurrency.sh` para transferencias.

### 5. Carga masiva y rendimiento (2 min)

- Mostrar `seed.sh --scale full` con 350k renglones.
- Mencionar el benchmark: COPY es 125x más rápido que INSERT.
- Mostrar `008_indices.sql` y la tabla comparativa de `05-indices.md`.
- Destacar S1: 4.946ms → 3.332ms con índices.

### 6. Consultas analíticas (2 min)

Ejecutar en vivo 2-3 consultas de `consultas/select.sql`:

- **S4** (ranking vinos): rápido y visual.
- **S11** (rank + acumulado): muestra funciones de ventana.
- **S12** (vinos en todas las salas): división relacional.

### 7. Seguridad y roles (1 min)

- Mostrar `007_roles.sql`: `app_rw` para la API, `reporte_ro` para consultas.
- Mencionar que la API usa `SET LOCAL app.usuario` para auditoría (RN-13).
- Confirmar que PostgreSQL no está expuesto a internet (ip_filter en Aiven).

### 8. Cierre (1 min)

> "El sistema cubre modelado, integridad, lógica de negocio en la base, carga masiva determinística, optimización con índices y consultas analíticas. Todo verificado con tests automatizados y documentado."

## Preguntas frecuentes y respuestas

| Pregunta | Respuesta |
|---|---|
| ¿Por qué triggers y no todo en la API? | Para que la integridad esté garantizada sin importar quién use la base. |
| ¿Qué pasa si se cae la base? | Aiven tiene backup automático; además hacemos `pg_dump` manual pre-demo. |
| ¿Por qué `GENERATED ALWAYS` en vino? | El Anexo A.2 lo pide; evita IDs manuales y conflictos. |
| ¿Cuántos datos puede manejar? | El seed genera 350k renglones sin problemas; los índices mantienen las consultas bajo 5s. |
