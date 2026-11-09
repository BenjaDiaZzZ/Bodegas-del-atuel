"""Unit tests for the central SQLSTATE -> HTTP mapping (no database needed)."""

import types

from psycopg import Error, errors as psycopg_errors

from app.errors import DatabaseHttpError, ErrorBody, map_db_error


def forged(error_class, message=None, detail=None):
    """Build a real psycopg error instance with a controlled diag."""

    class Forged(error_class):
        diag = types.SimpleNamespace(message_primary=message, detail=detail)

    return Forged()


def test_unique_violation_maps_to_409():
    error = forged(psycopg_errors.UniqueViolation, "duplicate key value violates unique constraint")

    assert map_db_error(error) == ErrorBody(
        status=409,
        codigo="23505",
        mensaje="duplicate key value violates unique constraint",
    )


def test_foreign_key_blocked_by_dependent_rows_maps_to_409():
    error = forged(
        psycopg_errors.ForeignKeyViolation,
        detail='Key (cuit)=(20222222223) is still referenced from table "vino".',
    )

    mapping = map_db_error(error)

    assert mapping.status == 409
    assert mapping.codigo == "23503"


def test_foreign_key_message_fallback_blocked_maps_to_409():
    error = forged(
        psycopg_errors.ForeignKeyViolation,
        message='update or delete on table "bodega" violates foreign key constraint',
    )

    assert map_db_error(error).status == 409


def test_foreign_key_missing_parent_maps_to_422():
    error = forged(
        psycopg_errors.ForeignKeyViolation,
        detail='Key (cuit_bodega)=(20000000001) is not present in table "bodega".',
    )

    assert map_db_error(error).status == 422


def test_foreign_key_message_fallback_missing_parent_maps_to_422():
    error = forged(
        psycopg_errors.ForeignKeyViolation,
        message='insert or update on table "vino" violates foreign key constraint',
    )

    assert map_db_error(error).status == 422


def test_foreign_key_unrecognized_maps_to_422():
    error = forged(psycopg_errors.ForeignKeyViolation, detail="mensaje localizado inesperado")

    assert map_db_error(error).status == 422


def test_fk_detail_is_carried_into_the_body():
    detail = 'Key (cuit)=(20222222223) is still referenced from table "vino".'
    error = forged(psycopg_errors.ForeignKeyViolation, detail=detail)

    mapping = map_db_error(error)
    assert mapping.detalle == detail


def test_check_violation_maps_to_422():
    error = forged(psycopg_errors.CheckViolation, 'new row violates check constraint "ck_vino_tipo"')

    mapping = map_db_error(error)

    assert mapping.status == 422
    assert mapping.codigo == "23514"


def test_not_null_violation_maps_to_422():
    error = forged(psycopg_errors.NotNullViolation, 'null value in column "nombre"')

    mapping = map_db_error(error)

    assert mapping.status == 422
    assert mapping.codigo == "23502"


def test_raise_exception_with_regla_maps_to_409():
    error = forged(
        psycopg_errors.RaiseException,
        "[RN-05] La composicion del vino 1 suma 90, debe sumar 100",
    )

    mapping = map_db_error(error)

    assert mapping.status == 409
    assert mapping.codigo == "P0001"
    assert mapping.regla == "RN-05"
    assert "La composicion del vino 1 suma 90, debe sumar 100" in mapping.mensaje


def test_raise_exception_without_regla_keeps_409_without_regla():
    error = forged(psycopg_errors.RaiseException, "mensaje sin regla")

    mapping = map_db_error(error)

    assert mapping.status == 409
    assert mapping.regla is None
    assert mapping.mensaje == "mensaje sin regla"


def test_no_data_found_maps_to_404():
    error = forged(psycopg_errors.NoDataFound, "no such document")

    assert map_db_error(error).status == 404


def test_invalid_text_representation_maps_to_400():
    error = forged(psycopg_errors.InvalidTextRepresentation, 'invalid input syntax for type integer: "abc"')

    mapping = map_db_error(error)

    assert mapping.status == 400
    assert mapping.codigo == "22P02"


def test_serialization_failure_maps_to_503_with_retry_hint():
    error = forged(psycopg_errors.SerializationFailure, "could not serialize access due to concurrent update")

    mapping = map_db_error(error)

    assert mapping.status == 503
    assert "reintent" in mapping.mensaje.lower()
    assert mapping.detalle is None


def test_deadlock_detected_maps_to_503_with_retry_hint():
    error = forged(psycopg_errors.DeadlockDetected, "deadlock detected")

    mapping = map_db_error(error)

    assert mapping.status == 503
    assert "reintent" in mapping.mensaje.lower()


def test_insufficient_privilege_maps_to_500_without_internal_details():
    error = forged(psycopg_errors.InsufficientPrivilege, "permission denied for table bodega")

    mapping = map_db_error(error)

    assert mapping.status == 500
    assert mapping.codigo == "INTERNAL_ERROR"
    assert "permission denied" not in mapping.mensaje
    assert "bodega" not in mapping.mensaje
    assert mapping.detalle is None


def test_unknown_sqlstate_maps_to_500_generic():
    error = Error("fallo inexplicable con detalles internos")
    error.sqlstate = "XX000"

    mapping = map_db_error(error)

    assert mapping.status == 500
    assert mapping.codigo == "INTERNAL_ERROR"
    assert "inexplicable" not in mapping.mensaje


def test_psycopg_error_without_sqlstate_maps_to_500_generic():
    error = Error()

    mapping = map_db_error(error)

    assert mapping.status == 500
    assert mapping.codigo == "INTERNAL_ERROR"
    assert mapping.regla is None


def test_generic_mensaje_is_never_the_raw_exception_text():
    error = Error("detalles internos de la base")
    error.sqlstate = "XX000"

    mapping = map_db_error(error)

    assert "detalles internos" not in mapping.mensaje


def test_database_http_error_carries_status_and_payload():
    error = DatabaseHttpError(409, {"codigo": "P0001", "mensaje": "x", "detalle": None, "regla": "RN-05"})

    assert error.status == 409
    assert error.payload["regla"] == "RN-05"
