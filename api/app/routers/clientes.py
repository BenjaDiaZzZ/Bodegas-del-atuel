"""Stub endpoints for clientes (Bodegas del Atuel API)."""

from typing import Annotated

from fastapi import APIRouter, Query

from ..schemas import (
    ClienteCreate,
    ClienteDetalle,
    ClientePage,
    ClienteResumen,
    ClienteUpdate,
    PageMeta,
)

router = APIRouter(tags=["Clientes"])

_EXAMPLE_META = {"page": 1, "per_page": 20, "total": 137, "total_pages": 7}

_EXAMPLE_CLIENTE = {
    "id_cliente": 1,
    "nombre": "Juan Pérez",
    "tipo": "socio",
    "tipo_documento": "DNI",
    "nro_documento": "30123456",
    "direccion": "Av. San Martín 123",
    "id_localidad": 1,
    "localidad": "San Rafael",
    "fecha_alta": "2024-03-10",
    "descuento": 10.0,
    "zona_cobertura": None,
    "nro_habilitacion": None,
    "pais_destino_principal": None,
    "permisos": [],
}


@router.get("/clientes", operation_id="listarClientes", response_model=ClientePage)
def listar_clientes(
    page: Annotated[int, Query(ge=1)] = 1,
    per_page: Annotated[int, Query(ge=1, le=100)] = 20,
    tipo: str | None = None,
    id_localidad: int | None = None,
    q: str | None = None,
) -> ClientePage:
    # TODO(6.7): leer el listado paginado de clientes desde PostgreSQL.
    return ClientePage(
        data=[ClienteResumen.model_validate(_EXAMPLE_CLIENTE)],
        meta=PageMeta.model_validate(_EXAMPLE_META),
    )


@router.post(
    "/clientes",
    operation_id="crearCliente",
    response_model=ClienteDetalle,
    status_code=201,
)
def crear_cliente(body: ClienteCreate) -> ClienteDetalle:
    # TODO(6.7): crear el cliente; la base calcula el descuento por tipo (R-002).
    return ClienteDetalle.model_validate(_EXAMPLE_CLIENTE)


@router.get("/clientes/{id}", operation_id="obtenerCliente", response_model=ClienteDetalle)
def obtener_cliente(id: int) -> ClienteDetalle:
    # TODO(6.7): leer el cliente con los datos de su subtipo desde PostgreSQL.
    return ClienteDetalle.model_validate({**_EXAMPLE_CLIENTE, "id_cliente": id})


@router.put(
    "/clientes/{id}",
    operation_id="actualizarCliente",
    response_model=ClienteDetalle,
)
def actualizar_cliente(id: int, body: ClienteUpdate) -> ClienteDetalle:
    # TODO(6.7): actualizar el cliente y, si cambia el tipo, sus datos de subtipo.
    return ClienteDetalle.model_validate({**_EXAMPLE_CLIENTE, "id_cliente": id})


@router.delete("/clientes/{id}", operation_id="eliminarCliente", status_code=204)
def eliminar_cliente(id: int) -> None:
    # TODO(6.7): eliminar el cliente y traducir a 409 si tiene comprobantes.
    return None
