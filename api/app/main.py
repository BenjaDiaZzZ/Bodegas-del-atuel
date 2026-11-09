"""FastAPI application factory and entrypoint."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from psycopg_pool import ConnectionPool

from .config import Settings
from .db import create_pool
from .routers.salud import router as salud_router


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
    return app


app = create_app()
