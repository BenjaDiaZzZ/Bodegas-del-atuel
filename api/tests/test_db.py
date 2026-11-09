import pytest

from app.config import Settings
from app.db import create_pool, get_connection
from app.repos.salud import fetch_database_version


def test_config_defaults_to_app_rw_user(monkeypatch):
    monkeypatch.delenv("DB_USER", raising=False)
    monkeypatch.delenv("POSTGRES_HOST", raising=False)
    monkeypatch.delenv("POSTGRES_PORT", raising=False)
    monkeypatch.setenv("POSTGRES_DB", "bodegas_del_atuel")
    monkeypatch.setenv("DB_PASSWORD", "not-a-real-password")

    settings = Settings.from_env()

    assert settings.user == "app_rw"
    assert settings.host == "localhost"
    assert settings.port == 5432


def test_config_requires_database_name(monkeypatch):
    monkeypatch.delenv("POSTGRES_DB", raising=False)
    monkeypatch.setenv("DB_PASSWORD", "not-a-real-password")

    with pytest.raises(RuntimeError, match="POSTGRES_DB"):
        Settings.from_env()


def test_config_rejects_non_numeric_postgres_port(monkeypatch):
    monkeypatch.setenv("POSTGRES_DB", "bodegas_del_atuel")
    monkeypatch.setenv("DB_PASSWORD", "not-a-real-password")
    monkeypatch.setenv("POSTGRES_PORT", "abc")

    with pytest.raises(RuntimeError, match="POSTGRES_PORT"):
        Settings.from_env()


def test_connection_helper_executes_select_1():
    pool = create_pool(Settings.from_env())
    try:
        with get_connection(pool) as connection:
            assert connection.execute("SELECT 1").fetchone() == (1,)
    finally:
        pool.close()


def test_repo_reports_postgres_version():
    pool = create_pool(Settings.from_env())
    try:
        version = fetch_database_version(pool)
    finally:
        pool.close()

    assert version.startswith("PostgreSQL ")
