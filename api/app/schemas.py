"""Pydantic models mirroring the response and request schemas of api/openapi.yaml."""

from typing import Literal

from pydantic import BaseModel, Field

TipoVino = Literal["tinto", "blanco", "rosado", "espumante"]
TipoCliente = Literal["socio", "distribuidor", "exportador"]
TipoDocumento = Literal["DNI", "CUIT", "CUIL", "PASAPORTE", "LE", "LC"]
EstadoDocumento = Literal["en_confeccion", "terminado", "procesado"]
PresentacionML = Literal[187, 375, 750, 1500, 3000]


class PageMeta(BaseModel):
    page: int
    per_page: int
    total: int
    total_pages: int


class ComposicionItem(BaseModel):
    id_cepa: int
    nombre: str
    porcentaje: float


class MaridajeItem(BaseModel):
    id_maridaje: int
    nombre: str
    temperatura_servicio: float


class StockVino(BaseModel):
    deposito: int
    salas: int
    total: int


class VinoResumen(BaseModel):
    cod_vino: int
    nombre_comercial: str
    tipo: TipoVino
    anada: int
    presentacion_ml: PresentacionML
    graduacion: float
    precio_venta: float
    cuit_bodega: str
    bodega: str


class VinoDetalle(VinoResumen):
    composicion: list[ComposicionItem]
    maridajes: list[MaridajeItem]
    stock: StockVino


class VinoPage(BaseModel):
    data: list[VinoResumen]
    meta: PageMeta


class PermisoExportacion(BaseModel):
    cod_permiso: str
    fecha_emision: str
    fecha_vencimiento: str


class ClienteResumen(BaseModel):
    id_cliente: int
    nombre: str
    tipo: TipoCliente
    tipo_documento: TipoDocumento
    nro_documento: str
    direccion: str | None = None
    id_localidad: int
    localidad: str
    fecha_alta: str
    descuento: float


class ClienteDetalle(ClienteResumen):
    zona_cobertura: str | None = None
    nro_habilitacion: str | None = None
    pais_destino_principal: str | None = None
    permisos: list[PermisoExportacion] = []


class ClientePage(BaseModel):
    data: list[ClienteResumen]
    meta: PageMeta


class ComprobanteRenglon(BaseModel):
    cod_vino: int
    nombre_comercial: str
    cantidad: int
    precio_unitario: float
    descuento: float
    subtotal: float


class Comprobante(BaseModel):
    nro_comprobante: int
    fecha: str
    id_cliente: int
    id_sala: int
    subtotal: float
    descuento: float
    total: float
    renglones: list[ComprobanteRenglon]


class DocumentoRenglon(BaseModel):
    cod_vino: int
    nombre_comercial: str
    cantidad: int


class Transferencia(BaseModel):
    nro_solicitud: int
    id_sala: int
    fecha_confeccion: str
    estado: EstadoDocumento
    renglones: list[DocumentoRenglon] = []


class Ingreso(BaseModel):
    cod_ingreso: int
    fecha: str
    estado: EstadoDocumento
    id_transportista: int
    cuit_bodega: str
    renglones: list[DocumentoRenglon] = []


class TopVino(BaseModel):
    cod_vino: int
    nombre_comercial: str
    botellas_vendidas: int


class VentaMensualSala(BaseModel):
    id_sala: int
    localidad: str
    mes: str
    botellas_vendidas: int
    monto_total: float


class VinoSinStock(BaseModel):
    cod_vino: int
    nombre_comercial: str
    stock_sala: int
    stock_deposito: int

class StockPorSala(BaseModel):
    cod_vino: int
    nombre_comercial: str
    stock_sala: int
    stock_deposito: int


class TransportistaActivo(BaseModel):
    id_transportista: int
    razon_social: str
    ingresos_trasladados: int


class ComposicionCreateItem(BaseModel):
    id_cepa: int
    porcentaje: float


class VinoCreate(BaseModel):
    nombre_comercial: str
    tipo: TipoVino
    anada: int
    presentacion_ml: PresentacionML
    graduacion: float
    precio_venta: float
    cuit_bodega: str
    composicion: list[ComposicionCreateItem]
    maridajes: list[int] = []


class VinoUpdate(BaseModel):
    nombre_comercial: str | None = None
    tipo: TipoVino | None = None
    anada: int | None = None
    presentacion_ml: PresentacionML | None = None
    graduacion: float | None = None
    precio_venta: float | None = None
    cuit_bodega: str | None = None
    composicion: list[ComposicionCreateItem] | None = None
    maridajes: list[int] | None = None


class ClienteCreate(BaseModel):
    nombre: str
    tipo: TipoCliente
    tipo_documento: TipoDocumento
    nro_documento: str
    direccion: str
    id_localidad: int
    fecha_alta: str | None = None
    zona_cobertura: str | None = None
    nro_habilitacion: str | None = None
    pais_destino_principal: str | None = None
    permisos: list[PermisoExportacion] | None = None


class ClienteUpdate(BaseModel):
    nombre: str | None = None
    tipo_documento: TipoDocumento | None = None
    nro_documento: str | None = None
    direccion: str | None = None
    id_localidad: int | None = None
    zona_cobertura: str | None = None
    nro_habilitacion: str | None = None
    pais_destino_principal: str | None = None
    permisos: list[PermisoExportacion] | None = None


class ComprobanteRenglonCreate(BaseModel):
    cod_vino: int
    cantidad: int = Field(ge=1)


class ComprobanteCreate(BaseModel):
    id_cliente: int
    id_sala: int
    fecha: str | None = None
    renglones: list[ComprobanteRenglonCreate] = Field(min_length=1)


class TransferenciaCreate(BaseModel):
    id_sala: int


class RenglonDocumentoCreate(BaseModel):
    cod_vino: int
    cantidad: int = Field(ge=1)


class IngresoCreate(BaseModel):
    id_transportista: int
    cuit_bodega: str = Field(pattern=r"^[0-9]{11}$")
    fecha: str | None = None
