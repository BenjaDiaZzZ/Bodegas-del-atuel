"""Data access for the vinos endpoints.

Every function owns its connection: reads use ``app.db.get_connection``
and writes run inside ``app.db.transaction`` (BEGIN ... COMMIT with
rollback and central error mapping). SQL is always parameterized; the
dynamic filters are fixed SQL fragments whose values stay bound
parameters. Row results use ``psycopg.rows.dict_row``.

The database enforces the business rules (CHECK of 002, triggers of 005).
This module never computes derived data: totals, discounts and stock are
read from the objects that keep them (vw_ficha_vino / vw_stock_total_vino).
"""

from decimal import Decimal

import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from ..db import get_connection, transaction

# Fields of VinoResumen, in the shape of api/openapi.yaml.
_VINO_RESUMEN = (
    "v.cod_vino, v.nombre_comercial, v.tipo, v.anada, v.presentacion_ml,"
    " v.graduacion, v.precio_venta, v.cuit_bodega, b.razon_social AS bodega"
)

# Fixed SQL fragments for the optional filters of listar_vinos. Every value
# remains a bound parameter; nothing user-provided is interpolated. The
# explicit casts let PostgreSQL infer the type of the %(x)s = NULL pattern.
_FILTROS_VINO = (
    "(%(nombre)s::text IS NULL OR v.nombre_comercial ILIKE '%%' || %(nombre)s::text || '%%')",
    "(%(tipo)s::varchar IS NULL OR v.tipo = %(tipo)s::varchar)",
    "(%(id_cepa)s::integer IS NULL OR EXISTS ("
    "     SELECT 1 FROM composicion co"
    "     WHERE co.cod_vino = v.cod_vino AND co.id_cepa = %(id_cepa)s::integer))",
    "(%(cuit_bodega)s::varchar IS NULL OR v.cuit_bodega = %(cuit_bodega)s::varchar)",
    "(%(anada)s::integer IS NULL OR v.anada = %(anada)s::integer)",
)

# Updatable wine fields of the VinoUpdate contract.
_CAMPOS_VINO = (
    "nombre_comercial",
    "tipo",
    "anada",
    "presentacion_ml",
    "graduacion",
    "precio_venta",
    "cuit_bodega",
)


def _cargar_ficha(connection: psycopg.Connection, cod_vino: int) -> dict | None:
    """Read one complete wine card from vw_ficha_vino (obtener shape).

    The view already joins the bodega name, the stock totals and the
    composition/pairing lists (JSONB, parsed to lists of dicts by
    psycopg); only the stock keys are renamed to the StockVino shape.
    """

    row = connection.execute(
        "SELECT cod_vino, nombre_comercial, tipo, anada, presentacion_ml,"
        " graduacion, precio_venta, cuit_bodega, bodega,"
        " stock_deposito, stock_salas, stock_total, composicion, maridajes"
        " FROM vw_ficha_vino WHERE cod_vino = %s",
        (cod_vino,),
    ).fetchone()
    if row is None:
        return None

    row["stock"] = {
        "deposito": row.pop("stock_deposito"),
        "salas": row.pop("stock_salas"),
        "total": row.pop("stock_total"),
    }
    return row


def _insertar_composicion(connection: psycopg.Connection, cod_vino: int, composicion: list[dict]) -> None:
    """Insert one composition row per (id_cepa, porcentaje), id_cepa ASC."""

    for item in sorted(composicion, key=lambda item: item["id_cepa"]):
        connection.execute(
            "INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (%s, %s, %s)",
            (cod_vino, item["id_cepa"], item["porcentaje"]),
        )


def _insertar_maridajes(connection: psycopg.Connection, cod_vino: int, maridajes: list[int]) -> None:
    """Insert one vino_maridaje row per id, id_maridaje ASC."""

    for id_maridaje in sorted(maridajes):
        connection.execute(
            "INSERT INTO vino_maridaje (cod_vino, id_maridaje) VALUES (%s, %s)",
            (cod_vino, id_maridaje),
        )


def listar_vinos(
    pool: ConnectionPool,
    *,
    nombre: str | None = None,
    tipo: str | None = None,
    id_cepa: int | None = None,
    cuit_bodega: str | None = None,
    anada: int | None = None,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[dict], int]:
    """List the wine catalog with optional filters and pagination.

    Returns ``(rows, total)``: ``total`` is the full count of filtered
    rows, taken from ``COUNT(*) OVER ()`` of the same query; for an empty
    page beyond the last one, a fallback COUNT with the same WHERE keeps
    the total exact. ``nombre`` is a CONTAINS filter (ILIKE); the
    wildcards live in the SQL literal and the user value stays bound.
    """

    filtros = " AND ".join(_FILTROS_VINO)
    parametros = {
        "nombre": nombre,
        "tipo": tipo,
        "id_cepa": id_cepa,
        "cuit_bodega": cuit_bodega,
        "anada": anada,
        "limite": per_page,
        "offset": (page - 1) * per_page,
    }

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        filas = connection.execute(
            f"SELECT {_VINO_RESUMEN}, COUNT(*) OVER () AS total"
            f" FROM vino v JOIN bodega b ON b.cuit = v.cuit_bodega"
            f" WHERE {filtros}"
            " ORDER BY v.cod_vino LIMIT %(limite)s OFFSET %(offset)s",
            parametros,
        ).fetchall()

        if not filas and page > 1:
            fila_total = connection.execute(
                f"SELECT COUNT(*) AS total FROM vino v JOIN bodega b ON b.cuit = v.cuit_bodega"
                f" WHERE {filtros}",
                parametros,
            ).fetchone()
            return [], fila_total["total"]

    total = filas[0].pop("total") if filas else 0
    for fila in filas:
        fila.pop("total", None)
    return filas, total


def obtener_vino(pool: ConnectionPool, cod_vino: int) -> dict | None:
    """Return the full detail of one wine, or None if it does not exist.

    The shape matches VinoDetalle of api/openapi.yaml: the VinoResumen
    fields plus ``composicion`` ([{id_cepa, nombre, porcentaje}]),
    ``maridajes`` ([{id_maridaje, nombre, temperatura_servicio}]) and
    ``stock`` ({deposito, salas, total}).
    """

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        return _cargar_ficha(connection, cod_vino)


def crear_vino(
    pool: ConnectionPool,
    *,
    nombre_comercial: str,
    tipo: str,
    anada: int,
    presentacion_ml: int,
    graduacion: Decimal | float,
    precio_venta: Decimal | float,
    cuit_bodega: str,
    composicion: list[dict],
    maridajes: list[int] | None = None,
) -> dict:
    """Create one wine with its composition and pairings in one transaction.

    ``cod_vino`` is GENERATED ALWAYS AS IDENTITY and is never sent. The
    composition row order follows id_cepa ASC. RN-05 (``tg_composicion_cien``)
    is a DEFERRABLE INITIALLY DEFERRED constraint trigger: a composition that
    does not sum to 100 fails at COMMIT and ``transaction`` surfaces the
    P0001 as DatabaseHttpError 409, so nothing persists.

    Returns the created detail in the exact shape of :func:`obtener_vino`
    (read from vw_ficha_vino inside the same transaction).
    """

    with transaction(pool) as connection:
        connection.row_factory = dict_row
        fila = connection.execute(
            "INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml,"
            " graduacion, precio_venta, cuit_bodega)"
            " VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING cod_vino",
            (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega),
        ).fetchone()
        cod_vino = fila["cod_vino"]

        _insertar_composicion(connection, cod_vino, composicion)
        if maridajes:
            _insertar_maridajes(connection, cod_vino, maridajes)

        return _cargar_ficha(connection, cod_vino)


def actualizar_vino(
    pool: ConnectionPool,
    cod_vino: int,
    *,
    usuario: str,
    composicion: list[dict] | None = None,
    maridajes: list[int] | None = None,
    **campos,
) -> dict | None:
    """Update one wine inside one transaction; None if it does not exist.

    First sets ``app.usuario`` transaction-local with
    ``set_config('app.usuario', %s, true)``: the price-audit trigger
    ``fn_tg_vino_precio_auditoria`` (RN-13) reads it when ``precio_venta``
    changes. Mirrors consultas/update.sql (U3).

    Only the provided fields of ``_CAMPOS_VINO`` are updated; the SET
    clauses are fixed fragments and every value stays bound. When
    ``composicion``/``maridajes`` are given, the whole collection is
    replaced (DELETE + INSERT). Replacing the composition with percentages
    that do not sum to 100 fails at COMMIT through RN-05 as 409.

    Returns the updated detail (the shape of :func:`obtener_vino`) or None.
    """

    with transaction(pool) as connection:
        connection.row_factory = dict_row
        connection.execute("SELECT set_config('app.usuario', %s, true)", (usuario,))

        fragmentos = [f"{campo} = %({campo})s" for campo in _CAMPOS_VINO if campo in campos]
        parametros = dict(campos)

        if fragmentos:
            fila = connection.execute(
                f"UPDATE vino SET {', '.join(fragmentos)}"
                " WHERE cod_vino = %(cod_vino)s RETURNING cod_vino",
                {**parametros, "cod_vino": cod_vino},
            ).fetchone()
        else:
            fila = connection.execute(
                "SELECT cod_vino FROM vino WHERE cod_vino = %s", (cod_vino,)
            ).fetchone()

        if fila is None:
            return None

        if composicion is not None:
            connection.execute("DELETE FROM composicion WHERE cod_vino = %s", (cod_vino,))
            _insertar_composicion(connection, cod_vino, composicion)

        if maridajes is not None:
            connection.execute("DELETE FROM vino_maridaje WHERE cod_vino = %s", (cod_vino,))
            _insertar_maridajes(connection, cod_vino, maridajes)

        return _cargar_ficha(connection, cod_vino)


def eliminar_vino(pool: ConnectionPool, cod_vino: int) -> int:
    """Delete one wine and return the number of deleted rows (0 or 1).

    ``composicion`` and ``vino_maridaje`` are CASCADE from vino, so the
    base deletes them itself with the owner's privileges. Every other
    reference is RESTRICT (renglon_comprobante, renglon_ingreso,
    renglon_transferencia, stock_deposito, stock_sala, auditoria_precio):
    those sessions simply fail with SQLSTATE 23503, which the central
    mapper turns into 409 \u2014 that mapped error is the correct outcome, never
    worked around here.
    """

    with transaction(pool) as connection:
        eliminadas = connection.execute(
            "DELETE FROM vino WHERE cod_vino = %s RETURNING cod_vino", (cod_vino,)
        ).fetchall()
        return len(eliminadas)
