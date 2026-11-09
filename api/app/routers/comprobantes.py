"""Stub endpoint for comprobantes (Bodegas del Atuel API)."""

from fastapi import APIRouter

from ..schemas import Comprobante, ComprobanteCreate

router = APIRouter(tags=["Comprobantes"])

_EXAMPLE_RENGLON = {
    "cod_vino": 1,
    "nombre_comercial": "Malbec Reserva",
    "cantidad": 3,
    "precio_unitario": 12500.0,
    "descuento": 3750.0,
    "subtotal": 33750.0,
}


def _comprobante_example(nro: int) -> Comprobante:
    return Comprobante.model_validate(
        {
            "nro_comprobante": nro,
            "fecha": "2026-11-05",
            "id_cliente": 1,
            "id_sala": 1,
            "subtotal": 37500.0,
            "descuento": 3750.0,
            "total": 33750.0,
            "renglones": [_EXAMPLE_RENGLON],
        }
    )


@router.post(
    "/comprobantes",
    operation_id="crearComprobante",
    response_model=Comprobante,
    status_code=201,
)
def crear_comprobante(body: ComprobanteCreate) -> Comprobante:
    # TODO(6.8): registrar la venta completa en una transacción (solo cod_vino y cantidad).
    return _comprobante_example(1001)


@router.get(
    "/comprobantes/{nro}",
    operation_id="obtenerComprobante",
    response_model=Comprobante,
)
def obtener_comprobante(nro: int) -> Comprobante:
    # TODO(6.8): leer el comprobante con sus renglones desde PostgreSQL.
    return _comprobante_example(nro)
