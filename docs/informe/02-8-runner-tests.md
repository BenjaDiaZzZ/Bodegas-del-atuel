# 2.8 · Runner de tests

**Responsable:** P4 (Front e Infraestructura)
**Dependencias:** 2.6 y 2.7, mergeadas en `main` (PR #16/#17 y PR #20).

## Objetivo

Centralizar la ejecución de los suites de reglas en un script y hacer que el CI
falle cuando una regla se rompe. Antes cada suite se corría a mano, con comandos
distintos y sin un resultado único que pudiera consumir el workflow.

## Entregables

### 1. `scripts/run_db_tests.sh`

Corre los cinco suites contra la base local y devuelve un código distinto de
cero si alguno falla:

| Suite | Qué cubre |
| --- | --- |
| `test_007_roles.sql` | Matriz de privilegios de 006/007, denegaciones 42501, fugas por PUBLIC, ACL por defecto y humo como `app_rw`. |
| `test_006_vistas.sql` | Consistencia de las cuatro vistas y estabilidad de `vw_ventas_mensuales_sala` en distintas zonas horarias. |
| `security_r001.sql` | R-001: `SECURITY DEFINER`, inmutabilidad de documentos y auditoría de precio. |
| `db_tests.sql` | RN-01 a RN-15 y D1, incluidos RN-10/11/12 de 2.7. |
| `test_004_concurrency.sh` | RN-11/RN-12 bajo concurrencia real entre sesiones. |

Comportamiento:

- Carga `.env` y verifica que el contenedor `db` esté corriendo y `healthy`.
- Imprime `PASS`/`FAIL` por suite y las líneas `OK` que cada suite emite por
  regla.
- Ante un fallo, muestra el `ERROR`/`FAIL` y continúa con el resto para dar un
  panorama completo.
- Resume `Suites / PASS / FAIL` y termina con exit code `1` si falló alguna.
- `--reset` llama primero a `./scripts/reset_db.sh` (los prechecks de
  `test_007` exigen una base limpia).
- `--verbose` muestra la salida completa de cada suite.

Uso:

```bash
./scripts/run_db_tests.sh            # base ya inicializada
./scripts/run_db_tests.sh --reset    # recrea la base y corre todo
./scripts/run_db_tests.sh --verbose
```

El orden es `test_007` → `test_006` → `security_r001` → `db_tests` →
`test_004_concurrency`. Los cuatro primeros corren dentro de transacciones o
limpian sus fixtures; el último usa nombres e IDs propios y limpia al salir.
No se ejecuta el seed: los suites crean sus propios datos y `test_007` rechaza
una base con residuos de los IDs `91xx`.

### 2. Job `tests` en el CI

`.github/workflows/ci.yml` agrega el job **Tests de reglas**:

- checkout, cliente de PostgreSQL y `.env` efímero (mismas credenciales que el
  job `db`);
- `./scripts/run_db_tests.sh --reset`, que recrea la base y corre los cinco
  suites.

Se mantiene como job separado de **Migraciones PostgreSQL** para que una regla
rota se vea como un chequeo propio. Cada job de GitHub Actions corre en una
máquina distinta, por eso el runner vuelve a recrear la base con `--reset`.

## Verificación

### Línea base

`./scripts/run_db_tests.sh --reset` sobre base limpia (migraciones 001 a 008):

```text
== test_007_roles ==
PASS test_007_roles
== test_006_vistas ==
PASS test_006_vistas
== security_r001 ==
PASS security_r001
== db_tests ==
PASS db_tests
== test_004_concurrency ==
PASS test_004_concurrency

== Resumen ==
Suites: 5 | PASS: 5 | FAIL: 0
OK: todas las reglas pasaron
```

Los suites de 2.7 confirman RN-10, RN-11 y RN-12:

```text
PASS OK: RN-10 ingreso solo avanza en_confeccion -> terminado -> procesado
PASS OK: RN-11 transferencia solo avanza y fecha_confeccion es inmutable
PASS OK: RN-12 renglones bloqueados fuera de en_confeccion y CASCADE sin error
```

La concurrencia cierra con:

```text
PASS RN-12 rechazo la edicion concurrente: OK
PASS stock_deposito=90 stock_sala=10 estado=procesado (esperado: 90 / 10 / procesado)
```

### Prueba negativa

Para comprobar que el runner detecta una regla rota se revocó a mano
`EXECUTE` de `fn_descuento_cliente(varchar)` a `app_rw` y se corrió el script:

```text
== test_007_roles ==
FAIL test_007_roles (exit 3)
...
== Resumen ==
Suites: 5 | PASS: 4 | FAIL: 1
Fallaron: test_007_roles
runner_exit=1
```

Después se restauró la base con `./scripts/reset_db.sh`. Con esto queda
verificado el criterio de "hecho": el runner devuelve un código distinto de
cero y el job del CI falla si se rompe una regla.

### Validación del workflow

El YAML parsea correctamente y expone tres jobs: `db`, `tests` y `contrato`.

La primera ejecución real del job (`PR #28`) falló en
`test_004_concurrency.sh` con `la sesion A no quedo bloqueada; setup no
deterministico`: en el runner, A podía terminar antes de que la sesión C tomara
el lock. Se agregó una barrera que espera a que C esté durmiendo en `pg_sleep`
(lock ya tomado) antes de lanzar A, y C se libera al terminar la verificación
en vez de esperar 30 s. La prueba pasó 3 de 3 corridas locales y el runner
completo volvió a dar `5/5`.

## Pendientes y observaciones

- El job `tests` todavía no es un chequeo obligatorio para mergear: eso se
  configura en las reglas de protección de rama del repositorio.
- La prueba de concurrencia depende de locks y tiempos; si vuelve a resultar
  inestable en el runner de GitHub se puede aislar como job aparte con
  reintento, sin tocar el resto del runner.
- El runner no reemplaza las mediciones de las Fases 4 y 5; solo ejecuta los
  suites de reglas.
