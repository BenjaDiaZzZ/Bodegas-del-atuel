import pytest
from psycopg.conninfo import conninfo_to_dict

from app.config import Settings
from app.db import build_conninfo, create_pool, get_connection
from app.repos.salud import fetch_database_version


def test_config_defaults_to_app_rw_user(monkeypatch):
    monkeypatch.delenv("DB_USER", raising=False)
    monkeypatch.delenv("POSTGRES_HOST", raising=False)
    monkeypatch.delenv("POSTGRES_PORT", raising=False)
    monkeypatch.delenv("POSTGRES_SSLMODE", raising=False)
    monkeypatch.setenv("POSTGRES_DB", "bodegas_del_atuel")
    monkeypatch.setenv("DB_PASSWORD", "not-a-real-password")

    settings = Settings.from_env()

    assert settings.user == "app_rw"
    assert settings.host == "localhost"
    assert settings.port == 5432
    assert settings.sslmode == "prefer"


def test_config_defaults_sslmode_to_prefer(monkeypatch):
    monkeypatch.delenv("POSTGRES_SSLMODE", raising=False)
    monkeypatch.setenv("POSTGRES_DB", "bodegas_del_atuel")
    monkeypatch.setenv("DB_PASSWORD", "not-a-real-password")

    assert Settings.from_env().sslmode == "prefer"


def test_config_respects_postgres_sslmode_require(monkeypatch):
    monkeypatch.setenv("POSTGRES_SSLMODE", "require")
    monkeypatch.setenv("POSTGRES_DB", "bodegas_del_atuel")
    monkeypatch.setenv("DB_PASSWORD", "not-a-real-password")

    assert Settings.from_env().sslmode == "require"


def test_config_rejects_invalid_sslmode(monkeypatch):
    monkeypatch.setenv("POSTGRES_SSLMODE", "maybe")
    monkeypatch.setenv("POSTGRES_DB", "bodegas_del_atuel")
    monkeypatch.setenv("DB_PASSWORD", "not-a-real-password")

    with pytest.raises(RuntimeError, match="POSTGRES_SSLMODE"):
        Settings.from_env()


def test_build_conninfo_includes_configured_sslmode(monkeypatch):
    monkeypatch.setenv("POSTGRES_SSLMODE", "require")
    monkeypatch.setenv("POSTGRES_DB", "bodegas_del_atuel")
    monkeypatch.setenv("DB_PASSWORD", "not-a-real-password")
    monkeypatch.delenv("DB_USER", raising=False)

    conninfo = build_conninfo(Settings.from_env())
    parsed = conninfo_to_dict(conninfo)

    assert parsed["sslmode"] == "require"
    assert parsed["user"] == "app_rw"


def test_build_conninfo_default_sslmode_is_prefer(monkeypatch):
    monkeypatch.delenv("POSTGRES_SSLMODE", raising=False)
    monkeypatch.setenv("POSTGRES_DB", "bodegas_del_atuel")
    monkeypatch.setenv("DB_PASSWORD", "not-a-real-password")

    conninfo = build_conninfo(Settings.from_env())
    parsed = conninfo_to_dict(conninfo)

    assert parsed["sslmode"] == "prefer"


def test_config_errors_do_not_leak_password(monkeypatch):
    sentinel = "super-secreta-no-filtrar"
    monkeypatch.setenv("DB_PASSWORD", sentinel)
    monkeypatch.delenv("POSTGRES_DB", raising=False)
    monkeypatch.delenv("POSTGRES_SSLMODE", raising=False)

    with pytest.raises(RuntimeError) as excinfo:
        Settings.from_env()
    assert sentinel not in str(excinfo.value)

    monkeypatch.setenv("POSTGRES_DB", "bodegas_del_atuel")
    monkeypatch.setenv("POSTGRES_PORT", "abc")
    with pytest.raises(RuntimeError) as excinfo:
        Settings.from_env()
    assert sentinel not in str(excinfo.value)

    monkeypatch.delenv("POSTGRES_PORT", raising=False)
    monkeypatch.setenv("POSTGRES_SSLMODE", "maybe")
    with pytest.raises(RuntimeError) as excinfo:
        Settings.from_env()
    assert sentinel not in str(excinfo.value)


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
