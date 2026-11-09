"""Endpoints of the transferencias operations (Bodegas del Atuel API)."""

from datetime import date

from fastapi import APIRouter, Request

from ..errors import DatabaseHttpError
from ..repos import transferencias as repo_transferencias
from ..schemas import RenglonDocumentoCreate, Transferencia, TransferenciaCreate

router = APIRouter(tags=["Transferencias"])


def _fecha_iso(valor):
    """Native DB ``date`` -> ISO string expected by the response schemas."""
    return valor.isoformat() if isinstance(valor, date) else valor


def _detalle(fila: dict) -> Transferencia:
    """Shape one repository row (cabecera + renglones) as Transferencia."""
    return Transferencia.model_validate(
        {**fila, "fecha_confeccion": _fecha_iso(fila["fecha_confeccion"])}
    )


@router.post(
    "/transferencias",
    operation_id="crearTransferencia",
    response_model=Transferencia,
    status_code=201,
)
def crear_transferencia(request: Request, body: TransferenciaCreate) -> Transferencia:
    """Create one transferencia in confeccion for ``id_sala``.

    The request carries ONLY ``id_sala``: ``fecha_confeccion`` is NEVER sent
    (trigger T5 forces CURRENT_DATE, RN-11) and ``estado`` takes the DEFAULT
    'en_confeccion'. Every error flows through the centralized handlers.
    """
    ficha = repo_transferencias.crear_transferencia(
        request.app.state.pool, **body.model_dump()
    )
    return _detalle(ficha)


@router.post(
    "/transferencias/{nro}/renglones",
    operation_id="agregarRenglonTransferencia",
    response_model=Transferencia,
    status_code=201,
)
def agregar_renglon_transferencia(
    nro: int, request: Request, body: RenglonDocumentoCreate
) -> Transferencia:
    """Add one renglon (cod_vino, cantidad) while the document is en_confeccion.

    Editing renglones outside ``en_confeccion`` raises ``[RN-12]`` (P0001 ->
    409): the error flows through the centralized handlers, nothing is
    written. Only the missing-document case is raised here.
    """
    ficha = repo_transferencias.agregar_renglon_transferencia(
        request.app.state.pool, nro, **body.model_dump()
    )
    if ficha is None:
        raise DatabaseHttpError(
            404,
            {
                "codigo": "NOT_FOUND",
                "mensaje": f"No existe la transferencia {nro}.",
                "detalle": None,
                "regla": None,
            },
        )
    return _detalle(ficha)


@router.post(
    "/transferencias/{nro}/terminar",
    operation_id="terminarTransferencia",
    response_model=Transferencia,
)
def terminar_transferencia(nro: int, request: Request) -> Transferencia:
    """Advance the transferencia from en_confeccion to terminado.

    Trigger T4 validates the transition and raises ``[RN-11]`` (P0001 ->
    409) on any invalid move. Repeating ``terminar`` on an already
    ``terminado`` document is a silent no-op that returns 200: the trigger
    never fires when ``estado`` does not change (open team decision P1/P3).
    """
    ficha = repo_transferencias.terminar_transferencia(request.app.state.pool, nro)
    if ficha is None:
        raise DatabaseHttpError(
            404,
            {
                "codigo": "NOT_FOUND",
                "mensaje": f"No existe la transferencia {nro}.",
                "detalle": None,
                "regla": None,
            },
        )
    return _detalle(ficha)


@router.post(
    "/transferencias/{nro}/procesar",
    operation_id="procesarTransferencia",
    response_model=Transferencia,
)
def procesar_transferencia(nro: int, request: Request) -> Transferencia:
    """Process the transferencia: ``CALL sp_procesar_transferencia``.

    The procedure moves the stock depósito -> sala and sets ``procesado``:
    a missing document raises P0002 (-> 404) and any pre-condition failure
    raises ``[RN-11]`` (P0001 -> 409, nothing persists). The router maps
    nothing: both errors flow through the centralized handlers.
    """
    ficha = repo_transferencias.procesar_transferencia(request.app.state.pool, nro)
    return _detalle(ficha)
