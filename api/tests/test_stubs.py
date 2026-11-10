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

# (method, path, body, expected_status, expected_keys)
# expected_keys=None means no response body (204).
ROUTES = [
    ("GET", "/salud", None, 200, SALUD_KEYS),
    # /salud is the only row left: every other documented operation became
    # real. GET /vinos and GET /vinos/{cod} (6.5) moved to
    # test_vinos_endpoints.py; POST/PUT/DELETE /vinos (6.6) too; the 5
    # /clientes operations (6.7) to test_clientes_endpoints.py; the 2
    # /comprobantes operations (6.8) to test_comprobantes_endpoints.py; the
    # 8 document operations (4 /transferencias + 4 /ingresos, 6.9) to
    # test_documentos_endpoints.py; and the 5 read-only /reportes
    # operations (6.10) to test_reportes_endpoints.py. Remove rows here as
    # each endpoint becomes real — none remains to retire (6.11+).
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
