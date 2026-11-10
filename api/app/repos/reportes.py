"""Data access for the reportes endpoints (Canonical S-queries).

Same conventions as ``app.repos.vinos``: every function owns its
connection through ``get_connection`` (all reports are read-only), SQL
is always parameterized and rows come back as dicts with native DB
values. Each report reproduces the team's canonical query semantics
instead of inventing new ones:

- ``top_vinos`` (S1 of api/openapi.yaml, "ranking de vinos más
  vendidos"): the canonical JOIN ``renglon_comprobante × vino`` (S4 of
  consultas/select.sql) grouped by wine and ordered by
  ``SUM(rc.cantidad) DESC`` — aggregated across all salas, with LIMIT n.
- ``ventas_por_sala`` (S8): the view ``vw_ventas_mensuales_sala``
  (``app_rw`` has SELECT), which already computes ``botellas_vendidas``
  from the renglones and ``monto_total`` from ``comprobante.total``;
  the optional ``desde``/``hasta`` filter compares the ``mes`` bucket,
  always bound.
- ``vinos_sin_stock`` (S6): the canonical FULL/LEFT JOIN stock
  pattern of consultas/select.sql — wines whose ``stock_sala`` in that
  sala is 0 (or absent, COALESCE → 0) while ``stock_deposito > 0``.
- ``transportista_activo`` (S7): the transportista ranking style of
  consultas (I1 control query: ``COUNT(i.cod_ingreso)`` per
  transportista) with the relative-date filter of consultas/select.sql
  (``i.fecha >= CURRENT_DATE - INTERVAL '1 month'``).
- ``trazabilidad_vino`` (S9): the full card from ``vw_ficha_vino`` in
  the exact shape of ``vinos.obtener_vino``.

The database computed every figure (comprobantes totals, stocks, view
aggregates); this module only reads.
"""

import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from ..db import get_connection
from .vinos import _cargar_ficha

# Optional range of ventas_por_sala: fixed fragments whose values stay
# bound; explicit casts let PostgreSQL infer the %(x)s = NULL types.
_FILTROS_MES = (
    "(%(desde)s::date IS NULL OR mes >= %(desde)s::date)",
    "(%(hasta)s::date IS NULL OR mes <= %(hasta)s::date)",
)


def top_vinos(pool: ConnectionPool, limite: int = 10) -> list[dict]:
    """Return the ranking of the most sold wines across all salas (S1).

    The shape matches TopVino of api/openapi.yaml:
    ``{cod_vino, nombre_comercial, botellas_vendidas}``, where
    ``botellas_vendidas`` is ``SUM(renglon_comprobante.cantidad)``. The
    ties are broken by ``cod_vino`` ASC so the ranking is deterministic.
    """

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        return connection.execute(
            "SELECT v.cod_vino, v.nombre_comercial, SUM(rc.cantidad) AS botellas_vendidas"
            " FROM renglon_comprobante rc JOIN vino v ON v.cod_vino = rc.cod_vino"
            " GROUP BY v.cod_vino, v.nombre_comercial"
            " ORDER BY botellas_vendidas DESC, v.cod_vino LIMIT %s",
            (limite,),
        ).fetchall()


def ventas_por_sala(pool: ConnectionPool, *, desde=None, hasta=None) -> list[dict]:
    """Return the monthly sales per sala, optionally filtered on ``mes`` (S8).

    Reads the team's view ``vw_ventas_mensuales_sala``. The shape matches
    VentaMensualSala of api/openapi.yaml: ``{id_sala, localidad, mes,
    botellas_vendidas, monto_total}``. ``desde``/``hasta`` may be None;
    both values stay bound parameters. Rows are ordered by salas
    month-by-month ("id_sala, mes") for deterministic output.
    """

    filtros = " AND ".join(_FILTROS_MES)

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        return connection.execute(
            f"SELECT id_sala, localidad, mes, botellas_vendidas, monto_total"
            f" FROM vw_ventas_mensuales_sala"
            f" WHERE {filtros}"
            " ORDER BY id_sala, mes",
            {"desde": desde, "hasta": hasta},
        ).fetchall()


def vinos_sin_stock(pool: ConnectionPool, id_sala: int) -> list[dict]:
    """Return the wines without stock in one sala but with stock stored (S6).

    Same join semantics as the canonical stock reports of
    consultas/select.sql: a missing ``stock_sala`` row counts as 0
    (COALESCE). The shape matches VinoSinStock of api/openapi.yaml:
    ``{cod_vino, nombre_comercial, stock_sala, stock_deposito}``, with
    ``stock_deposito > 0`` and ``stock_sala = 0``, ordered by
    ``cod_vino``.
    """

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        return connection.execute(
            "SELECT v.cod_vino, v.nombre_comercial,"
            " COALESCE(ss.cantidad, 0) AS stock_sala, d.cantidad AS stock_deposito"
            " FROM vino v"
            " JOIN stock_deposito d ON d.cod_vino = v.cod_vino"
            " LEFT JOIN stock_sala ss"
            "   ON ss.cod_vino = v.cod_vino AND ss.id_sala = %s"
            " WHERE d.cantidad > 0 AND COALESCE(ss.cantidad, 0) = 0"
            " ORDER BY v.cod_vino",
            (id_sala,),
        ).fetchall()

def stock_por_sala(pool: ConnectionPool, id_sala: int) -> list[dict]:
    """Return stock of wines in deposito and sala for a given sala.

    Returns all wines with stock in deposito, with sala stock (COALESCE 0).
    Ordered by stock_sala DESC, nombre_comercial.
    """
    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        return connection.execute(
            "SELECT v.cod_vino, v.nombre_comercial,"
            " COALESCE(ss.cantidad, 0) AS stock_sala, d.cantidad AS stock_deposito"
            " FROM vino v"
            " JOIN stock_deposito d ON d.cod_vino = v.cod_vino"
            " LEFT JOIN stock_sala ss"
            "   ON ss.cod_vino = v.cod_vino AND ss.id_sala = %s"
            " WHERE d.cantidad > 0"
            " ORDER BY COALESCE(ss.cantidad, 0) DESC, v.nombre_comercial",
            (id_sala,),
        ).fetchall()


def transportista_activo(pool: ConnectionPool) -> dict | None:
    """Return the transportista with most ingresos in the last month (S7).

    Semantics copied from the canonical timing (consultas/select.sql):
    ``i.fecha >= CURRENT_DATE - INTERVAL '1 month'``; the ranking column
    is ``COUNT(i.cod_ingreso)`` per transportista (like the I1 ranking).
    The shape matches TransportistaActivo of api/openapi.yaml:
    ``{id_transportista, razon_social, ingresos_trasladados}``. Returns
    None when no transportista had activity (the router surfaces 404).
    """

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        return connection.execute(
            "SELECT t.id_transportista, t.razon_social, COUNT(i.cod_ingreso) AS ingresos_trasladados"
            " FROM ingreso i"
            " JOIN transportista t ON t.id_transportista = i.id_transportista"
            " WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'"
            " GROUP BY t.id_transportista, t.razon_social"
            " ORDER BY ingresos_trasladados DESC, t.id_transportista"
            " LIMIT 1",
        ).fetchone()


def trazabilidad_vino(pool: ConnectionPool, cod_vino: int) -> dict | None:
    """Return the full traceability card of one wine (S9) from vw_ficha_vino.

    Uses the same loader as :func:`app.repos.vinos.obtener_vino` so both
    endpoints return the identical VinoDetalle shape (composicion and
    maridajes as JSONB lists, ``stock`` = {deposito, salas, total}).
    Returns None if the wine does not exist.
    """

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        return _cargar_ficha(connection, cod_vino)
