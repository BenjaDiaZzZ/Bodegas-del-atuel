# Tablero de tareas

Lista de issues para cargar en GitHub Projects. Crear **un issue por fila**, con etiqueta de fase (`fase-0` … `fase-9`) y responsable. Los IDs coinciden con el plan de trabajo del grupo.

## Fase 0 · Arranque común

- [ ] **0.1** Crear el repositorio y el tablero — P4
- [ ] **0.2** Docker Compose inicial — P4
- [ ] **0.3** Convenciones y contrato técnico — P1
- [ ] **0.4** Decidir el stack — P3
- [ ] **0.5** Consultas al docente — P3
- [ ] **0.6** Pre-chequeo de proveedores de nube — P4
- [ ] **0.7** Primer commit de cada integrante — todos

## Fase 1 · Modelado (H1)

- [ ] **1.1** Diagrama entidad-relación — P1
- [ ] **1.2** Esquema relacional y decisiones de diseño — P1
- [ ] **1.3** Esquema físico `001_esquema.sql` — P1
- [ ] **1.4** Catálogos en CSV — P2
- [ ] **1.5** Normalización a 3FN — P2
- [ ] **1.6** Diccionario de datos — P2
- [ ] **1.7** OpenAPI borrador y revisión de 001 — P3
- [ ] **1.8** CI, mock y bocetos — P4
- [ ] **1.9** Revisión cruzada y cierre de H1 — P2 y P3

## Fase 2 · Integridad y lógica (H2)

- [ ] **2.1** Constraints `002_constraints.sql` — P1
- [ ] **2.2** Funciones `003_funciones.sql` — P1
- [ ] **2.3** Procedimientos `004_procedimientos.sql` — P2
- [ ] **2.4** Triggers `005_triggers.sql` — P1
- [ ] **2.5** Vistas y roles — P3
- [ ] **2.6** Tests RN-01 a RN-09 y RN-13 a RN-15 — P1
- [ ] **2.7** Tests RN-10 a RN-12 y procedimientos — P2
- [ ] **2.8** Runner de tests — P4
- [ ] **2.9** Demostración de concurrencia — P2
- [ ] **2.10** Tabla de trazabilidad — P1 y P2

## Fase 3 · Carga masiva (H3)

- [ ] **3.1** Orden de carga — P2
- [ ] **3.2** Script de carga — P2
- [ ] **3.3** Datos pensados para las consultas de la sección 8 — P2
- [ ] **3.4** Estrategia frente a los triggers — P2
- [ ] **3.5** Carga eficiente y medición — P2
- [ ] **3.6** Consultas de control — P2
- [ ] **3.7** Script y volcado — P2
- [ ] **3.8** Prueba de reproducibilidad — P1
- [ ] **3.9** Backup y restauración locales — P4

## Fase 4 · Índices y rendimiento (H4)

- [x] **4.1** Mediciones «antes» — P2
- [x] **4.2** Diseño de índices `008_indices.sql` — P2
- [x] **4.3** Mediciones «después» y tabla comparativa — P2
- [x] **4.4** Orden de columnas e índice descartado — P2
- [x] **4.5** Costo de escritura — P2
- [x] **4.6** Caso en que el planificador no usa un índice — P2
- [x] **4.7** Revisión cruzada — P1

## Fase 5 · Consultas SQL (H5)

- [ ] **5.1** `consultas/update.sql` (U1 a U6) — P1
- [ ] **5.2** `consultas/insert.sql` (I1 a I6) — P1
- [ ] **5.3** `consultas/delete.sql` (D1 a D6) — P3
- [ ] **5.4** `consultas/select.sql` parte 1 (S1, S4, S8 a S12) — P2
- [ ] **5.5** `consultas/select.sql` parte 2 (S2, S3, S5, S6, S7) — P4

## Fase 6 · API REST (H6)

- [ ] **6.1** Esqueleto y `/salud` — P3
- [ ] **6.2** Stubs de los endpoints — P3
- [ ] **6.3** Capa de acceso a datos — P3
- [ ] **6.4** Manejo central de errores — P3
- [ ] **6.5** Catálogo de vinos — P3
- [ ] **6.6** Alta, modificación y baja de vinos — P3
- [ ] **6.7** CRUD de clientes — P3
- [ ] **6.8** Comprobantes — P3
- [ ] **6.9** Transferencias e ingresos — P3
- [ ] **6.10** Reportes — P3
- [ ] **6.11** Pruebas automáticas — P3
- [ ] **6.12** Demostración de inyección SQL fallida — P3
- [ ] **6.13** Dockerfile y documentación — P3
- [ ] **6.14** Revisión de seguridad y lógica — P1

## Fase 7 · Front (H7)

- [ ] **7.1** Estructura y capa de llamadas — P4
- [ ] **7.2** Catálogo de vinos — P4
- [ ] **7.3** Alta y edición de vino — P4
- [ ] **7.4** Nueva venta — P4
- [ ] **7.5** Transferencias — P4
- [ ] **7.6** Tablero — P4
- [ ] **7.7** Errores y compose — P4

## Fase 8 · Despliegue en la nube (H8)

- [ ] **8.1** Elección de proveedor — P4
- [ ] **8.2** Base y roles en la nube — P4
- [ ] **8.3** Migraciones — P4
- [ ] **8.4** Datos — P2
- [ ] **8.5** Despliegue de la API — P4 con apoyo de P3
- [ ] **8.6** Despliegue del front — P4
- [ ] **8.7** Verificación de seguridad — P1
- [ ] **8.8** Backup y restauración — P2
- [ ] **8.9** Regla funcionando en la nube — P1

## Fase 9 · Documentación y defensa (H9)

- [ ] **9.1** README principal — P4
- [ ] **9.2** Informe final — P3
- [ ] **9.3** Trazabilidad completa — P1
- [ ] **9.4** Guion de la demo — P2
- [ ] **9.5** Prueba en máquina limpia — P2
- [ ] **9.6** Preparación de la defensa individual — todos
- [ ] **9.7** Ensayo de modificaciones en vivo — todos
- [ ] **9.8** Lista de control final — todos

## Revisiones a cargo de P4

- [ ] **2.5** Vistas y roles (P3)
- [ ] **2.6 y 2.7** Tests de reglas (P1 y P2)
- [ ] **5.3** `consultas/delete.sql` (P3)
- [ ] **6.11** Pruebas automáticas (P3)
- [ ] **6.13** Dockerfile y documentación (P3)
