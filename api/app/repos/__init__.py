"""Data access layer: one module per API resource."""

from . import clientes, comprobantes, ingresos, reportes, transferencias, vinos

__all__ = ["clientes", "comprobantes", "ingresos", "reportes", "transferencias", "vinos"]
