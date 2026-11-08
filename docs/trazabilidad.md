# Trazabilidad de reglas de negocio

Una fila por regla RN-01 a RN-15: que la implementa (`Mecanismo`), en que archivo vive
(`Archivo`) y que caso la prueba (`Caso de prueba`). Las reglas que implementa la tarea 2.4
(`005_triggers.sql`) quedan completas; el resto se completa en las tareas 2.6 y 2.7.

| RN | Regla | Mecanismo | Archivo | Caso de prueba |
| :--- | :--- | :--- | :--- | :--- |
| RN-01 | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) |
| RN-02 | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) |
| RN-03 | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) |
| RN-04 | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) |
| RN-05 | La composicion de cepas suma 100 % | `fn_tg_composicion_cien` (constraint trigger diferido) | `db/migrations/005_triggers.sql` | pendiente tareas 2.6/2.7 (matriz plan_005.md §9) |
| RN-06 | Porcentaje de descuento segun tipo de cliente | `fn_descuento_cliente` + columna generada `cliente.descuento` (R-002) | `db/migrations/001_esquema.sql` (funcion y columna), `db/migrations/003_funciones.sql` (COMMENT), `db/migrations/005_triggers.sql` (T1 lee la columna) | `db/tests/db_tests.sql` seccion 16 (R-002) |
| RN-07 | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) |
| RN-08 | Calculo de importes de linea y de totales | `fn_tg_renglon_venta_completar`, `fn_tg_renglon_venta_actualizar` | `db/migrations/005_triggers.sql` | pendiente tareas 2.6/2.7 (matriz plan_005.md §9) |
| RN-09 | Stock suficiente en la venta | `fn_tg_renglon_venta_completar`, `fn_tg_renglon_venta_actualizar` | `db/migrations/005_triggers.sql` | pendiente tareas 2.6/2.7 (matriz plan_005.md §9) |
| RN-10 | Estado del ingreso avanza por pasos; cabecera inmutable tras en_confeccion (R-003) | `fn_tg_ingreso_estado`: valida transición y congela `fecha`, `id_transportista` y `cuit_bodega` | `db/migrations/005_triggers.sql` | `db/tests/db_tests.sql` sección 17 |
| RN-11 | Estado de transferencia avanza por pasos; sala y fecha_confeccion inmutables tras en_confeccion (R-005) | `fn_tg_transferencia_estado` congela `id_sala`; `fn_tg_transferencia_fecha` protege `fecha_confeccion` | `db/migrations/005_triggers.sql` | `db/tests/db_tests.sql` sección 17 |
| RN-12 | Renglones solo editables en en_confeccion y sus claves no cambian (R-006) | `fn_tg_renglon_documento_bloqueo` rechaza cambios de PK/FK; los renglones se borran y reinsertan | `db/migrations/005_triggers.sql` | `db/tests/db_tests.sql` sección 17 |
| RN-13 | Auditoria de cambios de precio | `fn_tg_vino_precio_auditoria` | `db/migrations/005_triggers.sql` | pendiente tareas 2.6/2.7 (matriz plan_005.md §9) |
| RN-14 | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) |
| RN-15 | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) |
