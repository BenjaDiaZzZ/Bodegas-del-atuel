"""Endpoints of the reportes operations (Bodegas del Atuel API)."""

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query, Request

from ..errors import DatabaseHttpError
from ..repos import reportes as repo_reportes
from ..schemas import (
    TopVino,
    TransportistaActivo,
    VentaMensualSala,
    VinoDetalle,
    VinoSinStock,
)

router = APIRouter(tags=["Reportes"])


def _fecha_iso(valor):
    """Native DB ``date`` -> ISO string expected by the response schemas."""
    return valor.isoformat() if isinstance(valor, date) else valor


def _mes(fila: dict) -> VentaMensualSala:
    """Shape one repository row of ``vw_ventas_mensuales_sala``."""
    return VentaMensualSala.model_validate({**fila, "mes": _fecha_iso(fila["mes"])})


@router.get(
    "/reportes/top-vinos",
    operation_id="reporteTopVinos",
    response_model=list[TopVino],
)
def reporte_top_vinos(
    request: Request,
    limite: Annotated[int, Query(ge=1, le=100)] = 10,
) -> list[TopVino]:
    """Return the most sold wines (S1), ranked by SUM(cantidad) DESC."""
    filas = repo_reportes.top_vinos(request.app.state.pool, limite=limite)
    return [TopVino.model_validate(fila) for fila in filas]


@router.get(
    "/reportes/ventas-por-sala",
    operation_id="reporteVentasPorSala",
    response_model=list[VentaMensualSala],
)
def reporte_ventas_por_sala(
    request: Request,
    desde: date | None = None,
    hasta: date | None = None,
) -> list[VentaMensualSala]:
    """Return the monthly sales per sala (S8) from the team's view."""
    filas = repo_reportes.ventas_por_sala(
        request.app.state.pool, desde=desde, hasta=hasta
    )
    return [_mes(fila) for fila in filas]


@router.get(
    "/reportes/vinos-sin-stock",
    operation_id="reporteVinosSinStock",
    response_model=list[VinoSinStock],
)
def reporte_vinos_sin_stock(request: Request, id_sala: int) -> list[VinoSinStock]:
    """Return the wines with stock in deposito but none in the sala (S6)."""
    filas = repo_reportes.vinos_sin_stock(request.app.state.pool, id_sala)
    return [VinoSinStock.model_validate(fila) for fila in filas]


@router.get(
    "/reportes/transportista-activo",
    operation_id="reporteTransportistaActivo",
    response_model=TransportistaActivo,
)
def reporte_transportista_activo(request: Request) -> TransportistaActivo:
    """Return the transportista with most ingresos in the last month (S7) or 404."""
    fila = repo_reportes.transportista_activo(request.app.state.pool)
    if fila is None:
        raise DatabaseHttpError(
            404,
            {
                "codigo": "NOT_FOUND",
                "mensaje": "No hay transportistas con actividad en el ultimo mes.",
                "detalle": None,
                "regla": None,
            },
        )
    return TransportistaActivo.model_validate(fila)


@router.get(
    "/reportes/trazabilidad/{cod}",
    operation_id="reporteTrazabilidadVino",
    response_model=VinoDetalle,
)
def reporte_trazabilidad_vino(cod: int, request: Request) -> VinoDetalle:
    """Return the full wine card from ``vw_ficha_vino`` (S9) or 404."""
    ficha = repo_reportes.trazabilidad_vino(request.app.state.pool, cod)
    if ficha is None:
        raise DatabaseHttpError(
            404,
            {
                "codigo": "NOT_FOUND",
                "mensaje": f"No existe el vino {cod}.",
                "detalle": None,
                "regla": None,
            },
        )
    return VinoDetalle.model_validate(ficha)
