"""Data access for the ingresos endpoints.

Mirror of ``app.repos.transferencias``: each function owns its
connection (``get_connection`` for reads, ``transaction`` for writes),
SQL is always parameterized and rows come back as dicts with native DB
values. The state machine belongs to the database: T3 validates the
transitions (RN-10) and freezes the cabecera al salir de
``en_confeccion`` (R-003), T6 rejects edits of the renglones outside
``en_confeccion`` (RN-12) and ``sp_procesar_ingreso`` (004) upserts the
``stock_deposito``.
"""

import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from ..db import get_connection, transaction

# Fields of Ingreso / DocumentoRenglon, in the shape of api/openapi.yaml.
_CABECERA_INGRESO = "i.cod_ingreso, i.fecha, i.estado, i.id_transportista, i.cuit_bodega"
_RENGLON_INGRESO = "d.cod_vino, v.nombre_comercial, d.cantidad"


def _cargar_ingreso(connection: psycopg.Connection, cod_ingreso: int) -> dict | None:
    """Read one complete ingreso: cabecera plus renglones (cod_vino ASC)."""

    fila = connection.execute(
        f"SELECT {_CABECERA_INGRESO}"
        " FROM ingreso i WHERE i.cod_ingreso = %s",
        (cod_ingreso,),
    ).fetchone()
    if fila is None:
        return None

    fila["renglones"] = connection.execute(
        f"SELECT {_RENGLON_INGRESO}"
        " FROM renglon_ingreso d"
        " JOIN vino v ON v.cod_vino = d.cod_vino"
        " WHERE d.cod_ingreso = %s"
        " ORDER BY d.cod_vino",
        (cod_ingreso,),
    ).fetchall()
    return fila


def crear_ingreso(
    pool: ConnectionPool,
    *,
    id_transportista: int,
    cuit_bodega: str,
    fecha=None,
) -> dict:
    """Create one ingreso for ``id_transportista`` from ``cuit_bodega``.

    Sends only the granted columns ``(fecha, id_transportista,
    cuit_bodega)`` with ``COALESCE(%s, CURRENT_DATE)`` for the optional
    ``fecha``: ``estado`` takes the DEFAULT 'en_confeccion' validated by
    T3 (RN-10). Returns the created document with the shape of the
    Ingreso contract.
    """

    with transaction(pool) as connection:
        connection.row_factory = dict_row
        fila = connection.execute(
            "INSERT INTO ingreso (fecha, id_transportista, cuit_bodega)"
            " VALUES (COALESCE(%s, CURRENT_DATE), %s, %s)"
            " RETURNING cod_ingreso",
            (fecha, id_transportista, cuit_bodega),
        ).fetchone()
        return _cargar_ingreso(connection, fila["cod_ingreso"])


def agregar_renglon_ingreso(
    pool: ConnectionPool,
    cod_ingreso: int,
    *,
    cod_vino: int,
    cantidad: int,
) -> dict | None:
    """Add one renglón (cod_vino, cantidad) to the ingreso.

    Sends only the granted columns ``(cod_ingreso, cod_vino,
    cantidad)``. Returns None if the document does not exist; otherwise
    returns the updated document. T6 refuses the edit when the document
    is not ``en_confeccion`` ([RN-12], P0001 → 409): the error
    propagates, nothing is written.
    """

    with transaction(pool) as connection:
        connection.row_factory = dict_row
        existe = connection.execute(
            "SELECT 1 AS uno FROM ingreso WHERE cod_ingreso = %s",
            (cod_ingreso,),
        ).fetchone()
        if existe is None:
            return None

        connection.execute(
            "INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)"
            " VALUES (%s, %s, %s)",
            (cod_ingreso, cod_vino, cantidad),
        )
        return _cargar_ingreso(connection, cod_ingreso)


def terminar_ingreso(pool: ConnectionPool, cod_ingreso: int) -> dict | None:
    """Advance the ingreso from ``en_confeccion`` to ``terminado``.

    It is a plain UPDATE by PK: T3 validates the transition and raises
    ``[RN-10]`` (P0001 → 409) on any invalid move — including from
    ``procesado`` — and the same trigger freezes the cabecera data
    (R-003). Returns the updated document, or None if the document does
    not exist.
    """

    with transaction(pool) as connection:
        connection.row_factory = dict_row
        fila = connection.execute(
            "UPDATE ingreso SET estado = 'terminado'"
            " WHERE cod_ingreso = %s RETURNING cod_ingreso",
            (cod_ingreso,),
        ).fetchone()
        if fila is None:
            return None
        return _cargar_ingreso(connection, cod_ingreso)


def procesar_ingreso(pool: ConnectionPool, cod_ingreso: int) -> dict | None:
    """Process the ingreso: upsert ``stock_deposito``, estado ``procesado``.

    Runs ``CALL sp_procesar_ingreso(%s)`` (004, SECURITY DEFINER) inside
    one explicit transaction — the procedure owns no COMMIT and the
    caller owns the transaction. A missing document raises P0002
    ('No existe…' → 404) and any pre-condition failure raises ``[RN-10]``
    (P0001 → 409); both propagate and the ROLLBACK undoes everything.
    On success, reads back and returns the updated document.
    """

    with transaction(pool) as connection:
        connection.row_factory = dict_row
        connection.execute("CALL sp_procesar_ingreso(%s)", (cod_ingreso,))
        return _cargar_ingreso(connection, cod_ingreso)
