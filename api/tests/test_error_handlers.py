"""Regression tests for import safety and the app-level error rendering seam."""

import os
import subprocess
import sys
import types
from pathlib import Path

from fastapi.testclient import TestClient
from psycopg import errors as psycopg_errors

import app.main as main
from app.config import Settings
from app.errors import DatabaseHttpError


def _dummy_settings() -> Settings:
    return Settings(
        host="127.0.0.1",
        port=1,
        dbname="dummy-not-used",
        user="app_rw",
        password="not-used",
        sslmode="prefer",
    )


def forged(error_class, message=None, detail=None):
    """Build a real psycopg error instance with a controlled diag."""

    class Forged(error_class):
        diag = types.SimpleNamespace(message_primary=message, detail=detail)

    return Forged()


def test_app_main_imports_without_database_environment():
    api_dir = Path(__file__).resolve().parents[1]
    stripped_env = os.environ.copy()
    for name in (
        "POSTGRES_DB",
        "DB_PASSWORD",
        "DB_USER",
        "POSTGRES_HOST",
        "POSTGRES_PORT",
        "POSTGRES_SSLMODE",
    ):
        stripped_env.pop(name, None)

    result = subprocess.run(
        [sys.executable, "-c", "import app.main"],
        cwd=str(api_dir),
        env=stripped_env,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr


def test_p0001_raised_in_route_renders_contract_error_with_regla():
    app = main.create_app(_dummy_settings())

    @app.get("/_prueba/rn", include_in_schema=False)
    def ruta_regla():
        raise forged(psycopg_errors.RaiseException, "[RN-99] mensaje de prueba")

    with TestClient(app) as test_client:
        response = test_client.get("/_prueba/rn")

    assert response.status_code == 409
    body = response.json()
    assert body["codigo"] == "P0001"
    assert body["regla"] == "RN-99"
    assert "RN-99" in body["mensaje"]


def test_database_http_error_in_route_passes_through():
    app = main.create_app(_dummy_settings())
    payload = {
        "codigo": "P0002",
        "mensaje": "No existe el ingreso 1",
        "detalle": None,
        "regla": None,
    }

    @app.get("/_prueba/404", include_in_schema=False)
    def ruta_404():
        raise DatabaseHttpError(404, payload)

    with TestClient(app) as test_client:
        response = test_client.get("/_prueba/404")

    assert response.status_code == 404
    assert response.json() == payload
