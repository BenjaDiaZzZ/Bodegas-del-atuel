"""PostgreSQL connection pool built from application settings."""

from contextlib import contextmanager
from typing import Iterator

from psycopg import Connection
from psycopg.conninfo import make_conninfo
from psycopg_pool import ConnectionPool

from .config import Settings

DEFAULT_POOL_TIMEOUT_SECONDS = 3.0
MIN_POOL_SIZE = 1
MAX_POOL_SIZE = 5


def build_conninfo(settings: Settings) -> str:
    return make_conninfo(
        host=settings.host,
        port=settings.port,
        dbname=settings.dbname,
        user=settings.user,
        password=settings.password,
    )


def create_pool(
    settings: Settings,
    timeout: float = DEFAULT_POOL_TIMEOUT_SECONDS,
) -> ConnectionPool:
    return ConnectionPool(
        conninfo=build_conninfo(settings),
        min_size=MIN_POOL_SIZE,
        max_size=MAX_POOL_SIZE,
        timeout=timeout,
        open=True,
    )


@contextmanager
def get_connection(pool: ConnectionPool) -> Iterator[Connection]:
    with pool.connection() as connection:
        yield connection
