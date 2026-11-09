"""HTTP integration tests for the GET vinos endpoints (task 6.5).

The pool connects as ``app_rw``; only the app_rw-tested repository
functions seed wines. Catalog tables app_rw cannot write (bodega, cepa,
maridaje) are created with a superuser connection. Every marker value
includes a per-run unique suffix, and the fixtures tear down FK-safe.
"""

import os
import uuid
from decimal import Decimal

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row

import app.main as main
from app.config import Settings
from app.repos import vinos

_TAIL = uuid.uuid4().hex[:10]
PAGE_KEYS = {"data", "meta"}
META_KEYS = {"page", "per_page", "total", "total_pages"}
RESUMEN_KEYS = {
    "cod_vino",
    "nombre_comercial",
    "tipo",
    "anada",
    "presentacion_ml",
    "graduacion",
    "precio_venta",
    "cuit_bodega",
    "bodega",
}
DETALLE_KEYS = RESUMEN_KEYS | {"composicion", "maridajes", "stock"}

_CEPAS = (f"Cepa endp {_TAIL} 1", f"Cepa endp {_TAIL} 2")


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
def catalogo(pool):
    """Creates bodega + 2 cepas + 1 maridaje; teardown deletes FK-safe."""
    cuit = "93" + f"{(uuid.uuid4().int % 10**9):09d}"
    superuser = _superuser()
    try:
        superuser.execute(
            "INSERT INTO bodega (cuit, razon_social, domicilio) VALUES (%s, 'Bodega endpoints', 'Domicilio endpoints')"
            " ON CONFLICT (cuit) DO NOTHING",
            (cuit,),
        )
        cepas = [
            superuser.execute(
                "INSERT INTO cepa (nombre, tipo) VALUES (%s, 'tinta') RETURNING id_cepa",
                (nombre,),
            ).fetchone()[0]
            for nombre in _CEPAS
        ]
        maridaje = superuser.execute(
            "INSERT INTO maridaje (nombre, temperatura_servicio) VALUES (%s, 17.5) RETURNING id_maridaje",
            (f"Maridaje endp {_TAIL}",),
        ).fetchone()[0]
        superuser.commit()
        yield {"cuit": cuit, "cepas": cepas, "maridaje": maridaje}
    finally:
        try:
            superuser.execute(
                "DELETE FROM auditoria_precio WHERE cod_vino IN"
                " (SELECT cod_vino FROM vino WHERE cuit_bodega = %s)",
                (cuit,),
            )
            superuser.execute(
                "DELETE FROM stock_deposito WHERE cod_vino IN"
                " (SELECT cod_vino FROM vino WHERE cuit_bodega = %s)",
                (cuit,),
            )
            superuser.execute(
                "DELETE FROM stock_sala WHERE cod_vino IN"
                " (SELECT cod_vino FROM vino WHERE cuit_bodega = %s)",
                (cuit,),
            )
            superuser.execute("DELETE FROM vino WHERE cuit_bodega = %s", (cuit,))
            superuser.execute("DELETE FROM cepa WHERE nombre LIKE %s", (f"Cepa endp {_TAIL}%",))
            superuser.execute("DELETE FROM maridaje WHERE nombre = %s", (f"Maridaje endp {_TAIL}",))
            superuser.execute("DELETE FROM bodega WHERE cuit = %s", (cuit,))
            superuser.commit()
        finally:
            superuser.close()


@pytest.fixture(scope="module")
def seeded(pool, catalogo):
    """Creates 4 wines with distinctive markers; returns cods indexed by case."""

    def crear(nombre, tipo, anada, composicion):
        return vinos.crear_vino(pool, nombre_comercial=nombre, tipo=tipo, anada=anada,
                                presentacion_ml=750, graduacion=Decimal("13.50"),
                                precio_venta=Decimal("100.00"),
                                cuit_bodega=catalogo["cuit"],
                                composicion=composicion,
                                maridajes=[catalogo["maridaje"]])

    c1, c2 = catalogo["cepas"]
    tinto_2021 = crear(f"Tinto Loma Blanca {_TAIL}", "tinto", 2021,
                       [{"id_cepa": c1, "porcentaje": Decimal("70.00")},
                        {"id_cepa": c2, "porcentaje": Decimal("30.00")}])
    tinto_2022 = crear(f"Tinto Finca Alta {_TAIL}", "tinto", 2022,
                       [{"id_cepa": c1, "porcentaje": Decimal("100.00")}])
    blanco_2022 = crear(f"Blanco Rio Yeso {_TAIL}", "blanco", 2022,
                        [{"id_cepa": c2, "porcentaje": Decimal("100.00")}])
    rosado_2021 = crear(f"Rosado Atuel {_TAIL}", "rosado", 2021,
                        [{"id_cepa": c1, "porcentaje": Decimal("60.00")},
                         {"id_cepa": c2, "porcentaje": Decimal("40.00")}])

    return {
        "tinto_2021": tinto_2021,
        "tinto_2022": tinto_2022,
        "blanco_2022": blanco_2022,
        "rosado_2021": rosado_2021,
        "todos": [tinto_2021["cod_vino"], tinto_2022["cod_vino"],
                  blanco_2022["cod_vino"], rosado_2021["cod_vino"]],
        "tintos": [tinto_2021["cod_vino"], tinto_2022["cod_vino"]],
        "anada_2022": [tinto_2022["cod_vino"], blanco_2022["cod_vino"]],
        "cepa_2": [tinto_2021["cod_vino"], blanco_2022["cod_vino"], rosado_2021["cod_vino"]],
    }


def test_listar_vinos_200_devuelve_shape_contrato(client, seeded):
    response = client.get("/vinos", params={"nombre": _TAIL})

    assert response.status_code == 200
    body = response.json()
    assert set(body) == PAGE_KEYS
    assert set(body["meta"]) == META_KEYS
    assert body["meta"] == {"page": 1, "per_page": 20, "total": 4, "total_pages": 1}
    assert [item["cod_vino"] for item in body["data"]] == seeded["todos"]
    for item in body["data"]:
        assert set(item) == RESUMEN_KEYS


def test_filtro_nombre_devuelve_solo_el_vino_con_nivel_contenido(client, seeded):
    response = client.get("/vinos", params={"nombre": f"Loma Blanca {_TAIL}"})

    assert response.status_code == 200
    body = response.json()
    assert body["meta"]["total"] == 1
    assert [item["cod_vino"] for item in body["data"]] == [seeded["tinto_2021"]["cod_vino"]]


def test_filtro_tipo_devuelve_solo_tintos(client, seeded):
    response = client.get("/vinos", params={"tipo": "tinto"})

    assert response.status_code == 200
    body = response.json()
    assert body["meta"]["total"] == 2
    assert {item["cod_vino"] for item in body["data"]} == set(seeded["tintos"])


def test_filtro_id_cepa_devuelve_solo_vinos_con_esa_cepa(client, seeded, catalogo):
    response = client.get("/vinos", params={"id_cepa": catalogo["cepas"][1]})

    assert response.status_code == 200
    body = response.json()
    assert body["meta"]["total"] == 3
    assert {item["cod_vino"] for item in body["data"]} == set(seeded["cepa_2"])


def test_filtro_cuit_bodega_devuelve_solo_los_vinos_de_esa_bodega(client, seeded, catalogo):
    response = client.get("/vinos", params={"cuit_bodega": catalogo["cuit"]})

    assert response.status_code == 200
    body = response.json()
    assert body["meta"]["total"] == 4
    assert {item["cod_vino"] for item in body["data"]} == set(seeded["todos"])
    for item in body["data"]:
        assert item["cuit_bodega"] == catalogo["cuit"]
        assert item["bodega"] == "Bodega endpoints"


def test_filtro_anada_devuelve_los_vinos_de_esa_anada(client, seeded):
    response = client.get("/vinos", params={"anada": 2022})

    assert response.status_code == 200
    body = response.json()
    assert body["meta"]["total"] == 2
    assert {item["cod_vino"] for item in body["data"]} == set(seeded["anada_2022"])


def test_filtros_combinados_se_intersecan(client, seeded):
    response = client.get("/vinos", params={"tipo": "tinto", "anada": 2022, "nombre": "Finca Alta"})

    assert response.status_code == 200
    body = response.json()
    assert body["meta"]["total"] == 1
    assert [item["cod_vino"] for item in body["data"]] == [seeded["tinto_2022"]["cod_vino"]]


def test_paginacion_de_a_dos_devuelve_paginas_disjuntas(client, seeded):
    page1 = client.get("/vinos", params={"nombre": _TAIL, "page": 1, "per_page": 2}).json()
    page2 = client.get("/vinos", params={"nombre": _TAIL, "page": 2, "per_page": 2}).json()

    assert page1["meta"] == {"page": 1, "per_page": 2, "total": 4, "total_pages": 2}
    assert page2["meta"] == {"page": 2, "per_page": 2, "total": 4, "total_pages": 2}
    assert [item["cod_vino"] for item in page1["data"]] == seeded["todos"][:2]
    assert [item["cod_vino"] for item in page2["data"]] == seeded["todos"][2:]


def test_pagina_fuera_de_rango_devuelve_data_vacia_con_meta_consistente(client, seeded):
    response = client.get("/vinos", params={"nombre": _TAIL, "page": 9, "per_page": 2})

    assert response.status_code == 200
    body = response.json()
    assert body["data"] == []
    assert body["meta"] == {"page": 9, "per_page": 2, "total": 4, "total_pages": 2}


def test_filtro_sin_coincidencias_devuelve_pagina_vacia(client):
    response = client.get("/vinos", params={"nombre": uuid.uuid4().hex})

    assert response.status_code == 200
    body = response.json()
    assert body["data"] == []
    assert body["meta"] == {"page": 1, "per_page": 20, "total": 0, "total_pages": 0}


def test_obtener_vino_200_devuelve_ficha_completa(client, seeded, catalogo):
    response = client.get(f"/vinos/{seeded['tinto_2021']['cod_vino']}")

    assert response.status_code == 200
    body = response.json()
    assert set(body) == DETALLE_KEYS
    assert body["cod_vino"] == seeded["tinto_2021"]["cod_vino"]
    assert body["nombre_comercial"] == f"Tinto Loma Blanca {_TAIL}"
    assert body["tipo"] == "tinto"
    assert body["anada"] == 2021
    assert body["cuit_bodega"] == catalogo["cuit"]
    assert body["bodega"] == "Bodega endpoints"
    assert body["composicion"] == [
        {"id_cepa": catalogo["cepas"][0], "nombre": f"Cepa endp {_TAIL} 1", "porcentaje": 70.0},
        {"id_cepa": catalogo["cepas"][1], "nombre": f"Cepa endp {_TAIL} 2", "porcentaje": 30.0},
    ]
    assert body["maridajes"] == [
        {"id_maridaje": catalogo["maridaje"], "nombre": f"Maridaje endp {_TAIL}", "temperatura_servicio": 17.5}
    ]
    assert body["stock"] == {"deposito": 0, "salas": 0, "total": 0}


def test_obtener_vino_inexistente_devuelve_404_error_contrato(client):
    response = client.get("/vinos/999999999")

    assert response.status_code == 404
    body = response.json()
    assert set(body) == {"codigo", "mensaje", "detalle", "regla"}
    assert body["codigo"] == "NOT_FOUND"
    assert "999999999" in body["mensaje"]
    assert "detail" not in response.text
    assert "detail" not in body
