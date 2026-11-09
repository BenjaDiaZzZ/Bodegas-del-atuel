#!/usr/bin/env python3
"""Carga masiva determinística para el TPI «Bodegas del Atuel».

Genera un dataset reproducible a partir de semillas fijas (random.seed(42),
Faker.seed(42)) y los catálogos CSV de db/seed/catalogos/. Usa COPY para
tablas volumétricas e INSERT para vino (GENERATED ALWAYS).

Uso:
    python3 db/seed/seed.py --scale small --fecha-base 2026-01-01
    python3 db/seed/seed.py --scale full --fecha-base 2026-01-01 --benchmark
"""

from __future__ import annotations

import argparse
import csv
import random
import sys
import time
from datetime import date, timedelta
from pathlib import Path

import psycopg
from faker import Faker

SEED = 42
CATALOGOS = Path(__file__).parent / "catalogos"

# ---------------------------------------------------------------------------
# Escalas
# ---------------------------------------------------------------------------

SMALL = {
    "bodegas": 5, "transportistas": 5, "fincas": 3, "salas": 4,
    "empleados": 10, "parcelas": 10, "vinos": 20, "clientes": 15,
    "lotes": 10, "comprobantes": 50, "ingresos": 20, "transferencias": 15,
    "analisis": 10,
}

FULL = {
    "bodegas": 20, "transportistas": 20, "fincas": 50, "salas": 20,
    "empleados": 100, "parcelas": 200, "vinos": 300, "clientes": 200,
    "lotes": 500, "comprobantes": 20000, "ingresos": 500, "transferencias": 500,
    "analisis": 500,
}


def load_csv(name: str) -> list[dict]:
    with open(CATALOGOS / name, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def random_cuit() -> str:
    """Genera un CUIT válido de 11 dígitos (formato cuit_dom)."""
    return f"{random.randint(10, 99)}{random.randint(10000000, 99999999)}{random.randint(0, 9)}"


# ---------------------------------------------------------------------------
# Carga de datos con COPY
# ---------------------------------------------------------------------------

def copy_rows(cur, table: str, columns: list[str], rows: list[tuple]) -> None:
    if not rows:
        return
    with cur.copy(f"COPY {table} ({', '.join(columns)}) FROM STDIN") as copy:
        for row in rows:
            copy.write_row(row)


def insert_vino_batch(cur, rows: list[tuple]) -> list[int]:
    """INSERT para vino (GENERATED ALWAYS) y retorna los IDs generados."""
    ids = []
    for row in rows:
        cur.execute(
            "INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml,"
            " graduacion, precio_venta, cuit_bodega)"
            " VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING cod_vino",
            row,
        )
        ids.append(cur.fetchone()[0])
    return ids


# ---------------------------------------------------------------------------
# Generadores
# ---------------------------------------------------------------------------

def disable_triggers(cur, tables: list[str]) -> None:
    for t in tables:
        cur.execute(f'ALTER TABLE {t} DISABLE TRIGGER USER')


def enable_triggers(cur, tables: list[str]) -> None:
    for t in tables:
        cur.execute(f'ALTER TABLE {t} ENABLE TRIGGER USER')


def recalc_totales(cur) -> None:
    """Recalcula subtotal/descuento/total de todos los comprobantes."""
    cur.execute("""
        UPDATE comprobante cb
           SET subtotal  = COALESCE(s.sub, 0),
               descuento = COALESCE(s.desc, 0),
               total     = COALESCE(s.sub, 0) - COALESCE(s.desc, 0)
          FROM (
            SELECT nro_comprobante,
                   SUM(subtotal + descuento) AS sub,
                   SUM(descuento)            AS desc
              FROM renglon_comprobante
             GROUP BY nro_comprobante
          ) s
         WHERE cb.nro_comprobante = s.nro_comprobante
    """)
    # Los comprobantes sin renglones quedan en 0
    cur.execute("""
        UPDATE comprobante SET subtotal=0, descuento=0, total=0
         WHERE nro_comprobante NOT IN (SELECT DISTINCT nro_comprobante FROM renglon_comprobante)
    """)


# ---------------------------------------------------------------------------
# Seed principal
# ---------------------------------------------------------------------------

def run_seed(conn, scale_name: str, fecha_base: date, benchmark: bool = False) -> None:
    cfg = SMALL if scale_name == "small" else FULL
    random.seed(SEED)
    Faker.seed(SEED)
    fake = Faker("es_AR")

    # Diccionarios nombre -> id para resolver FKs
    ids: dict[str, dict[str, int]] = {
        "localidad": {}, "cepa": {}, "maridaje": {}, "bodega": {},
        "transportista": {}, "finca": {}, "sala": {}, "empleado": {},
        "vino": {}, "cliente": {},
    }
    # Listas planas para referencias
    vino_ids: list[int] = []
    cliente_ids: list[int] = []
    lote_keys: list[tuple[int, int, int]] = []  # (id_finca, nro_parcela, campania)
    parcela_keys: list[tuple[int, int]] = []    # (id_finca, nro_parcela)

    with conn.cursor() as cur:
        print(f"== Seed scale={scale_name} fecha_base={fecha_base} ==")

        # -- 1-3. Catálogos CSV -------------------------------------------
        print("  [1/27] localidad (CSV)")
        localidades = load_csv("localidades_mendoza.csv")
        loc_rows = []
        for i, row in enumerate(localidades, start=1):
            loc_rows.append((
                i, row["codigo_postal"], row["nombre"],
                row["provincia"], fake.name(),
            ))
            ids["localidad"][row["nombre"]] = i
        copy_rows(cur, "localidad",
                  ["id_localidad", "codigo_postal", "nombre", "provincia", "encargado_regional"],
                  loc_rows)

        print("  [2/27] cepa (CSV)")
        cepas = load_csv("cepas.csv")
        cepa_rows = [(i, r["nombre"], r["tipo"]) for i, r in enumerate(cepas, start=1)]
        for i, r in enumerate(cepas, start=1):
            ids["cepa"][r["nombre"]] = i
        copy_rows(cur, "cepa", ["id_cepa", "nombre", "tipo"], cepa_rows)

        print("  [3/27] maridaje (CSV)")
        maridajes = load_csv("maridajes.csv")
        mar_rows = [(i, r["nombre"], int(r["temperatura_servicio"]))
                    for i, r in enumerate(maridajes, start=1)]
        for i, r in enumerate(maridajes, start=1):
            ids["maridaje"][r["nombre"]] = i
        copy_rows(cur, "maridaje", ["id_maridaje", "nombre", "temperatura_servicio"], mar_rows)

        # -- 4. Bodegas ---------------------------------------------------
        print("  [4/27] bodega")
        bodegas = []
        for i in range(1, cfg["bodegas"] + 1):
            cuit = random_cuit()
            bodegas.append((cuit, fake.company(), fake.address().replace("\n", ", ")))
            ids["bodega"][cuit] = i
        copy_rows(cur, "bodega", ["cuit", "razon_social", "domicilio"], bodegas)

        # -- 5. Transportistas -------------------------------------------
        print("  [5/27] transportista")
        trans_rows = []
        for i in range(1, cfg["transportistas"] + 1):
            cuit = random_cuit()
            trans_rows.append((i, fake.company(), cuit, fake.email(),
                               fake.phone_number()[:20], fake.address().replace("\n", ", ")))
            ids["transportista"][cuit] = i
        copy_rows(cur, "transportista",
                  ["id_transportista", "razon_social", "cuit", "email", "telefono", "domicilio"],
                  trans_rows)

        # -- 6. Fincas ---------------------------------------------------
        print("  [6/27] finca")
        finca_rows = []
        for i in range(1, cfg["fincas"] + 1):
            finca_rows.append((i, fake.company(), round(random.uniform(5, 500), 2),
                               fake.city(), "Mendoza"))
            ids["finca"][str(i)] = i
        copy_rows(cur, "finca",
                  ["id_finca", "nombre", "superficie_hectareas", "departamento", "provincia"],
                  finca_rows)

        # -- 7. Salas ----------------------------------------------------
        print("  [7/27] sala")
        sala_rows = []
        loc_nombres = list(ids["localidad"].keys())
        for i in range(1, cfg["salas"] + 1):
            loc_id = ids["localidad"][random.choice(loc_nombres)]
            # U4: salas con cierre Lunes(1) y Miércoles(3)
            dia = random.choice([1, 3, 2, 4, 5]) if i <= 4 else random.randint(1, 7)
            if i == 1:
                dia = 1  # Lunes
            elif i == 2:
                dia = 3  # Miércoles
            sala_rows.append((i, fake.address().replace("\n", ", "), dia, loc_id))
            ids["sala"][str(i)] = i
        copy_rows(cur, "sala", ["id_sala", "direccion", "dia_cierre_semanal", "id_localidad"], sala_rows)

        # -- 8. Empleados ------------------------------------------------
        print("  [8/27] empleado")
        emp_rows = []
        for i in range(1, cfg["empleados"] + 1):
            cuit = random_cuit()
            # U2/D3: mezcla de antigüedad > 5 y < 5 años
            if i <= cfg["empleados"] // 2:
                ingreso = fecha_base - timedelta(days=365 * random.randint(6, 20))
            else:
                ingreso = fecha_base - timedelta(days=random.randint(30, 365 * 4))
            salario = round(random.uniform(300000, 1200000), 2)
            sala_id = random.randint(1, cfg["salas"])
            emp_rows.append((cuit, fake.name(), ingreso, salario, sala_id))
            ids["empleado"][cuit] = i
        copy_rows(cur, "empleado",
                  ["cuit", "nombre", "fecha_ingreso", "salario", "id_sala"], emp_rows)

        # -- 9. Parcelas -------------------------------------------------
        print("  [9/27] parcela")
        par_rows = []
        nro_par = 0
        for finca_id in range(1, cfg["fincas"] + 1):
            for _ in range(random.randint(1, max(1, cfg["parcelas"] // cfg["fincas"]))):
                nro_par += 1
                cepa_id = random.randint(1, len(cepa_rows))
                par_rows.append((finca_id, nro_par,
                                 round(random.uniform(1, 50), 2),
                                 random.randint(1995, 2020), cepa_id))
                parcela_keys.append((finca_id, nro_par))
        copy_rows(cur, "parcela",
                  ["id_finca", "nro_parcela", "superficie_hectareas", "anio_plantacion", "id_cepa"],
                  par_rows)

        # -- 10. Vinos (INSERT por GENERATED ALWAYS) ----------------------
        print("  [10/27] vino")
        tipos_vino = [r["tipo"] for r in load_csv("tipos_vino.csv")]
        presentaciones = [int(r["presentacion_ml"]) for r in load_csv("presentaciones.csv")]
        bodega_cuits = list(ids["bodega"].keys())
        vino_rows = []
        for i in range(1, cfg["vinos"] + 1):
            nombre = f"{fake.word().title()} {random.choice(['Reserva', 'Clásico', 'Especial', 'Gran'])}"
            tipo = random.choice(tipos_vino)
            anada = random.randint(2015, 2024)
            pres = random.choice(presentaciones)
            grad = round(random.uniform(5.5, 19.5), 2)
            precio = round(random.uniform(1500, 25000), 2)
            cuit = random.choice(bodega_cuits)
            vino_rows.append((nombre, tipo, anada, pres, grad, precio, cuit))
        # I6: vino específico
        vino_rows.append(("Malbec Reserva", "tinto", 2020, 750, 14.5, 8500.00,
                          random.choice(bodega_cuits)))
        # I2: tintos con graduación >= 14
        for _ in range(5):
            vino_rows.append((f"Alto {fake.word().title()}", "tinto", 2021, 750,
                              round(random.uniform(14.0, 18.5), 2),
                              round(random.uniform(3000, 18000), 2),
                              random.choice(bodega_cuits)))
        vino_ids = insert_vino_batch(cur, vino_rows)
        for i, vid in enumerate(vino_ids):
            ids["vino"][vino_rows[i][0] + str(i)] = vid

        # -- 11. Clientes ------------------------------------------------
        print("  [11/27] cliente")
        cli_rows = []
        for i in range(1, cfg["clientes"] + 1):
            tipo = random.choice(["socio", "distribuidor", "exportador"])
            td = random.choice(["DNI", "CUIT", "CUIL", "PASAPORTE"])
            nd = f"{random.randint(10000000, 99999999)}"
            loc_id = ids["localidad"][random.choice(loc_nombres)]
            # D1/D4/D6: algunos socios con antigüedad > 5 años
            if tipo == "socio" and i <= 5:
                alta = fecha_base - timedelta(days=365 * 5 + 30)
            else:
                alta = fecha_base - timedelta(days=random.randint(1, 365 * 8))
            cli_rows.append((i, fake.name(), tipo, td, nd,
                             fake.address().replace("\n", ", "), loc_id, alta))
            ids["cliente"][str(i)] = i
        copy_rows(cur, "cliente",
                  ["id_cliente", "nombre", "tipo", "tipo_documento", "nro_documento",
                   "direccion", "id_localidad", "fecha_alta"], cli_rows)
        cliente_ids = list(range(1, cfg["clientes"] + 1))

        # -- 12. Lote uva ------------------------------------------------
        print("  [12/27] lote_uva")
        lote_rows = []
        used_lote_keys = set()
        for i in range(1, cfg["lotes"] + 1):
            for _attempt in range(50):
                finca_id, nro_par = random.choice(parcela_keys)
                campania = random.randint(2018, 2025)
                lk = (finca_id, nro_par, campania)
                if lk not in used_lote_keys:
                    used_lote_keys.add(lk)
                    break
            else:
                continue  # skip if no unique combo found
            fecha = date(campania, random.randint(1, 12), random.randint(1, 28))
            kilos = round(random.uniform(100, 50000), 2)
            cuit = random.choice(bodega_cuits)
            lote_rows.append((i, finca_id, nro_par, campania, fecha, kilos, cuit))
            lote_keys.append((finca_id, nro_par, campania))
        copy_rows(cur, "lote_uva",
                  ["nro_lote", "id_finca", "nro_parcela", "campania", "fecha_cosecha",
                   "kilos_cosechados", "cuit_bodega"], lote_rows)

        # -- 13. Composición (suma 100) ---------------------------------
        print("  [13/27] composicion")
        comp_rows = []
        n_cepas = len(cepa_rows)
        for vid in vino_ids:
            n = random.randint(2, min(3, n_cepas))
            seleccion = random.sample(range(1, n_cepas + 1), n)
            pct = [round(random.uniform(10, 60), 2) for _ in range(n)]
            total = sum(pct)
            pct = [round(p * 100.0 / total, 2) for p in pct]
            diff = round(100.0 - sum(pct), 2)
            pct[-1] = round(pct[-1] + diff, 2)
            for cepa_id, p in zip(seleccion, pct):
                comp_rows.append((vid, cepa_id, p))
        copy_rows(cur, "composicion", ["cod_vino", "id_cepa", "porcentaje"], comp_rows)

        # -- 14. Vino × maridaje -----------------------------------------
        print("  [14/27] vino_maridaje")
        vm_rows = []
        mar_ids = list(ids["maridaje"].values())
        for vid in vino_ids:
            for mid in random.sample(mar_ids, min(len(mar_ids), random.randint(1, 3))):
                vm_rows.append((vid, mid))
        copy_rows(cur, "vino_maridaje", ["cod_vino", "id_maridaje"], vm_rows)

        # -- 15. Subtipos de cliente -------------------------------------
        print("  [15/27] socio/distribuidor/exportador")
        socios, dists, exps = [], [], []
        used_hab = set()
        for i in range(1, cfg["clientes"] + 1):
            cur.execute("SELECT tipo FROM cliente WHERE id_cliente = %s", (i,))
            t = cur.fetchone()[0]
            if t == "socio":
                socios.append((i,))
            elif t == "distribuidor":
                hab = f"HAB-{i:04d}"
                while hab in used_hab:
                    hab = f"HAB-{random.randint(1000, 9999)}"
                used_hab.add(hab)
                dists.append((i, fake.city(), hab))
            else:
                exps.append((i, random.choice(["Chile", "Brasil", "Uruguay", "EE.UU.", "España"])))
        copy_rows(cur, "socio", ["id_cliente"], socios)
        copy_rows(cur, "distribuidor", ["id_cliente", "zona_cobertura", "nro_habilitacion"], dists)
        copy_rows(cur, "exportador", ["id_cliente", "pais_destino_principal"], exps)

        # -- 16. Permisos de exportación (U6) ----------------------------
        print("  [16/27] permiso_exportacion")
        perm_rows = []
        pid = 0
        for e in exps:
            cid = e[0]
            n_perm = random.randint(4, 8) if random.random() < 0.3 else random.randint(1, 3)
            for j in range(n_perm):
                pid += 1
                emision = fecha_base - timedelta(days=random.randint(30, 700))
                venc = emision + timedelta(days=random.randint(90, 365))
                perm_rows.append((cid, f"PERM-{pid:04d}", emision, venc))
        copy_rows(cur, "permiso_exportacion",
                  ["id_cliente", "cod_permiso", "fecha_emision", "fecha_vencimiento"], perm_rows)

        # -- 17. Transportista × localidad -------------------------------
        print("  [17/27] transportista_localidad")
        tl_rows = []
        for tid in range(1, cfg["transportistas"] + 1):
            for lid in random.sample(range(1, len(loc_rows) + 1), min(3, len(loc_rows))):
                tl_rows.append((tid, lid))
        copy_rows(cur, "transportista_localidad",
                  ["id_transportista", "id_localidad"], tl_rows)

        # -- 18. Análisis de calidad -------------------------------------
        print("  [18/27] analisis_calidad")
        an_rows = []
        for i in range(1, cfg["analisis"] + 1):
            lk = random.choice(lote_keys)
            # Buscar nro_lote correspondiente
            cur.execute(
                "SELECT nro_lote FROM lote_uva WHERE id_finca=%s AND nro_parcela=%s AND campania=%s",
                lk,
            )
            r = cur.fetchone()
            if not r:
                continue
            an_rows.append((i, r[0], fecha_base - timedelta(days=random.randint(1, 365)),
                            round(random.uniform(15, 30), 2),
                            round(random.uniform(2.8, 4.2), 2),
                            round(random.uniform(3, 12), 2)))
        copy_rows(cur, "analisis_calidad",
                  ["id_analisis", "nro_lote", "fecha", "grado_brix", "ph", "acidez_total"], an_rows)

        # -- 19-20. Comprobantes + renglones (triggers desactivados) -----
        print("  [19/27] comprobante (triggers OFF)")
        trigger_tables = ["renglon_comprobante", "comprobante",
                          "ingreso", "transferencia",
                          "renglon_ingreso", "renglon_transferencia"]
        disable_triggers(cur, trigger_tables)

        comp_cb_rows = []
        renglon_rows = []
        cb_id = 0
        reng_id = 0
        for _ in range(cfg["comprobantes"]):
            cb_id += 1
            cid = random.choice(cliente_ids)
            sid = random.randint(1, cfg["salas"])
            # D1: comprobantes de socios con > 5 años
            if cb_id <= 5:
                fecha = fecha_base - timedelta(days=365 * 5 + 30)
            else:
                fecha = fecha_base - timedelta(days=random.randint(1, 365 * 6))
            comp_cb_rows.append((cb_id, fecha, cid, sid, 0, 0, 0))
            n_reng = random.randint(1, min(5, len(vino_ids)))
            for vid in random.sample(vino_ids, n_reng):
                reng_id += 1
                cant = random.randint(1, 12)
                precio = round(random.uniform(1500, 25000), 2)
                desc = round(precio * cant * 0.10, 2)  # socio 10% approx
                sub = round(precio * cant - desc, 2)
                renglon_rows.append((cb_id, vid, cant, precio, desc, sub))

        # D5: ingresos procesados > 365 días (se generan más abajo)

        copy_rows(cur, "comprobante",
                  ["nro_comprobante", "fecha", "id_cliente", "id_sala",
                   "subtotal", "descuento", "total"], comp_cb_rows)

        print("  [20/27] renglon_comprobante (triggers OFF)")
        # Adaptar escala full: si se pide más renglones, multiplicar
        if scale_name == "full":
            extra = max(0, 350000 - len(renglon_rows))
            used_pairs = {(r[0], r[1]) for r in renglon_rows}
            for _ in range(extra):
                reng_id += 1
                cb_ref = random.randint(1, cb_id)
                # Find a vino not yet used for this comprobante
                candidates = [v for v in vino_ids if (cb_ref, v) not in used_pairs]
                if not candidates:
                    continue
                vid = random.choice(candidates)
                used_pairs.add((cb_ref, vid))
                cant = random.randint(1, 6)
                precio = round(random.uniform(1500, 25000), 2)
                desc = round(precio * cant * 0.10, 2)
                sub = round(precio * cant - desc, 2)
                renglon_rows.append((cb_ref, vid, cant, precio, desc, sub))

        copy_rows(cur, "renglon_comprobante",
                  ["nro_comprobante", "cod_vino", "cantidad",
                   "precio_unitario", "descuento", "subtotal"], renglon_rows)

        # -- 21-22. Ingresos + renglones ---------------------------------
        print("  [21/27] ingreso")
        ing_rows = []
        ing_reng = []
        for i in range(1, cfg["ingresos"] + 1):
            tid = random.randint(1, cfg["transportistas"])
            cuit = random.choice(bodega_cuits)
            # D5: procesados > 365 días
            if i <= 5:
                fecha = fecha_base - timedelta(days=400)
                estado = "procesado"
            else:
                fecha = fecha_base - timedelta(days=random.randint(1, 300))
                estado = random.choice(["procesado", "terminado", "en_confeccion"])
            ing_rows.append((i, fecha, estado, tid, cuit))
            for vid in random.sample(vino_ids, min(len(vino_ids), random.randint(1, 4))):
                ing_reng.append((i, vid, random.randint(1, 50)))
        copy_rows(cur, "ingreso",
                  ["cod_ingreso", "fecha", "estado", "id_transportista", "cuit_bodega"], ing_rows)
        copy_rows(cur, "renglon_ingreso",
                  ["cod_ingreso", "cod_vino", "cantidad"], ing_reng)

        # -- 23-24. Transferencias + renglones ---------------------------
        print("  [23/27] transferencia")
        tra_rows = []
        tra_reng = []
        for i in range(1, cfg["transferencias"] + 1):
            sid = random.randint(1, cfg["salas"])
            fecha = fecha_base - timedelta(days=random.randint(1, 180))
            estado = random.choice(["procesado", "terminado", "en_confeccion"])
            tra_rows.append((i, sid, fecha, estado))
            for vid in random.sample(vino_ids, min(len(vino_ids), random.randint(1, 3))):
                tra_reng.append((i, vid, random.randint(1, 30)))
        copy_rows(cur, "transferencia",
                  ["nro_solicitud", "id_sala", "fecha_confeccion", "estado"], tra_rows)
        copy_rows(cur, "renglon_transferencia",
                  ["nro_solicitud", "cod_vino", "cantidad"], tra_reng)

        # -- 25-26. Stock ------------------------------------------------
        print("  [25/27] stock_deposito")
        sd_rows = [(vid, random.randint(50, 500)) for vid in vino_ids]
        copy_rows(cur, "stock_deposito", ["cod_vino", "cantidad"], sd_rows)

        print("  [26/27] stock_sala")
        ss_rows = []
        for sid in range(1, cfg["salas"] + 1):
            for vid in random.sample(vino_ids, min(len(vino_ids), 10)):
                ss_rows.append((sid, vid, random.randint(0, 100)))
        copy_rows(cur, "stock_sala", ["id_sala", "cod_vino", "cantidad"], ss_rows)

        # -- 27. Recalcular y reactivar triggers --------------------------
        print("  [27/27] recalcular totales y reactivar triggers")
        recalc_totales(cur)
        enable_triggers(cur, trigger_tables)

        # COPY inserts explicit IDs, so synchronize each identity sequence.
        cur.execute("""
            DO $$
            DECLARE
                item record;
                max_id bigint;
                sequence_name text;
            BEGIN
                FOR item IN
                    SELECT * FROM (VALUES
                        ('analisis_calidad', 'id_analisis'),
                        ('auditoria_precio', 'id_auditoria'),
                        ('cepa', 'id_cepa'),
                        ('cliente', 'id_cliente'),
                        ('comprobante', 'nro_comprobante'),
                        ('finca', 'id_finca'),
                        ('ingreso', 'cod_ingreso'),
                        ('localidad', 'id_localidad'),
                        ('maridaje', 'id_maridaje'),
                        ('sala', 'id_sala'),
                        ('transferencia', 'nro_solicitud'),
                        ('transportista', 'id_transportista'),
                        ('vino', 'cod_vino')
                    ) AS identities(table_name, column_name)
                LOOP
                    EXECUTE format('SELECT MAX(%I) FROM %I', item.column_name, item.table_name)
                       INTO max_id;
                    sequence_name := pg_get_serial_sequence(
                        format('%I.%I', 'public', item.table_name), item.column_name);
                    PERFORM setval(sequence_name, COALESCE(max_id, 1), max_id IS NOT NULL);
                END LOOP;
            END $$;
        """)

        conn.commit()
        print(f"== Seed completo: {scale_name} ==")


# ---------------------------------------------------------------------------
# Benchmark
# ---------------------------------------------------------------------------

def run_benchmark(conn) -> None:
    print("== Benchmark: INSERT fila por fila vs COPY ==")
    n = 5000
    with conn.cursor() as cur:
        # Preparar tabla temporal
        cur.execute("CREATE TEMP TABLE bench (id int, val text)")

        # INSERT fila por fila
        t0 = time.perf_counter()
        for i in range(n):
            cur.execute("INSERT INTO bench VALUES (%s, %s)", (i, f"row-{i}"))
        t_insert = time.perf_counter() - t0
        cur.execute("DELETE FROM bench")

        # COPY por lotes
        t0 = time.perf_counter()
        with cur.copy("COPY bench (id, val) FROM STDIN") as copy:
            for i in range(n):
                copy.write_row((i, f"row-{i}"))
        t_copy = time.perf_counter() - t0

        cur.execute("DROP TABLE bench")
        conn.commit()

    print(f"  INSERT fila por fila: {t_insert:.3f}s para {n} filas")
    print(f"  COPY por lotes:       {t_copy:.3f}s para {n} filas")
    print(f"  Speedup:              {t_insert / t_copy:.1f}x")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Seed determinístico para Bodegas del Atuel")
    parser.add_argument("--scale", choices=["small", "full"], default="small")
    parser.add_argument("--fecha-base", type=date.fromisoformat, default=date.today())
    parser.add_argument("--db-url", default="postgresql://bodegas@localhost:5433/bodegas_del_atuel")
    parser.add_argument("--benchmark", action="store_true")
    args = parser.parse_args()

    if args.benchmark:
        with psycopg.connect(args.db_url) as conn:
            run_benchmark(conn)
        return

    with psycopg.connect(args.db_url) as conn:
        run_seed(conn, args.scale, args.fecha_base, args.benchmark)


if __name__ == "__main__":
    main()
