"""Data access for the transferencias endpoints.

Same conventions as ``app.repos.vinos``: each function owns its
connection (``get_connection`` for reads, ``transaction`` for writes),
SQL is always parameterized and rows come back as dicts with native DB
values. The state machine belongs to the database: T4 validates the
transitions (RN-11), T5 forces ``fecha_confeccion``, T6 freezes the
renglones outside ``en_confeccion`` (RN-12) and
``sp_procesar_transferencia`` (004) moves the stock del depósito → sala.
"""

import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from ..db import get_connection, transaction

# Fields of Transferencia / DocumentoRenglon, in the shape of api/openapi.yaml.
_CABECERA_TRANSFERENCIA = "t.nro_solicitud, t.id_sala, t.fecha_confeccion, t.estado"
_RENGLON_DOCUMENTO = "d.cod_vino, v.nombre_comercial, d.cantidad"


def _cargar_transferencia(connection: psycopg.Connection, nro_solicitud: int) -> dict | None:
    """Read one complete transferencia: cabecera plus renglones (cod_vino ASC)."""

    fila = connection.execute(
        f"SELECT {_CABECERA_TRANSFERENCIA}"
        " FROM transferencia t WHERE t.nro_solicitud = %s",
        (nro_solicitud,),
    ).fetchone()
    if fila is None:
        return None

    fila["renglones"] = connection.execute(
        f"SELECT {_RENGLON_DOCUMENTO}"
        " FROM renglon_transferencia d"
        " JOIN vino v ON v.cod_vino = d.cod_vino"
        " WHERE d.nro_solicitud = %s"
        " ORDER BY d.cod_vino",
        (nro_solicitud,),
    ).fetchall()
    return fila


def crear_transferencia(pool: ConnectionPool, *, id_sala: int) -> dict:
    """Create one transferencia for ``id_sala`` in ``en_confeccion``.

    Sends only the granted column ``(id_sala)``: T5 forces
    ``fecha_confeccion = CURRENT_DATE`` and the ``estado`` column takes
    the DEFAULT 'en_confeccion' validated by T4 (RN-11). Returns the
    created document with the shape of the Transferencia contract.
    """

    with transaction(pool) as connection:
        connection.row_factory = dict_row
        fila = connection.execute(
            "INSERT INTO transferencia (id_sala) VALUES (%s) RETURNING nro_solicitud",
            (id_sala,),
        ).fetchone()
        return _cargar_transferencia(connection, fila["nro_solicitud"])


def agregar_renglon_transferencia(
    pool: ConnectionPool,
    nro_solicitud: int,
    *,
    cod_vino: int,
    cantidad: int,
) -> dict | None:
    """Add one renglón (cod_vino, cantidad) to the transferencia.

    Sends only the granted columns ``(nro_solicitud, cod_vino,
    cantidad)``. Returns None if the document does not exist; otherwise
    returns the updated document. T6 refuses the edit when the document
    is not ``en_confeccion`` ([RN-12], P0001 → 409): the error
    propagates, nothing is written.
    """

    with transaction(pool) as connection:
        connection.row_factory = dict_row
        existe = connection.execute(
            "SELECT 1 AS uno FROM transferencia WHERE nro_solicitud = %s",
            (nro_solicitud,),
        ).fetchone()
        if existe is None:
            return None

        connection.execute(
            "INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad)"
            " VALUES (%s, %s, %s)",
            (nro_solicitud, cod_vino, cantidad),
        )
        return _cargar_transferencia(connection, nro_solicitud)


def terminar_transferencia(pool: ConnectionPool, nro_solicitud: int) -> dict | None:
    """Advance the transferencia from ``en_confeccion`` to ``terminado``.

    It is a plain UPDATE by PK: T4 validates the transition and raises
    ``[RN-11]`` (P0001 → 409) on any invalid move — including from
    ``procesado`` — and T5 rejects afterwards edits of
    ``fecha_confeccion``. Returns the updated document, or None if the
    document does not exist.
    """

    with transaction(pool) as connection:
        connection.row_factory = dict_row
        fila = connection.execute(
            "UPDATE transferencia SET estado = 'terminado'"
            " WHERE nro_solicitud = %s RETURNING nro_solicitud",
            (nro_solicitud,),
        ).fetchone()
        if fila is None:
            return None
        return _cargar_transferencia(connection, nro_solicitud)


def procesar_transferencia(pool: ConnectionPool, nro_solicitud: int) -> dict | None:
    """Process the transferencia: depósito → sala, estado ``procesado``.

    Runs ``CALL sp_procesar_transferencia(%s)`` (004, SECURITY DEFINER)
    inside one explicit transaction — the procedure owns no COMMIT and
    the caller owns the transaction. A missing document raises P0002
    ('No existe…' → 404) and any pre-condition failure raises ``[RN-11]``
    (P0001 → 409); both propagate and the ROLLBACK undoes everything.
    On success, reads back and returns the updated document.
    """

    with transaction(pool) as connection:
        connection.row_factory = dict_row
        connection.execute("CALL sp_procesar_transferencia(%s)", (nro_solicitud,))
        return _cargar_transferencia(connection, nro_solicitud)
