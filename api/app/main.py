"""FastAPI application factory and entrypoint."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from psycopg_pool import ConnectionPool

from .config import Settings
from .db import create_pool
from .routers.clientes import router as clientes_router
from .routers.comprobantes import router as comprobantes_router
from .routers.ingresos import router as ingresos_router
from .routers.reportes import router as reportes_router
from .routers.salud import router as salud_router
from .routers.transferencias import router as transferencias_router
from .routers.vinos import router as vinos_router


def create_app(settings: Settings | None = None) -> FastAPI:
    app_settings = settings or Settings.from_env()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
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
    return app


app = create_app()
