"""Integration tests for the transferencias and ingresos repositories (app_rw).

Catalog rows and stock that app_rw cannot write (bodega, cepa,
localidad, sala, transportista, stock_deposito, stock_sala) are created
with a superuser connection; every document operation goes through the
repository functions only.
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
from app.repos import ingresos, transferencias, vinos

_TAIL = uuid.uuid4().hex[:10]
BODEGA_CUIT = f"94{(uuid.uuid4().int % 10**9):09d}"
LOCALIDAD = f"Localidad doc {_TAIL}"
SALA_DIRECCION = f"Direccion doc {_TAIL}"
TRANSP_CUIT = f"20{(uuid.uuid4().int % 10**9):09d}"
VINO_NOMBRE = f"Vino doc {_TAIL}"


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
    """Base catalog (bodega, cepas, localidad, sala, transportista) via superuser."""
    superuser = _superuser()
    try:
        superuser.execute(
            "INSERT INTO bodega (cuit, razon_social, domicilio) VALUES (%s, 'Bodega doc', 'Domicilio doc')"
            " ON CONFLICT (cuit) DO NOTHING",
            (BODEGA_CUIT,),
        )
        cepas = [
            superuser.execute(
                "INSERT INTO cepa (nombre, tipo) VALUES (%s, 'tinta') RETURNING id_cepa",
                (f"Cepa doc {_TAIL} {n}",),
            ).fetchone()[0]
            for n in (1, 2)
        ]
        localidad = superuser.execute(
            "INSERT INTO localidad (nombre, codigo_postal, provincia)"
            " VALUES (%s, '5610', 'Mendoza') RETURNING id_localidad",
            (LOCALIDAD,),
        ).fetchone()[0]
        sala = superuser.execute(
            "INSERT INTO sala (direccion, dia_cierre_semanal, id_localidad)"
            " VALUES (%s, 3, %s) RETURNING id_sala",
            (SALA_DIRECCION, localidad),
        ).fetchone()[0]
        transportista = superuser.execute(
            "INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)"
            " VALUES ('Transporte doc', %s, 'transporte.doc@mail.test', '5600000000', 'Domicilio transporte')"
            " RETURNING id_transportista",
            (TRANSP_CUIT,),
        ).fetchone()[0]
        superuser.commit()
        yield {
            "cepas": cepas,
            "id_localidad": localidad,
            "id_sala": sala,
            "id_transportista": transportista,
        }
    finally:
        try:
            superuser.execute(
                "DELETE FROM ingreso WHERE cuit_bodega = %s", (BODEGA_CUIT,))
            superuser.execute(
                "DELETE FROM transferencia WHERE id_sala = %s", (sala,))
            superuser.execute(
                "DELETE FROM stock_sala WHERE id_sala = %s", (sala,))
            superuser.execute(
                "DELETE FROM stock_deposito WHERE cod_vino IN"
                " (SELECT cod_vino FROM vino WHERE cuit_bodega = %s)",
                (BODEGA_CUIT,),
            )
            superuser.execute(
                "DELETE FROM vino WHERE cuit_bodega = %s", (BODEGA_CUIT,))
            superuser.execute(
                "DELETE FROM transportista WHERE id_transportista = %s",
                (transportista,),
            )
            superuser.execute("DELETE FROM sala WHERE id_sala = %s", (sala,))
            superuser.execute("DELETE FROM localidad WHERE nombre = %s", (LOCALIDAD,))
            superuser.execute(
                "DELETE FROM cepa WHERE nombre LIKE %s", (f"Cepa doc {_TAIL}%",))
            superuser.execute("DELETE FROM bodega WHERE cuit = %s", (BODEGA_CUIT,))
            superuser.commit()
        finally:
            superuser.close()


def _crear_vino(pool, escenario, sufijo, precio=Decimal("100.00")):
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


def _sembrar_deposito(su, cod_vino, cantidad):
    su.execute(
        "INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (%s, %s)"
        " ON CONFLICT (cod_vino) DO UPDATE SET cantidad = EXCLUDED.cantidad",
        (cod_vino, cantidad),
    )


def _stock_deposito_de(pool, cod_vino):
    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        fila = connection.execute(
            "SELECT cantidad FROM stock_deposito WHERE cod_vino = %s", (cod_vino,)
        ).fetchone()
    return fila["cantidad"] if fila else None


def _stock_sala_de(pool, id_sala, cod_vino):
    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        fila = connection.execute(
            "SELECT cantidad FROM stock_sala WHERE id_sala = %s AND cod_vino = %s",
            (id_sala, cod_vino),
        ).fetchone()
    return fila["cantidad"] if fila else None


def test_transferencia_flujo_completo(pool, escenario):
    vino_a = _crear_vino(pool, escenario, "tr flujo")
    su = _superuser()
    try:
        _sembrar_deposito(su, vino_a["cod_vino"], 10)
        su.commit()
    finally:
        su.close()

    cabecera = transferencias.crear_transferencia(pool, id_sala=escenario["id_sala"])
    assert cabecera["nro_solicitud"] > 0
    assert cabecera["id_sala"] == escenario["id_sala"]
    assert cabecera["estado"] == "en_confeccion"
    assert cabecera["fecha_confeccion"] == date.today()
    assert cabecera["renglones"] == []

    con_renglon = transferencias.agregar_renglon_transferencia(
        pool, cabecera["nro_solicitud"], cod_vino=vino_a["cod_vino"], cantidad=3
    )
    assert con_renglon["renglones"] == [
        {
            "cod_vino": vino_a["cod_vino"],
            "nombre_comercial": f"{VINO_NOMBRE} tr flujo",
            "cantidad": 3,
        }
    ]

    terminado = transferencias.terminar_transferencia(pool, cabecera["nro_solicitud"])
    assert terminado["estado"] == "terminado"

    procesado = transferencias.procesar_transferencia(pool, cabecera["nro_solicitud"])
    assert procesado["estado"] == "procesado"

    # sp_procesar_transferencia muevo el stock: deposito -3, sala +3.
    assert _stock_deposito_de(pool, vino_a["cod_vino"]) == 7
    assert _stock_sala_de(pool, escenario["id_sala"], vino_a["cod_vino"]) == 3


def test_transferencia_procesar_sin_terminar_409(pool, escenario):
    vino = _crear_vino(pool, escenario, "tr sin terminar")
    su = _superuser()
    try:
        _sembrar_deposito(su, vino["cod_vino"], 5)
        su.commit()
    finally:
        su.close()

    cabecera = transferencias.crear_transferencia(pool, id_sala=escenario["id_sala"])
    transferencias.agregar_renglon_transferencia(
        pool, cabecera["nro_solicitud"], cod_vino=vino["cod_vino"], cantidad=1
    )

    with pytest.raises(DatabaseHttpError) as raised:
        transferencias.procesar_transferencia(pool, cabecera["nro_solicitud"])

    assert raised.value.status == 409
    assert raised.value.payload["regla"] == "RN-11"
    assert raised.value.payload["codigo"] == "P0001"
    assert _stock_deposito_de(pool, vino["cod_vino"]) == 5
    assert _stock_sala_de(pool, escenario["id_sala"], vino["cod_vino"]) is None


def test_transferencia_repetir_o_retroceder(pool, escenario):
    vino = _crear_vino(pool, escenario, "tr repetir")
    su = _superuser()
    try:
        _sembrar_deposito(su, vino["cod_vino"], 5)
        su.commit()
    finally:
        su.close()

    # Terminar dos veces seguidas es un no-op del trigger T4 (sin cambio de
    # estado no hay transicion que validar): la base conserva 'terminado'.
    cabecera = transferencias.crear_transferencia(pool, id_sala=escenario["id_sala"])
    transferencias.agregar_renglon_transferencia(
        pool, cabecera["nro_solicitud"], cod_vino=vino["cod_vino"], cantidad=1
    )
    transferencias.terminar_transferencia(pool, cabecera["nro_solicitud"])
    repetida = transferencias.terminar_transferencia(pool, cabecera["nro_solicitud"])
    assert repetida["estado"] == "terminado"
    transferencias.procesar_transferencia(pool, cabecera["nro_solicitud"])

    # Retroceder de procesado a terminado SI es una transicion invalida.
    with pytest.raises(DatabaseHttpError) as raised:
        transferencias.terminar_transferencia(pool, cabecera["nro_solicitud"])

    assert raised.value.status == 409
    assert raised.value.payload["regla"] == "RN-11"


def test_transferencia_agregar_renglon_tras_terminar_409(pool, escenario):
    vino1 = _crear_vino(pool, escenario, "tr bloqueo 1")
    vino2 = _crear_vino(pool, escenario, "tr bloqueo 2")
    su = _superuser()
    try:
        _sembrar_deposito(su, vino1["cod_vino"], 5)
        su.commit()
    finally:
        su.close()

    cabecera = transferencias.crear_transferencia(pool, id_sala=escenario["id_sala"])
    transferencias.agregar_renglon_transferencia(
        pool, cabecera["nro_solicitud"], cod_vino=vino1["cod_vino"], cantidad=1
    )
    transferencias.terminar_transferencia(pool, cabecera["nro_solicitud"])

    with pytest.raises(DatabaseHttpError) as raised:
        transferencias.agregar_renglon_transferencia(
            pool, cabecera["nro_solicitud"], cod_vino=vino2["cod_vino"], cantidad=1
        )

    assert raised.value.status == 409
    assert raised.value.payload["regla"] == "RN-12"


def test_transferencias_inexistentes(pool, escenario):
    assert transferencias.agregar_renglon_transferencia(
        pool, 999999999, cod_vino=1, cantidad=1
    ) is None
    assert transferencias.terminar_transferencia(pool, 999999999) is None

    with pytest.raises(DatabaseHttpError) as raised:
        transferencias.procesar_transferencia(pool, 999999999)

    error = raised.value
    assert error.status == 404
    assert error.payload["codigo"] == "P0002"


def test_ingreso_flujo_completo(pool, escenario):
    vino_a = _crear_vino(pool, escenario, "ing flujo a")
    vino_b = _crear_vino(pool, escenario, "ing flujo b")

    cabecera = ingresos.crear_ingreso(
        pool,
        id_transportista=escenario["id_transportista"],
        cuit_bodega=BODEGA_CUIT,
    )
    assert cabecera["cod_ingreso"] > 0
    assert cabecera["id_transportista"] == escenario["id_transportista"]
    assert cabecera["cuit_bodega"] == BODEGA_CUIT
    assert cabecera["estado"] == "en_confeccion"
    assert cabecera["fecha"] == date.today()
    assert cabecera["renglones"] == []

    con_renglones = ingresos.agregar_renglon_ingreso(
        pool,
        cabecera["cod_ingreso"],
        cod_vino=vino_a["cod_vino"],
        cantidad=3,
    )
    con_renglones = ingresos.agregar_renglon_ingreso(
        pool,
        cabecera["cod_ingreso"],
        cod_vino=vino_b["cod_vino"],
        cantidad=120,
    )
    assert [
        (r["cod_vino"], r["cantidad"], r["nombre_comercial"]) for r in con_renglones["renglones"]
    ] == [
        (vino_a["cod_vino"], 3, f"{VINO_NOMBRE} ing flujo a"),
        (vino_b["cod_vino"], 120, f"{VINO_NOMBRE} ing flujo b"),
    ]

    terminado = ingresos.terminar_ingreso(pool, cabecera["cod_ingreso"])
    assert terminado["estado"] == "terminado"

    procesado = ingresos.procesar_ingreso(pool, cabecera["cod_ingreso"])
    assert procesado["estado"] == "procesado"

    # sp_procesar_ingreso upserta el deposito: crea la fila del vino nuevo.
    assert _stock_deposito_de(pool, vino_a["cod_vino"]) == 3
    assert _stock_deposito_de(pool, vino_b["cod_vino"]) == 120


def test_ingreso_procesar_y_retrocesos_409(pool, escenario):
    vino = _crear_vino(pool, escenario, "ing reglas")

    cabecera = ingresos.crear_ingreso(
        pool,
        id_transportista=escenario["id_transportista"],
        cuit_bodega=BODEGA_CUIT,
    )
    ingresos.agregar_renglon_ingreso(
        pool, cabecera["cod_ingreso"], cod_vino=vino["cod_vino"], cantidad=1
    )

    # Procesar sin terminar: invalido (P0001 [RN-10]).
    with pytest.raises(DatabaseHttpError) as raised:
        ingresos.procesar_ingreso(pool, cabecera["cod_ingreso"])
    assert raised.value.status == 409
    assert raised.value.payload["regla"] == "RN-10"

    ingresos.terminar_ingreso(pool, cabecera["cod_ingreso"])
    ingresos.procesar_ingreso(pool, cabecera["cod_ingreso"])

    # Retroceder de procesado a terminado: invalido.
    with pytest.raises(DatabaseHttpError) as raised:
        ingresos.terminar_ingreso(pool, cabecera["cod_ingreso"])
    assert raised.value.status == 409
    assert raised.value.payload["regla"] == "RN-10"


def test_ingreso_agregar_renglon_tras_terminar_409(pool, escenario):
    vino1 = _crear_vino(pool, escenario, "ing bloqueo 1")
    vino2 = _crear_vino(pool, escenario, "ing bloqueo 2")

    cabecera = ingresos.crear_ingreso(
        pool,
        id_transportista=escenario["id_transportista"],
        cuit_bodega=BODEGA_CUIT,
    )
    ingresos.agregar_renglon_ingreso(
        pool, cabecera["cod_ingreso"], cod_vino=vino1["cod_vino"], cantidad=1
    )
    ingresos.terminar_ingreso(pool, cabecera["cod_ingreso"])

    with pytest.raises(DatabaseHttpError) as raised:
        ingresos.agregar_renglon_ingreso(
            pool, cabecera["cod_ingreso"], cod_vino=vino2["cod_vino"], cantidad=1
        )

    assert raised.value.status == 409
    assert raised.value.payload["regla"] == "RN-12"


def test_ingresos_inexistentes(pool, escenario):
    assert ingresos.agregar_renglon_ingreso(
        pool, 999999999, cod_vino=1, cantidad=1
    ) is None
    assert ingresos.terminar_ingreso(pool, 999999999) is None

    with pytest.raises(DatabaseHttpError) as raised:
        ingresos.procesar_ingreso(pool, 999999999)

    error = raised.value
    assert error.status == 404
    assert error.payload["codigo"] == "P0002"
