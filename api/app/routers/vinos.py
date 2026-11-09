"""Real GET endpoints and stub writes for vinos (Bodegas del Atuel API)."""

from typing import Annotated, Literal

from fastapi import APIRouter, Query, Request

from ..errors import DatabaseHttpError
from ..repos import vinos as repo_vinos
from ..schemas import (
    PageMeta,
    VinoCreate,
    VinoDetalle,
    VinoPage,
    VinoResumen,
    VinoUpdate,
)

router = APIRouter(tags=["Vinos"])

_EXAMPLE_META = {"page": 1, "per_page": 20, "total": 137, "total_pages": 7}

_EXAMPLE_VINO = {
    "cod_vino": 1,
    "nombre_comercial": "Malbec Reserva",
    "tipo": "tinto",
    "anada": 2021,
    "presentacion_ml": 750,
    "graduacion": 14.0,
    "precio_venta": 12500.0,
    "cuit_bodega": "30712345678",
    "bodega": "Bodega del Atuel S.A.",
}

_EXAMPLE_COMPOSICION = [
    {"id_cepa": 1, "nombre": "Malbec", "porcentaje": 85.0},
    {"id_cepa": 2, "nombre": "Bonarda", "porcentaje": 15.0},
]

_EXAMPLE_MARIDAJES = [
    {"id_maridaje": 1, "nombre": "Carnes rojas", "temperatura_servicio": 17.0},
]

_EXAMPLE_STOCK = {"deposito": 120, "salas": 45, "total": 165}


def detalle_vino_example(cod: int) -> VinoDetalle:
    return VinoDetalle.model_validate(
        {
            **_EXAMPLE_VINO,
            "cod_vino": cod,
            "composicion": _EXAMPLE_COMPOSICION,
            "maridajes": _EXAMPLE_MARIDAJES,
            "stock": _EXAMPLE_STOCK,
        }
    )


@router.get("/vinos", operation_id="listarVinos", response_model=VinoPage)
def listar_vinos(
    request: Request,
    page: Annotated[int, Query(ge=1)] = 1,
    per_page: Annotated[int, Query(ge=1, le=100)] = 20,
    nombre: str | None = None,
    tipo: Literal["tinto", "blanco", "rosado", "espumante"] | None = None,
    id_cepa: int | None = None,
    cuit_bodega: Annotated[str | None, Query(pattern=r"^[0-9]{11}$")] = None,
    anada: int | None = None,
) -> VinoPage:
    """List the wine catalog with optional filters and pagination.

    Filters/reading delegate to the repository (app_rw). ``total_pages``
    is 0 when the filtered total is 0: an empty result has no pages.
    """
    filas, total = repo_vinos.listar_vinos(
        request.app.state.pool,
        page=page,
        per_page=per_page,
        nombre=nombre,
        tipo=tipo,
        id_cepa=id_cepa,
        cuit_bodega=cuit_bodega,
        anada=anada,
    )
    return VinoPage(
        data=[VinoResumen.model_validate(fila) for fila in filas],
        meta=PageMeta(
            page=page,
            per_page=per_page,
            total=total,
            total_pages=(total + per_page - 1) // per_page,
        ),
    )


@router.post("/vinos", operation_id="crearVino", response_model=VinoDetalle, status_code=201)
def crear_vino(body: VinoCreate) -> VinoDetalle:
    # TODO(6.6): crear el vino con composición y maridajes en una transacción.
    return detalle_vino_example(1)


@router.get("/vinos/{cod}", operation_id="obtenerVino", response_model=VinoDetalle)
def obtener_vino(cod: int, request: Request) -> VinoDetalle:
    """Return the full wine card (composition, pairings, stock) or 404."""
    ficha = repo_vinos.obtener_vino(request.app.state.pool, cod)
    if ficha is None:
        raise DatabaseHttpError(
            404,
            {"codigo": "NOT_FOUND", "mensaje": f"No existe el vino {cod}.", "detalle": None, "regla": None},
        )
    return VinoDetalle.model_validate(ficha)


@router.put(
    "/vinos/{cod}",
    operation_id="actualizarVino",
    response_model=VinoDetalle,
)
def actualizar_vino(cod: int, body: VinoUpdate) -> VinoDetalle:
    # TODO(6.6): actualizar el vino en transacción; registrar app.usuario para RN-13.
    return detalle_vino_example(cod)


@router.delete("/vinos/{cod}", operation_id="eliminarVino", status_code=204)
def eliminar_vino(cod: int) -> None:
    # TODO(6.6): eliminar el vino y traducir a 409 si hay movimientos (RN-14).
    return None
