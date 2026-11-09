"""Data access for the health endpoint."""

from psycopg_pool import ConnectionPool

from ..db import get_connection

_HEALTH_QUERY = "SELECT 1"


def fetch_database_version(pool: ConnectionPool) -> str:
    with get_connection(pool) as connection:
        connection.execute(_HEALTH_QUERY).fetchone()
        server_version = connection.info.parameter_status("server_version")

    if not server_version:
        raise RuntimeError("PostgreSQL no informó su versión")
    return f"PostgreSQL {server_version.split()[0]}"
