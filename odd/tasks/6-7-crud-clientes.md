# Feature 6.7 — CRUD de clientes (Fase 6, plan P3)

Repository-relative locator: `odd/tasks/6-7-crud-clientes.md`
Engram mirror topic: `odd/6-7-crud-clientes/tasks`
Branch: `feature/p3-api-fase6`

## Objective

Complete plan task **6.7 · CRUD de clientes**: wire the five `/clientes`
operations to the repository layer, cover them with HTTP tests, and update
the project documentation. Plan acceptance: "se puede crear y editar un
cliente de cada tipo" (socio, distribuidor, exportador) with export permits
handled in the same transaction.

## Outcome (closed)

Implemented, verified and committed. Final suite at the closing commit:
**153 passed** (136 baseline + 22 new HTTP tests − 5 retired stub rows);
`npx @redocly/cli lint api/openapi.yaml` exit 0 (2 preexisting warnings).

## Task checklist

| ID | Task | Route | Status |
|----|------|-------|--------|
| T1 | Verify worktree + baseline suite | parent inline | done — 136 passed |
| T2 | RED HTTP tests for 5 `/clientes` ops | delegated writer | done — 21 failed / 1 passed vs stubs (behavioral RED) |
| T3 | GREEN wiring `routers/clientes.py` → `repos/clientes.py` | delegated writer | done — 22 passed |
| T4 | Retire 5 `/clientes` rows from `test_stubs.py` | delegated writer | done |
| T5 | Docs `07-api.md` Tarea 6.7 + guía §17 (P3-14) | delegated writer | done |
| T6 | Full suite + Redocly lint (verification of record) | delegated writer + parent spot check | done — 153 passed re-run by parent |
| T7 | Review close-out | parent | done under RDD: slices C1/C2 approved+burned; C3/C4 declined by user; C5 pending when the user disabled RDD clone-scoped → ordinary policy (`disabled/unmanaged`) |
| T8 | Report 6.7; do NOT advance to 6.8 before closing | parent | done — reported; 6.8 proceeds under the user's acceleration instruction |

## Work-unit commits (evidence)

| Commit | Content |
|--------|---------|
| `99f4759` | `feat(api): add repository layer for clientes (6.3)` (prerequisite) |
| `ad3bde9` | `feat(api): add clientes CRUD endpoints (6.7)` — router + `test_clientes_endpoints.py` + stub rows retired |
| (docs) | this document + `docs/informe/07-api.md` + `docs/informe/continuidad-sesion.md` |

Repository-layer commits `8766704` (vinos), `f7a4d47` (comprobantes),
`fe91130` (transferencias/ingresos), `f229773` (reportes) and endpoint
commits `9c076c8` (6.5), `e5708ae` (400 fix), `8d7ae6b` (6.6) accompany this
feature in the same work-unit series authorized by the user.

## Discrepancy reported (not fixed)

- `api/openapi.yaml` documents filter `q` as "búsqueda parcial por nombre o
  documento" but `repos/clientes.py` applies ILIKE only to `c.nombre`.
  Needs P1/P2 coordination (contract vs implementation), tests pin the real
  behavior (name only).
- `DELETE /clientes/{id}` does not document `503` (unlike `/vinos/{cod}`);
  cosmetic contract alignment still open.

## Constraints honored

- No push/PR/merge. Tooling files (`.agents/`, `.atl/`, `AGENTS.md`,
  `skills-lock.json`) never staged. Existing work preserved byte-for-byte
  (intermediate commit states were staged index-only via `git hash-object`).
- Golden rule kept: no `descuento`/`id_cliente` sent, `tipo` never updated,
  derived data always computed by the database.

## Next steps

- 6.8 comprobantes (wire `POST /comprobantes`, `GET /comprobantes/{nro}`).
- 6.9 transferencias/ingresos (open decision: repeated `terminar` = no-op vs
  409 — repo behavior today is no-op; flag before changing semantics).
- 6.10 reportes (align S labels with P2, clean `detalle_vino_example`).
