"""Central conversion of PostgreSQL errors to the contract Error body.

This module is the ONLY place where a psycopg error is translated to an
HTTP status. Routers must raise/propagate the original psycopg error (or
a :class:`DatabaseHttpError` produced by ``app.db.transaction``) and let
the FastAPI exception handlers in ``app.main`` render the body.
"""

import re
from dataclasses import dataclass

SQLSTATE_UNIQUE_VIOLATION = "23505"
SQLSTATE_FOREIGN_KEY_VIOLATION = "23503"
SQLSTATE_CHECK_VIOLATION = "23514"
SQLSTATE_NOT_NULL_VIOLATION = "23502"
SQLSTATE_RAISE_EXCEPTION = "P0001"
SQLSTATE_NO_DATA_FOUND = "P0002"
SQLSTATE_INVALID_TEXT_REPRESENTATION = "22P02"
SQLSTATE_SERIALIZATION_FAILURE = "40001"
SQLSTATE_DEADLOCK_DETECTED = "40P01"
SQLSTATE_INSUFFICIENT_PRIVILEGE = "42501"

INTERNAL_ERROR_CODE = "INTERNAL_ERROR"
GENERIC_INTERNAL_MESSAGE = "Error interno del servidor."
RETRYABLE_MESSAGE = (
    "La base de datos no pudo completar la operacion por un conflicto de concurrencia."
    " La operacion puede reintentarse."
)

REGULA_PREFIX_PATTERN = re.compile(r"\[(RN-\d+)\]")

# PostgreSQL standard English FK messages. A localized server would fall
# back to Rule 3 below, which is safe and documented.
FK_BLOCKED_DETAIL_MARK = "is still referenced from table"
FK_BLOCKED_MESSAGE_PREFIX = "update or delete on table"
FK_MISSING_DETAIL_MARK = "is not present in table"
FK_MISSING_MESSAGE_PREFIX = "insert or update on table"

STATUS_BLOCKED = 409
STATUS_UNPROCESSABLE = 422
STATUS_BAD_REQUEST = 400
STATUS_NOT_FOUND = 404
STATUS_RETRYABLE = 503
STATUS_INTERNAL = 500

VALIDATION_STATUS_BY_SQLSTATE = {
    SQLSTATE_UNIQUE_VIOLATION: STATUS_BLOCKED,
    SQLSTATE_CHECK_VIOLATION: STATUS_UNPROCESSABLE,
    SQLSTATE_NOT_NULL_VIOLATION: STATUS_UNPROCESSABLE,
    SQLSTATE_NO_DATA_FOUND: STATUS_NOT_FOUND,
    SQLSTATE_INVALID_TEXT_REPRESENTATION: STATUS_BAD_REQUEST,
}


@dataclass(frozen=True)
class ErrorBody:
    """The `Error` schema of api/openapi.yaml."""

    status: int
    codigo: str
    mensaje: str
    detalle: str | None = None
    regla: str | None = None

    def payload(self) -> dict:
        return {
            "codigo": self.codigo,
            "mensaje": self.mensaje,
            "detalle": self.detalle,
            "regla": self.regla,
        }


class DatabaseHttpError(Exception):
    """Carries an already-mapped contract Error body (status + payload)."""

    def __init__(self, status: int, payload: dict):
        super().__init__(payload.get("mensaje", ""))
        self.status = status
        self.payload = payload

    @classmethod
    def from_body(cls, body: ErrorBody) -> "DatabaseHttpError":
        return cls(body.status, body.payload())


def _diagnostics(error: Exception) -> tuple[str | None, str | None]:
    """Return (message_primary, detail) without assuming psycopg internals."""

    diag = getattr(error, "diag", None)
    if diag is None:
        return None, None
    return getattr(diag, "message_primary", None), getattr(diag, "detail", None)


def _foreign_key_status(error: Exception) -> int:
    """Classify a FK violation by the direction of the referential problem.

    1. Detail contains "is still referenced from table" (or the message
       starts with "update or delete on table"): dependent rows block the
       operation -> 409 Conflict.
    2. Detail contains "is not present in table" (or the message starts
       with "insert or update on table"): the request references a
       missing parent -> 422.
    3. Unrecognized: documented fallback -> 422. Both standard texts are
       PostgreSQL's English messages; a localized server falls back to
       this default.
    """

    message, detail = _diagnostics(error)
    message = message or str(error)
    if detail and FK_BLOCKED_DETAIL_MARK in detail:
        return STATUS_BLOCKED
    if message.startswith(FK_BLOCKED_MESSAGE_PREFIX):
        return STATUS_BLOCKED
    if detail and FK_MISSING_DETAIL_MARK in detail:
        return STATUS_UNPROCESSABLE
    if message.startswith(FK_MISSING_MESSAGE_PREFIX):
        return STATUS_UNPROCESSABLE
    return STATUS_UNPROCESSABLE


def _business_rule(message: str) -> str | None:
    match = REGULA_PREFIX_PATTERN.search(message)
    return match.group(1) if match else None


def map_db_error(error: Exception) -> ErrorBody:
    """Map one psycopg error to exactly one contract Error body."""

    sqlstate = getattr(error, "sqlstate", None)

    if sqlstate == SQLSTATE_FOREIGN_KEY_VIOLATION:
        message, detail = _diagnostics(error)
        return ErrorBody(
            status=_foreign_key_status(error),
            codigo=SQLSTATE_FOREIGN_KEY_VIOLATION,
            mensaje=message or str(error) or detail or "",
            detalle=detail or None,
        )

    if sqlstate == SQLSTATE_RAISE_EXCEPTION:
        message, _ = _diagnostics(error)
        raise_message = message or str(error)
        return ErrorBody(
            status=STATUS_BLOCKED,
            codigo=SQLSTATE_RAISE_EXCEPTION,
            mensaje=raise_message,
            regla=_business_rule(raise_message),
        )

    if sqlstate in (SQLSTATE_SERIALIZATION_FAILURE, SQLSTATE_DEADLOCK_DETECTED):
        return ErrorBody(status=STATUS_RETRYABLE, codigo=sqlstate, mensaje=RETRYABLE_MESSAGE)

    if sqlstate == SQLSTATE_INSUFFICIENT_PRIVILEGE:
        return ErrorBody(status=STATUS_INTERNAL, codigo=INTERNAL_ERROR_CODE, mensaje=GENERIC_INTERNAL_MESSAGE)

    if sqlstate in VALIDATION_STATUS_BY_SQLSTATE:
        message, detail = _diagnostics(error)
        return ErrorBody(
            status=VALIDATION_STATUS_BY_SQLSTATE[sqlstate],
            codigo=sqlstate,
            mensaje=message or str(error),
            detalle=detail or None,
        )

    return ErrorBody(status=STATUS_INTERNAL, codigo=INTERNAL_ERROR_CODE, mensaje=GENERIC_INTERNAL_MESSAGE)
