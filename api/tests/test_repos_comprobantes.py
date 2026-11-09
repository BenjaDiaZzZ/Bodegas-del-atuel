"""Integration tests for the comprobantes repository (app_rw) against PostgreSQL.

Catalog tables that app_rw cannot write (bodega, cepa, localidad, sala,
stock_sala) are created with a superuser connection; every comprobante
operation goes through the repository functions only.
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
from app.db import create_pool, get_connection
from app.errors import DatabaseHttpError
from app.repos import clientes, comprobantes, vinos

_TAIL = uuid.uuid4().hex[:10]
BODEGA_CUIT = f"93{(uuid.uuid4().int % 10**9):09d}"
LOCALIDAD = f"Localidad repo {_TAIL}"
SALA_DIRECCION = f"Direccion repo {_TAIL}"
CLIENTE_NOMBRE = f"Cliente repo {_TAIL}"
VINO_NOMBRE = f"Vino repo {_TAIL}"

# Independent source of truth: precio 100.00 with the documented socio
# discount of 10% (fn_descuento_cliente, R-002) for every expected amount.
PRECIO = Decimal("100.00")


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


@pytest.fixture(scope="module")
def escenario():
    """Base catalog (bodega, cepas, localidad, sala) via superuser."""
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
        localidad = superuser.execute(
            "INSERT INTO localidad (nombre, codigo_postal, provincia)"
            " VALUES (%s, '5600', 'Mendoza') RETURNING id_localidad",
            (LOCALIDAD,),
        ).fetchone()[0]
        sala = superuser.execute(
            "INSERT INTO sala (direccion, dia_cierre_semanal, id_localidad)"
            " VALUES (%s, 2, %s) RETURNING id_sala",
            (SALA_DIRECCION, localidad),
        ).fetchone()[0]
        superuser.commit()
        yield {"cepas": cepas, "id_localidad": localidad, "id_sala": sala}
    finally:
        try:
            superuser.execute("DELETE FROM comprobante WHERE id_sala = %s", (sala,))
            superuser.execute("DELETE FROM stock_sala WHERE id_sala = %s", (sala,))
            superuser.execute(
                "DELETE FROM stock_deposito WHERE cod_vino IN"
                " (SELECT cod_vino FROM vino WHERE cuit_bodega = %s)",
                (BODEGA_CUIT,),
            )
            superuser.execute("DELETE FROM vino WHERE cuit_bodega = %s", (BODEGA_CUIT,))
            superuser.execute(
                "DELETE FROM cliente WHERE nombre LIKE %s", (f"{CLIENTE_NOMBRE}%",))
            superuser.execute("DELETE FROM sala WHERE id_sala = %s", (sala,))
            superuser.execute("DELETE FROM localidad WHERE nombre = %s", (LOCALIDAD,))
            superuser.execute(
                "DELETE FROM cepa WHERE nombre LIKE %s", (f"Cepa repo {_TAIL}%",))
            superuser.execute("DELETE FROM bodega WHERE cuit = %s", (BODEGA_CUIT,))
            superuser.commit()
        finally:
            superuser.close()


def _nuevo_cliente(pool, escenario, sufijo):
    """One unique socio per call keeps counts and teardown isolated."""
    return clientes.crear_cliente(
        pool,
        nombre=f"{CLIENTE_NOMBRE} {sufijo}",
        tipo="socio",
        tipo_documento="DNI",
        nro_documento=f"{(uuid.uuid4().int % 10**8):08d}",
        direccion="Calle repos",
        id_localidad=escenario["id_localidad"],
    )


def _crear_vino(pool, escenario, sufijo, precio=PRECIO):
    """One vino with a single cepa (100%) per call. app_rw owns the DML."""
    return vinos.crear_vino(
        pool,
        nombre_comercial=f"{VINO_NOMBRE} {sufijo}",
        tipo="tinto",
        anada=2021,
        presentacion_ml=750,
        graduacion=Decimal("13.50"),
        precio_venta=precio,
        cuit_bodega=BODEGA_CUIT,
        composicion=[{"id_cepa": escenario["cepas"][0], "porcentaje": Decimal("100.00")}],
    )


def _sembrar_stock(su, id_sala, cod_vino, cantidad):
    su.execute(
        "INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (%s, %s, %s)"
        " ON CONFLICT (id_sala, cod_vino) DO UPDATE SET cantidad = EXCLUDED.cantidad",
        (id_sala, cod_vino, cantidad),
    )


def _stock_de(pool, id_sala, cod_vino):
    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        return connection.execute(
            "SELECT cantidad FROM stock_sala WHERE id_sala = %s AND cod_vino = %s",
            (id_sala, cod_vino),
        ).fetchone()["cantidad"]


def test_crear_comprobante_renglones_ordenados_y_totales(pool, escenario):
    vino_mayor = _crear_vino(pool, escenario, "ordenado mayor")
    vino_menor = _crear_vino(pool, escenario, "ordenado menor")
    cliente = _nuevo_cliente(pool, escenario, "venta")
    su = _superuser()
    try:
        _sembrar_stock(su, escenario["id_sala"], vino_mayor["cod_vino"], 3)
        _sembrar_stock(su, escenario["id_sala"], vino_menor["cod_vino"], 5)
        su.commit()
    finally:
        su.close()

    # Enviados DESORDENADOS: el vino con mayor cod_vino primero.
    creado = comprobantes.crear_comprobante(
        pool,
        id_cliente=cliente["id_cliente"],
        id_sala=escenario["id_sala"],
        renglones=[
            {"cod_vino": vino_mayor["cod_vino"], "cantidad": 2},
            {"cod_vino": vino_menor["cod_vino"], "cantidad": 3},
        ],
    )

    assert creado["nro_comprobante"] > 0
    assert creado["fecha"] == date.today()
    assert creado["id_cliente"] == cliente["id_cliente"]
    assert creado["id_sala"] == escenario["id_sala"]

    renglones = creado["renglones"]
    assert [r["cod_vino"] for r in renglones] == [vino_mayor["cod_vino"], vino_menor["cod_vino"]]
    assert renglones[0]["nombre_comercial"] == f"{VINO_NOMBRE} ordenado mayor"
    # RN-08: precio vigente, descuento 10% del socio, subtotal con descuento.
    assert renglones[0]["precio_unitario"] == PRECIO
    assert renglones[0]["descuento"] == Decimal("20.00")
    assert renglones[0]["subtotal"] == Decimal("180.00")
    assert renglones[1]["precio_unitario"] == PRECIO
    assert renglones[1]["nombre_comercial"] == f"{VINO_NOMBRE} ordenado menor"
    assert renglones[1]["descuento"] == Decimal("30.00")
    assert renglones[1]["subtotal"] == Decimal("270.00")

    # Totales de cabecera calculados por T2 (fn_total_comprobante):
    # subtotal = SUM(subtotal + descuento) por renglon, total = SUM(subtotal),
    # descuento = subtotal - total.
    assert creado["subtotal"] == Decimal("500.00")
    assert creado["descuento"] == Decimal("50.00")
    assert creado["total"] == Decimal("450.00")
    assert creado["total"] == creado["subtotal"] - creado["descuento"]

    # T2 desconto el stock: la base hizo el trabajo.
    assert _stock_de(pool, escenario["id_sala"], vino_menor["cod_vino"]) == 2
    assert _stock_de(pool, escenario["id_sala"], vino_mayor["cod_vino"]) == 1


def test_crear_comprobante_rn09_nada_persiste(pool, escenario):
    vino = _crear_vino(pool, escenario, "rn09")
    cliente = _nuevo_cliente(pool, escenario, "rn09")
    su = _superuser()
    try:
        _sembrar_stock(su, escenario["id_sala"], vino["cod_vino"], 1)
        su.commit()
    finally:
        su.close()

    with pytest.raises(DatabaseHttpError) as raised:
        comprobantes.crear_comprobante(
            pool,
            id_cliente=cliente["id_cliente"],
            id_sala=escenario["id_sala"],
            renglones=[{"cod_vino": vino["cod_vino"], "cantidad": 5}],
        )

    error = raised.value
    assert error.status == 409
    assert error.payload["regla"] == "RN-09"
    assert error.payload["codigo"] == "P0001"
    assert _stock_de(pool, escenario["id_sala"], vino["cod_vino"]) == 1

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        filas = connection.execute(
            "SELECT COUNT(*) AS n FROM comprobante WHERE id_cliente = %s",
            (cliente["id_cliente"],),
        ).fetchone()
    assert filas["n"] == 0


def test_crear_comprobante_renglon_duplicado_409(pool, escenario):
    vino = _crear_vino(pool, escenario, "duplicado")
    cliente = _nuevo_cliente(pool, escenario, "duplicado")
    su = _superuser()
    try:
        _sembrar_stock(su, escenario["id_sala"], vino["cod_vino"], 10)
        su.commit()
    finally:
        su.close()

    with pytest.raises(DatabaseHttpError) as raised:
        comprobantes.crear_comprobante(
            pool,
            id_cliente=cliente["id_cliente"],
            id_sala=escenario["id_sala"],
            renglones=[
                {"cod_vino": vino["cod_vino"], "cantidad": 1},
                {"cod_vino": vino["cod_vino"], "cantidad": 2},
            ],
        )

    error = raised.value
    assert error.status == 409
    assert error.payload["codigo"] == "23505"

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        filas = connection.execute(
            "SELECT COUNT(*) AS n FROM comprobante WHERE id_cliente = %s",
            (cliente["id_cliente"],),
        ).fetchone()
    assert filas["n"] == 0


def test_obtener_comprobante_roundtrip(pool, escenario):
    vino = _crear_vino(pool, escenario, "obtener")
    cliente = _nuevo_cliente(pool, escenario, "obtener")
    su = _superuser()
    try:
        _sembrar_stock(su, escenario["id_sala"], vino["cod_vino"], 4)
        su.commit()
    finally:
        su.close()

    creado = comprobantes.crear_comprobante(
        pool,
        id_cliente=cliente["id_cliente"],
        id_sala=escenario["id_sala"],
        renglones=[{"cod_vino": vino["cod_vino"], "cantidad": 1}],
    )
    detalle = comprobantes.obtener_comprobante(pool, creado["nro_comprobante"])

    assert detalle["nro_comprobante"] == creado["nro_comprobante"]
    assert detalle["total"] == Decimal("90.00")
    assert len(detalle["renglones"]) == 1
    assert detalle["renglones"][0]["nombre_comercial"] == f"{VINO_NOMBRE} obtener"
    assert comprobantes.obtener_comprobante(pool, 999999999) is None


def test_app_rw_no_puede_actualizar_renglon_comprobante(pool, escenario):
    vino = _crear_vino(pool, escenario, "permiso")
    cliente = _nuevo_cliente(pool, escenario, "permiso")
    su = _superuser()
    try:
        _sembrar_stock(su, escenario["id_sala"], vino["cod_vino"], 4)
        su.commit()
    finally:
        su.close()

    creado = comprobantes.crear_comprobante(
        pool,
        id_cliente=cliente["id_cliente"],
        id_sala=escenario["id_sala"],
        renglones=[{"cod_vino": vino["cod_vino"], "cantidad": 1}],
    )

    with pytest.raises(psycopg.errors.InsufficientPrivilege) as raised:
        with get_connection(pool) as connection:
            connection.execute(
                "UPDATE renglon_comprobante SET cantidad = 1 WHERE nro_comprobante = %s",
                (creado["nro_comprobante"],),
            )

    assert raised.value.sqlstate == "42501"
