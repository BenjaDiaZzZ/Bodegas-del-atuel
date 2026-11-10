"""PostgreSQL connection pool built from application settings."""

from contextlib import contextmanager
from typing import Iterator

from psycopg import Connection
from psycopg.conninfo import make_conninfo
from psycopg import Error as PsycopgError
from psycopg_pool import ConnectionPool

from .config import Settings
from .errors import DatabaseHttpError, map_db_error

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
        sslmode=settings.sslmode,
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


@contextmanager
def transaction(pool: ConnectionPool) -> Iterator[Connection]:
    """Run one explicit BEGIN ... COMMIT and roll back on any failure.

    COMMIT runs inside the ``try``: a deferred constraint trigger (for
    example ``tg_composicion_cien`` / RN-05) surfaces its P0001 at COMMIT,
    so the commit itself must go through the central mapper. Any
    ``PsycopgError`` raised inside the block - including by the COMMIT -
    triggers a ROLLBACK and is converted once by ``app.errors.map_db_error``
    into a :class:`DatabaseHttpError`.
    """

    with get_connection(pool) as connection:
        try:
            connection.execute("BEGIN")
            yield connection
            connection.execute("COMMIT")
        except PsycopgError as exc:
            _safe_rollback(connection)
            raise DatabaseHttpError.from_body(map_db_error(exc)) from exc
        except Exception:
            _safe_rollback(connection)
            raise


def _safe_rollback(connection: Connection) -> None:
    try:
        connection.execute("ROLLBACK")
    except PsycopgError:
        pass
