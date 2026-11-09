"""Route coverage for the OpenAPI contract: every documented operation must respond."""

import pytest
from fastapi.testclient import TestClient

import app.main as main


@pytest.fixture
def client():
    with TestClient(main.create_app()) as test_client:
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

VINO_DETALLE_KEYS = set(_PDF)
CLIENTE_RESUMEN_KEYS = {
    "id_cliente",
    "nombre",
    "tipo",
    "tipo_documento",
    "nro_documento",
    "id_localidad",
    "fecha_alta",
    "descuento",
}
CLIENTE_DETALLE_KEYS = CLIENTE_RESUMEN_KEYS
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

VINO_CREATE_BODY = {
    "nombre_comercial": "Malbec Reserva",
    "tipo": "tinto",
    "anada": 2021,
    "presentacion_ml": 750,
    "graduacion": 14.0,
    "precio_venta": 12500.0,
    "cuit_bodega": "30712345678",
    "composicion": [
        {"id_cepa": 1, "porcentaje": 85.0},
        {"id_cepa": 2, "porcentaje": 15.0},
    ],
    "maridajes": [1],
}

CLIENTE_CREATE_BODY = {
    "nombre": "Juan Pérez",
    "tipo": "socio",
    "tipo_documento": "DNI",
    "nro_documento": "30123456",
    "direccion": "Av. San Martín 123",
    "id_localidad": 1,
}

COMPROBANTE_CREATE_BODY = {
    "id_cliente": 1,
    "id_sala": 1,
    "renglones": [{"cod_vino": 1, "cantidad": 3}],
}

TRANSFERENCIA_CREATE_BODY = {"id_sala": 1}

INGRESO_CREATE_BODY = {"id_transportista": 1, "cuit_bodega": "30712345678"}

REGLON_CREATE_BODY = {"cod_vino": 1, "cantidad": 120}

# (method, path, body, expected_status, expected_keys)
# expected_keys=None means no response body (204).
ROUTES = [
    ("GET", "/salud", None, 200, SALUD_KEYS),
    ("GET", "/vinos", None, 200, PAGE_KEYS),
    ("POST", "/vinos", VINO_CREATE_BODY, 201, VINO_DETALLE_KEYS),
    ("GET", "/vinos/1", None, 200, VINO_DETALLE_KEYS),
    ("PUT", "/vinos/1", VINO_CREATE_BODY, 200, VINO_DETALLE_KEYS),
    ("DELETE", "/vinos/1", None, 204, None),
    ("GET", "/clientes", None, 200, PAGE_KEYS),
    ("POST", "/clientes", CLIENTE_CREATE_BODY, 201, CLIENTE_DETALLE_KEYS),
    ("GET", "/clientes/1", None, 200, CLIENTE_DETALLE_KEYS),
    ("PUT", "/clientes/1", CLIENTE_CREATE_BODY, 200, CLIENTE_DETALLE_KEYS),
    ("DELETE", "/clientes/1", None, 204, None),
    ("POST", "/comprobantes", COMPROBANTE_CREATE_BODY, 201, COMPROBANTE_KEYS),
    ("GET", "/comprobantes/1001", None, 200, COMPROBANTE_KEYS),
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
