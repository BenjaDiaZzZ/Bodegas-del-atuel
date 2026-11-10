"""Integration tests for the reportes repository (app_rw) against PostgreSQL.

Seeds a tiny known dataset (2 vinos con ventas, 1 transportista activo,
1 transportista con un ingreso viejo) and asserts the canonical S1/S6/
S7/S8 semantics plus the view- and binding-based behavior of the
repository. Catalog/stock rows that app_rw cannot write are created
with a superuser connection.
"""

import os
import uuid
from datetime import date, timedelta
from decimal import Decimal

import psycopg
import pytest
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row

from app.config import Settings
from app.db import create_pool, get_connection
from app.repos import clientes, comprobantes, ingresos, reportes, vinos

_TAIL = uuid.uuid4().hex[:10]
BODEGA_CUIT = f"95{(uuid.uuid4().int % 10**9):09d}"
LOCALIDAD = f"Localidad rep {_TAIL}"
SALA_DIRECCION = f"Direccion rep {_TAIL}"
TRANSP_ACTIVO = f"Transporte rep {_TAIL}"
TRANSP_VIEJO = f"Transporte viejo {_TAIL}"
TRANSP_ACTIVO_CUIT = f"20{(uuid.uuid4().int % 10**9):09d}"
TRANSP_VIEJO_CUIT = f"23{(uuid.uuid4().int % 10**9):09d}"
VINO_NOMBRE = f"Vino rep {_TAIL}"

# Independent source of truth: precios 100.00/50.00, socio = 10% (R-002).
HOY = date.today()
MES_ACTUAL = HOY.replace(day=1)
PRECIO_A = Decimal("100.00")
PRECIO_B = Decimal("50.00")


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
def datos(pool):
    """Seeds the dataset once: catalog via superuser, business rows via repos.

    Expected figures (documented literals, not recomputed):
      ventas de A: 2 botellas x 100.00, socio -10%  -> subtotal 180.00
      ventas de B: 1 botella  x  50.00, socio -10%  -> subtotal  45.00
      S1 ranking = [A: 2 botellas, B: 1]; S8 = 3 botellas / 225.00.
      S6: C tiene 7 en deposito y nada en la sala; A y B, stock en la sala.
      S7: activo con 2 ingresos de hoy; el otro, un ingreso hace 35 dias.
    """

    superuser = _superuser()
    try:
        superuser.execute(
            "INSERT INTO bodega (cuit, razon_social, domicilio) VALUES (%s, 'Bodega rep', 'Domicilio rep')"
            " ON CONFLICT (cuit) DO NOTHING",
            (BODEGA_CUIT,),
        )
        cepa = superuser.execute(
            "INSERT INTO cepa (nombre, tipo) VALUES (%s, 'tinta') RETURNING id_cepa",
            (f"Cepa rep {_TAIL}",),
        ).fetchone()[0]
        localidad = superuser.execute(
            "INSERT INTO localidad (nombre, codigo_postal, provincia)"
            " VALUES (%s, '5620', 'Mendoza') RETURNING id_localidad",
            (LOCALIDAD,),
        ).fetchone()[0]
        sala = superuser.execute(
            "INSERT INTO sala (direccion, dia_cierre_semanal, id_localidad)"
            " VALUES (%s, 4, %s) RETURNING id_sala",
            (SALA_DIRECCION, localidad),
        ).fetchone()[0]
        activo = superuser.execute(
            "INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)"
            " VALUES (%s, %s, 'activo.rep@mail.test', '5600000000', 'Domicilio rep')"
            " RETURNING id_transportista",
            (TRANSP_ACTIVO, TRANSP_ACTIVO_CUIT),
        ).fetchone()[0]
        viejo = superuser.execute(
            "INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)"
            " VALUES (%s, %s, 'viejo.rep@mail.test', '5600000001', 'Domicilio rep')"
            " RETURNING id_transportista",
            (TRANSP_VIEJO, TRANSP_VIEJO_CUIT),
        ).fetchone()[0]
        superuser.commit()
        referencia = {
            "cepa": cepa,
            "id_localidad": localidad,
            "id_sala": sala,
            "id_activo": activo,
            "id_viejo": viejo,
        }
    finally:
        superuser.close()

    vino_a = _crear_vino(pool, referencia, "top a", PRECIO_A)
    vino_b = _crear_vino(pool, referencia, "top b", PRECIO_B)
    vino_c = _crear_vino(pool, referencia, "sin stock", Decimal("70.00"))
    cliente = clientes.crear_cliente(
        pool,
        nombre=f"Cliente rep {_TAIL}",
        tipo="socio",
        tipo_documento="DNI",
        nro_documento=f"{(uuid.uuid4().int % 10**8):08d}",
        direccion="Calle rep",
        id_localidad=referencia["id_localidad"],
    )

    superuser = _superuser()
    try:
        _sembrar_stock(superuser, referencia["id_sala"], vino_a["cod_vino"], 10)
        _sembrar_stock(superuser, referencia["id_sala"], vino_b["cod_vino"], 1)
        superuser.execute(
            "INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (%s, 7)",
            (vino_c["cod_vino"],),
        )
        superuser.commit()
    finally:
        superuser.close()

    comprobantes.crear_comprobante(
        pool,
        id_cliente=cliente["id_cliente"],
        id_sala=referencia["id_sala"],
        fecha=HOY,
        renglones=[{"cod_vino": vino_a["cod_vino"], "cantidad": 2}],
    )
    comprobantes.crear_comprobante(
        pool,
        id_cliente=cliente["id_cliente"],
        id_sala=referencia["id_sala"],
        fecha=HOY,
        renglones=[{"cod_vino": vino_b["cod_vino"], "cantidad": 1}],
    )
    ingresos.crear_ingreso(
        pool,
        id_transportista=referencia["id_activo"],
        cuit_bodega=BODEGA_CUIT,
        fecha=HOY,
    )
    ingresos.crear_ingreso(
        pool,
        id_transportista=referencia["id_activo"],
        cuit_bodega=BODEGA_CUIT,
        fecha=HOY,
    )
    ingresos.crear_ingreso(
        pool,
        id_transportista=referencia["id_viejo"],
        cuit_bodega=BODEGA_CUIT,
        fecha=HOY - timedelta(days=35),
    )

    referencia.update(
        {
            "vino_a": vino_a,
            "vino_b": vino_b,
            "vino_c": vino_c,
            "cliente": cliente,
        }
    )
    yield referencia

    teardown = _superuser()
    try:
        teardown.execute(
            "DELETE FROM comprobante WHERE id_sala = %s", (referencia["id_sala"],))
        teardown.execute(
            "DELETE FROM ingreso WHERE cuit_bodega = %s", (BODEGA_CUIT,))
        teardown.execute(
            "DELETE FROM stock_sala WHERE id_sala = %s", (referencia["id_sala"],))
        teardown.execute(
            "DELETE FROM stock_deposito WHERE cod_vino IN"
            " (SELECT cod_vino FROM vino WHERE cuit_bodega = %s)",
            (BODEGA_CUIT,),
        )
        teardown.execute(
            "DELETE FROM vino WHERE cuit_bodega = %s", (BODEGA_CUIT,))
        teardown.execute(
            "DELETE FROM cliente WHERE nombre LIKE %s", (f"Cliente rep {_TAIL}%",))
        teardown.execute(
            "DELETE FROM transportista WHERE id_transportista IN (%s, %s)",
            (referencia["id_activo"], referencia["id_viejo"]),
        )
        teardown.execute(
            "DELETE FROM sala WHERE id_sala = %s", (referencia["id_sala"],))
        teardown.execute(
            "DELETE FROM localidad WHERE nombre = %s", (LOCALIDAD,))
        teardown.execute(
            "DELETE FROM cepa WHERE nombre LIKE %s", (f"Cepa rep {_TAIL}%",))
        teardown.execute("DELETE FROM bodega WHERE cuit = %s", (BODEGA_CUIT,))
        teardown.commit()
    finally:
        teardown.close()


def _crear_vino(pool, referencia, sufijo, precio):
    return vinos.crear_vino(
        pool,
        nombre_comercial=f"{VINO_NOMBRE} {sufijo}",
        tipo="tinto",
        anada=2021,
        presentacion_ml=750,
        graduacion=Decimal("13.50"),
        precio_venta=precio,
        cuit_bodega=BODEGA_CUIT,
        composicion=[{"id_cepa": referencia["cepa"], "porcentaje": Decimal("100.00")}],
    )


def _sembrar_stock(su, id_sala, cod_vino, cantidad):
    su.execute(
        "INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (%s, %s, %s)"
        " ON CONFLICT (id_sala, cod_vino) DO UPDATE SET cantidad = EXCLUDED.cantidad",
        (id_sala, cod_vino, cantidad),
    )


def test_top_vinos_orden_y_limite(pool, datos):
    ranking = reportes.top_vinos(pool)

    assert ranking == [
        {
            "cod_vino": datos["vino_a"]["cod_vino"],
            "nombre_comercial": f"{VINO_NOMBRE} top a",
            "botellas_vendidas": 2,
        },
        {
            "cod_vino": datos["vino_b"]["cod_vino"],
            "nombre_comercial": f"{VINO_NOMBRE} top b",
            "botellas_vendidas": 1,
        },
    ]
    solo_primero = reportes.top_vinos(pool, limite=1)
    assert solo_primero == [ranking[0]]


def test_ventas_por_sala_desde_vista_y_filtro(pool, datos):
    filas = reportes.ventas_por_sala(pool)

    assert filas == [
        {
            "id_sala": datos["id_sala"],
            "localidad": LOCALIDAD,
            "mes": MES_ACTUAL,
            "botellas_vendidas": 3,
            "monto_total": Decimal("225.00"),
        }
    ]

    # Filtros vinculados sobre el bucket mensual: fuera de rango, vacio.
    assert reportes.ventas_por_sala(pool, desde=HOY) == []
    assert reportes.ventas_por_sala(pool, hasta=MES_ACTUAL - timedelta(days=1)) == []

    completa = reportes.ventas_por_sala(pool, desde=MES_ACTUAL, hasta=HOY)
    assert completa == filas


def test_vinos_sin_stock(pool, datos):
    resultado = reportes.vinos_sin_stock(pool, datos["id_sala"])

    # Solo C: 7 en deposito, sin fila de stock en la sala; A y B excluidos.
    assert resultado == [
        {
            "cod_vino": datos["vino_c"]["cod_vino"],
            "nombre_comercial": f"{VINO_NOMBRE} sin stock",
            "stock_sala": 0,
            "stock_deposito": 7,
        }
    ]


def test_transportista_activo(pool, datos):
    activo = reportes.transportista_activo(pool)

    assert activo == {
        "id_transportista": datos["id_activo"],
        "razon_social": TRANSP_ACTIVO,
        "ingresos_trasladados": 2,
    }


def test_trazabilidad_vino(pool, datos):
    ficha = reportes.trazabilidad_vino(pool, datos["vino_a"]["cod_vino"])

    assert ficha == vinos.obtener_vino(pool, datos["vino_a"]["cod_vino"])
    assert ficha["stock"]["salas"] == 8
    assert reportes.trazabilidad_vino(pool, 999999999) is None


def test_filtro_malicioso_no_inyecta(pool, datos):
    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        antes = connection.execute("SELECT COUNT(*) AS n FROM vino").fetchone()["n"]

    # El valor queda como parametro vinculado: el servidor solo rechaza el
    # cast a date (22007) y el texto nunca entra a la consulta.
    with pytest.raises(psycopg.DatabaseError) as raised:
        reportes.ventas_por_sala(pool, desde="'; DROP TABLE vino; --")

    assert raised.value.sqlstate == "22007"

    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        despues = connection.execute("SELECT COUNT(*) AS n FROM vino").fetchone()["n"]

    assert despues == antes
