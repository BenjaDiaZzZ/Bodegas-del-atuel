"""Stub endpoints for vinos (Bodegas del Atuel API)."""

from typing import Annotated

from fastapi import APIRouter, Query

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
    page: Annotated[int, Query(ge=1)] = 1,
    per_page: Annotated[int, Query(ge=1, le=100)] = 20,
    nombre: str | None = None,
    tipo: str | None = None,
    id_cepa: int | None = None,
    cuit_bodega: str | None = None,
    anada: int | None = None,
) -> VinoPage:
    # TODO(6.5): leer el catálogo con filtros y paginación desde PostgreSQL.
    return VinoPage(
        data=[VinoResumen.model_validate(_EXAMPLE_VINO)],
        meta=PageMeta.model_validate(_EXAMPLE_META),
    )


@router.post("/vinos", operation_id="crearVino", response_model=VinoDetalle, status_code=201)
def crear_vino(body: VinoCreate) -> VinoDetalle:
    # TODO(6.6): crear el vino con composición y maridajes en una transacción.
    return detalle_vino_example(1)


@router.get("/vinos/{cod}", operation_id="obtenerVino", response_model=VinoDetalle)
def obtener_vino(cod: int) -> VinoDetalle:
    # TODO(6.5): leer la ficha completa del vino desde PostgreSQL.
    return detalle_vino_example(cod)


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
