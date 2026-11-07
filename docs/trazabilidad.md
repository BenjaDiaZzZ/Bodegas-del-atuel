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
| RN-06 | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) |
| RN-07 | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) |
| RN-08 | Calculo de importes de linea y de totales | `fn_tg_renglon_venta_completar`, `fn_tg_renglon_venta_actualizar` | `db/migrations/005_triggers.sql` | pendiente tareas 2.6/2.7 (matriz plan_005.md §9) |
| RN-09 | Stock suficiente en la venta | `fn_tg_renglon_venta_completar`, `fn_tg_renglon_venta_actualizar` | `db/migrations/005_triggers.sql` | pendiente tareas 2.6/2.7 (matriz plan_005.md §9) |
| RN-10 | Los estados del ingreso solo avanzan | `fn_tg_ingreso_estado` | `db/migrations/005_triggers.sql` | pendiente tareas 2.6/2.7 (matriz plan_005.md §9) |
| RN-11 | Los estados de la transferencia solo avanzan; fecha_confeccion inmutable | `fn_tg_transferencia_estado`, `fn_tg_transferencia_fecha` | `db/migrations/005_triggers.sql` | pendiente tareas 2.6/2.7 (matriz plan_005.md §9) |
| RN-12 | Los renglones son editables solo en en_confeccion | `fn_tg_renglon_documento_bloqueo` | `db/migrations/005_triggers.sql` | pendiente tareas 2.6/2.7 (matriz plan_005.md §9) |
| RN-13 | Auditoria de cambios de precio | `fn_tg_vino_precio_auditoria` | `db/migrations/005_triggers.sql` | pendiente tareas 2.6/2.7 (matriz plan_005.md §9) |
| RN-14 | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) |
| RN-15 | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) | pendiente (tarea 2.6/2.7) |
