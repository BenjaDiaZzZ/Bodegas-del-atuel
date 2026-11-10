"""FastAPI application factory and entrypoint."""

import json
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response
from fastapi.exceptions import RequestValidationError
from psycopg import Error as PsycopgError
from psycopg_pool import ConnectionPool

from .config import Settings
from .db import create_pool
from .errors import DatabaseHttpError, ErrorBody, STATUS_BAD_REQUEST, map_db_error
from .routers.clientes import router as clientes_router
from .routers.comprobantes import router as comprobantes_router
from .routers.ingresos import router as ingresos_router
from .routers.reportes import router as reportes_router
from .routers.salud import router as salud_router
from .routers.transferencias import router as transferencias_router
from .routers.vinos import router as vinos_router


def _error_response(body: ErrorBody) -> Response:
    return Response(
        content=json.dumps(body.payload()),
        status_code=body.status,
        media_type="application/json",
    )


def _handle_mapped_db_error(request: Request, exc: PsycopgError | DatabaseHttpError) -> Response:
    if isinstance(exc, DatabaseHttpError):
        return _error_response(ErrorBody(status=exc.status, **exc.payload))
    return _error_response(map_db_error(exc))


VALIDATION_ERROR_CODE = "VALIDATION_ERROR"
VALIDATION_MESSAGE = "La solicitud es inválida."
_VALIDATION_DETAIL_LIMIT = 5


def _validation_detalle(exc: RequestValidationError) -> str:
    partes = [f"{'.'.join(str(ubicacion) for ubicacion in error['loc'])}: {error['msg']}" for error in exc.errors()]
    excedentes = partes[_VALIDATION_DETAIL_LIMIT:]
    return "; ".join(partes[:_VALIDATION_DETAIL_LIMIT]) + ("…" if excedentes else "")


def _handle_request_validation_error(request: Request, exc: RequestValidationError) -> Response:
    """Render framework validation failures as the contract 400 Error body.

    Location and Pydantic's generic message only: user input, ``ctx`` and
    stack details are never echoed.
    """
    return _error_response(
        ErrorBody(
            status=STATUS_BAD_REQUEST,
            codigo=VALIDATION_ERROR_CODE,
            mensaje=VALIDATION_MESSAGE,
            detalle=_validation_detalle(exc),
        )
    )


def create_app(settings: Settings | None = None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app_settings = settings or Settings.from_env()
        pool: ConnectionPool = create_pool(app_settings)
        app.state.pool = pool
        try:
            yield
        finally:
            pool.close()

    app = FastAPI(
        title="Bodegas del Atuel API",
        version="0.1.0",
        lifespan=lifespan,
    )
    app.include_router(salud_router)
    app.include_router(clientes_router)
    app.include_router(comprobantes_router)
    app.include_router(ingresos_router)
    app.include_router(reportes_router)
    app.include_router(transferencias_router)
    app.include_router(vinos_router)
    app.add_exception_handler(PsycopgError, _handle_mapped_db_error)
    app.add_exception_handler(DatabaseHttpError, _handle_mapped_db_error)
    app.add_exception_handler(RequestValidationError, _handle_request_validation_error)
    return app


app = create_app()
