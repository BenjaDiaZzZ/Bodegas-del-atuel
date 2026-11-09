"""HTTP integration tests for the reportes operations (task 6.10).

The five /reportes operations are read-only: the router only converts
repository rows to the response schemas and every figure is computed by
PostgreSQL (comprobantes triggers, stock tables and the views
``vw_ventas_mensuales_sala`` / ``vw_ficha_vino``). The expected values
here are documented literals with an independent source of truth
(precios 100.00/50.00, socio = 10% de descuento, R-002), the same dataset
recipe than ``test_repos_reportes.py``: catalog via superuser PGSU/PGSUPW
and business rows via app_rw repos. Mirrors ``test_comprobantes_endpoints.py``.
"""

import os
import uuid
from datetime import date, timedelta
from decimal import Decimal

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row

import app.main as main
from app.config import Settings
from app.repos import clientes, comprobantes, ingresos, vinos

_TAIL = uuid.uuid4().hex[:10]
BODEGA_CUIT = f"97{(uuid.uuid4().int % 10**9):09d}"
LOCALIDAD = f"Localidad rep http {_TAIL}"
SALA_DIRECCION = f"Direccion rep http {_TAIL}"
SALA_VACIA_DIRECCION = f"Sala vacia rep http {_TAIL}"
TRANSP_ACTIVO = f"Transporte rep http {_TAIL}"
TRANSP_VIEJO = f"Transporte viejo http {_TAIL}"
TRANSP_ACTIVO_CUIT = f"20{(uuid.uuid4().int % 10**9):09d}"
TRANSP_VIEJO_CUIT = f"23{(uuid.uuid4().int % 10**9):09d}"
VINO_NOMBRE = f"Vino rep http {_TAIL}"
CLIENTE_NOMBRE = f"Cliente rep http {_TAIL}"

ERROR_KEYS = {"codigo", "mensaje", "detalle", "regla"}
VINO_DETALLE_KEYS = {
    "cod_vino",
    "nombre_comercial",
    "tipo",
    "anada",
    "presentacion_ml",
    "graduacion",
    "precio_venta",
    "cuit_bodega",
    "bodega",
    "composicion",
    "maridajes",
    "stock",
}

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
    pool_inst = main.create_pool(Settings.from_env())
    yield pool_inst
    pool_inst.close()


@pytest.fixture(scope="module")
def client(pool):
    """HTTP client with the module pool as safety net for seeding."""
    with TestClient(main.create_app()) as test_client:
        yield test_client


@pytest.fixture(scope="module")
def datos(pool):
    """Seeds the dataset once; expected figures are documented literals.

      ventas de A: 2 botellas x 100.00, socio -10%  -> 180.00
      ventas de B: 1 botella  x  50.00, socio -10%  ->  45.00
      top-vinos = [A: 2, B: 1]; ventas del mes = 3 botellas / 225.00.
      C tiene 7 en deposito y nada en la sala -> unica fila sin stock.
      activo: 2 ingresos de hoy; viejo: un ingreso hace 35 dias.
    """

    superuser = _superuser()
    try:
        superuser.execute(
            "INSERT INTO bodega (cuit, razon_social, domicilio) VALUES (%s, 'Bodega rep http', 'Domicilio rep http')"
            " ON CONFLICT (cuit) DO NOTHING",
            (BODEGA_CUIT,),
        )
        cepa = superuser.execute(
            "INSERT INTO cepa (nombre, tipo) VALUES (%s, 'tinta') RETURNING id_cepa",
            (f"Cepa rep http {_TAIL}",),
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
        sala_vacia = superuser.execute(
            "INSERT INTO sala (direccion, dia_cierre_semanal, id_localidad)"
            " VALUES (%s, 4, %s) RETURNING id_sala",
            (SALA_VACIA_DIRECCION, localidad),
        ).fetchone()[0]
        activo = superuser.execute(
            "INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)"
            " VALUES (%s, %s, 'activo.rep.http@mail.test', '5600000000', 'Domicilio rep')"
            " RETURNING id_transportista",
            (TRANSP_ACTIVO, TRANSP_ACTIVO_CUIT),
        ).fetchone()[0]
        viejo = superuser.execute(
            "INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)"
            " VALUES (%s, %s, 'viejo.rep.http@mail.test', '5600000001', 'Domicilio rep')"
            " RETURNING id_transportista",
            (TRANSP_VIEJO, TRANSP_VIEJO_CUIT),
        ).fetchone()[0]
        superuser.commit()
        referencia = {
            "cepa": cepa,
            "id_localidad": localidad,
            "id_sala": sala,
            "id_sala_vacia": sala_vacia,
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
        nombre=f"{CLIENTE_NOMBRE} venta",
        tipo="socio",
        tipo_documento="DNI",
        nro_documento=f"{(uuid.uuid4().int % 10**8):08d}",
        direccion="Calle rep http",
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
    _sembrar_ingresos(pool, referencia)

    referencia.update(
        {
            "vino_a": vino_a,
            "vino_b": vino_b,
            "vino_c": vino_c,
            "cliente": cliente,
        }
    )
    yield referencia

    _borrar_ingresos()
    superuser = _superuser()
    try:
        superuser.execute(
            "DELETE FROM comprobante WHERE id_sala IN (%s, %s)",
            (referencia["id_sala"], referencia["id_sala_vacia"]),
        )
        superuser.execute(
            "DELETE FROM stock_sala WHERE id_sala IN (%s, %s)",
            (referencia["id_sala"], referencia["id_sala_vacia"]),
        )
        superuser.execute(
            "DELETE FROM stock_deposito WHERE cod_vino IN"
            " (SELECT cod_vino FROM vino WHERE cuit_bodega = %s)",
            (BODEGA_CUIT,),
        )
        superuser.execute(
            "DELETE FROM vino WHERE cuit_bodega = %s", (BODEGA_CUIT,)
        )
        superuser.execute(
            "DELETE FROM cliente WHERE nombre LIKE %s", (f"{CLIENTE_NOMBRE}%",)
        )
        superuser.execute(
            "DELETE FROM transportista WHERE id_transportista IN (%s, %s)",
            (referencia["id_activo"], referencia["id_viejo"]),
        )
        superuser.execute(
            "DELETE FROM sala WHERE id_sala IN (%s, %s)",
            (referencia["id_sala"], referencia["id_sala_vacia"]),
        )
        superuser.execute(
            "DELETE FROM localidad WHERE nombre = %s", (LOCALIDAD,)
        )
        superuser.execute(
            "DELETE FROM cepa WHERE nombre LIKE %s", (f"Cepa rep http {_TAIL}%",)
        )
        superuser.execute("DELETE FROM bodega WHERE cuit = %s", (BODEGA_CUIT,))
        superuser.commit()
    finally:
        superuser.close()


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


def _sembrar_ingresos(pool, referencia):
    """The same dataset than the 200 test: activo 2, viejo 1 (hace 35 dias)."""
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


def _borrar_ingresos():
    superuser = _superuser()
    try:
        superuser.execute(
            "DELETE FROM ingreso WHERE cuit_bodega = %s", (BODEGA_CUIT,)
        )
        superuser.commit()
    finally:
        superuser.close()


# ---------------------------------------------------------------------------
# S1 · GET /reportes/top-vinos
# ---------------------------------------------------------------------------


def test_top_vinos_200_ranking_ordenado_y_limite(client, datos):
    response = client.get("/reportes/top-vinos")

    assert response.status_code == 200, response.text
    body = response.json()
    assert body == [
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

    solo_primero = client.get("/reportes/top-vinos", params={"limite": 1})
    assert solo_primero.status_code == 200, solo_primero.text
    assert solo_primero.json() == [body[0]]


def test_top_vinos_limite_fuera_rango_400_validation_error(client):
    cero = client.get("/reportes/top-vinos", params={"limite": 0})
    grande = client.get("/reportes/top-vinos", params={"limite": 101})

    for response in (cero, grande):
        assert response.status_code == 400, response.text
        body = response.json()
        assert set(body) == ERROR_KEYS
        assert body["codigo"] == "VALIDATION_ERROR"
        assert body["detalle"]


# ---------------------------------------------------------------------------
# S8 · GET /reportes/ventas-por-sala
# ---------------------------------------------------------------------------


def test_ventas_por_sala_200_fila_de_la_vista_y_filtro_desde_hasta(client, datos):
    response = client.get(
        "/reportes/ventas-por-sala",
        params={"desde": MES_ACTUAL.isoformat(), "hasta": HOY.isoformat()},
    )

    assert response.status_code == 200, response.text
    assert response.json() == [
        {
            "id_sala": datos["id_sala"],
            "localidad": LOCALIDAD,
            "mes": MES_ACTUAL.isoformat(),
            "botellas_vendidas": 3,
            "monto_total": 225.0,
        }
    ]

    # The month bucket sits before the limits: bound filters, empty report.
    vacio = client.get("/reportes/ventas-por-sala", params={"desde": HOY.isoformat()})
    assert vacio.status_code == 200, vacio.text
    assert vacio.json() == []


def test_ventas_por_sala_fecha_invalida_400_validation_error(client):
    response = client.get("/reportes/ventas-por-sala", params={"desde": "ayer"})

    assert response.status_code == 400, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "VALIDATION_ERROR"
    assert body["detalle"]


# ---------------------------------------------------------------------------
# S6 · GET /reportes/vinos-sin-stock
# ---------------------------------------------------------------------------


def test_vinos_sin_stock_200_sala_con_sin_fila_de_stock(client, datos):
    response = client.get(
        "/reportes/vinos-sin-stock", params={"id_sala": datos["id_sala"]}
    )

    assert response.status_code == 200, response.text
    assert response.json() == [
        {
            "cod_vino": datos["vino_c"]["cod_vino"],
            "nombre_comercial": f"{VINO_NOMBRE} sin stock",
            "stock_sala": 0,
            "stock_deposito": 7,
        }
    ]

    # The room stock does not exist: a missing row counts as 0 (COALESCE).
    otra_sala = client.get(
        "/reportes/vinos-sin-stock", params={"id_sala": datos["id_sala_vacia"]}
    )
    assert otra_sala.status_code == 200, otra_sala.text
    assert otra_sala.json() == [
        {
            "cod_vino": datos["vino_c"]["cod_vino"],
            "nombre_comercial": f"{VINO_NOMBRE} sin stock",
            "stock_sala": 0,
            "stock_deposito": 7,
        }
    ]


def test_vinos_sin_stock_id_sala_requerida_400_validation_error(client):
    response = client.get("/reportes/vinos-sin-stock")

    assert response.status_code == 400, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "VALIDATION_ERROR"
    assert body["detalle"]


# ---------------------------------------------------------------------------
# S7 · GET /reportes/transportista-activo
# ---------------------------------------------------------------------------


def test_transportista_activo_200_mas_ingresos_del_ultimo_mes(client, datos):
    response = client.get("/reportes/transportista-activo")

    assert response.status_code == 200, response.text
    assert response.json() == {
        "id_transportista": datos["id_activo"],
        "razon_social": TRANSP_ACTIVO,
        "ingresos_trasladados": 2,
    }


def test_transportista_activo_404_sin_actividad_en_el_ultimo_mes(client, pool, datos):
    _borrar_ingresos()

    try:
        response = client.get("/reportes/transportista-activo")
        assert response.status_code == 404, response.text
        body = response.json()
        assert set(body) == ERROR_KEYS
        assert body["codigo"] == "NOT_FOUND"
        assert body["detalle"] is None
        assert body["regla"] is None
    finally:
        _sembrar_ingresos(pool, datos)


# ---------------------------------------------------------------------------
# S9 · GET /reportes/trazabilidad/{cod}
# ---------------------------------------------------------------------------


def test_trazabilidad_200_ficha_igual_a_vinos_detalle(client, datos):
    cod = datos["vino_a"]["cod_vino"]
    ficha_vinos = client.get(f"/vinos/{cod}")

    response = client.get(f"/reportes/trazabilidad/{cod}")

    assert response.status_code == 200, response.text
    assert response.json() == ficha_vinos.json()
    body = response.json()
    assert set(body) == VINO_DETALLE_KEYS
    assert body["nombre_comercial"] == f"{VINO_NOMBRE} top a"
    assert body["precio_venta"] == 100.0
    assert body["composicion"] == [
        {
            "id_cepa": datos["cepa"],
            "nombre": f"Cepa rep http {_TAIL}",
            "porcentaje": 100.0,
        }
    ]
    assert body["stock"] == {"deposito": 0, "salas": 8, "total": 8}


def test_trazabilidad_vino_inexistente_404_error_contrato(client):
    response = client.get("/reportes/trazabilidad/999999999")

    assert response.status_code == 404, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "NOT_FOUND"
    assert "999999999" in body["mensaje"]
    assert body["detalle"] is None
    assert body["regla"] is None
