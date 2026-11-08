# Contratos Técnicos y Convenciones

Este documento define las reglas de juego entre la Base de Datos, la API y el Front-End. Si una decisión está aquí, se asume como ley para todo el equipo. Cualquier cambio sobre este archivo debe hacerse vía PR y avisando a los demás.

## 1. Convenciones Generales
*   **Nombres:** Todo en `snake_case`, sin tildes ni caracteres especiales. 
*   **Claves:** Formato `id_<entidad>`.
*   **Nombres Oficiales:** La fuente de la verdad para nombres de tablas y columnas es `db/migrations/001_esquema.sql`.
*   **Identificadores:** Son autogenerados por las columnas `IDENTITY`, con excepción de los `CUIT` (bodegas, empleados, transportistas) y el `nro_lote`, que deben ser asignados por el usuario.
*   **Zona Horaria:** La base de datos (tanto local como en la nube) debe operar en `America/Argentina/Buenos_Aires`.

## 2. Tipos de Datos y Semántica
*   **Dinero:** Siempre se usa `NUMERIC(12,2)`.
*   **Porcentajes:** Siempre se usa `NUMERIC(5,2)` (ej. composición de cepas, `cliente.descuento`).
*   **⚠️ ATENCIÓN con los descuentos:** 
    *   `cliente.descuento` = Porcentaje (0 a 100). Es una columna generada (`GENERATED ALWAYS AS (fn_descuento_cliente(tipo)) STORED`, R-002): la base la deriva de `tipo`. La API nunca la envía ni la modifica; un `INSERT` o `UPDATE` que la incluya falla con `SQLSTATE 428C9`.
    *   `comprobante.descuento` y `renglon_comprobante.descuento` = **Monto de dinero descontado** (ej. $150.00), no porcentaje.

## 3. Interacción con la API (Reglas de Negocio)
*   **Errores de Reglas:** Los triggers y funciones usarán `RAISE EXCEPTION '[RN-XX] Mensaje'`. Esto genera un `SQLSTATE P0001`.
*   **Manejo de Mensajes:** La API debe interceptar el error P0001, traducirlo a HTTP 409 y enviar al Front exactamente el mismo texto del mensaje (ej. `[RN-09] Stock insuficiente...`).
*   **Transacciones Diferidas:** El constraint trigger de la RN-05 (porcentajes suman 100) falla recién al ejecutar el `COMMIT`. La API debe capturar las excepciones en la confirmación de la transacción, no solo en la ejecución del `INSERT`/`UPDATE`.
*   **Roles:** La API se conectará utilizando el rol `app_rw`. Para consultas de los reportes se puede usar `reporte_ro`. (Definidos en las variables de entorno).

### Modelo de privilegios de `app_rw` (hallazgo R-001)

La corrección de R-001 (en `db/migrations/004_procedimientos.sql`,
`db/migrations/005_triggers.sql` y `db/migrations/007_roles.sql`) mueve la
integridad a rutinas `SECURITY DEFINER` y reduce lo que la API puede escribir
directamente con `app_rw`:

*   `app_rw` **no puede** hacer `UPDATE` sobre totales (`comprobante.subtotal`,
    `descuento`, `total`), `stock_sala` ni `stock_deposito`, y **no puede**
    `DELETE` `comprobante` ni `renglon_comprobante`. Esos cambios ocurren solo
    dentro de T1, T2, T7 y los procedures.
*   Los `INSERT` deben indicar la lista de columnas permitida: `comprobante`
    (`fecha`, `id_cliente`, `id_sala`), `renglon_comprobante` (`nro_comprobante`,
    `cod_vino`, `cantidad`), `ingreso` (`fecha`, `id_transportista`,
    `cuit_bodega`) y `transferencia` (`id_sala`). Las columnas calculadas por
    trigger y los `DEFAULT`/`IDENTITY` quedan fuera del `GRANT`.
*   El avance de estado se limita a `UPDATE ... SET estado = ...` en `ingreso` y
    `transferencia`; los movimientos de stock se hacen únicamente con
    `CALL sp_procesar_ingreso(...)` y `CALL sp_procesar_transferencia(...)`.
*   Los renglones de documento admiten `UPDATE (cantidad)` y `DELETE` mientras
    el documento esté `en_confeccion`.
*   La auditoría la escribe T7: `usuario` sale de `app.usuario` o, si no está
    seteado, de `session_user`.

La matriz completa, el `SET search_path` de cada rutina DEFINER y las razones
están en `db/migrations/005_triggers.sql` (T1, T2, T7),
`db/migrations/004_procedimientos.sql` (procedures) y
`db/migrations/007_roles.sql` (matriz de `app_rw`), y se verifican en
`db/tests/security_r001.sql`.

### Tabla de Traducción de Errores en la API
| SQLSTATE | HTTP | Significado |
| :--- | :--- | :--- |
| `23505` | 409 | UNIQUE violado (Registro duplicado). |
| `23503` | 409 / 422 | FK violada (Dato inexistente o en uso). |
| `23514` / `23502` | 422 | CHECK o NOT NULL violado. |
| `428C9` | 422 | Escritura sobre una columna generada (`cliente.descuento`, R-002). |
| `P0001` | 409 | Regla de negocio rechazada (RAISE EXCEPTION). |
| `P0002` | 404 | Documento inexistente (`sp_procesar_ingreso` / `sp_procesar_transferencia`). |
| `22P02` | 400 | Formato de texto inválido (ej. letra en un ID numérico).|
| `55P03` | 503 | Espera de lock vencida, solo si el despliegue configura `lock_timeout`/`statement_timeout` (la base no lo hace por defecto). Reintentar. |
| `40001` / `40P01` | 503 | Fallo de concurrencia o deadlock (Sugerir reintento). |

## 4. Flujos Operativos y Transacciones

### Ventas (Comprobantes)
*   **Comprobante Inmutable:** No existe la anulación ni modificación de ventas una vez creadas.
*   **Un vino por documento:** Un mismo `cod_vino` no puede aparecer en dos renglones distintos del mismo comprobante, ingreso o transferencia. La API debe sumar las cantidades antes de enviar.
*   **Carga de renglones:** La API **solo** envía `(cod_vino, cantidad)`. 
    *   *El Trigger BEFORE* completa el `precio_unitario`, `descuento` y `subtotal`.
    *   *El Trigger AFTER* descuenta el stock de la sala y actualiza los totales de la cabecera.
    ```sql
    -- Ejemplo de la API (en una misma transacción):
    INSERT INTO comprobante (id_cliente, id_sala) VALUES (1, 2) RETURNING nro_comprobante;
    INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (123, 10, 5);
    ```

### Ingresos y Transferencias
*   **Cabeceras y claves inmutables (R-003/R-005/R-006):** al salir de `en_confeccion`, no se modifican `ingreso.fecha`, `ingreso.id_transportista`, `ingreso.cuit_bodega` ni `transferencia.id_sala`. Las claves de `renglon_ingreso` y `renglon_transferencia` tampoco se actualizan: para mover o cambiar el vino, se borra y reinserta el renglón mientras el documento siga en confección.
*   **Fecha de Transferencia:** La API NO envía la fecha. Un trigger fuerza la inserción de la fecha actual y bloquea las modificaciones (RN-11).
*   **Cambio de Estado:** La API avanza el documento a terminado con un `UPDATE`:
    ```sql
    UPDATE transferencia SET estado = 'terminado' WHERE nro_solicitud = 123;
    ```
*   **Procesamiento:** Para mover el stock, la API delega todo llamando al procedimiento almacenado:
    ```sql
    CALL sp_procesar_transferencia(123);
    ```

### Clientes
*   **Alta de clientes:** La API debe insertar en la misma transacción el registro en la tabla `cliente` y el registro correspondiente en su tabla de subtipo (`socio`, `distribuidor` o `exportador`), usando el mismo valor de la columna `tipo` en ambas.

### Auditoría (RN-13)
*   **Usuario Activo:** La API debe configurar la variable local de sesión para que el trigger sepa quién cambia un precio. Esto se hace inmediatamente después del `BEGIN`:
    ```sql
    BEGIN;
    SET LOCAL app.usuario = 'admin@bodega.com';
    UPDATE vino SET precio_venta = 15000 WHERE cod_vino = 10;
    COMMIT;
    ```
*   **Trigger:** Utilizará la función `COALESCE(NULLIF(current_setting('app.usuario', true), ''), current_user)` para capturar el valor o el rol de BD si está vacío.

## 5. Firmas Oficiales en Base de Datos y Fórmulas

### Funciones y Reglas de Negocio (RN-06 y RN-08)
Cualquier cambio en estas implementaciones debe ser discutido, ya que impacta en los cálculos financieros del sistema.

| Función | Retorno | Volatilidad | STRICT | Lenguaje | Propósito |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `fn_descuento_cliente(p_tipo varchar)` | `NUMERIC(5,2)` | `IMMUTABLE` | Sí | `plpgsql` | Retorna el porcentaje según tipo de cliente; `NULL` devuelve `NULL`. |
| `fn_total_comprobante(p_nro integer)` | `TABLE(subtotal NUMERIC(12,2), descuento NUMERIC(12,2), total NUMERIC(12,2))` | `STABLE` | No | `sql` | Devuelve una fila con los totales de cabecera, incluso sin renglones. |
| `fn_stock_sala(p_sala integer, p_vino integer)` | `INTEGER` | `STABLE` | No | `sql` | Retorna cantidad o 0 si no existe. |
| `fn_antiguedad_anios(p_fecha date)` | `INTEGER` | `STABLE` | Sí | `sql` | Años completos; fecha futura devuelve 0 y `NULL` devuelve `NULL`. |

#### Especificaciones Matemáticas:
*   **Mapeo de Descuentos (RN-06 para `fn_descuento_cliente`):** 
    *   `'socio'` → `10.00`
    *   `'distribuidor'` → `20.00`
    *   `'exportador'` → `30.00`
    *   Si se recibe un tipo inexistente, lanzar excepción: `RAISE EXCEPTION '[RN-06] Tipo de cliente desconocido: %', p_tipo;`
*   **Fórmulas y Redondeos (RN-08 para triggers de renglones):**
    Todo cálculo monetario debe redondearse a 2 decimales explícitamente en base de datos.
    *   `precio_bruto = cantidad * precio_unitario`
    *   `descuento = ROUND(precio_bruto * (porcentaje_cliente / 100.0), 2)`
    *   `subtotal = precio_bruto - descuento`
*   **Agregación de cabecera (`fn_total_comprobante`):** `renglon_comprobante.subtotal` es neto y ya incluye el redondeo por línea; cabecera `subtotal` = `SUM(renglon_comprobante.subtotal + renglon_comprobante.descuento)`, `total` = `SUM(renglon_comprobante.subtotal)` y `descuento` = `subtotal - total`. Sin renglones (o con `p_nro IS NULL`) devuelve una fila `(0, 0, 0)`. El consumidor debe actualizar las tres columnas de cabecera en un único `UPDATE` para satisfacer `ck_comprobante_total`.
*   **Antigüedad:** `fn_antiguedad_anios` usa años completos (`AGE(CURRENT_DATE, p_fecha)`); fechas futuras se limitan a 0. Al ser `STRICT`, una fecha `NULL` devuelve `NULL`.

### Procedimientos (El llamador es dueño de la transacción)
Los procedimientos **no** hacen `COMMIT` ni `ROLLBACK`. La API abre la transacción (`BEGIN`) y confirma o revierte; cualquier excepción del procedimiento sube y revierte todo (estado y stocks). Un `COMMIT` interno fallaría con `SQLSTATE 2D000` cuando el `CALL` está dentro de un `BEGIN` explícito.

| Procedimiento | Parámetros | Propósito |
| :--- | :--- | :--- |
| `sp_procesar_ingreso` | `p_cod integer` | Mueve el ingreso a procesado y suma stock al depósito. |
| `sp_procesar_transferencia` | `p_nro integer` | Valida stock del depósito, resta de allí, suma a sala y cambia estado. |

## 6. Datasets y Pruebas
*   **Herramienta de carga:** Se debe usar `scripts/seed.sh`.
*   **Escalas:** 
    *   `--scale small` (datos mínimos para desarrollar).
    *   `--scale full` (carga completa para medir rendimiento).
