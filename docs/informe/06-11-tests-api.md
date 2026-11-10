# 6.11 · Pruebas automáticas de la API (lado P3)

**Responsable:** P3 (API)
**Revisa:** P4 (Front e Infraestructura)
**Dependencias:** 6.3 (repositorios), 6.5–6.10 (endpoints reales) y 6.4
(manejo central de errores).

## Objetivo

Escribir al menos ocho pruebas automáticas de la API, de las cuales al menos
tres provoquen la violación de una regla de negocio y verifiquen el código de
respuesta HTTP: venta sin stock → `409`, transición de estado inválida → `409`
y precio negativo → `422`. El criterio de «hecho» es que las pruebas pasen en
el CI.

## Alcance de este informe

Este documento registra el lado P3: qué pruebas se escribieron, dónde viven y
qué reglas cubren. No duplica:

- `docs/informe/07-api.md`, sección «Estado de 6.11», que resume el estado
  general de la tarea.
- `docs/informe/06-13-compose-ci.md`, que documenta la revisión de P4 sobre
  6.11/6.13 y la integración al CI.

## Suite de pruebas

La suite vive en `api/tests/` y tiene **17 archivos** `test_*.py`. El conteo
estático de definiciones `def test_` es **184** al momento de este informe.

| Archivo | `def test_` |
|---|---:|
| `test_clientes_endpoints.py` | 22 |
| `test_comprobantes_endpoints.py` | 8 |
| `test_db.py` | 11 |
| `test_documentos_endpoints.py` | 18 |
| `test_error_handlers.py` | 3 |
| `test_errors_pg.py` | 6 |
| `test_errors.py` | 21 |
| `test_reportes_endpoints.py` | 10 |
| `test_repos_clientes.py` | 13 |
| `test_repos_comprobantes.py` | 5 |
| `test_repos_documentos.py` | 9 |
| `test_repos_reportes.py` | 6 |
| `test_repos_vinos.py` | 13 |
| `test_salud.py` | 4 |
| `test_stubs.py` | 1 |
| `test_validation_errors.py` | 7 |
| `test_vinos_endpoints.py` | 27 |

El mínimo del plan (8 pruebas, 3 violaciones de regla) queda superado con
amplitud. La suite cubre endpoints HTTP, repositorios, mapeo de errores
SQLSTATE, configuración y conexión.

## Pruebas que violan reglas y verifican el código HTTP

| Regla | Prueba | Archivo:línea | Resultado esperado |
|---|---|---|---|
| RN-09 (venta sin stock) | `test_crear_comprobante_stock_insuficiente_409_rn09_y_atomico` | `test_comprobantes_endpoints.py:325` | `409` `P0001`, `regla: RN-09`, sin persistencia |
| RN-11 (procesar transferencia antes de terminar) | `test_transferencia_procesar_antes_de_terminar_409_rn11` | `test_documentos_endpoints.py:344` | `409` `P0001`, `regla: RN-11` |
| RN-10 (procesar ingreso antes de terminar) | `test_ingreso_procesar_antes_de_terminar_409_rn10` | `test_documentos_endpoints.py:582` | `409` `P0001`, `regla: RN-10` |
| RN-05 (composición que no suma 100) | `test_crear_vino_rn05_409_y_atomi_unicamente` | `test_vinos_endpoints.py:385` | `409` `regla: RN-05`, falla diferida en COMMIT |
| CHECK de precio | `test_crear_vino_precio_negativo_422` | `test_vinos_endpoints.py:434` | `422` `23514` (`ck_vino_precio_venta`) |

Las pruebas de stock y de transición comprueban además que la operación sea
atómica: no queda una fila parcial ni un estado intermedio. La prueba de RN-05
verifica el constraint trigger diferido, que solo falla al hacer `COMMIT`.

## Integración al CI

La integración la cerró P4 en el **PR #31** («feat(infra): API en docker
compose y pytest de la API en CI (6.11, 6.13)»), mergeado el
**2026-11-10 03:16:40 UTC**. El workflow `.github/workflows/ci.yml` define el
job `api` (`API (pytest y compose)`, L118) y ejecuta:

```bash
python -m pytest api/tests -q
```

en la línea 156, después de recrear la base e instalar `api/requirements.txt`.
El informe de P4 (`06-13-compose-ci.md`) documenta la corrida local con
`176 passed` y la revisión de las violaciones de reglas.

## Discrepancia de cifras

Hay tres cifras distintas en la documentación y una cuarta en el conteo actual.
No son equivalentes:

| Cifra | Fuente | Momento |
|---|---|---|
| 174 | `docs/informe/07-api.md`, «Estado de 6.11» | al escribir `07-api.md`, antes de la integración al CI |
| 176 | `docs/informe/06-13-compose-ci.md` L10 y L76 | revisión de P4 sobre PR #30 |
| 178 | conteo estático en el merge del PR #30 (`b32f9b0`) | al mergear la Fase 6 |
| 184 | conteo estático actual | después del PR #40 |

La diferencia entre 178 y 184 se explica por el **PR #40**: agregó 6 funciones
`test_*` en `api/tests/test_db.py` (SSL, `sslmode` y no fuga de contraseña).
La diferencia entre 174/176 y 178 corresponde a pruebas agregadas durante el
cierre de la Fase 6; el commit exacto de la revisión de 176 no quedó
registrado, pero el merge del PR #30 ya tenía 178. El conteo estático puede
diferir del número que reporta pytest si hay parametrización (`test_stubs.py`
tiene un `@pytest.mark.parametrize`) o pruebas que no se colectan por falta de
dependencias.

**Reconciliación pendiente:** no se pudo ejecutar `pytest --collect-only`
porque el entorno local no tiene `psycopg` instalado. La colección falla con
17 errores de importación. No se instalaron dependencias. Para cerrar la cifra
exacta hay que correr, en un entorno con `api/requirements.txt`:

```bash
python -m pytest api/tests --collect-only -q
```

## Verificación

```text
$ grep -rn "def test_" api/tests --include='*.py' | wc -l
184

$ python3 -m pytest api/tests --collect-only -q
ModuleNotFoundError: No module named 'psycopg'
!!!!!!!!!!!!!!!!!!! Interrupted: 17 errors during collection !!!!!!!!!!!!!!!!!!!!
no tests collected, 17 errors in 1.60s

$ git grep -c "def test_" b32f9b0 -- 'api/tests/*.py' | awk -F: '{s+=$3} END{print s}'
178

$ git show fbb4cc6 -- api/tests/test_db.py | grep "^+def test_"
+def test_config_defaults_sslmode_to_prefer(monkeypatch):
+def test_config_respects_postgres_sslmode_require(monkeypatch):
+def test_config_rejects_invalid_sslmode(monkeypatch):
+def test_build_conninfo_includes_configured_sslmode(monkeypatch):
+def test_build_conninfo_default_sslmode_is_prefer(monkeypatch):
+def test_config_errors_do_not_leak_password(monkeypatch):
```

## Estado

**Hecho.** El mínimo del plan está superado: hay 184 definiciones de prueba y
al menos cinco casos que violan reglas y verifican el código HTTP, incluidos
los tres pedidos explícitamente (stock `409`, transición inválida `409`,
precio negativo `422`). La integración al CI quedó cerrada por P4 en el PR #31.

## Pendientes y observaciones

- **Reconciliación de cifras:** ejecutar `pytest --collect-only` en un entorno
  con las dependencias de `api/requirements.txt` y dejar el número exacto.
- **Riesgo residual de zona horaria:** `06-13-compose-ci.md` señaló 7 pruebas
  que comparaban `date.today()` del host con `CURRENT_DATE` de la base. La
  mayoría se corrigió usando `CURRENT_DATE` de PostgreSQL, pero
  `test_repos_reportes.py:35` y `test_reportes_endpoints.py:57` todavía
  calculan `HOY = date.today()` al importar el módulo. Conviene revisarlas
  antes de la defensa.
- **No verificable en esta sesión:** no se corrió la suite completa; el
  resultado `176 passed` es el documentado por P4 en `06-13-compose-ci.md`.
