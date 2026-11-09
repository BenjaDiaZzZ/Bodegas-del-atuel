"""Data access for the clientes endpoints.

Same conventions as ``app.repos.vinos``: each function owns its
connection (``get_connection`` for reads, ``transaction`` for writes),
SQL is always parameterized, rows come back as dicts with native DB
values, and this module never computes derived data (``cliente.descuento``
is a GENERATED ALWAYS column since R-002).
"""

from datetime import date

import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from ..db import get_connection, transaction

_CLIENTE_RESUMEN = (
    "c.id_cliente, c.nombre, c.tipo, c.tipo_documento, c.nro_documento,"
    " c.direccion, c.id_localidad, l.nombre AS localidad, c.fecha_alta, c.descuento"
)

# Fixed SQL fragments for the optional filters of listar_clientes (values
# always bound; explicit casts so PostgreSQL can infer the %(x)s = NULL types).
_FILTROS_CLIENTE = (
    "(%(tipo)s::varchar IS NULL OR c.tipo = %(tipo)s::varchar)",
    "(%(id_localidad)s::integer IS NULL OR c.id_localidad = %(id_localidad)s::integer)",
    "(%(q)s::text IS NULL OR c.nombre ILIKE '%%' || %(q)s::text || '%%')",
)

# Updatable client fields of the ClienteUpdate contract. ``tipo`` is NOT
# updatable: changing it is constrained by the composite FK
# (id_cliente, tipo) of the subtype tables, and is out of scope.
_CAMPOS_CLIENTE = ("nombre", "tipo_documento", "nro_documento", "direccion", "id_localidad")


def _cargar_detalle(connection: psycopg.Connection, id_cliente: int) -> dict | None:
    """Load one client detail row plus its export permission list."""

    fila = connection.execute(
        f"SELECT {_CLIENTE_RESUMEN}, d.zona_cobertura, d.nro_habilitacion,"
        " e.pais_destino_principal"
        " FROM cliente c"
        " JOIN localidad l ON l.id_localidad = c.id_localidad"
        " LEFT JOIN distribuidor d ON d.id_cliente = c.id_cliente"
        " LEFT JOIN exportador e ON e.id_cliente = c.id_cliente"
        " WHERE c.id_cliente = %s",
        (id_cliente,),
    ).fetchone()
    if fila is None:
        return None

    fila["permisos"] = connection.execute(
        "SELECT cod_permiso, fecha_emision, fecha_vencimiento"
        " FROM permiso_exportacion WHERE id_cliente = %s ORDER BY cod_permiso",
        (id_cliente,),
    ).fetchall()
    return fila


def _insertar_subtipo(connection: psycopg.Connection, id_cliente: int, tipo: str, datos: dict) -> None:
    """Insert the subtype row required by the composite FK (id_cliente, tipo).

    Socio has no extra data (the ``tipo`` column has DEFAULT 'socio');
    distribuidor and exportador bring their NOT NULL fields, and the
    database rejects the insert if they are missing.
    """

    if tipo == "socio":
        connection.execute("INSERT INTO socio (id_cliente) VALUES (%s)", (id_cliente,))
    elif tipo == "distribuidor":
        connection.execute(
            "INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion) VALUES (%s, %s, %s)",
            (id_cliente, datos.get("zona_cobertura"), datos.get("nro_habilitacion")),
        )
    elif tipo == "exportador":
        connection.execute(
            "INSERT INTO exportador (id_cliente, pais_destino_principal) VALUES (%s, %s)",
            (id_cliente, datos.get("pais_destino_principal")),
        )


def _insertar_permisos(connection: psycopg.Connection, id_cliente: int, permisos: list[dict]) -> None:
    """Insert export permissions, cod_permiso ASC."""

    for permiso in sorted(permisos, key=lambda permiso: permiso["cod_permiso"]):
        connection.execute(
            "INSERT INTO permiso_exportacion (id_cliente, cod_permiso, fecha_emision, fecha_vencimiento)"
            " VALUES (%s, %s, %s, %s)",
            (id_cliente, permiso["cod_permiso"], permiso["fecha_emision"], permiso["fecha_vencimiento"]),
        )


def listar_clientes(
    pool: ConnectionPool,
    *,
    tipo: str | None = None,
    id_localidad: int | None = None,
    q: str | None = None,
    page: int = 1,
    per_page: int = 20,
) -> tuple[list[dict], int]:
    """List clients with optional filters and pagination.

    Returns ``(rows, total)`` with the ClienteResumen fields (``localidad``
    joined); ``total`` comes from ``COUNT(*) OVER ()`` of the same query,
    with the same empty-page fallback as the Wine catalog.
    """

    filtros = " AND ".join(_FILTROS_CLIENTE)
    parametros: dict = {
        "tipo": tipo,
        "id_localidad": id_localidad,
        "q": q,
        "limite": per_page,
        "offset": (page - 1) * per_page,
    }

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        filas = connection.execute(
            f"SELECT {_CLIENTE_RESUMEN}, COUNT(*) OVER () AS total"
            f" FROM cliente c JOIN localidad l ON l.id_localidad = c.id_localidad"
            f" WHERE {filtros}"
            " ORDER BY c.id_cliente LIMIT %(limite)s OFFSET %(offset)s",
            parametros,
        ).fetchall()

        if not filas and page > 1:
            fila_total = connection.execute(
                f"SELECT COUNT(*) AS total FROM cliente c JOIN localidad l ON l.id_localidad = c.id_localidad"
                f" WHERE {filtros}",
                parametros,
            ).fetchone()
            return [], fila_total["total"]

    total = filas[0].pop("total") if filas else 0
    for fila in filas:
        fila.pop("total", None)
    return filas, total


def obtener_cliente(pool: ConnectionPool, id_cliente: int) -> dict | None:
    """Return the detail of one client, or None if it does not exist.

    The shape matches ClienteDetalle of api/openapi.yaml: ClienteResumen
    fields plus the subtype fields (``zona_cobertura``/``nro_habilitacion``
    for distribuidor, ``pais_destino_principal`` for exportador) and
    ``permisos`` ([{cod_permiso, fecha_emision, fecha_vencimiento}],
    cod_permiso ASC). Subtype fields of other subtypes stay None.
    """

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        return _cargar_detalle(connection, id_cliente)


def crear_cliente(
    pool: ConnectionPool,
    *,
    nombre: str,
    tipo: str,
    tipo_documento: str,
    nro_documento: str,
    direccion: str,
    id_localidad: int,
    fecha_alta: date | None = None,
    zona_cobertura: str | None = None,
    nro_habilitacion: str | None = None,
    pais_destino_principal: str | None = None,
    permisos: list[dict] | None = None,
) -> dict:
    """Create one client with its subtype (and permissions) in one transaction.

    ``id_cliente`` is identity and ``descuento`` is GENERATED ALWAYS: both
    columns are never sent. ``fecha_alta`` falls back to CURRENT_DATE with
    ``COALESCE(%s, CURRENT_DATE)``. The subtype row and the rows in
    ``permiso_exportacion`` are inserted inside the same transaction; the
    database rejects a subtype without its NOT NULL fields, and a
    ``permisos`` list for a non-exporter fails the composite FK.

    Returns the created detail in the exact shape of :func:`obtener_cliente`.
    """

    datos_subtipo = {
        "zona_cobertura": zona_cobertura,
        "nro_habilitacion": nro_habilitacion,
        "pais_destino_principal": pais_destino_principal,
    }

    with transaction(pool) as connection:
        connection.row_factory = dict_row
        fila = connection.execute(
            "INSERT INTO cliente (nombre, tipo, tipo_documento, nro_documento,"
            " direccion, id_localidad, fecha_alta)"
            " VALUES (%s, %s, %s, %s, %s, %s, COALESCE(%s, CURRENT_DATE))"
            " RETURNING id_cliente",
            (nombre, tipo, tipo_documento, nro_documento, direccion, id_localidad, fecha_alta),
        ).fetchone()
        id_cliente = fila["id_cliente"]

        _insertar_subtipo(connection, id_cliente, tipo, datos_subtipo)

        if permisos:
            _insertar_permisos(connection, id_cliente, permisos)

        return _cargar_detalle(connection, id_cliente)


def actualizar_cliente(
    pool: ConnectionPool,
    id_cliente: int,
    *,
    permisos: list[dict] | None = None,
    **campos,
) -> dict | None:
    """Update one client inside one transaction; None if it does not exist.

    Updates only the provided fields of ``_CAMPOS_CLIENTE`` (never
    ``tipo`` nor ``descuento``). ``zona_cobertura``/``nro_habilitacion``
    update the distribuidor row and ``pais_destino_principal`` the
    exportador row; if the client is not that subtype the UPDATE affects
    no rows and stays a no-op. When ``permisos`` is given the whole
    collection is replaced (DELETE + INSERT); for a non-exporter the
    DELETE removes nothing and the INSERT fails with 422 (missing parent
    of the composite FK).
    """

    with transaction(pool) as connection:
        connection.row_factory = dict_row

        fragmentos = [f"{campo} = %({campo})s" for campo in _CAMPOS_CLIENTE if campo in campos]
        if fragmentos:
            fila = connection.execute(
                f"UPDATE cliente SET {', '.join(fragmentos)}"
                " WHERE id_cliente = %(id_cliente)s RETURNING id_cliente",
                {**campos, "id_cliente": id_cliente},
            ).fetchone()
        else:
            fila = connection.execute(
                "SELECT id_cliente FROM cliente WHERE id_cliente = %s", (id_cliente,)
            ).fetchone()

        if fila is None:
            return None

        subtype_fields = {
            "zona_cobertura": campos.get("zona_cobertura"),
            "nro_habilitacion": campos.get("nro_habilitacion"),
        }
        subtype_fields = {clave: valor for clave, valor in subtype_fields.items() if clave in campos}
        if subtype_fields:
            connection.execute(
                f"UPDATE distribuidor SET {', '.join(f'{clave} = %({clave})s' for clave in subtype_fields)}"
                " WHERE id_cliente = %(id_cliente)s",
                {**subtype_fields, "id_cliente": id_cliente},
            )

        if "pais_destino_principal" in campos:
            connection.execute(
                "UPDATE exportador SET pais_destino_principal = %s WHERE id_cliente = %s",
                (campos["pais_destino_principal"], id_cliente),
            )

        if permisos is not None:
            connection.execute("DELETE FROM permiso_exportacion WHERE id_cliente = %s", (id_cliente,))
            if permisos:
                _insertar_permisos(connection, id_cliente, permisos)

        return _cargar_detalle(connection, id_cliente)


def eliminar_cliente(pool: ConnectionPool, id_cliente: int) -> int:
    """Delete one client and return the number of deleted rows (0 or 1).

    socio / distribuidor / exportador / permiso_exportacion are CASCADE
    from cliente, so the base removes them with the owner's privileges.
    ``comprobante`` is RESTRICT: that session simply fails with SQLSTATE
    23503, which the central mapper turns into 409 \u2014 the mapped error is the
    correct outcome, never worked around here.
    """

    with transaction(pool) as connection:
        eliminadas = connection.execute(
            "DELETE FROM cliente WHERE id_cliente = %s RETURNING id_cliente", (id_cliente,)
        ).fetchall()
        return len(eliminadas)
