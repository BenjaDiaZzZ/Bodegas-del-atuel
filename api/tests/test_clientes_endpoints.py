"""HTTP integration tests for the clientes CRUD (task 6.7).

The pool connects as ``app_rw``; the HTTP layer exercises the routers and the
repository functions own every write. ``localidad`` and ``sala`` are catalog
tables app_rw cannot create, so they are seeded with a superuser connection.
Every marker value includes a per-run unique suffix and the fixtures tear down
FK-safe. Mirrors ``test_vinos_endpoints.py``.
"""

import os
import uuid
from datetime import date

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg.conninfo import make_conninfo

import app.main as main
from app.config import Settings
from app.repos import clientes, comprobantes

_TAIL = uuid.uuid4().hex[:10]
NOMBRE = f"Cliente http {_TAIL}"

PAGE_KEYS = {"data", "meta"}
META_KEYS = {"page", "per_page", "total", "total_pages"}
RESUMEN_KEYS = {
    "id_cliente",
    "nombre",
    "tipo",
    "tipo_documento",
    "nro_documento",
    "direccion",
    "id_localidad",
    "localidad",
    "fecha_alta",
    "descuento",
}
DETALLE_KEYS = RESUMEN_KEYS | {
    "zona_cobertura",
    "nro_habilitacion",
    "pais_destino_principal",
    "permisos",
}
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
    pool_inst = main.create_pool(Settings.from_env())
    yield pool_inst
    pool_inst.close()


@pytest.fixture(scope="module")
def client(pool):
    """HTTP client with the module pool as safety net for seeding."""
    with TestClient(main.create_app()) as test_client:
        yield test_client


@pytest.fixture(scope="module")
def localidades():
    """Creates two localidades with a superuser; teardown deletes FK-safe."""
    superuser = _superuser()
    marcador = uuid.uuid4().hex[:6]
    ids: list[int] = []
    try:
        ids = [
            superuser.execute(
                "INSERT INTO localidad (codigo_postal, nombre, provincia)"
                " VALUES (%s, %s, 'Mendoza') RETURNING id_localidad",
                (f"{uuid.uuid4().int % 10000:04d}", f"Localidad http {marcador} {n}"),
            ).fetchone()[0]
            for n in (1, 2)
        ]
        superuser.commit()
        yield {"ids": ids}
    finally:
        try:
            superuser.execute(
                "DELETE FROM comprobante WHERE id_cliente IN"
                " (SELECT id_cliente FROM cliente WHERE id_localidad = ANY(%s))",
                (ids,),
            )
            superuser.execute("DELETE FROM cliente WHERE id_localidad = ANY(%s)", (ids,))
            superuser.execute("DELETE FROM localidad WHERE id_localidad = ANY(%s)", (ids,))
            superuser.commit()
        finally:
            superuser.close()


@pytest.fixture(scope="module")
def sala(localidades):
    """Creates one sala (superuser) for the DELETE + comprobante RESTRICT case."""
    superuser = _superuser()
    try:
        id_sala = superuser.execute(
            "INSERT INTO sala (direccion, dia_cierre_semanal, id_localidad)"
            " VALUES (%s, 1, %s) RETURNING id_sala",
            (f"Sala http {_TAIL}", localidades["ids"][0]),
        ).fetchone()[0]
        superuser.commit()
        yield {"id": id_sala}
    finally:
        try:
            superuser.execute("DELETE FROM comprobante WHERE id_sala = %s", (id_sala,))
            superuser.execute("DELETE FROM sala WHERE id_sala = %s", (id_sala,))
            superuser.commit()
        finally:
            superuser.close()


def _crear_repo(pool, localidades, nro, *, tipo="socio", extra=None, permisos=None):
    """Seeds one client through the repository (same pattern as the repo tests)."""
    datos = dict(
        nombre=f"{NOMBRE} {nro}",
        tipo=tipo,
        tipo_documento="DNI",
        nro_documento=f"40{_TAIL[:6]}{nro:02d}",
        direccion=f"Calle {nro} 100",
        id_localidad=localidades["ids"][0],
    )
    if tipo == "distribuidor":
        datos.update(zona_cobertura="Zona Sur", nro_habilitacion=f"HAB-{_TAIL}-{nro}")
    if tipo == "exportador":
        datos.update(pais_destino_principal="Brasil")
    if extra:
        datos.update(extra)
    if permisos is not None:
        datos["permisos"] = permisos
    return clientes.crear_cliente(pool, **datos)


@pytest.fixture(scope="module")
def seed(pool, localidades):
    """Creates 4 marked clients spanning both localidades and all three types."""
    primera, segunda = localidades["ids"]
    permiso = {
        "cod_permiso": f"EXP-HTTP-{_TAIL}",
        "fecha_emision": date(2026, 1, 15),
        "fecha_vencimiento": date(2027, 1, 15),
    }
    socio_a = _crear_repo(pool, localidades, 1)
    distribuidor_b = _crear_repo(pool, localidades, 2, tipo="distribuidor")
    exportador_c = _crear_repo(
        pool, localidades, 3, tipo="exportador", extra={"id_localidad": segunda}, permisos=[permiso]
    )
    socio_d = _crear_repo(pool, localidades, 4, extra={"id_localidad": segunda})
    return {
        "socio_a": socio_a,
        "distribuidor_b": distribuidor_b,
        "exportador_c": exportador_c,
        "socio_d": socio_d,
        "permiso": permiso,
        "ids": [c["id_cliente"] for c in (socio_a, distribuidor_b, exportador_c, socio_d)],
        "socios": [socio_a["id_cliente"], socio_d["id_cliente"]],
        "localidad_2": [exportador_c["id_cliente"], socio_d["id_cliente"]],
        "primera": primera,
        "segunda": segunda,
    }


# ---------------------------------------------------------------------------
# Lectura · GET /clientes y GET /clientes/{id}
# ---------------------------------------------------------------------------


def test_listar_clientes_200_devuelve_shape_contrato(client, seed):
    response = client.get("/clientes", params={"q": NOMBRE})

    assert response.status_code == 200, response.text
    body = response.json()
    assert set(body) == PAGE_KEYS
    assert set(body["meta"]) == META_KEYS
    assert body["meta"] == {"page": 1, "per_page": 20, "total": 4, "total_pages": 1}
    assert {item["id_cliente"] for item in body["data"]} == set(seed["ids"])
    for item in body["data"]:
        assert set(item) == RESUMEN_KEYS


def test_filtro_tipo_devuelve_solo_socios(client, seed):
    response = client.get("/clientes", params={"tipo": "socio", "q": NOMBRE})

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["meta"]["total"] == 2
    assert {item["id_cliente"] for item in body["data"]} == set(seed["socios"])


def test_filtro_id_localidad_devuelve_solo_esa_localidad(client, seed):
    response = client.get("/clientes", params={"id_localidad": seed["segunda"], "q": NOMBRE})

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["meta"]["total"] == 2
    assert {item["id_cliente"] for item in body["data"]} == set(seed["localidad_2"])
    assert {item["id_localidad"] for item in body["data"]} == {seed["segunda"]}


def test_filtro_q_busca_nombre_parcial(client, seed):
    response = client.get("/clientes", params={"q": f"{NOMBRE} 1"})

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["meta"]["total"] == 1
    assert [item["id_cliente"] for item in body["data"]] == [seed["socio_a"]["id_cliente"]]


def test_filtros_combinados_se_intersecan(client, seed):
    response = client.get(
        "/clientes",
        params={"tipo": "socio", "id_localidad": seed["segunda"], "q": NOMBRE},
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["meta"]["total"] == 1
    assert [item["id_cliente"] for item in body["data"]] == [seed["socio_d"]["id_cliente"]]


def test_paginacion_de_a_dos_devuelve_paginas_disjuntas(client, seed):
    page1 = client.get("/clientes", params={"q": NOMBRE, "page": 1, "per_page": 2}).json()
    page2 = client.get("/clientes", params={"q": NOMBRE, "page": 2, "per_page": 2}).json()

    assert page1["meta"] == {"page": 1, "per_page": 2, "total": 4, "total_pages": 2}
    assert page2["meta"] == {"page": 2, "per_page": 2, "total": 4, "total_pages": 2}
    ids1 = {item["id_cliente"] for item in page1["data"]}
    ids2 = {item["id_cliente"] for item in page2["data"]}
    assert len(ids1) == len(ids2) == 2
    assert ids1.isdisjoint(ids2)
    assert ids1 | ids2 == set(seed["ids"])


def test_pagina_fuera_de_rango_devuelve_data_vacia_con_meta_consistente(client, seed):
    response = client.get("/clientes", params={"q": NOMBRE, "page": 9, "per_page": 2})

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["data"] == []
    assert body["meta"] == {"page": 9, "per_page": 2, "total": 4, "total_pages": 2}


def test_filtro_sin_coincidencias_devuelve_pagina_vacia(client):
    response = client.get("/clientes", params={"q": uuid.uuid4().hex})

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["data"] == []
    assert body["meta"] == {"page": 1, "per_page": 20, "total": 0, "total_pages": 0}


def test_obtener_exportador_200_expone_subtipo_y_permisos(client, seed):
    id_cliente = seed["exportador_c"]["id_cliente"]
    response = client.get(f"/clientes/{id_cliente}")

    assert response.status_code == 200, response.text
    body = response.json()
    assert set(body) == DETALLE_KEYS
    assert body["id_cliente"] == id_cliente
    assert body["tipo"] == "exportador"
    assert body["descuento"] == 30.0
    assert body["pais_destino_principal"] == "Brasil"
    assert body["zona_cobertura"] is None
    assert body["nro_habilitacion"] is None
    assert body["permisos"] == [
        {
            "cod_permiso": seed["permiso"]["cod_permiso"],
            "fecha_emision": "2026-01-15",
            "fecha_vencimiento": "2027-01-15",
        }
    ]


def test_obtener_socio_200_no_expone_datos_de_otro_subtipo(client, seed):
    id_cliente = seed["socio_a"]["id_cliente"]
    response = client.get(f"/clientes/{id_cliente}")

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["tipo"] == "socio"
    assert body["descuento"] == 10.0
    assert body["zona_cobertura"] is None
    assert body["nro_habilitacion"] is None
    assert body["pais_destino_principal"] is None
    assert body["permisos"] == []


def test_obtener_cliente_inexistente_404_error_contrato(client):
    response = client.get("/clientes/999999999")

    assert response.status_code == 404, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "NOT_FOUND"
    assert "999999999" in body["mensaje"]


def test_tipo_invalido_en_listado_devuelve_400_error_contrato(client):
    response = client.get("/clientes", params={"tipo": "mayorista"})

    assert response.status_code == 400, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "VALIDATION_ERROR"


# ---------------------------------------------------------------------------
# Escritura · POST /clientes
# ---------------------------------------------------------------------------


def _cuerpo_post(nombre, tipo, id_localidad, *, nro=None, extra=None):
    cuerpo = {
        "nombre": nombre,
        "tipo": tipo,
        "tipo_documento": "DNI",
        "nro_documento": nro or f"41{_TAIL[:8]}",
        "direccion": "Av. Alta 123",
        "id_localidad": id_localidad,
    }
    if extra:
        cuerpo.update(extra)
    return cuerpo


def test_crear_socio_201_ignora_descuento_e_id_cliente(client, seed):
    nombre = f"Cliente post socio {_TAIL}"
    cuerpo = _cuerpo_post(
        nombre,
        "socio",
        seed["primera"],
        nro=f"41{_TAIL[:8]}",
        # Contract never accepts them: descuento is GENERATED ALWAYS and
        # id_cliente is identity. Both extras must be ignored, not echoed.
        extra={"descuento": 99.9, "id_cliente": 777777},
    )

    response = client.post("/clientes", json=cuerpo)

    assert response.status_code == 201, response.text
    body = response.json()
    assert set(body) == DETALLE_KEYS
    assert body["id_cliente"] != 777777
    assert body["nombre"] == nombre
    assert body["tipo"] == "socio"
    # The database computed the discount from tipo (R-002).
    assert body["descuento"] == 10.0
    assert body["permisos"] == []
    assert body["zona_cobertura"] is None
    assert body["pais_destino_principal"] is None

    detalle = client.get(f"/clientes/{body['id_cliente']}")
    assert detalle.status_code == 200, detalle.text
    assert detalle.json()["descuento"] == 10.0
    assert detalle.json()["nombre"] == nombre


def test_crear_distribuidor_201_con_su_subtipo(client, seed):
    nombre = f"Cliente post distri {_TAIL}"
    cuerpo = _cuerpo_post(
        nombre,
        "distribuidor",
        seed["primera"],
        nro=f"42{_TAIL[:8]}",
        extra={"zona_cobertura": "Zona Norte", "nro_habilitacion": f"HAB-HTTP-{_TAIL}"},
    )

    response = client.post("/clientes", json=cuerpo)

    assert response.status_code == 201, response.text
    body = response.json()
    assert set(body) == DETALLE_KEYS
    assert body["tipo"] == "distribuidor"
    assert body["descuento"] == 20.0
    assert body["zona_cobertura"] == "Zona Norte"
    assert body["nro_habilitacion"] == f"HAB-HTTP-{_TAIL}"
    assert body["pais_destino_principal"] is None

    detalle = client.get(f"/clientes/{body['id_cliente']}").json()
    assert detalle["zona_cobertura"] == "Zona Norte"
    assert detalle["nro_habilitacion"] == f"HAB-HTTP-{_TAIL}"


def test_crear_exportador_201_con_permiso_en_la_misma_transaccion(client, seed):
    nombre = f"Cliente post export {_TAIL}"
    permiso = {
        "cod_permiso": f"EXP-POST-{_TAIL}",
        "fecha_emision": "2026-02-01",
        "fecha_vencimiento": "2027-02-01",
    }
    cuerpo = _cuerpo_post(
        nombre,
        "exportador",
        seed["segunda"],
        nro=f"43{_TAIL[:8]}",
        extra={"pais_destino_principal": "Chile", "permisos": [permiso]},
    )

    response = client.post("/clientes", json=cuerpo)

    assert response.status_code == 201, response.text
    body = response.json()
    assert set(body) == DETALLE_KEYS
    assert body["tipo"] == "exportador"
    assert body["descuento"] == 30.0
    assert body["pais_destino_principal"] == "Chile"
    assert body["permisos"] == [permiso]

    detalle = client.get(f"/clientes/{body['id_cliente']}").json()
    assert detalle["permisos"] == [permiso]
    assert detalle["pais_destino_principal"] == "Chile"


def test_crear_cliente_documento_duplicado_409(client, seed):
    nro = f"44{_TAIL[:8]}"
    cuerpo = _cuerpo_post(f"Cliente post dup {_TAIL}", "socio", seed["primera"], nro=nro)
    client.post("/clientes", json=cuerpo)

    response = client.post("/clientes", json=cuerpo)

    assert response.status_code == 409, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "23505"
    listado = client.get("/clientes", params={"q": f"Cliente post dup {_TAIL}"}).json()
    assert listado["meta"]["total"] == 1


def test_crear_cliente_check_violado_422_y_atomico(client, seed):
    nombre = f"Cliente post check {_TAIL}"
    permiso_invalido = {
        "cod_permiso": f"EXP-CHK-{_TAIL}",
        # ck_permiso_fechas: vencimiento must be after emision (23514).
        "fecha_emision": "2027-02-01",
        "fecha_vencimiento": "2026-02-01",
    }
    cuerpo = _cuerpo_post(
        nombre,
        "exportador",
        seed["segunda"],
        nro=f"45{_TAIL[:8]}",
        extra={"pais_destino_principal": "Brasil", "permisos": [permiso_invalido]},
    )

    response = client.post("/clientes", json=cuerpo)

    assert response.status_code == 422, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "23514"
    listado = client.get("/clientes", params={"q": nombre}).json()
    assert listado["meta"]["total"] == 0


# ---------------------------------------------------------------------------
# Escritura · PUT /clientes/{id} y DELETE /clientes/{id}
# ---------------------------------------------------------------------------


def test_actualizar_cliente_200_actualiza_solo_lo_enviado(client, pool, localidades):
    creado = _crear_repo(pool, localidades, 21, tipo="distribuidor")
    id_cliente = creado["id_cliente"]

    # ``tipo`` is absent from ClienteUpdate: sending it is ignored, never applied.
    response = client.put(
        f"/clientes/{id_cliente}",
        json={"direccion": "Direccion editada 456", "tipo": "exportador"},
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert set(body) == DETALLE_KEYS
    assert body["direccion"] == "Direccion editada 456"
    assert body["tipo"] == "distribuidor"
    # Untouched fields keep their seeded values (partial update).
    assert body["nombre"] == f"{NOMBRE} 21"
    assert body["nro_documento"] == f"40{_TAIL[:6]}21"
    assert body["descuento"] == 20.0
    assert body["zona_cobertura"] == "Zona Sur"

    detalle = client.get(f"/clientes/{id_cliente}").json()
    assert detalle["direccion"] == "Direccion editada 456"
    assert detalle["tipo"] == "distribuidor"
    assert detalle["nombre"] == f"{NOMBRE} 21"


def test_actualizar_cliente_inexistente_404(client):
    response = client.put("/clientes/999999999", json={"nombre": "No existe"})

    assert response.status_code == 404, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "NOT_FOUND"
    assert "999999999" in body["mensaje"]


def test_eliminar_cliente_204_deja_de_existir(client, pool, localidades):
    creado = _crear_repo(pool, localidades, 22)
    id_cliente = creado["id_cliente"]

    response = client.delete(f"/clientes/{id_cliente}")

    assert response.status_code == 204
    assert response.content == b""
    assert client.get(f"/clientes/{id_cliente}").status_code == 404


def test_eliminar_cliente_inexistente_404(client):
    response = client.delete("/clientes/999999999")

    assert response.status_code == 404, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "NOT_FOUND"
    assert "999999999" in body["mensaje"]


def test_eliminar_cliente_con_comprobante_409_y_persiste(client, pool, localidades, sala):
    creado = _crear_repo(pool, localidades, 23)
    id_cliente = creado["id_cliente"]
    comprobante = comprobantes.crear_comprobante(
        pool, id_cliente=id_cliente, id_sala=sala["id"], renglones=[]
    )
    assert comprobante["id_cliente"] == id_cliente

    response = client.delete(f"/clientes/{id_cliente}")

    assert response.status_code == 409, response.text
    body = response.json()
    assert set(body) == ERROR_KEYS
    assert body["codigo"] == "23503"
    assert client.get(f"/clientes/{id_cliente}").status_code == 200
