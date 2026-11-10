"""Data access for the comprobantes endpoints.

Same conventions as ``app.repos.vinos``: each function owns its
connection (``get_connection`` for reads, ``transaction`` for writes),
SQL is always parameterized, rows come back as dicts with native DB
values, and this module never computes derived data: ``precio_unitario``,
``descuento``, ``subtotal``, the cabecera totals and the ``stock_sala``
deduction belong to the triggers of 005 (T1/T2, RN-08/RN-09). The repo
only inserts the granted columns and reads back what the database
computed.
"""

import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from ..db import get_connection, transaction

# Fields of Comprobante / ComprobanteRenglon, in the shape of api/openapi.yaml.
_CABECERA_COMPROBANTE = (
    "c.nro_comprobante, c.fecha, c.id_cliente, c.id_sala,"
    " c.subtotal, c.descuento, c.total"
)
_RENGLON_COMPROBANTE = (
    "r.cod_vino, v.nombre_comercial, r.cantidad,"
    " r.precio_unitario, r.descuento, r.subtotal"
)


def _cargar_comprobante(connection: psycopg.Connection, nro_comprobante: int) -> dict | None:
    """Read one complete comprobante: cabecera plus renglones (cod_vino ASC)."""

    fila = connection.execute(
        f"SELECT {_CABECERA_COMPROBANTE}"
        " FROM comprobante c WHERE c.nro_comprobante = %s",
        (nro_comprobante,),
    ).fetchone()
    if fila is None:
        return None

    fila["renglones"] = connection.execute(
        f"SELECT {_RENGLON_COMPROBANTE}"
        " FROM renglon_comprobante r"
        " JOIN vino v ON v.cod_vino = r.cod_vino"
        " WHERE r.nro_comprobante = %s"
        " ORDER BY r.cod_vino",
        (nro_comprobante,),
    ).fetchall()
    return fila


def obtener_comprobante(pool: ConnectionPool, nro_comprobante: int) -> dict | None:
    """Return one comprobante with its renglones, or None if it does not exist.

    The shape matches Comprobante of api/openapi.yaml: the cabecera fields
    (``subtotal``, ``descuento`` and ``total`` computed by T2) plus
    ``renglones`` ([{cod_vino, nombre_comercial, cantidad, precio_unitario,
    descuento, subtotal}], cod_vino ASC).
    """

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        return _cargar_comprobante(connection, nro_comprobante)


def crear_comprobante(
    pool: ConnectionPool,
    *,
    id_cliente: int,
    id_sala: int,
    fecha=None,
    renglones: list[dict],
) -> dict:
    """Create one comprobante and its renglones in one transaction.

    Mirrors consultas/insert.sql (I3): the INSERT sends only the granted
    columns — cabecera ``(fecha, id_cliente, id_sala)`` with
    ``COALESCE(%s, CURRENT_DATE)`` for the optional ``fecha`` and each
    renglón ``(nro_comprobante, cod_vino, cantidad)``. The BEFORE trigger
    T1 completes ``precio_unitario``/``descuento``/``subtotal`` and
    validates the stock (RN-09); the AFTER trigger T2 deducts
    ``stock_sala`` and recalculates the cabecera totals (RN-08).

    The renglones are sent to the database sorted by ``cod_vino`` ASC:
    that is the single lock order of deposito → stock_sala → renglones
    (004, section 3), so two concurrent comprobantes never deadlock.

    ``PRECIO`` rules surface from the database and ``transaction`` maps
    them centrally: insufficient stock raises ``[RN-09]`` (P0001 → 409)
    and a repeated ``cod_vino`` violates the composite PK (23505 → 409);
    in both cases the ROLLBACK leaves nothing persisted.

    Returns the created comprobante with the shape of
    :func:`obtener_comprobante`.
    """

    with transaction(pool) as connection:
        connection.row_factory = dict_row
        fila = connection.execute(
            "INSERT INTO comprobante (fecha, id_cliente, id_sala)"
            " VALUES (COALESCE(%s, CURRENT_DATE), %s, %s)"
            " RETURNING nro_comprobante",
            (fecha, id_cliente, id_sala),
        ).fetchone()
        nro_comprobante = fila["nro_comprobante"]

        for renglon in sorted(renglones, key=lambda renglon: renglon["cod_vino"]):
            connection.execute(
                "INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)"
                " VALUES (%s, %s, %s)",
                (nro_comprobante, renglon["cod_vino"], renglon["cantidad"]),
            )

        return _cargar_comprobante(connection, nro_comprobante)
