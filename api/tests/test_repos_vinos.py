"""Integration tests for the vinos repository (app_rw) against PostgreSQL.

Catalog tables that app_rw cannot write (bodega, cepa, maridaje) are
created with a superuser connection; every vino operation goes through
the repository functions only.
"""

import os
import uuid
from decimal import Decimal

import psycopg
import pytest
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row

from app.config import Settings
from app.db import create_pool, get_connection
from app.errors import DatabaseHttpError
from app.repos import vinos

_TAIL = uuid.uuid4().hex[:10]
BODEGA_CUIT = f"93{(uuid.uuid4().int % 10**9):09d}"
VINO_NOMBRE = f"Vino repo {_TAIL}"


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
def catalogo():
    """Creates bodega + 2 cepas + 2 maridajes with the superuser role."""
    superuser = _superuser()
    try:
        superuser.execute(
            "INSERT INTO bodega (cuit, razon_social, domicilio) VALUES (%s, 'Bodega repos', 'Domicilio repos')"
            " ON CONFLICT (cuit) DO NOTHING",
            (BODEGA_CUIT,),
        )
        cepas = [
            superuser.execute(
                "INSERT INTO cepa (nombre, tipo) VALUES (%s, 'tinta') RETURNING id_cepa",
                (f"Cepa repo {_TAIL} {n}",),
            ).fetchone()[0]
            for n in (1, 2)
        ]
        maridajes = [
            superuser.execute(
                "INSERT INTO maridaje (nombre, temperatura_servicio) VALUES (%s, %s) RETURNING id_maridaje",
                (f"Maridaje repo {_TAIL} {n}", 18.0 + n),
            ).fetchone()[0]
            for n in (1, 2)
        ]
        superuser.commit()
        yield {"cuit": BODEGA_CUIT, "cepas": cepas, "maridajes": maridajes}
    finally:
        try:
            superuser.execute(
                "DELETE FROM auditoria_precio WHERE cod_vino IN"
                " (SELECT cod_vino FROM vino WHERE cuit_bodega = %s)",
                (BODEGA_CUIT,),
            )
            superuser.execute(
                "DELETE FROM stock_deposito WHERE cod_vino IN"
                " (SELECT cod_vino FROM vino WHERE cuit_bodega = %s)",
                (BODEGA_CUIT,),
            )
            superuser.execute(
                "DELETE FROM stock_sala WHERE cod_vino IN"
                " (SELECT cod_vino FROM vino WHERE cuit_bodega = %s)",
                (BODEGA_CUIT,),
            )
            superuser.execute("DELETE FROM vino WHERE cuit_bodega = %s", (BODEGA_CUIT,))
            superuser.execute("DELETE FROM maridaje WHERE nombre LIKE %s", (f"Maridaje repo {_TAIL}%",))
            superuser.execute("DELETE FROM cepa WHERE nombre LIKE %s", (f"Cepa repo {_TAIL}%",))
            superuser.execute("DELETE FROM bodega WHERE cuit = %s", (BODEGA_CUIT,))
            superuser.commit()
        finally:
            superuser.close()


def _crear_vino(pool, catalogo, sufijo, *, tipo="tinto", anada=2021, composicion=None, maridajes=None):
    return vinos.crear_vino(
        pool,
        nombre_comercial=f"{VINO_NOMBRE} {sufijo}",
        tipo=tipo,
        anada=anada,
        presentacion_ml=750,
        graduacion=Decimal("13.50"),
        precio_venta=Decimal("100.00"),
        cuit_bodega=catalogo["cuit"],
        composicion=composicion
        or [
            {"id_cepa": catalogo["cepas"][0], "porcentaje": Decimal("70.00")},
            {"id_cepa": catalogo["cepas"][1], "porcentaje": Decimal("30.00")},
        ],
        maridajes=maridajes,
    )


def test_crear_vino_devuelve_ficha_completa(pool, catalogo):
    detalle = _crear_vino(pool, catalogo, "ficha", maridajes=[catalogo["maridajes"][0]])

    assert detalle["cod_vino"] > 0
    assert detalle["nombre_comercial"] == f"{VINO_NOMBRE} ficha"
    assert detalle["tipo"] == "tinto"
    assert detalle["anada"] == 2021
    assert detalle["presentacion_ml"] == 750
    assert detalle["graduacion"] == Decimal("13.50")
    assert detalle["precio_venta"] == Decimal("100.00")
    assert detalle["cuit_bodega"] == BODEGA_CUIT
    assert detalle["bodega"] == "Bodega repos"
    assert detalle["composicion"] == [
        {"id_cepa": catalogo["cepas"][0], "nombre": f"Cepa repo {_TAIL} 1", "porcentaje": 70.0},
        {"id_cepa": catalogo["cepas"][1], "nombre": f"Cepa repo {_TAIL} 2", "porcentaje": 30.0},
    ]
    assert detalle["maridajes"] == [
        {"id_maridaje": catalogo["maridajes"][0], "nombre": f"Maridaje repo {_TAIL} 1", "temperatura_servicio": 19.0}
    ]
    assert detalle["stock"] == {"deposito": 0, "salas": 0, "total": 0}


def test_obtener_vino_roundtrip(pool, catalogo):
    creado = _crear_vino(pool, catalogo, "obtener")
    detalle = vinos.obtener_vino(pool, creado["cod_vino"])

    assert detalle["cod_vino"] == creado["cod_vino"]
    assert detalle["bodega"] == "Bodega repos"
    assert len(detalle["composicion"]) == 2
    assert detalle["stock"] == {"deposito": 0, "salas": 0, "total": 0}
    assert vinos.obtener_vino(pool, 999999999) is None


def test_listar_vinos_filtros(pool, catalogo):
    creado = _crear_vino(pool, catalogo, "filtro", tipo="rosado", anada=2024)
    _crear_vino(pool, catalogo, "otro", tipo="tinto", anada=2020)

    resultado, total = vinos.listar_vinos(pool, nombre=f"{VINO_NOMBRE} filtro")
    assert total == 1
    assert resultado[0]["cod_vino"] == creado["cod_vino"]
    assert resultado[0]["bodega"] == "Bodega repos"
    assert "stock" not in resultado[0]
    assert "composicion" not in resultado[0]

    resultado, total = vinos.listar_vinos(pool, id_cepa=catalogo["cepas"][1])
    assert total >= 1
    assert creado["cod_vino"] in {row["cod_vino"] for row in resultado}

    resultado, total = vinos.listar_vinos(pool, tipo="rosado", anada=2024, nombre=VINO_NOMBRE)
    assert total == 1
    assert resultado[0]["cod_vino"] == creado["cod_vino"]


def test_listar_vinos_paginacion(pool, catalogo):
    _crear_vino(pool, catalogo, "pag1")
    _crear_vino(pool, catalogo, "pag2")

    pagina1, total1 = vinos.listar_vinos(pool, nombre=VINO_NOMBRE, page=1, per_page=1)
    pagina2, total2 = vinos.listar_vinos(pool, nombre=VINO_NOMBRE, page=2, per_page=1)
    assert total1 == 2
    assert len(pagina1) == 1
    assert len(pagina2) == 1
    assert pagina1[0]["cod_vino"] != pagina2[0]["cod_vino"]

    fuera, total = vinos.listar_vinos(pool, nombre=VINO_NOMBRE, page=3, per_page=1)
    assert fuera == []
    assert total == 2

    _, total = vinos.listar_vinos(pool, nombre=f"{VINO_NOMBRE} inexistente")
    assert total == 0


def test_filtros_seguros_contra_inyeccion(pool, catalogo):
    malicioso = "'; DROP TABLE vino; --"

    resultado, total = vinos.listar_vinos(pool, nombre=malicioso)
    assert resultado == []
    assert total == 0

    # '%' es un comodin valido: no rompe, simplemente empareja lo ILIKEable
    con_porcentaje, _ = vinos.listar_vinos(pool, nombre="%")
    assert isinstance(con_porcentaje, list)

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        filas = connection.execute("SELECT COUNT(*) AS n FROM vino").fetchone()
    assert filas["n"] >= 0


def test_crear_vino_rn05_deferred_nada_persiste(pool, catalogo):
    with pytest.raises(DatabaseHttpError) as raised:
        _crear_vino(
            pool,
            catalogo,
            "rn05",
            composicion=[
                {"id_cepa": catalogo["cepas"][0], "porcentaje": Decimal("60.00")},
                {"id_cepa": catalogo["cepas"][1], "porcentaje": Decimal("30.00")},
            ],
        )

    error = raised.value
    assert error.status == 409
    assert error.payload["regla"] == "RN-05"
    assert error.payload["codigo"] == "P0001"

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        filas = connection.execute(
            "SELECT COUNT(*) AS n FROM vino WHERE nombre_comercial = %s",
            (f"{VINO_NOMBRE} rn05",),
        ).fetchone()
    assert filas["n"] == 0


def test_crear_vino_duplicado_409(pool, catalogo):
    _crear_vino(pool, catalogo, "dup")
    with pytest.raises(DatabaseHttpError) as raised:
        _crear_vino(pool, catalogo, "dup")

    error = raised.value
    assert error.status == 409
    assert error.payload["codigo"] == "23505"


def test_actualizar_vino_campos_y_auditoria_precio(pool, catalogo):
    creado = _crear_vino(pool, catalogo, "audit")
    nuevo_precio = Decimal("123.45")

    detalle = vinos.actualizar_vino(
        pool,
        creado["cod_vino"],
        usuario="p3_prueba_precio",
        precio_venta=nuevo_precio,
    )

    assert detalle["precio_venta"] == nuevo_precio
    assert detalle["nombre_comercial"] == f"{VINO_NOMBRE} audit"

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        filas = connection.execute(
            "SELECT usuario, precio_anterior, precio_nuevo"
            " FROM auditoria_precio WHERE cod_vino = %s ORDER BY id_auditoria",
            (creado["cod_vino"],),
        ).fetchall()
    assert len(filas) == 1
    assert filas[0]["usuario"] == "p3_prueba_precio"
    assert filas[0]["precio_anterior"] == Decimal("100.00")
    assert filas[0]["precio_nuevo"] == nuevo_precio


def test_actualizar_vino_reemplaza_composicion_y_maridajes(pool, catalogo):
    creado = _crear_vino(pool, catalogo, "replace", maridajes=[catalogo["maridajes"][0]])

    detalle = vinos.actualizar_vino(
        pool,
        creado["cod_vino"],
        usuario="p3_prueba_reemplazo",
        composicion=[{"id_cepa": catalogo["cepas"][1], "porcentaje": Decimal("100.00")}],
        maridajes=[catalogo["maridajes"][1]],
    )

    assert detalle["composicion"] == [
        {"id_cepa": catalogo["cepas"][1], "nombre": f"Cepa repo {_TAIL} 2", "porcentaje": 100.0}
    ]
    assert detalle["maridajes"] == [
        {"id_maridaje": catalogo["maridajes"][1], "nombre": f"Maridaje repo {_TAIL} 2", "temperatura_servicio": 20.0}
    ]


def test_actualizar_vino_inexistente_none(pool, catalogo):
    assert vinos.actualizar_vino(pool, 999999999, usuario="p3", nombre_comercial="nada") is None


def test_eliminar_vino_roundtrip(pool, catalogo):
    creado = _crear_vino(pool, catalogo, "baja")

    eliminados = vinos.eliminar_vino(pool, creado["cod_vino"])
    assert eliminados == 1
    assert vinos.obtener_vino(pool, creado["cod_vino"]) is None
    assert vinos.eliminar_vino(pool, creado["cod_vino"]) == 0


def test_eliminar_vino_con_dependencia_restringida_409(pool, catalogo):
    creado = _crear_vino(pool, catalogo, "restringido")
    superuser = _superuser()
    try:
        superuser.execute("INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (%s, 5)", (creado["cod_vino"],))
        superuser.commit()
    finally:
        superuser.close()

    with pytest.raises(DatabaseHttpError) as raised:
        vinos.eliminar_vino(pool, creado["cod_vino"])

    assert raised.value.status == 409
    assert raised.value.payload["codigo"] == "23503"
    # el vino sigue existiendo: la FK RESTRICT lo bloquea
    assert vinos.obtener_vino(pool, creado["cod_vino"]) is not None


def test_app_rw_no_puede_insertar_bodega(pool):
    with pytest.raises(psycopg.errors.InsufficientPrivilege) as raised:
        with get_connection(pool) as connection:
            connection.execute(
                "INSERT INTO bodega (cuit, razon_social, domicilio) VALUES (%s, 'x', 'y')",
                (f"91{(uuid.uuid4().int % 10**9):09d}",),
            )

    assert raised.value.sqlstate == "42501"
