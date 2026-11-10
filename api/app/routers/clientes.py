"""Endpoints de lectura y escritura de clientes (Bodegas del Atuel API)."""

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query, Request

from ..errors import DatabaseHttpError
from ..repos import clientes as repo_clientes
from ..schemas import (
    ClienteCreate,
    ClienteDetalle,
    ClientePage,
    ClienteResumen,
    ClienteUpdate,
    PageMeta,
    TipoCliente,
)

router = APIRouter(tags=["Clientes"])


def _fecha_iso(valor):
    """Native DB ``date`` -> ISO string expected by the response schemas."""
    return valor.isoformat() if isinstance(valor, date) else valor


def _resumen(fila: dict) -> ClienteResumen:
    """Shape one repository row as ClienteResumen."""
    return ClienteResumen.model_validate({**fila, "fecha_alta": _fecha_iso(fila["fecha_alta"])})


def _detalle(fila: dict) -> ClienteDetalle:
    """Shape one repository detail row (subtype fields + permisos) as ClienteDetalle."""
    permisos = [
        {
            **permiso,
            "fecha_emision": _fecha_iso(permiso["fecha_emision"]),
            "fecha_vencimiento": _fecha_iso(permiso["fecha_vencimiento"]),
        }
        for permiso in fila["permisos"]
    ]
    return ClienteDetalle.model_validate(
        {**fila, "fecha_alta": _fecha_iso(fila["fecha_alta"]), "permisos": permisos}
    )


@router.get("/clientes", operation_id="listarClientes", response_model=ClientePage)
def listar_clientes(
    request: Request,
    page: Annotated[int, Query(ge=1)] = 1,
    per_page: Annotated[int, Query(ge=1, le=100)] = 20,
    tipo: TipoCliente | None = None,
    id_localidad: int | None = None,
    q: str | None = None,
) -> ClientePage:
    """List the client catalog with optional filters and pagination.

    Filters/reading delegate to the repository (app_rw). ``total_pages`` is 0
    when the filtered total is 0: an empty result has no pages.
    """
    filas, total = repo_clientes.listar_clientes(
        request.app.state.pool,
        page=page,
        per_page=per_page,
        tipo=tipo,
        id_localidad=id_localidad,
        q=q,
    )
    return ClientePage(
        data=[_resumen(fila) for fila in filas],
        meta=PageMeta(
            page=page,
            per_page=per_page,
            total=total,
            total_pages=(total + per_page - 1) // per_page,
        ),
    )


@router.post("/clientes", operation_id="crearCliente", response_model=ClienteDetalle, status_code=201)
def crear_cliente(request: Request, body: ClienteCreate) -> ClienteDetalle:
    """Create one client with its subtype (and export permits) in one transaction.

    ``descuento`` is GENERATED ALWAYS and ``id_cliente`` is identity: neither is
    ever sent. The database computes the discount from ``tipo`` (R-002); the
    subtype row and permits are inserted inside the repository transaction.
    Every error flows through the centralized handlers (23505 -> 409, CHECK /
    NOT NULL / FK parent -> 422, request validation -> 400).
    """
    ficha = repo_clientes.crear_cliente(request.app.state.pool, **body.model_dump())
    return _detalle(ficha)


@router.get("/clientes/{id}", operation_id="obtenerCliente", response_model=ClienteDetalle)
def obtener_cliente(id: int, request: Request) -> ClienteDetalle:
    """Return the client with its subtype fields and permits, or 404."""
    ficha = repo_clientes.obtener_cliente(request.app.state.pool, id)
    if ficha is None:
        raise DatabaseHttpError(
            404,
            {"codigo": "NOT_FOUND", "mensaje": f"No existe el cliente {id}.", "detalle": None, "regla": None},
        )
    return _detalle(ficha)


@router.put("/clientes/{id}", operation_id="actualizarCliente", response_model=ClienteDetalle)
def actualizar_cliente(id: int, request: Request, body: ClienteUpdate) -> ClienteDetalle:
    """Update only the fields the client actually sent (partial update).

    ``tipo`` is absent from ClienteUpdate: it never changes through the API.
    When ``permisos`` is sent the whole collection is replaced inside the
    repository transaction; ``409``/``422`` flow through the centralized
    handlers and only the missing-client case is raised here.
    """
    cambios = body.model_dump(exclude_unset=True)
    permisos = cambios.pop("permisos", None)
    ficha = repo_clientes.actualizar_cliente(
        request.app.state.pool, id, permisos=permisos, **cambios
    )
    if ficha is None:
        raise DatabaseHttpError(
            404,
            {"codigo": "NOT_FOUND", "mensaje": f"No existe el cliente {id}.", "detalle": None, "regla": None},
        )
    return _detalle(ficha)


@router.delete("/clientes/{id}", operation_id="eliminarCliente", status_code=204)
def eliminar_cliente(id: int, request: Request) -> None:
    """Delete one client; subtype/permits cascade, dependent comprobantes 409."""
    if repo_clientes.eliminar_cliente(request.app.state.pool, id) == 0:
        raise DatabaseHttpError(
            404,
            {"codigo": "NOT_FOUND", "mensaje": f"No existe el cliente {id}.", "detalle": None, "regla": None},
        )
    return None
