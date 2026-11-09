"""Stub endpoints for transferencias (Bodegas del Atuel API)."""

from fastapi import APIRouter

from ..schemas import RenglonDocumentoCreate, Transferencia, TransferenciaCreate

router = APIRouter(tags=["Transferencias"])

_EXAMPLE_RENGLON = {
    "cod_vino": 1,
    "nombre_comercial": "Malbec Reserva",
    "cantidad": 120,
}


def _transferencia_example(nro: int, estado: str, con_renglones: bool) -> Transferencia:
    renglones = [_EXAMPLE_RENGLON] if con_renglones else []
    return Transferencia.model_validate(
        {
            "nro_solicitud": nro,
            "id_sala": 1,
            "fecha_confeccion": "2026-11-05",
            "estado": estado,
            "renglones": renglones,
        }
    )


@router.post(
    "/transferencias",
    operation_id="crearTransferencia",
    response_model=Transferencia,
    status_code=201,
)
def crear_transferencia(body: TransferenciaCreate) -> Transferencia:
    # TODO(6.9): crear la transferencia; la base fuerza la fecha (RN-11).
    return _transferencia_example(5001, "en_confeccion", con_renglones=False)


@router.post(
    "/transferencias/{nro}/renglones",
    operation_id="agregarRenglonTransferencia",
    response_model=Transferencia,
    status_code=201,
)
def agregar_renglon_transferencia(nro: int, body: RenglonDocumentoCreate) -> Transferencia:
    # TODO(6.9): agregar el renglón a la transferencia en confección.
    return _transferencia_example(nro, "en_confeccion", con_renglones=True)


@router.post(
    "/transferencias/{nro}/terminar",
    operation_id="terminarTransferencia",
    response_model=Transferencia,
)
def terminar_transferencia(nro: int) -> Transferencia:
    # TODO(6.9): pasar la transferencia de en_confeccion a terminado.
    return _transferencia_example(nro, "terminado", con_renglones=True)


@router.post(
    "/transferencias/{nro}/procesar",
    operation_id="procesarTransferencia",
    response_model=Transferencia,
)
def procesar_transferencia(nro: int) -> Transferencia:
    # TODO(6.9): invocar sp_procesar_transferencia y mover el stock.
    return _transferencia_example(nro, "procesado", con_renglones=True)
