"""Integration tests against the ephemeral PostgreSQL database.

Exercises the central SQLSTATE -> HTTP mapping through the transaction
helper, using the app role (app_rw) and superuser fixtures for tables
that app_rw cannot write.
"""

import os
import uuid

import psycopg
import pytest
from psycopg.conninfo import make_conninfo

from app.config import Settings
from app.db import create_pool, get_connection, transaction
from app.errors import DatabaseHttpError

# Per-run markers: unique keys so a shared test database never loses
# unrelated data at teardown and crashed runs cannot collide on UNIQUE.
_FIXTURE_TAIL = uuid.uuid4().hex[:10]
FIXTURE_CUIT = f"92{(uuid.uuid4().int % 10**9):09d}"
FIXTURE_VINO_NOMBRE = f"Vino prueba {_FIXTURE_TAIL}"
FIXTURE_CEPA_NOMBRE = f"Cepa prueba {_FIXTURE_TAIL}"


@pytest.fixture(scope="module")
def pool():
    pool_inst = create_pool(Settings.from_env())
    yield pool_inst
    pool_inst.close()


@pytest.fixture
def bodega_y_cepas():
    superuser = psycopg.connect(
        make_conninfo(
            host=os.environ["POSTGRES_HOST"],
            port=os.environ["POSTGRES_PORT"],
            dbname=os.environ["POSTGRES_DB"],
            user=os.environ["PGSU"],
            password=os.environ["PGSUPW"],
        )
    )
    cepas = []
    try:
        superuser.execute(
            "INSERT INTO bodega (cuit, razon_social, domicilio) VALUES (%s, 'Bodega de pruebas', 'Domicilio de pruebas')"
            " ON CONFLICT (cuit) DO NOTHING",
            (FIXTURE_CUIT,),
        )
        for numero in (1, 2):
            cepas.append(
                superuser.execute(
                    "INSERT INTO cepa (nombre, tipo) VALUES (%s, 'tinta') RETURNING id_cepa",
                    (f"{FIXTURE_CEPA_NOMBRE} {numero}",),
                ).fetchone()[0]
            )
        superuser.commit()
        yield cepas
    finally:
        try:
            superuser.execute("DELETE FROM vino WHERE cuit_bodega = %s", (FIXTURE_CUIT,))
            superuser.execute("DELETE FROM cepa WHERE nombre LIKE %s", (f"{FIXTURE_CEPA_NOMBRE}%",))
            superuser.execute("DELETE FROM bodega WHERE cuit = %s", (FIXTURE_CUIT,))
            superuser.commit()
        finally:
            superuser.close()


def test_p0001_fn_descuento_cliente_maps_to_409_with_regla(pool):
    with pytest.raises(DatabaseHttpError) as raised:
        with transaction(pool) as connection:
            connection.execute("SELECT fn_descuento_cliente('tipo_invalido')")

    error = raised.value
    assert error.status == 409
    assert error.payload["codigo"] == "P0001"
    assert error.payload["regla"] == "RN-06"
    assert "RN-06" in error.payload["mensaje"]
    assert "tipo" in error.payload["mensaje"].lower()


def test_rn05_deferred_trigger_surfaces_at_commit_as_409(pool, bodega_y_cepas):
    cepa_ids = bodega_y_cepas
    executed = []

    with pytest.raises(DatabaseHttpError) as raised:
        with transaction(pool) as connection:
            vino_cod = connection.execute(
                "INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)"
                " VALUES (%s, 'tinto', 2026, 750, 13.50, 100.00, %s) RETURNING cod_vino",
                (FIXTURE_VINO_NOMBRE, FIXTURE_CUIT),
            ).fetchone()[0]
            executed.append("insert vino")

            connection.execute(
                "INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (%s, %s, 60)",
                (vino_cod, cepa_ids[0]),
            )
            executed.append("insert composicion 1")

            connection.execute(
                "INSERT INTO composicion (cod_vino, id_cepa, porcentaje) VALUES (%s, %s, 30)",
                (vino_cod, cepa_ids[1]),
            )
            executed.append("insert composicion 2")

    # Every INSERT completed before the failure: the P0001 only fired at COMMIT.
    assert executed == ["insert vino", "insert composicion 1", "insert composicion 2"]

    error = raised.value
    assert error.status == 409
    assert error.payload["regla"] == "RN-05"
    assert "RN-05" in error.payload["mensaje"]
    assert raised.value.__cause__.sqlstate == "P0001"


def test_unique_violation_duplicate_vino_maps_to_409(pool, bodega_y_cepas):
    with pytest.raises(DatabaseHttpError) as raised:
        with transaction(pool) as connection:
            for _ in range(2):
                connection.execute(
                    "INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)"
                    " VALUES (%s, 'rosado', 2027, 375, 11.00, 55.00, %s)",
                    (FIXTURE_VINO_NOMBRE + " unica", FIXTURE_CUIT),
                )

    error = raised.value
    assert error.status == 409
    assert error.payload["codigo"] == "23505"


def test_transaction_rolls_back_and_reraises_generic_exception(pool, bodega_y_cepas):
    vino_nombre = f"Vino rollback {_FIXTURE_TAIL}"

    with pytest.raises(ValueError, match="boom interno") as raised:
        with transaction(pool) as connection:
            connection.execute(
                "INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)"
                " VALUES (%s, 'blanco', 2025, 750, 12.00, 90.00, %s)",
                (vino_nombre, FIXTURE_CUIT),
            )
            raise ValueError("boom interno")

    assert type(raised.value) is ValueError

    with get_connection(pool) as connection:
        row = connection.execute(
            "SELECT COUNT(*) FROM vino WHERE nombre_comercial = %s",
            (vino_nombre,),
        ).fetchone()

    assert row == (0,)


def test_p0002_missing_ingreso_maps_to_404(pool):
    with pytest.raises(DatabaseHttpError) as raised:
        with transaction(pool) as connection:
            connection.execute("CALL sp_procesar_ingreso(999999)")

    error = raised.value
    assert error.status == 404
    assert error.payload["codigo"] == "P0002"
