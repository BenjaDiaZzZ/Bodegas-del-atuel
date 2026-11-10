"""Endpoints of the comprobantes operations (Bodegas del Atuel API)."""

from datetime import date

from fastapi import APIRouter, Request

from ..errors import DatabaseHttpError
from ..repos import comprobantes as repo_comprobantes
from ..schemas import Comprobante, ComprobanteCreate

router = APIRouter(tags=["Comprobantes"])


def _fecha_iso(valor):
    """Native DB ``date`` -> ISO string expected by the response schemas."""
    return valor.isoformat() if isinstance(valor, date) else valor


def _detalle(fila: dict) -> Comprobante:
    """Shape one repository row (cabecera + renglones) as Comprobante."""
    return Comprobante.model_validate({**fila, "fecha": _fecha_iso(fila["fecha"])})


@router.post("/comprobantes", operation_id="crearComprobante", response_model=Comprobante, status_code=201)
def crear_comprobante(request: Request, body: ComprobanteCreate) -> Comprobante:
    """Register the full sale in one transaction: cabecera plus renglones.

    The request carries ONLY ``id_cliente``, ``id_sala`` (optionally
    ``fecha``) and ``renglones`` as ``(cod_vino, cantidad)``: the database
    triggers compute ``precio_unitario``, ``descuento``, ``subtotal`` per
    renglón and the cabecera ``subtotal``/``descuento``/``total``
    (RN-08/RN-09). Every error flows through the centralized handlers:
    insufficient stock raises ``[RN-09]`` (P0001 -> 409, nothing persists),
    a repeated ``cod_vino`` violates the composite PK (23505 -> 409) and a
    missing cliente/vino FK parent maps to 422.
    """
    ficha = repo_comprobantes.crear_comprobante(request.app.state.pool, **body.model_dump())
    return _detalle(ficha)


@router.get("/comprobantes/{nro}", operation_id="obtenerComprobante", response_model=Comprobante)
def obtener_comprobante(nro: int, request: Request) -> Comprobante:
    """Return the comprobante with its renglones as stored, or 404."""
    ficha = repo_comprobantes.obtener_comprobante(request.app.state.pool, nro)
    if ficha is None:
        raise DatabaseHttpError(
            404,
            {
                "codigo": "NOT_FOUND",
                "mensaje": f"No existe el comprobante {nro}.",
                "detalle": None,
                "regla": None,
            },
        )
    return _detalle(ficha)
