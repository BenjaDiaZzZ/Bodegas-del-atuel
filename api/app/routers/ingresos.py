"""Stub endpoints for ingresos (Bodegas del Atuel API)."""

from fastapi import APIRouter

from ..schemas import Ingreso, IngresoCreate, RenglonDocumentoCreate

router = APIRouter(tags=["Ingresos"])

_EXAMPLE_RENGLON = {
    "cod_vino": 1,
    "nombre_comercial": "Malbec Reserva",
    "cantidad": 120,
}


def _ingreso_example(cod: int, estado: str, con_renglones: bool) -> Ingreso:
    renglones = [_EXAMPLE_RENGLON] if con_renglones else []
    return Ingreso.model_validate(
        {
            "cod_ingreso": cod,
            "fecha": "2026-11-05",
            "estado": estado,
            "id_transportista": 1,
            "cuit_bodega": "30712345678",
            "renglones": renglones,
        }
    )


@router.post(
    "/ingresos",
    operation_id="crearIngreso",
    response_model=Ingreso,
    status_code=201,
)
def crear_ingreso(body: IngresoCreate) -> Ingreso:
    # TODO(6.9): crear el ingreso en confección; si falta fecha usa CURRENT_DATE.
    return _ingreso_example(3001, "en_confeccion", con_renglones=False)


@router.post(
    "/ingresos/{cod}/renglones",
    operation_id="agregarRenglonIngreso",
    response_model=Ingreso,
    status_code=201,
)
def agregar_renglon_ingreso(cod: int, body: RenglonDocumentoCreate) -> Ingreso:
    # TODO(6.9): agregar el renglón al ingreso en confección.
    return _ingreso_example(cod, "en_confeccion", con_renglones=True)


@router.post(
    "/ingresos/{cod}/terminar",
    operation_id="terminarIngreso",
    response_model=Ingreso,
)
def terminar_ingreso(cod: int) -> Ingreso:
    # TODO(6.9): pasar el ingreso de en_confeccion a terminado.
    return _ingreso_example(cod, "terminado", con_renglones=True)


@router.post(
    "/ingresos/{cod}/procesar",
    operation_id="procesarIngreso",
    response_model=Ingreso,
)
def procesar_ingreso(cod: int) -> Ingreso:
    # TODO(6.9): invocar sp_procesar_ingreso e impactar el stock del depósito.
    return _ingreso_example(cod, "procesado", con_renglones=True)
