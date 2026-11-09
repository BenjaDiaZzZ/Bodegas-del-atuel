"""Route coverage for the OpenAPI contract: every documented operation must respond."""

import pytest
from fastapi.testclient import TestClient

import app.main as main
from app.config import Settings


@pytest.fixture
def client(monkeypatch):
    from app.routers import salud as router_salud

    def version_registrada(pool):
        return "PostgreSQL 0.0-stub"

    monkeypatch.setattr(router_salud, "fetch_database_version", version_registrada)
    settings = Settings(
        host="127.0.0.1",
        port=1,
        dbname="stub_tests",
        user="app_rw",
        password="stub-not-used",
    )
    with TestClient(main.create_app(settings)) as test_client:
        yield test_client


SALUD_KEYS = {"status", "db", "version", "timestamp"}

PAGE_KEYS = {"data", "meta"}

_PDF = (
    "cod_vino",
    "nombre_comercial",
    "tipo",
    "anada",
    "presentacion_ml",
    "graduacion",
    "precio_venta",
    "cuit_bodega",
)

VINO_RESUMEN_KEYS = set(_PDF)
VINO_DETALLE_KEYS = VINO_RESUMEN_KEYS | {"composicion", "maridajes", "stock"}
TRANSFERENCIA_KEYS = {"nro_solicitud", "id_sala", "fecha_confeccion", "estado"}
INGRESO_KEYS = {"cod_ingreso", "fecha", "estado", "id_transportista", "cuit_bodega"}
TOP_VINO_KEYS = {"cod_vino", "nombre_comercial", "botellas_vendidas"}
VENTA_MENSUAL_KEYS = {
    "id_sala",
    "localidad",
    "mes",
    "botellas_vendidas",
    "monto_total",
}
VINO_SIN_STOCK_KEYS = {
    "cod_vino",
    "nombre_comercial",
    "stock_sala",
    "stock_deposito",
}
TRANSPORTISTA_KEYS = {"id_transportista", "razon_social", "ingresos_trasladados"}

TRANSFERENCIA_CREATE_BODY = {"id_sala": 1}

INGRESO_CREATE_BODY = {"id_transportista": 1, "cuit_bodega": "30712345678"}

REGLON_CREATE_BODY = {"cod_vino": 1, "cantidad": 120}

# (method, path, body, expected_status, expected_keys)
# expected_keys=None means no response body (204).
ROUTES = [
    ("GET", "/salud", None, 200, SALUD_KEYS),
    # GET /vinos, GET /vinos/{cod} (6.5) and POST/PUT/DELETE /vinos (6.6) are
    # real: their behavior is covered by test_vinos_endpoints.py against a
    # real database, so they no longer belong to the fixed-payload stub
    # matrix. The 5 /clientes operations (6.7) moved to
    # test_clientes_endpoints.py and the 2 /comprobantes operations (6.8) to
    # test_comprobantes_endpoints.py for the same reason. Remove rows here as
    # each endpoint becomes real (6.9-6.10).
    ("POST", "/transferencias", TRANSFERENCIA_CREATE_BODY, 201, TRANSFERENCIA_KEYS),
    (
        "POST",
        "/transferencias/5001/renglones",
        REGLON_CREATE_BODY,
        201,
        TRANSFERENCIA_KEYS,
    ),
    ("POST", "/transferencias/5001/terminar", None, 200, TRANSFERENCIA_KEYS),
    ("POST", "/transferencias/5001/procesar", None, 200, TRANSFERENCIA_KEYS),
    ("POST", "/ingresos", INGRESO_CREATE_BODY, 201, INGRESO_KEYS),
    ("POST", "/ingresos/3001/renglones", REGLON_CREATE_BODY, 201, INGRESO_KEYS),
    ("POST", "/ingresos/3001/terminar", None, 200, INGRESO_KEYS),
    ("POST", "/ingresos/3001/procesar", None, 200, INGRESO_KEYS),
    ("GET", "/reportes/top-vinos", None, 200, TOP_VINO_KEYS),
    ("GET", "/reportes/ventas-por-sala", None, 200, VENTA_MENSUAL_KEYS),
    ("GET", "/reportes/vinos-sin-stock?id_sala=1", None, 200, VINO_SIN_STOCK_KEYS),
    ("GET", "/reportes/transportista-activo", None, 200, TRANSPORTISTA_KEYS),
    ("GET", "/reportes/trazabilidad/1", None, 200, VINO_DETALLE_KEYS),
]


def _required_keys_present(body, expected_keys):
    if "data" in expected_keys:
        assert "meta" in body
        assert len(body["data"]) >= 1
        assert expected_keys - PAGE_KEYS <= set(body["data"][0])
        return
    assert expected_keys <= set(body)


def _assert_body(response, expected_keys):
    if expected_keys is None:
        assert response.content == b""
        return
    body = response.json()
    if isinstance(body, list):
        assert len(body) >= 1
        assert expected_keys <= set(body[0])
        return
    _required_keys_present(body, expected_keys)


@pytest.mark.parametrize(
    "method,path,body,expected_status,expected_keys",
    ROUTES,
    ids=[f"{m} {p}" for m, p, _, _, _ in ROUTES],
)
def test_every_documented_route_has_a_stub(client, method, path, body, expected_status, expected_keys):
    response = client.request(method, path, json=body)

    assert response.status_code == expected_status, response.text
    _assert_body(response, expected_keys)
