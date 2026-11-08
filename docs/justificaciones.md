# Decisiones de Diseño - Bodegas del Atuel
**Trabajo Práctico Integrador - Etapa 1**

En este documento explicamos y justificamos las decisiones que tomamos como grupo para diseñar el Modelo Relacional y la base de datos, cumpliendo con lo que pide la cátedra en la Sección 5.

## 1. Jerarquía de clientes
Teníamos tres tipos de clientes (Socio, Distribuidor y Exportador). Para pasarlo a tablas elegimos la opción de **Supertipo y Subtipos**.
*   **Cómo lo hicimos:** Creamos una tabla general llamada `cliente` con todos los datos comunes (documento, dirección, localidad) y una columna `tipo` (que funciona como discriminador). Luego creamos tres tablas (`socio`, `distribuidor` y `exportador`) donde la Primary Key (PK) es la misma que la Foreign Key (FK) hacia `cliente`.
*   **Por qué lo elegimos:** Nos pareció la mejor forma de no tener celdas con valores `NULL`. Si hacíamos una sola tabla grande, el socio iba a tener vacía la zona de cobertura del distribuidor. 
*   **Ejemplo:** Al tener una tabla `exportador` separada, podemos conectarle los `permiso_exportacion` directamente ahí. Así la base de datos asegura por estructura que un "Socio" jamás pueda tener asociado un permiso de exportación.

## 2. Claves Naturales vs Subrogadas (IDs generados)
Analizamos tabla por tabla para ver qué convenía usar como Primary Key (PK).
*   **Claves Subrogadas (Identity):** Las usamos en la mayoría de las tablas (`localidad`, `sala`, `vino`, `cliente`, `comprobante`). Lo hicimos porque son más cortas, seguras y los datos reales pueden cambiar (como si un cliente cambia de DNI a CUIT). 
    *   *Ejemplo:* En `vino`, usamos `cod_vino` numérico generado por la base. Para que no nos carguen datos duplicados, en `002_constraints.sql` le agregamos un `UNIQUE (nombre_comercial, anada, presentacion_ml)` para asegurarnos de que no exista dos veces el "Malbec Reserva 2021 de 750ml".
*   **Claves Naturales:** Solo las dejamos en la `bodega` y en el `empleado` usando el **CUIT**, porque es un dato único, obligatorio y que no cambia nunca. El mismo apunte de la teoría daba el ejemplo usando el CUIT de la bodega, así que seguimos esa línea.
*   **Claves Compuestas:** Las usamos en las tablas intermedias y débiles. 
    *   *Ejemplo:* La `parcela` es débil, así que su clave es `(id_finca, nro_parcela)`. Y en `renglon_comprobante`, la clave es la combinación `(nro_comprobante, cod_vino)`.

## 3. Atributos Derivados (Totales, Subtotales y Descuentos)
Teníamos que decidir si guardar los importes en las tablas o calcularlos al vuelo con consultas SELECT. 
*   **Decisión:** Decidimos **almacenar** los totales, subtotales y los descuentos aplicados en las tablas `comprobante` y `renglon_comprobante`. El porcentaje de descuento que corresponde a cada cliente es una columna generada de `cliente.tipo` (`cliente.descuento NUMERIC(5,2) GENERATED ALWAYS AS (fn_descuento_cliente(tipo)) STORED`, R-002), mientras que en `comprobante` y `renglon_comprobante` el `descuento` es el importe ya aplicado (`NUMERIC(12,2)`).
*   **Tradeoff:** Al ser una columna generada desde `tipo`, no se puede fijar un descuento distinto por cliente individual; el porcentaje queda determinado por la regla RN-06 (socio 10 %, distribuidor 20 %, exportador 30 %).
*   **Justificación:** Lo hicimos por rendimiento y para proteger la historia. Si mañana nos piden un reporte de ventas trimestral sobre 150.000 comprobantes, calcular todo al vuelo iba a ser muy lento. 
*   **Ejemplo:** En `renglon_comprobante` copiamos y guardamos el `precio_unitario` y el `descuento` exactos del momento de la venta. Si la semana que viene el vino aumenta de $12.500 a $15.000 (RN-13), la venta vieja no se rompe ni altera su total.
*   **Consistencia:** Para que estos datos no queden desactualizados, **no vamos a dejar que se carguen a mano por sistema**. Vamos a programar Triggers (RN-08) que calculen solos los totales cada vez que se inserte un renglón. 
*   *Excepción:* La antigüedad laboral del empleado sí la vamos a calcular al vuelo con una función (`fn_antiguedad_anios`), porque cambia todos los días y guardarla fija no tiene sentido.

## 4. Acciones Referenciales (ON DELETE y ON UPDATE)
*   **RESTRICT:** Lo usamos en los catálogos y tablas principales (`vino`, `sala`, `comprobante`, `bodega`). La justificación es proteger la historia productiva y comercial. 
    *   *Ejemplo:* Cumpliendo la regla RN-14, si intentamos hacer un DELETE de un `vino` que ya tiene movimientos en `renglon_comprobante` o `auditoria_precio`, el RESTRICT frenará la acción para no dejar datos huérfanos.
*   **CASCADE:** Lo usamos solamente cuando el "hijo" no tiene sentido si desaparece el "padre". 
    *   *Ejemplo:* En la relación de `comprobante` hacia sus renglones. Si por la consigna D1 de la Etapa 5 nos toca borrar comprobantes viejos de hace más de 5 años, el CASCADE va a limpiar automáticamente todas sus botellas detalladas sin que tengamos que borrarlas a mano.
*   **ON UPDATE CASCADE:** Lo pusimos en todas las claves foráneas del esquema. En las claves subrogadas (identity) el valor nunca se actualiza, así que es inocuo; en las claves naturales (como el CUIT de la `bodega`) cubre el caso de que un administrador cargue mal el CUIT y lo edite, para que el número nuevo se propague solo a todos los vinos que elabora.

## 5. Dónde va a vivir cada regla de negocio
Para proteger la base de datos sin importar si se accede desde la API o desde PgAdmin, definimos esto:
*   **CHECK:** Para las reglas de una sola fila. 
    *   *Ejemplo:* La RN-15 dice que la graduación alcohólica está entre 5 y 20, eso lo resolvemos fácil con `CHECK (graduacion BETWEEN 5 AND 20)` en la tabla `vino`.
*   **UNIQUE / FK:** Para garantizar que un dato no se repita o que exista en un catálogo (RN-02, RN-03, RN-04).
*   **Triggers y Procedimientos:** Para todo lo que implique mirar el estado actual de otras tablas. 
    *   *Ejemplo:* La RN-09 exige no vender más de lo que hay en stock en la sala. Eso no se puede hacer con un CHECK, requiere un `TRIGGER BEFORE INSERT` en el renglón que vaya a hacer un `SELECT cantidad FROM stock_sala` antes de autorizar la venta.

## 6. Detalles extras de normalización (3FN)
Revisamos que todo cumpla con la Tercera Forma Normal (3FN). 
*   **Encargado Regional:** Lo dejamos como un campo de texto adentro de `localidad` y no en la `sala_venta`. Si lo poníamos en la sala, el encargado dependía de la localidad y no de la sala (dependencia transitiva), lo cual rompía la 3FN.
*   **Departamentos y Provincias:** No hicimos tablas separadas para "Provincia" o "Departamento", simplemente son atributos descriptivos en `finca` o `localidad`. Un nombre de departamento (ej. "San Martín") existe en varias provincias distintas, así que no hay dependencia funcional directa que nos obligue a crear esas tablas extra. 
*   **Tipos de Datos:** Elegimos `NUMERIC` para todo lo que sea plata (salarios, precios) para no tener errores de redondeo como pasa con los `FLOAT`. Y usamos `ENUM` (`estado_documento`) para los estados (en_confeccion, terminado, procesado) así nos aseguramos de que no ingresen texto basura en la BD.