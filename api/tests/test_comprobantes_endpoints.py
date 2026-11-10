"""HTTP integration tests for the comprobantes operations (task 6.8).

The pool connects as ``app_rw``; the HTTP layer exercises the routers and the
repository functions own every write. The API never computes amounts: every
expected value here comes from an independent source of truth (precio 100.00
with the documented socio discount of 10%, R-002) and asserts the arithmetic
the database triggers performed (RN-08/RN-09). Catalog tables app_rw cannot
write (bodega, cepa, localidad, sala, stock_sala) are seeded with a
superuser connection. Mirrors ``test_clientes_endpoints.py``.
"""

import os
import uuid
from decimal import Decimal

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row

import app.main as main
from app.config import Settings
from app.db import get_connection
from app.repos import clientes, vinos

_TAIL = uuid.uuid4().hex[:10]
BODEGA_CUIT = f"96{(uuid.uuid4().int % 10**9):09d}"
LOCALIDAD = f"Localidad comp http {_TAIL}"
CLIENTE_NOMBRE = f"Cliente comp http {_TAIL}"
VINO_NOMBRE = f"Vino comp http {_TAIL}"

COMPROBANTE_KEYS = {
    "nro_comprobante",
    "fecha",
    "id_cliente",
    "id_sala",
    "subtotal",
    "descuento",
    "total",
    "renglones",
}
RENGLON_KEYS = {
    "cod_vino",
    "nombre_comercial",
    "cantidad",
    "precio_unitario",
    "descuento",
    "subtotal",
}
ERROR_KEYS = {"codigo", "mensaje", "detalle", "regla"}

# Independent source of truth: precio 100.00, socio discount 10% (R-002).
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
    pool_inst = main.create_pool(Settings.from_env())
    yield pool_inst
    pool_inst.close()


@pytest.fixture(scope="module")
def client(pool):
    """HTTP client with the module pool as safety net for seeding."""
    with TestClient(main.create_app()) as test_client:
        yield test_client


@pytest.fixture(scope="module")
def escenario():
    """Base catalog (bodega, cepas, localidad, sala) via superuser."""
    superuser = _superuser()
    try:
        superuser.execute(
            "INSERT INTO bodega (cuit, razon_social, domicilio) VALUES (%s, 'Bodega comp http', 'Domicilio comp http')"
            " ON CONFLICT (cuit) DO NOTHING",
            (BODEGA_CUIT,),
        )
        cepas = [
            superuser.execute(
                "INSERT INTO cepa (nombre, tipo) VALUES (%s, 'tinta') RETURNING id_cepa",
                (f"Cepa comp http {_TAIL} {n}",),
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
            (f"Sala comp http {_TAIL}", localidad),
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
                "DELETE FROM cepa WHERE nombre LIKE %s", (f"Cepa comp http {_TAIL}%",))
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
        direccion="Calle comp http",
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


def _comprobantes_de(pool, id_cliente):
    """Count the comprobantes persisted for one client (atomicity pin)."""
    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        return connection.execute(
            "SELECT COUNT(*) AS n FROM comprobante WHERE id_cliente = %s",
            (id_cliente,),
        ).fetchone()["n"]


# ---------------------------------------------------------------------------
# Escritura · POST /comprobantes
# ---------------------------------------------------------------------------


def _fecha_db(pool):
    """CURRENT_DATE de PostgreSQL (UTC): la expectativa no depende del reloj ni la TZ del runner.

    Fija ``dict_row`` en la conexión: el row_factory puede persistir en
    conexiones reusadas del pool y esta consulta no debe depender de él.
    """
    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        return connection.execute("SELECT CURRENT_DATE AS fecha").fetchone()["fecha"]


def test_crear_comprobante_201_renglones_ordenados_y_totales_de_la_base(client, pool, escenario):
    # CREATED FIRST -> smaller cod_vino; sent in REVERSE order on purpose.
    vino_menor = _crear_vino(pool, escenario, "ordenado menor")
    vino_mayor = _crear_vino(pool, escenario, "ordenado mayor")
    cliente = _nuevo_cliente(pool, escenario, "venta")
    su = _superuser()
    try:
        _sembrar_stock(su, escenario["id_sala"], vino_menor["cod_vino"], 5)
        _sembrar_stock(su, escenario["id_sala"], vino_mayor["cod_vino"], 3)
        su.commit()
    finally:
        su.close()

    response = client.post(
        "/comprobantes",
        json={
            "id_cliente": cliente["id_cliente"],
            "id_sala": escenario["id_sala"],
            "renglones": [
                {"cod_vino": vino_mayor["cod_vino"], "cantidad": 2},
                {"cod_vino": vino_menor["cod_vino"], "cantidad": 3},
            ],
        },
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert set(body) == COMPROBANTE_KEYS
    assert body["nro_comprobante"] > 0
    assert body["fecha"] == _fecha_db(pool).isoformat()
    assert body["id_cliente"] == cliente["id_cliente"]
    assert body["id_sala"] == escenario["id_sala"]

    # The response presents the renglones stored sorted by cod_vino ASC,
    # not the order the request sent them.
    renglones = body["renglones"]
    assert [set(r) for r in renglones] == [RENGLON_KEYS, RENGLON_KEYS]
    assert [r["cod_vino"] for r in renglones] == [
        vino_menor["cod_vino"],
        vino_mayor["cod_vino"],
    ]
    # RN-08: precio vigente, descuento 10% socio, subtotal con descuento —
    # all computed by the DB triggers, never by the API.
    assert renglones[0]["nombre_comercial"] == f"{VINO_NOMBRE} ordenado menor"
    assert renglones[0]["cantidad"] == 3
    assert renglones[0]["precio_unitario"] == 100.0
    assert renglones[0]["descuento"] == 30.0
    assert renglones[0]["subtotal"] == 270.0
    assert renglones[1]["nombre_comercial"] == f"{VINO_NOMBRE} ordenado mayor"
    assert renglones[1]["cantidad"] == 2
    assert renglones[1]["precio_unitario"] == 100.0
    assert renglones[1]["descuento"] == 20.0
    assert renglones[1]["subtotal"] == 180.0

    # Cabecera totals computed by T2 (fn_total_comprobante): subtotal is the
    # gross SUM(precio*cantidad), total is SUM(subtotal after discount).
    assert body["subtotal"] == 500.0
    assert body["descuento"] == 50.0
    assert body["total"] == 450.0

    # T2 deducted stock_sala: the database did the work.
    assert _stock_de(pool, escenario["id_sala"], vino_menor["cod_vino"]) == 2
    assert _stock_de(pool, escenario["id_sala"], vino_mayor["cod_vino"]) == 1


def test_obtener_comprobante_200_roundtrip(client, pool, escenario):
    vino = _crear_vino(pool, escenario, "roundtrip")
    cliente = _nuevo_cliente(pool, escenario, "roundtrip")
    su = _superuser()
    try:
        _sembrar_stock(su, escenario["id_sala"], vino["cod_vino"], 4)
        su.commit()
    finally:
        su.close()

    creado = client.post(
        "/comprobantes",
        json={
            "id_cliente": cliente["id_cliente"],
            "id_sala": escenario["id_sala"],
            "renglones": [{"cod_vino": vino["cod_vino"], "cantidad": 2}],
        },
    ).json()

    detalle = client.get(f"/comprobantes/{creado['nro_comprobante']}")

    assert detalle.status_code == 200, detalle.text
    body = detalle.json()
    assert set(body) == COMPROBANTE_KEYS
    assert body["nro_comprobante"] == creado["nro_comprobante"]
    assert body["fecha"] == creado["fecha"]
    assert body["id_cliente"] == cliente["id_cliente"]
    assert body["id_sala"] == escenario["id_sala"]
    # 2 x 100.00, 10% socio: descuento 20.00, subtotal 180.00.
    assert body["subtotal"] == 200.0
    assert body["descuento"] == 20.0
    assert body["total"] == 180.0
    assert body["renglones"] == [
        {
            "cod_vino": vino["cod_vino"],
            "nombre_comercial": f"{VINO_NOMBRE} roundtrip",
            "cantidad": 2,
            "precio_unitario": 100.0,
            "descuento": 20.0,
            "subtotal": 180.0,
        }
    ]


def test_obtener_comprobante_inexistente_404_error_contrato(client):
    response = client.get("/comprobantes/999999999")

    assert response.status_code == 404, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "NOT_FOUND"
    assert "999999999" in body["mensaje"]
    assert body["regla"] is None


def test_crear_comprobante_stock_insuficiente_409_rn09_y_atomico(client, pool, escenario):
    vino = _crear_vino(pool, escenario, "rn09")
    cliente = _nuevo_cliente(pool, escenario, "rn09")
    su = _superuser()
    try:
        _sembrar_stock(su, escenario["id_sala"], vino["cod_vino"], 1)
        su.commit()
    finally:
        su.close()

    response = client.post(
        "/comprobantes",
        json={
            "id_cliente": cliente["id_cliente"],
            "id_sala": escenario["id_sala"],
            "renglones": [{"cod_vino": vino["cod_vino"], "cantidad": 5}],
        },
    )

    assert response.status_code == 409, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "P0001"
    assert body["regla"] == "RN-09"
    # Atomicity: the ROLLBACK left nothing persisted and stock untouched.
    assert _comprobantes_de(pool, cliente["id_cliente"]) == 0
    assert _stock_de(pool, escenario["id_sala"], vino["cod_vino"]) == 1


def test_crear_comprobante_renglon_duplicado_409_y_atomico(client, pool, escenario):
    vino = _crear_vino(pool, escenario, "duplicado")
    cliente = _nuevo_cliente(pool, escenario, "duplicado")
    su = _superuser()
    try:
        _sembrar_stock(su, escenario["id_sala"], vino["cod_vino"], 10)
        su.commit()
    finally:
        su.close()

    response = client.post(
        "/comprobantes",
        json={
            "id_cliente": cliente["id_cliente"],
            "id_sala": escenario["id_sala"],
            "renglones": [
                {"cod_vino": vino["cod_vino"], "cantidad": 1},
                {"cod_vino": vino["cod_vino"], "cantidad": 2},
            ],
        },
    )

    assert response.status_code == 409, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "23505"
    assert _comprobantes_de(pool, cliente["id_cliente"]) == 0


def test_crear_comprobante_cliente_inexistente_422(client, pool, escenario):
    vino = _crear_vino(pool, escenario, "fk-vino")
    cliente = _nuevo_cliente(pool, escenario, "fk-cliente")

    response = client.post(
        "/comprobantes",
        json={
            "id_cliente": 999999999,
            "id_sala": escenario["id_sala"],
            "renglones": [{"cod_vino": vino["cod_vino"], "cantidad": 1}],
        },
    )

    assert response.status_code == 422, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "23503"
    # Nothing was left behind.
    assert _comprobantes_de(pool, cliente["id_cliente"]) == 0


def test_crear_comprobante_vino_inexistente_409_rn09_a_nivel_base(client, pool, escenario):
    """A missing vino surfaces as RN-09, not as a 422 FK error.

    T1 (005) raises ``[RN-09]`` when the vino has no stock in the sala
    BEFORE the renglon_comprobante FK to vino can surface (23503), so the
    centralized handler renders 409 with ``regla: RN-09``. The API changes
    nothing: this is what the database decides.
    """
    cliente = _nuevo_cliente(pool, escenario, "fk-vino-409")

    response = client.post(
        "/comprobantes",
        json={
            "id_cliente": cliente["id_cliente"],
            "id_sala": escenario["id_sala"],
            "renglones": [{"cod_vino": 999999999, "cantidad": 1}],
        },
    )

    assert response.status_code == 409, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "P0001"
    assert body["regla"] == "RN-09"
    assert _comprobantes_de(pool, cliente["id_cliente"]) == 0


def test_crear_comprobante_cuerpo_invalido_400_validation_error(client):
    faltante = client.post(
        "/comprobantes",
        json={"id_cliente": 1, "renglones": [{"cod_vino": 1, "cantidad": 1}]},
    )
    sin_renglones = client.post(
        "/comprobantes",
        json={"id_cliente": 1, "id_sala": 1},
    )
    lista_vacia = client.post(
        "/comprobantes",
        json={"id_cliente": 1, "id_sala": 1, "renglones": []},
    )
    cantidad_cero = client.post(
        "/comprobantes",
        json={"id_cliente": 1, "id_sala": 1, "renglones": [{"cod_vino": 1, "cantidad": 0}]},
    )

    for response in (faltante, sin_renglones, lista_vacia, cantidad_cero):
        assert response.status_code == 400, response.text
        body = response.json()
        assert set(body) == ERROR_KEYS
        assert body["codigo"] == "VALIDATION_ERROR"
        assert body["detalle"]
