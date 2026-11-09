"""HTTP integration tests for the transferencias and ingresos operations (task 6.9).

The pool connects as ``app_rw``; the HTTP layer exercises the routers and the
repository functions own every write. The API never touches stock or dates:
every expected value here comes from what the database procedures and
triggers computed (RN-10/RN-11/RN-12). Catalog tables app_rw cannot write
(bodega, cepa, localidad, sala, transportista, stock_deposito) are seeded
with a superuser connection. Mirrors ``test_comprobantes_endpoints.py``.
"""

import os
import uuid
from datetime import date
from decimal import Decimal

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row

import app.main as main
from app.config import Settings
from app.db import create_pool, get_connection
from app.repos import vinos

_TAIL = uuid.uuid4().hex[:10]
BODEGA_CUIT = f"93{(uuid.uuid4().int % 10**9):09d}"
LOCALIDAD = f"Localidad doc http {_TAIL}"
SALA_DIRECCION = f"Direccion doc http {_TAIL}"
TRANSP_CUIT = f"20{(uuid.uuid4().int % 10**9):09d}"
VINO_NOMBRE = f"Vino doc http {_TAIL}"

TRANSFERENCIA_KEYS = {
    "nro_solicitud",
    "id_sala",
    "fecha_confeccion",
    "estado",
    "renglones",
}
INGRESO_KEYS = {
    "cod_ingreso",
    "fecha",
    "estado",
    "id_transportista",
    "cuit_bodega",
    "renglones",
}
RENGLON_KEYS = {"cod_vino", "nombre_comercial", "cantidad"}
ERROR_KEYS = {"codigo", "mensaje", "detalle", "regla"}


def _superuser():
    return psycopg.connect(
        make_conninfo(
            host=os.environ["POSTGRES_HOST"],
            port=os.environ["POSTGRES_PORT"],
            dbname=os.environ["POSTGRES_DB"],
            user=os.environ["PGSU"],
            password=os.environ["PGSUPW"],
        )
    )


@pytest.fixture(scope="module")
def pool():
    pool_inst = create_pool(Settings.from_env())
    yield pool_inst
    pool_inst.close()


@pytest.fixture(scope="module")
def client(pool):
    """HTTP client with the module pool as safety net for seeding."""
    with TestClient(main.create_app()) as test_client:
        yield test_client


@pytest.fixture(scope="module")
def escenario():
    """Base catalog (bodega, cepas, localidad, sala, transportista) via superuser."""
    superuser = _superuser()
    try:
        superuser.execute(
            "INSERT INTO bodega (cuit, razon_social, domicilio) VALUES (%s, 'Bodega doc http', 'Domicilio doc http')"
            " ON CONFLICT (cuit) DO NOTHING",
            (BODEGA_CUIT,),
        )
        cepas = [
            superuser.execute(
                "INSERT INTO cepa (nombre, tipo) VALUES (%s, 'tinta') RETURNING id_cepa",
                (f"Cepa doc http {_TAIL} {n}",),
            ).fetchone()[0]
            for n in (1, 2)
        ]
        localidad = superuser.execute(
            "INSERT INTO localidad (nombre, codigo_postal, provincia)"
            " VALUES (%s, '5620', 'Mendoza') RETURNING id_localidad",
            (LOCALIDAD,),
        ).fetchone()[0]
        sala = superuser.execute(
            "INSERT INTO sala (direccion, dia_cierre_semanal, id_localidad)"
            " VALUES (%s, 4, %s) RETURNING id_sala",
            (SALA_DIRECCION, localidad),
        ).fetchone()[0]
        transportista = superuser.execute(
            "INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)"
            " VALUES ('Transporte doc http', %s, 'transporte.doc.http@mail.test', '5600000000', 'Domicilio transporte')"
            " RETURNING id_transportista",
            (TRANSP_CUIT,),
        ).fetchone()[0]
        superuser.commit()
        yield {
            "cepas": cepas,
            "id_localidad": localidad,
            "id_sala": sala,
            "id_transportista": transportista,
        }
    finally:
        try:
            superuser.execute(
                "DELETE FROM ingreso WHERE cuit_bodega = %s", (BODEGA_CUIT,))
            superuser.execute(
                "DELETE FROM transferencia WHERE id_sala = %s", (sala,))
            superuser.execute(
                "DELETE FROM stock_sala WHERE id_sala = %s", (sala,))
            superuser.execute(
                "DELETE FROM stock_deposito WHERE cod_vino IN"
                " (SELECT cod_vino FROM vino WHERE cuit_bodega = %s)",
                (BODEGA_CUIT,),
            )
            superuser.execute(
                "DELETE FROM vino WHERE cuit_bodega = %s", (BODEGA_CUIT,))
            superuser.execute(
                "DELETE FROM transportista WHERE id_transportista = %s",
                (transportista,),
            )
            superuser.execute("DELETE FROM sala WHERE id_sala = %s", (sala,))
            superuser.execute("DELETE FROM localidad WHERE nombre = %s", (LOCALIDAD,))
            superuser.execute(
                "DELETE FROM cepa WHERE nombre LIKE %s", (f"Cepa doc http {_TAIL}%",))
            superuser.execute("DELETE FROM bodega WHERE cuit = %s", (BODEGA_CUIT,))
            superuser.commit()
        finally:
            superuser.close()


def _crear_vino(pool, escenario, sufijo):
    """One vino with a single cepa (100%) per call. app_rw owns the DML."""
    return vinos.crear_vino(
        pool,
        nombre_comercial=f"{VINO_NOMBRE} {sufijo}",
        tipo="tinto",
        anada=2021,
        presentacion_ml=750,
        graduacion=Decimal("13.50"),
        precio_venta=Decimal("100.00"),
        cuit_bodega=BODEGA_CUIT,
        composicion=[{"id_cepa": escenario["cepas"][0], "porcentaje": Decimal("100.00")}],
    )


def _sembrar_deposito(su, cod_vino, cantidad):
    su.execute(
        "INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (%s, %s)"
        " ON CONFLICT (cod_vino) DO UPDATE SET cantidad = EXCLUDED.cantidad",
        (cod_vino, cantidad),
    )


def _stock_deposito_de(pool, cod_vino):
    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        fila = connection.execute(
            "SELECT cantidad FROM stock_deposito WHERE cod_vino = %s", (cod_vino,)
        ).fetchone()
    return fila["cantidad"] if fila else None


def _stock_sala_de(pool, id_sala, cod_vino):
    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        fila = connection.execute(
            "SELECT cantidad FROM stock_sala WHERE id_sala = %s AND cod_vino = %s",
            (id_sala, cod_vino),
        ).fetchone()
    return fila["cantidad"] if fila else None


def _renglones_transferencia_de(pool, nro_solicitud):
    """Count the renglones persisted for one transferencia (atomicity pin)."""
    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        return connection.execute(
            "SELECT COUNT(*) AS n FROM renglon_transferencia WHERE nro_solicitud = %s",
            (nro_solicitud,),
        ).fetchone()["n"]


def _renglones_ingreso_de(pool, cod_ingreso):
    """Count the renglones persisted for one ingreso (atomicity pin)."""
    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        return connection.execute(
            "SELECT COUNT(*) AS n FROM renglon_ingreso WHERE cod_ingreso = %s",
            (cod_ingreso,),
        ).fetchone()["n"]


def _estado_transferencia_de(pool, nro_solicitud):
    with get_connection(pool) as connection:
        connection.row_factory = dict_row
        fila = connection.execute(
            "SELECT estado FROM transferencia WHERE nro_solicitud = %s",
            (nro_solicitud,),
        ).fetchone()
    return fila["estado"] if fila else None


def _hoy_iso():
    return date.today().isoformat()


# ---------------------------------------------------------------------------
# Transferencias · POST /transferencias y acciones
# ---------------------------------------------------------------------------


def test_crear_transferencia_201_fecha_forzada_por_la_base(client, escenario):
    # The body never carries fecha_confeccion: even if a client sneaks one in,
    # the trigger T5 (RN-11) forces CURRENT_DATE and Pydantic drops the extra.
    response = client.post(
        "/transferencias",
        json={"id_sala": escenario["id_sala"], "fecha_confeccion": "2001-01-01"},
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert set(body) == TRANSFERENCIA_KEYS
    assert body["nro_solicitud"] > 0
    assert body["id_sala"] == escenario["id_sala"]
    assert body["fecha_confeccion"] == _hoy_iso()
    assert body["estado"] == "en_confeccion"
    assert body["renglones"] == []


def test_transferencia_renglon_201_mientras_en_confeccion(client, pool, escenario):
    vino = _crear_vino(pool, escenario, "tr renglon")
    su = _superuser()
    try:
        _sembrar_deposito(su, vino["cod_vino"], 10)
        su.commit()
    finally:
        su.close()
    nro = client.post("/transferencias", json={"id_sala": escenario["id_sala"]}).json()[
        "nro_solicitud"
    ]

    response = client.post(
        f"/transferencias/{nro}/renglones",
        json={"cod_vino": vino["cod_vino"], "cantidad": 3},
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert set(body) == TRANSFERENCIA_KEYS
    assert body["estado"] == "en_confeccion"
    assert body["renglones"] == [
        {
            "cod_vino": vino["cod_vino"],
            "nombre_comercial": f"{VINO_NOMBRE} tr renglon",
            "cantidad": 3,
        }
    ]
    assert set(body["renglones"][0]) == RENGLON_KEYS


def test_transferencia_renglon_tras_terminar_409_rn12_y_atomico(client, pool, escenario):
    vino1 = _crear_vino(pool, escenario, "tr bloqueo 1")
    vino2 = _crear_vino(pool, escenario, "tr bloqueo 2")
    su = _superuser()
    try:
        _sembrar_deposito(su, vino1["cod_vino"], 5)
        su.commit()
    finally:
        su.close()
    nro = client.post("/transferencias", json={"id_sala": escenario["id_sala"]}).json()[
        "nro_solicitud"
    ]
    client.post(
        f"/transferencias/{nro}/renglones",
        json={"cod_vino": vino1["cod_vino"], "cantidad": 1},
    )
    assert client.post(f"/transferencias/{nro}/terminar").status_code == 200

    response = client.post(
        f"/transferencias/{nro}/renglones",
        json={"cod_vino": vino2["cod_vino"], "cantidad": 1},
    )

    assert response.status_code == 409, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "P0001"
    assert body["regla"] == "RN-12"
    # Atomicity: the ROLLBACK left the renglón count untouched.
    assert _renglones_transferencia_de(pool, nro) == 1


def test_transferencia_terminar_200_y_repetir_es_noop_200(client, pool, escenario):
    vino = _crear_vino(pool, escenario, "tr terminar")
    su = _superuser()
    try:
        _sembrar_deposito(su, vino["cod_vino"], 5)
        su.commit()
    finally:
        su.close()
    nro = client.post("/transferencias", json={"id_sala": escenario["id_sala"]}).json()[
        "nro_solicitud"
    ]
    client.post(
        f"/transferencias/{nro}/renglones",
        json={"cod_vino": vino["cod_vino"], "cantidad": 1},
    )

    terminada = client.post(f"/transferencias/{nro}/terminar")
    repetida = client.post(f"/transferencias/{nro}/terminar")

    assert terminada.status_code == 200, terminada.text
    assert terminada.json()["estado"] == "terminado"
    # DECISIÓN ABIERTA (P1/P3): repetir terminar sobre 'terminado' es un no-op
    # del trigger T4 (sin cambio de estado no hay transición que validar): la
    # base conserva 'terminado' y la API responde 200. Sin 409 inventado.
    assert repetida.status_code == 200, repetida.text
    assert repetida.json()["estado"] == "terminado"


def test_transferencia_procesar_antes_de_terminar_409_rn11(client, pool, escenario):
    vino = _crear_vino(pool, escenario, "tr sin terminar")
    su = _superuser()
    try:
        _sembrar_deposito(su, vino["cod_vino"], 5)
        su.commit()
    finally:
        su.close()
    nro = client.post("/transferencias", json={"id_sala": escenario["id_sala"]}).json()[
        "nro_solicitud"
    ]
    client.post(
        f"/transferencias/{nro}/renglones",
        json={"cod_vino": vino["cod_vino"], "cantidad": 1},
    )

    response = client.post(f"/transferencias/{nro}/procesar")

    assert response.status_code == 409, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "P0001"
    assert body["regla"] == "RN-11"
    # Nothing moved: the stock stays in the depósito and the sala got nothing.
    assert _stock_deposito_de(pool, vino["cod_vino"]) == 5
    assert _stock_sala_de(pool, escenario["id_sala"], vino["cod_vino"]) is None


def test_transferencia_procesar_200_mueve_stock(client, pool, escenario):
    vino = _crear_vino(pool, escenario, "tr procesar")
    su = _superuser()
    try:
        _sembrar_deposito(su, vino["cod_vino"], 10)
        su.commit()
    finally:
        su.close()
    nro = client.post("/transferencias", json={"id_sala": escenario["id_sala"]}).json()[
        "nro_solicitud"
    ]
    client.post(
        f"/transferencias/{nro}/renglones",
        json={"cod_vino": vino["cod_vino"], "cantidad": 3},
    )
    client.post(f"/transferencias/{nro}/terminar")

    response = client.post(f"/transferencias/{nro}/procesar")

    assert response.status_code == 200, response.text
    body = response.json()
    assert set(body) == TRANSFERENCIA_KEYS
    assert body["estado"] == "procesado"
    # sp_procesar_transferencia moved the stock: depósito -3, sala +3.
    assert _stock_deposito_de(pool, vino["cod_vino"]) == 7
    assert _stock_sala_de(pool, escenario["id_sala"], vino["cod_vino"]) == 3


def test_transferencia_stock_insuficiente_409_rn11_y_atomico(client, pool, escenario):
    vino = _crear_vino(pool, escenario, "tr rn11 stock")
    su = _superuser()
    try:
        _sembrar_deposito(su, vino["cod_vino"], 1)
        su.commit()
    finally:
        su.close()
    nro = client.post("/transferencias", json={"id_sala": escenario["id_sala"]}).json()[
        "nro_solicitud"
    ]
    client.post(
        f"/transferencias/{nro}/renglones",
        json={"cod_vino": vino["cod_vino"], "cantidad": 5},
    )
    client.post(f"/transferencias/{nro}/terminar")

    response = client.post(f"/transferencias/{nro}/procesar")

    assert response.status_code == 409, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "P0001"
    assert body["regla"] == "RN-11"
    # Atomicity: the CALL rolled back — stock untouched, estado still terminado.
    assert _stock_deposito_de(pool, vino["cod_vino"]) == 1
    assert _stock_sala_de(pool, escenario["id_sala"], vino["cod_vino"]) is None
    assert _estado_transferencia_de(pool, nro) == "terminado"


def test_transferencia_terminar_tras_procesado_409_rn11(client, pool, escenario):
    vino = _crear_vino(pool, escenario, "tr retroceso")
    su = _superuser()
    try:
        _sembrar_deposito(su, vino["cod_vino"], 5)
        su.commit()
    finally:
        su.close()
    nro = client.post("/transferencias", json={"id_sala": escenario["id_sala"]}).json()[
        "nro_solicitud"
    ]
    client.post(
        f"/transferencias/{nro}/renglones",
        json={"cod_vino": vino["cod_vino"], "cantidad": 1},
    )
    client.post(f"/transferencias/{nro}/terminar")
    assert client.post(f"/transferencias/{nro}/procesar").status_code == 200

    response = client.post(f"/transferencias/{nro}/terminar")

    assert response.status_code == 409, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "P0001"
    assert body["regla"] == "RN-11"


def test_transferencia_acciones_inexistentes_404_error_contrato(client):
    renglones = client.post(
        "/transferencias/999999999/renglones", json={"cod_vino": 1, "cantidad": 1}
    )
    terminar = client.post("/transferencias/999999999/terminar")
    procesar = client.post("/transferencias/999999999/procesar")

    for response in (renglones, terminar):
        assert response.status_code == 404, response.text
        body = response.json()
        assert set(body) == ERROR_KEYS
        assert body["codigo"] == "NOT_FOUND"
        assert "999999999" in body["mensaje"]
        assert body["regla"] is None
    # procesar delegates to sp_procesar_transferencia: the DB raises P0002 and
    # the centralized handler maps it to 404 with the SQLSTATE as codigo.
    assert procesar.status_code == 404, procesar.text
    body = procesar.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "P0002"
    assert "999999999" in body["mensaje"]


def test_crear_transferencia_cuerpo_invalido_400_validation_error(client):
    sin_sala = client.post("/transferencias", json={})
    sin_cod_vino = client.post(
        "/transferencias/1/renglones", json={"cantidad": 3}
    )
    cantidad_cero = client.post(
        "/transferencias/1/renglones", json={"cod_vino": 1, "cantidad": 0}
    )

    for response in (sin_sala, sin_cod_vino, cantidad_cero):
        assert response.status_code == 400, response.text
        body = response.json()
        assert set(body) == ERROR_KEYS
        assert body["codigo"] == "VALIDATION_ERROR"
        assert body["detalle"]


# ---------------------------------------------------------------------------
# Ingresos · POST /ingresos y acciones
# ---------------------------------------------------------------------------


def test_crear_ingreso_201_fecha_por_defecto_de_la_base(client, escenario):
    response = client.post(
        "/ingresos",
        json={
            "id_transportista": escenario["id_transportista"],
            "cuit_bodega": BODEGA_CUIT,
        },
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert set(body) == INGRESO_KEYS
    assert body["cod_ingreso"] > 0
    assert body["id_transportista"] == escenario["id_transportista"]
    assert body["cuit_bodega"] == BODEGA_CUIT
    # No fecha sent: the INSERT's COALESCE used CURRENT_DATE.
    assert body["fecha"] == _hoy_iso()
    assert body["estado"] == "en_confeccion"
    assert body["renglones"] == []


def test_ingreso_renglon_201_mientras_en_confeccion(client, pool, escenario):
    vino = _crear_vino(pool, escenario, "ing renglon")
    cod = client.post(
        "/ingresos",
        json={
            "id_transportista": escenario["id_transportista"],
            "cuit_bodega": BODEGA_CUIT,
        },
    ).json()["cod_ingreso"]

    response = client.post(
        f"/ingresos/{cod}/renglones",
        json={"cod_vino": vino["cod_vino"], "cantidad": 120},
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert set(body) == INGRESO_KEYS
    assert body["estado"] == "en_confeccion"
    assert body["renglones"] == [
        {
            "cod_vino": vino["cod_vino"],
            "nombre_comercial": f"{VINO_NOMBRE} ing renglon",
            "cantidad": 120,
        }
    ]
    assert set(body["renglones"][0]) == RENGLON_KEYS


def test_ingreso_renglon_tras_terminar_409_rn12_y_atomico(client, pool, escenario):
    vino1 = _crear_vino(pool, escenario, "ing bloqueo 1")
    vino2 = _crear_vino(pool, escenario, "ing bloqueo 2")
    cod = client.post(
        "/ingresos",
        json={
            "id_transportista": escenario["id_transportista"],
            "cuit_bodega": BODEGA_CUIT,
        },
    ).json()["cod_ingreso"]
    client.post(
        f"/ingresos/{cod}/renglones",
        json={"cod_vino": vino1["cod_vino"], "cantidad": 1},
    )
    assert client.post(f"/ingresos/{cod}/terminar").status_code == 200

    response = client.post(
        f"/ingresos/{cod}/renglones",
        json={"cod_vino": vino2["cod_vino"], "cantidad": 1},
    )

    assert response.status_code == 409, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "P0001"
    assert body["regla"] == "RN-12"
    # Atomicity: the ROLLBACK left the renglón count untouched.
    assert _renglones_ingreso_de(pool, cod) == 1


def test_ingreso_procesar_antes_de_terminar_409_rn10(client, pool, escenario):
    vino = _crear_vino(pool, escenario, "ing sin terminar")
    cod = client.post(
        "/ingresos",
        json={
            "id_transportista": escenario["id_transportista"],
            "cuit_bodega": BODEGA_CUIT,
        },
    ).json()["cod_ingreso"]
    client.post(
        f"/ingresos/{cod}/renglones",
        json={"cod_vino": vino["cod_vino"], "cantidad": 1},
    )

    response = client.post(f"/ingresos/{cod}/procesar")

    assert response.status_code == 409, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "P0001"
    assert body["regla"] == "RN-10"
    # Nothing moved: the depósito never saw the renglón's bottles.
    assert _stock_deposito_de(pool, vino["cod_vino"]) is None


def test_ingreso_procesar_200_upserta_deposito(client, pool, escenario):
    vino_a = _crear_vino(pool, escenario, "ing procesar a")
    vino_b = _crear_vino(pool, escenario, "ing procesar b")
    cod = client.post(
        "/ingresos",
        json={
            "id_transportista": escenario["id_transportista"],
            "cuit_bodega": BODEGA_CUIT,
        },
    ).json()["cod_ingreso"]
    client.post(
        f"/ingresos/{cod}/renglones",
        json={"cod_vino": vino_a["cod_vino"], "cantidad": 3},
    )
    client.post(
        f"/ingresos/{cod}/renglones",
        json={"cod_vino": vino_b["cod_vino"], "cantidad": 120},
    )
    client.post(f"/ingresos/{cod}/terminar")

    response = client.post(f"/ingresos/{cod}/procesar")

    assert response.status_code == 200, response.text
    body = response.json()
    assert set(body) == INGRESO_KEYS
    assert body["estado"] == "procesado"
    # sp_procesar_ingreso upserts stock_deposito: creates the missing rows.
    assert _stock_deposito_de(pool, vino_a["cod_vino"]) == 3
    assert _stock_deposito_de(pool, vino_b["cod_vino"]) == 120


def test_ingreso_terminar_tras_procesado_409_rn10(client, pool, escenario):
    vino = _crear_vino(pool, escenario, "ing retroceso")
    cod = client.post(
        "/ingresos",
        json={
            "id_transportista": escenario["id_transportista"],
            "cuit_bodega": BODEGA_CUIT,
        },
    ).json()["cod_ingreso"]
    client.post(
        f"/ingresos/{cod}/renglones",
        json={"cod_vino": vino["cod_vino"], "cantidad": 1},
    )
    client.post(f"/ingresos/{cod}/terminar")
    assert client.post(f"/ingresos/{cod}/procesar").status_code == 200

    response = client.post(f"/ingresos/{cod}/terminar")

    assert response.status_code == 409, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "P0001"
    assert body["regla"] == "RN-10"


def test_ingreso_acciones_inexistentes_404_error_contrato(client):
    renglones = client.post(
        "/ingresos/999999999/renglones", json={"cod_vino": 1, "cantidad": 1}
    )
    terminar = client.post("/ingresos/999999999/terminar")
    procesar = client.post("/ingresos/999999999/procesar")

    for response in (renglones, terminar):
        assert response.status_code == 404, response.text
        body = response.json()
        assert set(body) == ERROR_KEYS
        assert body["codigo"] == "NOT_FOUND"
        assert "999999999" in body["mensaje"]
        assert body["regla"] is None
    # procesar delegates to sp_procesar_ingreso: the DB raises P0002 and the
    # centralized handler maps it to 404 with the SQLSTATE as codigo.
    assert procesar.status_code == 404, procesar.text
    body = procesar.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "P0002"
    assert "999999999" in body["mensaje"]


def test_crear_ingreso_cuerpo_invalido_400_validation_error(client):
    sin_campos = client.post("/ingresos", json={})
    sin_cod_vino = client.post("/ingresos/1/renglones", json={"cantidad": 3})
    cuit_invalido = client.post(
        "/ingresos", json={"id_transportista": 1, "cuit_bodega": "no-es-un-cuit"}
    )

    for response in (sin_campos, sin_cod_vino, cuit_invalido):
        assert response.status_code == 400, response.text
        body = response.json()
        assert set(body) == ERROR_KEYS
        assert body["codigo"] == "VALIDATION_ERROR"
        assert body["detalle"]
