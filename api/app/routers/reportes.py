"""Stub endpoints for reportes (Bodegas del Atuel API)."""

from fastapi import APIRouter

from ..schemas import (
    TopVino,
    TransportistaActivo,
    VentaMensualSala,
    VinoDetalle,
    VinoSinStock,
)
from .vinos import detalle_vino_example

router = APIRouter(tags=["Reportes"])


@router.get(
    "/reportes/top-vinos",
    operation_id="reporteTopVinos",
    response_model=list[TopVino],
)
def reporte_top_vinos(limite: int = 10) -> list[TopVino]:
    # TODO(6.10): calcular el ranking de vinos más vendidos (S1) desde PostgreSQL.
    return [
        TopVino.model_validate(
            {
                "cod_vino": 1,
                "nombre_comercial": "Malbec Reserva",
                "botellas_vendidas": 1520,
            }
        )
    ]


@router.get(
    "/reportes/ventas-por-sala",
    operation_id="reporteVentasPorSala",
    response_model=list[VentaMensualSala],
)
def reporte_ventas_por_sala(desde: str | None = None, hasta: str | None = None) -> list[VentaMensualSala]:
    # TODO(6.10): leer las ventas mensuales por sala (S8) desde PostgreSQL.
    return [
        VentaMensualSala.model_validate(
            {
                "id_sala": 1,
                "localidad": "San Rafael",
                "mes": "2026-09-01",
                "botellas_vendidas": 430,
                "monto_total": 5375000.0,
            }
        )
    ]


@router.get(
    "/reportes/vinos-sin-stock",
    operation_id="reporteVinosSinStock",
    response_model=list[VinoSinStock],
)
def reporte_vinos_sin_stock(id_sala: int) -> list[VinoSinStock]:
    # TODO(6.10): comparar stock de sala y depósito (S6) desde PostgreSQL.
    return [
        VinoSinStock.model_validate(
            {
                "cod_vino": 1,
                "nombre_comercial": "Malbec Reserva",
                "stock_sala": 0,
                "stock_deposito": 120,
            }
        )
    ]


@router.get(
    "/reportes/transportista-activo",
    operation_id="reporteTransportistaActivo",
    response_model=TransportistaActivo,
)
def reporte_transportista_activo() -> TransportistaActivo:
    # TODO(6.10): calcular el transportista con mayor actividad del último mes (S7).
    return TransportistaActivo.model_validate(
        {
            "id_transportista": 1,
            "razon_social": "Transportes Cuyo SRL",
            "ingresos_trasladados": 48,
        }
    )


@router.get(
    "/reportes/trazabilidad/{cod}",
    operation_id="reporteTrazabilidadVino",
    response_model=VinoDetalle,
)
def reporte_trazabilidad_vino(cod: int) -> VinoDetalle:
    # TODO(6.10): leer la ficha completa del vino desde la vista vw_ficha_vino (S9).
    return detalle_vino_example(cod)
