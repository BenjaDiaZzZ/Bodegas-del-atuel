"""Health endpoint: reports API and database availability."""

from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from psycopg import Error as PsycopgError
from pydantic import BaseModel

from ..repos.salud import ServerVersionUnavailable, fetch_database_version

router = APIRouter(tags=["Salud"])


class SaludResponse(BaseModel):
    status: Literal["ok", "degraded"]
    db: bool
    version: str
    timestamp: datetime


class ErrorResponse(BaseModel):
    codigo: str
    mensaje: str


@router.get(
    "/salud",
    response_model=SaludResponse,
    responses={503: {"model": ErrorResponse}},
)
def get_salud(request: Request) -> SaludResponse | JSONResponse:
    try:
        version = fetch_database_version(request.app.state.pool)
    except (PsycopgError, ServerVersionUnavailable):
        return JSONResponse(
            status_code=503,
            content={
                "codigo": "DB_UNAVAILABLE",
                "mensaje": "Base de datos no disponible.",
            },
        )

    return SaludResponse(
        status="ok",
        db=True,
        version=version,
        timestamp=datetime.now(timezone.utc),
    )
