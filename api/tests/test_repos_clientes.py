"""Integration tests for the clientes repository (app_rw) against PostgreSQL.

localidad (and sala for the comprobante RESTRICT case) are created with a
superuser connection; every cliente operation goes through the repository
functions only.
"""

import os
import uuid
from datetime import date
from decimal import Decimal

import psycopg
import pytest
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row

from app.config import Settings
from app.db import create_pool, get_connection, transaction
from app.errors import DatabaseHttpError
from app.repos import clientes

_TAIL = uuid.uuid4().hex[:10]
CLIENTE_NOMBRE = f"Cliente repo {_TAIL}"


def _superuser():
    return psycopg.connect(
        make_conninfo(
            host=os.environ["POSTGRES_HOST"],
            port=os.environ["POSTGRES_PORT"],
            dbname=os.environ["POSTGRES_DB"],
            user=os.environ["PGSU"],
            password=os.environ["PGSUPW"],
        )
    )


@pytest.fixture(scope="module")
def pool():
    pool_inst = create_pool(Settings.from_env())
    yield pool_inst
    pool_inst.close()


@pytest.fixture
def localidades():
    """Creates two localidades with the superuser role."""
    superuser = _superuser()
    marcador = f"{uuid.uuid4().int:030x}"[-8:]
    prefijo_cp = str(uuid.uuid4().int)[:2]
    ids: list[int] = []
    try:
        ids = [
            superuser.execute(
                "INSERT INTO localidad (codigo_postal, nombre, provincia)"
                " VALUES (%s, %s, 'Mendoza') RETURNING id_localidad",
                (f"{prefijo_cp}{n:02d}"[:4], f"Localidad repo {marcador} {n}"),
            ).fetchone()[0]
            for n in (1, 2)
        ]
        superuser.commit()
        yield {"ids": ids}
    finally:
        try:
            superuser.execute(
                "DELETE FROM comprobante WHERE id_cliente IN"
                " (SELECT id_cliente FROM cliente WHERE id_localidad = ANY(%s))",
                (ids,),
            )
            superuser.execute("DELETE FROM cliente WHERE id_localidad = ANY(%s)", (ids,))
            superuser.execute("DELETE FROM localidad WHERE id_localidad = ANY(%s)", (ids,))
            superuser.commit()
        finally:
            superuser.close()


def _crear_cliente(pool, localidades, nro, *, tipo="socio", extra=None, permisos=None):
    datos = dict(
        nombre=f"{CLIENTE_NOMBRE} {nro}",
        tipo=tipo,
        tipo_documento="DNI",
        nro_documento=f"33{_TAIL[:5]}{nro}",
        direccion="Av. Prueba 123",
        id_localidad=localidades["ids"][0],
    )
    if tipo == "distribuidor":
        datos.update(zona_cobertura="Zona Sur", nro_habilitacion=f"HAB-{_TAIL}-{nro}")
    if tipo == "exportador":
        datos.update(pais_destino_principal="Brasil")
    if extra:
        datos.update(extra)
    if permisos is not None:
        datos["permisos"] = permisos
    return clientes.crear_cliente(pool, **datos)


def test_crear_y_obtener_socio(pool, localidades):
    creado = _crear_cliente(pool, localidades, 1)

    assert creado["id_cliente"] > 0
    assert creado["nombre"] == f"{CLIENTE_NOMBRE} 1"
    assert creado["tipo"] == "socio"
    assert creado["descuento"] == Decimal("10.00")
    assert creado["localidad"].startswith("Localidad repo")
    assert creado["fecha_alta"] == date.today()
    assert creado["zona_cobertura"] is None
    assert creado["nro_habilitacion"] is None
    assert creado["pais_destino_principal"] is None
    assert creado["permisos"] == []

    detalle = clientes.obtener_cliente(pool, creado["id_cliente"])
    assert detalle["id_cliente"] == creado["id_cliente"]
    assert detalle["localidad"].startswith("Localidad repo")
    assert clientes.obtener_cliente(pool, 999999999) is None


def test_crear_distribuidor_y_exportador(pool, localidades):
    distribuidor = _crear_cliente(pool, localidades, 2, tipo="distribuidor")
    assert distribuidor["zona_cobertura"] == "Zona Sur"
    assert distribuidor["nro_habilitacion"] == f"HAB-{_TAIL}-2"
    assert distribuidor["descuento"] == Decimal("20.00")
    assert distribuidor["pais_destino_principal"] is None

    exportador = _crear_cliente(
        pool,
        localidades,
        3,
        tipo="exportador",
        permisos=[
            {
                "cod_permiso": f"EXP-{_TAIL}-1",
                "fecha_emision": date(2026, 1, 15),
                "fecha_vencimiento": date(2027, 1, 15),
            }
        ],
    )
    assert exportador["pais_destino_principal"] == "Brasil"
    assert exportador["descuento"] == Decimal("30.00")
    assert exportador["permisos"] == [
        {
            "cod_permiso": f"EXP-{_TAIL}-1",
            "fecha_emision": date(2026, 1, 15),
            "fecha_vencimiento": date(2027, 1, 15),
        }
    ]

    detalle = clientes.obtener_cliente(pool, exportador["id_cliente"])
    assert detalle["permisos"] == exportador["permisos"]


def test_crear_cliente_fecha_alta_explicita(pool, localidades):
    creado = _crear_cliente(pool, localidades, 4, extra={"fecha_alta": date(2024, 3, 10)})
    assert creado["fecha_alta"] == date(2024, 3, 10)


def test_listar_clientes_filtros(pool, localidades):
    socio = _crear_cliente(pool, localidades, 5)
    exportador = _crear_cliente(
        pool, localidades, 6, tipo="exportador", extra={"id_localidad": localidades["ids"][1]}
    )

    resultado, total = clientes.listar_clientes(pool, q=f"{CLIENTE_NOMBRE} 5")
    assert total == 1
    assert resultado[0]["id_cliente"] == socio["id_cliente"]
    assert resultado[0]["localidad"].startswith("Localidad repo")

    _, total = clientes.listar_clientes(pool, tipo="exportador", q=CLIENTE_NOMBRE)
    assert total >= 1

    resultado, total = clientes.listar_clientes(
        pool, tipo="socio", id_localidad=localidades["ids"][1], q=CLIENTE_NOMBRE
    )
    assert total == 0


def test_listar_clientes_paginacion(pool, localidades):
    _crear_cliente(pool, localidades, 7)
    _crear_cliente(pool, localidades, 8)

    pagina1, total = clientes.listar_clientes(pool, q=CLIENTE_NOMBRE, page=1, per_page=1)
    pagina2, _ = clientes.listar_clientes(pool, q=CLIENTE_NOMBRE, page=2, per_page=1)
    assert total == 2
    assert len(pagina1) == 1
    (pg2,) = pagina2
    assert pg2["localidad"].startswith("Localidad repo")
    assert pagina1[0]["id_cliente"] != pagina2[0]["id_cliente"]

    fuera, total = clientes.listar_clientes(pool, q=CLIENTE_NOMBRE, page=3, per_page=1)
    assert fuera == []
    assert total == 2


def test_filtros_seguros_contra_inyeccion(pool, localidades):
    malicioso = "'; DROP TABLE cliente; --"

    resultado, total = clientes.listar_clientes(pool, q=malicioso)
    assert resultado == []
    assert total == 0

    clientes.listar_clientes(pool, q="%")

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        filas = connection.execute("SELECT COUNT(*) AS n FROM cliente").fetchone()
    assert filas["n"] >= 0


def test_crear_cliente_duplicado_documento_409(pool, localidades):
    datos = dict(
        nombre=f"{CLIENTE_NOMBRE} dup",
        tipo="socio",
        tipo_documento="DNI",
        nro_documento=f"88{_TAIL[:8]}",
        direccion="Av. Prueba 123",
        id_localidad=localidades["ids"][0],
    )
    clientes.crear_cliente(pool, **datos)
    with pytest.raises(DatabaseHttpError) as raised:
        clientes.crear_cliente(pool, **datos)

    error = raised.value
    assert error.status == 409
    assert error.payload["codigo"] == "23505"


def test_actualizar_cliente_campos(pool, localidades):
    creado = _crear_cliente(pool, localidades, 9)

    detalle = clientes.actualizar_cliente(
        pool,
        creado["id_cliente"],
        nombre=f"{CLIENTE_NOMBRE} 9 editado",
        direccion="Nueva direccion 456",
        id_localidad=localidades["ids"][1],
    )

    assert detalle["nombre"] == f"{CLIENTE_NOMBRE} 9 editado"
    assert detalle["direccion"] == "Nueva direccion 456"
    assert detalle["id_localidad"] == localidades["ids"][1]
    assert detalle["localidad"].startswith("Localidad repo")
    # tipo y descuento never change through the API
    assert detalle["tipo"] == "socio"
    assert detalle["descuento"] == Decimal("10.00")


def test_actualizar_cliente_subtipos_y_permisos(pool, localidades):
    distribuidor = _crear_cliente(pool, localidades, 10, tipo="distribuidor")
    detalle = clientes.actualizar_cliente(
        pool, distribuidor["id_cliente"], zona_cobertura="Zona Norte", nro_habilitacion=f"HAB-EDIT-{_TAIL}"
    )
    assert detalle["zona_cobertura"] == "Zona Norte"
    assert detalle["nro_habilitacion"] == f"HAB-EDIT-{_TAIL}"

    exportador = _crear_cliente(pool, localidades, 11, tipo="exportador")
    detalle = clientes.actualizar_cliente(pool, exportador["id_cliente"], pais_destino_principal="Chile")
    assert detalle["pais_destino_principal"] == "Chile"

    permisos = [
        {
            "cod_permiso": f"EXP-E-{_TAIL}-1",
            "fecha_emision": date(2026, 2, 1),
            "fecha_vencimiento": date(2027, 2, 1),
        },
        {
            "cod_permiso": f"EXP-E-{_TAIL}-2",
            "fecha_emision": date(2026, 3, 1),
            "fecha_vencimiento": date(2027, 3, 1),
        },
    ]
    detalle = clientes.actualizar_cliente(pool, exportador["id_cliente"], permisos=permisos)
    assert {p["cod_permiso"] for p in detalle["permisos"]} == {
        f"EXP-E-{_TAIL}-1",
        f"EXP-E-{_TAIL}-2",
    }

    # reemplazo: borra las viejas y deja solo la nueva
    nuevas = [
        {
            "cod_permiso": f"EXP-E-{_TAIL}-3",
            "fecha_emision": date(2026, 4, 1),
            "fecha_vencimiento": date(2027, 4, 1),
        }
    ]
    detalle = clientes.actualizar_cliente(pool, exportador["id_cliente"], permisos=nuevas)
    assert detalle["permisos"] == [
        {"cod_permiso": f"EXP-E-{_TAIL}-3", "fecha_emision": date(2026, 4, 1), "fecha_vencimiento": date(2027, 4, 1)}
    ]


def test_actualizar_cliente_inexistente_none(pool, localidades):
    assert clientes.actualizar_cliente(pool, 999999999, nombre="nada") is None


def test_eliminar_cliente_roundtrip(pool, localidades):
    creado = _crear_cliente(pool, localidades, 12)

    eliminados = clientes.eliminar_cliente(pool, creado["id_cliente"])
    assert eliminados == 1
    assert clientes.obtener_cliente(pool, creado["id_cliente"]) is None
    assert clientes.eliminar_cliente(pool, creado["id_cliente"]) == 0


def test_eliminar_cliente_cascada_subtipos(pool, localidades):
    exportador = _crear_cliente(
        pool,
        localidades,
        13,
        tipo="exportador",
        permisos=[
            {
                "cod_permiso": f"EXP-C-{_TAIL}",
                "fecha_emision": date(2026, 1, 1),
                "fecha_vencimiento": date(2027, 1, 1),
            }
        ],
    )

    assert clientes.eliminar_cliente(pool, exportador["id_cliente"]) == 1

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        permisos = connection.execute(
            "SELECT COUNT(*) AS n FROM permiso_exportacion WHERE id_cliente = %s",
            (exportador["id_cliente"],),
        ).fetchone()
    assert permisos["n"] == 0


def test_eliminar_cliente_con_comprobante_restringido_409(pool, localidades):
    """comprobante references cliente with RESTRICT: the mapped error wins."""
    creado = _crear_cliente(pool, localidades, 14)
    # sala + comprobante via superuser: app_rw no puede escribir sala ni
    # borrar comprobante; solo necesita el INSERT de cabecera concedido en 007.
    superuser = _superuser()
    try:
        id_sala = superuser.execute(
            "INSERT INTO sala (direccion, dia_cierre_semanal, id_localidad)"
            " VALUES (%s, 1, %s) RETURNING id_sala",
            (f"Sala repo {_TAIL}", localidades["ids"][0]),
        ).fetchone()[0]
        superuser.commit()
        with transaction(pool) as connection:
            connection.execute(
                "INSERT INTO comprobante (id_cliente, id_sala) VALUES (%s, %s)",
                (creado["id_cliente"], id_sala),
            )

        with pytest.raises(DatabaseHttpError) as raised:
            clientes.eliminar_cliente(pool, creado["id_cliente"])

        assert raised.value.status == 409
        assert raised.value.payload["codigo"] == "23503"
        assert clientes.obtener_cliente(pool, creado["id_cliente"]) is not None
    finally:
        # el DELETE de comprobante corta la RESTRICT que bloquea al cliente
        superuser.execute(
            "DELETE FROM comprobante WHERE id_cliente IN"
            " (SELECT id_cliente FROM cliente WHERE id_localidad = ANY(%s))",
            (localidades["ids"],),
        )
        superuser.execute("DELETE FROM sala WHERE direccion = %s", (f"Sala repo {_TAIL}",))
        superuser.commit()
        superuser.close()
