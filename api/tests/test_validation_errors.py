"""Request-validation errors must render the contract 400 BadRequest body.

The OpenAPI contract reserves 422 UnprocessableEntity for database-level
semantic violations (CHECK 23514 / NOT NULL 23502) and documents 400 with
the Error schema for invalid request parameters (query/path/body and
pagination out of range).

These tests use a dummy ``Settings`` (like ``test_stubs.py``): validation
rejects the request before any handler or pool connection runs, so no
live database is needed.
"""

import pytest
from fastapi.testclient import TestClient

import app.main as main
from app.config import Settings

ERROR_KEYS = {"codigo", "mensaje", "detalle", "regla"}
VALIDATION_MESSAGE = "La solicitud es inválida."


@pytest.fixture
def client():
    settings = Settings(
        host="127.0.0.1",
        port=1,
        dbname="stub_tests",
        user="app_rw",
        password="stub-not-used",
        sslmode="prefer",
    )
    with TestClient(main.create_app(settings)) as test_client:
        yield test_client


def _assert_contract_error(client) -> dict:
    response = client
    body = response.json()

    assert response.status_code == 400
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "VALIDATION_ERROR"
    assert body["mensaje"] == VALIDATION_MESSAGE
    assert body["regla"] is None
    assert "detail" not in body
    assert "detail" not in response.text
    return body


def test_invalid_query_param_returns_400_error_body(client):
    body = _assert_contract_error(client.get("/vinos", params={"cuit_bodega": "abc"}))

    assert "query.cuit_bodega" in body["detalle"]


def test_invalid_path_param_returns_400_error_body(client):
    body = _assert_contract_error(client.get("/vinos/abc"))

    assert "path.cod_vino" in body["detalle"] or body["detalle"].startswith("path.cod:")


def test_invalid_body_returns_400_error_body(client):
    body = _assert_contract_error(client.post("/vinos", json={}))

    assert any(item.startswith("body.") for item in body["detalle"].split("; "))


def test_validation_error_truncates_long_detalle(client):
    body = _assert_contract_error(client.post("/vinos", json={}))

    items = body["detalle"].split("; ")
    assert len(items) <= 5
    assert body["detalle"].endswith("…")


def test_validation_error_never_echoes_input(client):
    marked = "SECRETO_VALOR_123"

    response = client.get("/vinos", params={"cuit_bodega": marked})

    _assert_contract_error(response)
    assert marked not in response.text


def test_pagination_out_of_range_returns_400_error_body(client):
    body = _assert_contract_error(client.get("/vinos", params={"page": 0, "per_page": 999}))

    assert "query.page" in body["detalle"] or "query.per_page" in body["detalle"]


def test_validation_error_shape_is_uniform(client):
    responses = [
        client.get("/vinos", params={"cuit_bodega": "abc"}),
        client.get("/vinos/abc"),
        client.post("/vinos", json={}),
    ]

    for response in responses:
        body = _assert_contract_error(response)
        assert (body["codigo"], body["mensaje"]) == ("VALIDATION_ERROR", VALIDATION_MESSAGE)
