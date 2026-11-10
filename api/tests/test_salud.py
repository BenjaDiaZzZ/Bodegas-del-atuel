from datetime import datetime

import pytest
from fastapi.testclient import TestClient

import app.main as main
from app.config import Settings
from app.db import create_pool
from app.repos.salud import ServerVersionUnavailable


@pytest.fixture
def client():
    with TestClient(main.create_app()) as test_client:
        yield test_client


def test_salud_returns_documented_shape(client):
    response = client.get("/salud")

    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"status", "db", "version", "timestamp"}
    assert body["status"] == "ok"
    assert body["db"] is True
    assert body["version"].startswith("PostgreSQL ")
    datetime.fromisoformat(body["timestamp"].replace("Z", "+00:00"))


def test_salud_returns_503_when_database_is_unreachable(monkeypatch):
    def unreachable_pool(settings):
        return create_pool(settings, timeout=0.5)

    monkeypatch.setattr(main, "create_pool", unreachable_pool)
    settings = Settings(
        host="127.0.0.1",
        port=1,
        dbname="bodegas_del_atuel",
        user="app_rw",
        password="not-a-real-password",
    )

    with TestClient(main.create_app(settings)) as test_client:
        response = test_client.get("/salud")

    assert response.status_code == 503
    body = response.json()
    assert {"codigo", "mensaje"} <= set(body)
    assert "password" not in response.text.lower()


def test_salud_returns_503_when_version_is_not_reported(monkeypatch, client):
    from app.routers import salud as router_salud

    def sin_version(pool):
        raise ServerVersionUnavailable("PostgreSQL no informó su versión")

    monkeypatch.setattr(router_salud, "fetch_database_version", sin_version)

    response = client.get("/salud")

    assert response.status_code == 503
    body = response.json()
    assert body["codigo"] == "DB_UNAVAILABLE"
    assert "informó" not in body["mensaje"]
    assert body["mensaje"] == "Base de datos no disponible."


def test_salud_reports_internal_defect_as_500_not_503(monkeypatch):
    from app.routers import salud as router_salud

    def defecto_interno(pool):
        raise RuntimeError("bug interno")

    monkeypatch.setattr(router_salud, "fetch_database_version", defecto_interno)
    settings = Settings(
        host="127.0.0.1",
        port=1,
        dbname="defecto-not-used",
        user="app_rw",
        password="not-used",
    )

    with TestClient(main.create_app(settings), raise_server_exceptions=False) as test_client:
        response = test_client.get("/salud")

    assert response.status_code == 500
    assert "DB_UNAVAILABLE" not in response.text
    assert "Base de datos no disponible." not in response.text
