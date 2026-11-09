"""Endpoints of the ingresos operations (Bodegas del Atuel API)."""

from datetime import date

from fastapi import APIRouter, Request

from ..errors import DatabaseHttpError
from ..repos import ingresos as repo_ingresos
from ..schemas import Ingreso, IngresoCreate, RenglonDocumentoCreate

router = APIRouter(tags=["Ingresos"])


def _fecha_iso(valor):
    """Native DB ``date`` -> ISO string expected by the response schemas."""
    return valor.isoformat() if isinstance(valor, date) else valor


def _detalle(fila: dict) -> Ingreso:
    """Shape one repository row (cabecera + renglones) as Ingreso."""
    return Ingreso.model_validate({**fila, "fecha": _fecha_iso(fila["fecha"])})


@router.post(
    "/ingresos",
    operation_id="crearIngreso",
    response_model=Ingreso,
    status_code=201,
)
def crear_ingreso(request: Request, body: IngresoCreate) -> Ingreso:
    """Create one ingreso in confeccion for ``id_transportista``.

    Sends only the granted columns: ``fecha`` is optional and the INSERT's
    ``COALESCE`` falls back to CURRENT_DATE; ``estado`` takes the DEFAULT
    'en_confeccion' (RN-10). Every error flows through the centralized
    handlers.
    """
    ficha = repo_ingresos.crear_ingreso(request.app.state.pool, **body.model_dump())
    return _detalle(ficha)


@router.post(
    "/ingresos/{cod}/renglones",
    operation_id="agregarRenglonIngreso",
    response_model=Ingreso,
    status_code=201,
)
def agregar_renglon_ingreso(
    cod: int, request: Request, body: RenglonDocumentoCreate
) -> Ingreso:
    """Add one renglon (cod_vino, cantidad) while the document is en_confeccion.

    Editing renglones outside ``en_confeccion`` raises ``[RN-12]`` (P0001 ->
    409): the error flows through the centralized handlers, nothing is
    written. Only the missing-document case is raised here.
    """
    ficha = repo_ingresos.agregar_renglon_ingreso(
        request.app.state.pool, cod, **body.model_dump()
    )
    if ficha is None:
        raise DatabaseHttpError(
            404,
            {
                "codigo": "NOT_FOUND",
                "mensaje": f"No existe el ingreso {cod}.",
                "detalle": None,
                "regla": None,
            },
        )
    return _detalle(ficha)


@router.post(
    "/ingresos/{cod}/terminar",
    operation_id="terminarIngreso",
    response_model=Ingreso,
)
def terminar_ingreso(cod: int, request: Request) -> Ingreso:
    """Advance the ingreso from en_confeccion to terminado.

    Trigger T3 validates the transition and raises ``[RN-10]`` (P0001 ->
    409) on any invalid move. Repeating ``terminar`` on an already
    ``terminado`` document is a silent no-op that returns 200: the trigger
    never fires when ``estado`` does not change (open team decision P1/P3).
    """
    ficha = repo_ingresos.terminar_ingreso(request.app.state.pool, cod)
    if ficha is None:
        raise DatabaseHttpError(
            404,
            {
                "codigo": "NOT_FOUND",
                "mensaje": f"No existe el ingreso {cod}.",
                "detalle": None,
                "regla": None,
            },
        )
    return _detalle(ficha)


@router.post(
    "/ingresos/{cod}/procesar",
    operation_id="procesarIngreso",
    response_model=Ingreso,
)
def procesar_ingreso(cod: int, request: Request) -> Ingreso:
    """Process the ingreso: ``CALL sp_procesar_ingreso``.

    The procedure upserts ``stock_deposito`` and sets ``procesado``: a
    missing document raises P0002 (-> 404) and any pre-condition failure
    raises ``[RN-10]`` (P0001 -> 409, nothing persists). The router maps
    nothing: both errors flow through the centralized handlers.
    """
    ficha = repo_ingresos.procesar_ingreso(request.app.state.pool, cod)
    return _detalle(ficha)
