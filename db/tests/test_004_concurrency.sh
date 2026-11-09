#!/usr/bin/env bash
# =============================================================================
# test_004_concurrency.sh · TPI «Bodegas del Atuel»
# Regresion de concurrencia de sp_procesar_transferencia (RN-11).
#
# Objetivo original (TOCTOU): el conjunto (cod_vino, cantidad) que el
# procedimiento valida debe ser EXACTAMENTE el conjunto que resta del deposito y
# suma a la sala, aunque otra sesion intente editar renglon_transferencia en
# paralelo.
#
# Con los triggers de 005 (RN-12) la edicion concurrente ya no puede prosperar:
# un documento 'terminado' tiene sus renglones bloqueados, asi que la sesion B
# recibe [RN-12] y la sesion A sigue procesando el conjunto que valido (10).
# Este script ahora verifica AMBAS cosas: B es rechazada por RN-12 y el resultado
# final sigue siendo 90 / 10 / procesado.
#
# Metodo (interfaz publica, sin tocar el procedimiento):
#   1. La sesion C bloquea la fila stock_deposito del vino A (FOR UPDATE) y la
#      mantiene tomada unos segundos.
#   2. La sesion A ejecuta CALL sp_procesar_transferencia. En la version con la
#      proteccion, A queda esperando el lock del deposito; en la version con la
#      carrera, A ya leyo los renglones pero todavia no escribio.
#   3. Con A esperando, la sesion B intenta editar la cantidad del renglon
#      (10 -> 30): RN-12 la rechaza (P0001) porque el documento esta terminado.
#   4. C libera el lock; A termina.
#
# Resultado esperado (GREEN): B rechazada por [RN-12]; A proceso la cantidad que
# tenia bloqueada (10): stock_deposito = 90 y stock_sala = 10.
#
# Requiere una base con las migraciones 001-005 aplicadas. Usa las variables
# estandar de libpq (PGHOST, PGPORT, PGUSER, PGDATABASE).
#
# Uso:
#   PGHOST=localhost PGUSER=... PGDATABASE=... db/tests/test_004_concurrency.sh
# =============================================================================
set -euo pipefail

PSQL=(psql -X -q -v ON_ERROR_STOP=1)
NRO=""

cleanup() {
    "${PSQL[@]}" >/dev/null 2>&1 <<SQL || true
DELETE FROM stock_sala     WHERE id_sala = 1 AND cod_vino IN (SELECT cod_vino FROM vino WHERE nombre_comercial IN ('JD004 A','JD004 B'));
DELETE FROM stock_deposito WHERE cod_vino IN (SELECT cod_vino FROM vino WHERE nombre_comercial IN ('JD004 A','JD004 B'));
DELETE FROM transferencia  WHERE nro_solicitud = ${NRO:-0};
DELETE FROM vino           WHERE nombre_comercial IN ('JD004 A','JD004 B');
SQL
}
trap cleanup EXIT

echo "== setup =="
# Datos base minimos (idempotentes).
"${PSQL[@]}" >/dev/null <<'SQL'
BEGIN;
INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('20123456789', 'Bodega Prueba', 'Calle Falsa 123')
ON CONFLICT DO NOTHING;
INSERT INTO localidad (id_localidad, codigo_postal, nombre, provincia, encargado_regional)
VALUES (1, '5500', 'San Rafael', 'Mendoza', 'Encargado Test')
ON CONFLICT DO NOTHING;
INSERT INTO sala (id_sala, direccion, dia_cierre_semanal, id_localidad)
VALUES (1, 'Sala Prueba', 1, 1)
ON CONFLICT DO NOTHING;
COMMIT;
SQL

cleanup

"${PSQL[@]}" >/dev/null <<'SQL'
INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
VALUES ('JD004 A', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789');
INSERT INTO vino (nombre_comercial, tipo, anada, presentacion_ml, graduacion, precio_venta, cuit_bodega)
VALUES ('JD004 B', 'tinto', 2020, 750, 14.00, 1000.00, '20123456789');

INSERT INTO stock_deposito (cod_vino, cantidad)
SELECT cod_vino, 100 FROM vino WHERE nombre_comercial = 'JD004 A';
INSERT INTO stock_deposito (cod_vino, cantidad)
SELECT cod_vino, 100 FROM vino WHERE nombre_comercial = 'JD004 B';
SQL

# D2: el INSERT solo acepta en_confeccion (default). El renglon se carga con el
# documento en confeccion y recien despues se pasa a terminado (RN-12).
NRO=$("${PSQL[@]}" -tAc "INSERT INTO transferencia (id_sala) VALUES (1) RETURNING nro_solicitud")
VINO_A=$("${PSQL[@]}" -tAc "SELECT cod_vino FROM vino WHERE nombre_comercial = 'JD004 A'")

"${PSQL[@]}" >/dev/null -c "
INSERT INTO renglon_transferencia (nro_solicitud, cod_vino, cantidad)
VALUES ($NRO, $VINO_A, 10);
UPDATE transferencia SET estado = 'terminado' WHERE nro_solicitud = $NRO;
"
echo "nro_solicitud=$NRO vino_A=$VINO_A"

echo "== sesion C: bloquea stock_deposito del vino A =="
PGAPPNAME=jd004_C "${PSQL[@]}" -c "BEGIN; SELECT 1 FROM stock_deposito WHERE cod_vino = $VINO_A FOR UPDATE; SELECT pg_sleep(30); ROLLBACK;" >/dev/null 2>&1 &
C_PID=$!

# Barrera: esperar a que C ya tenga el lock (esta durmiendo en pg_sleep) antes
# de lanzar A. Sin esto, en un runner lento A puede terminar antes de que C
# bloquee y la prueba falla por setup, no por la regla.
c_ready=0
for _ in $(seq 1 80); do
    sleeping=$("${PSQL[@]}" -tAc "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'jd004_C' AND wait_event = 'PgSleep'")
    if [ "${sleeping:-0}" -gt 0 ]; then c_ready=1; break; fi
    sleep 0.25
done
if [ "$c_ready" -ne 1 ]; then
    echo "FAIL: la sesion C no llego a tomar el lock; setup no deterministico" >&2
    kill "$C_PID" 2>/dev/null || true
    exit 2
fi
echo "sesion C bloqueando el deposito"

echo "== sesion A: CALL sp_procesar_transferencia =="
PGAPPNAME=jd004_A "${PSQL[@]}" -c "CALL sp_procesar_transferencia($NRO);" >/dev/null 2>&1 &
A_PID=$!

# Esperar a que A quede bloqueada en el lock del deposito (o del renglon).
blocked=0
for _ in $(seq 1 40); do
    w=$("${PSQL[@]}" -tAc "SELECT COALESCE(wait_event_type,'') FROM pg_stat_activity WHERE application_name = 'jd004_A'")
    if [ "$w" = "Lock" ]; then blocked=1; break; fi
    sleep 0.25
done
if [ "$blocked" -ne 1 ]; then
    echo "FAIL: la sesion A no quedo bloqueada; setup no deterministico" >&2
    kill "$C_PID" "$A_PID" 2>/dev/null || true
    exit 2
fi
echo "sesion A bloqueada en un lock"

echo "== sesion B: intenta editar el renglon (10 -> 30); RN-12 lo rechaza =="
set +e
B_ERR=$(PGAPPNAME=jd004_B "${PSQL[@]}" -c "UPDATE renglon_transferencia SET cantidad = 30 WHERE nro_solicitud = $NRO AND cod_vino = $VINO_A;" 2>&1)
B_RC=$?
set -e
if [ "$B_RC" -eq 0 ] || ! printf '%s' "$B_ERR" | grep -q '\[RN-12\]'; then
    echo "FAIL: la edicion concurrente no fue rechazada por RN-12 (rc=$B_RC): $B_ERR" >&2
    kill "$C_PID" "$A_PID" 2>/dev/null || true
    exit 1
fi
echo "RN-12 rechazo la edicion concurrente: OK"

kill "$C_PID" 2>/dev/null || true
wait "$C_PID" 2>/dev/null || true
wait "$A_PID"

DEP=$("${PSQL[@]}" -tAc "SELECT cantidad FROM stock_deposito WHERE cod_vino = $VINO_A")
SALA=$("${PSQL[@]}" -tAc "SELECT COALESCE((SELECT cantidad FROM stock_sala WHERE id_sala = 1 AND cod_vino = $VINO_A), 0)")
ESTADO=$("${PSQL[@]}" -tAc "SELECT estado FROM transferencia WHERE nro_solicitud = $NRO")
echo "stock_deposito=$DEP stock_sala=$SALA estado=$ESTADO (esperado: 90 / 10 / procesado)"

if [ "$DEP" = "90" ] && [ "$SALA" = "10" ] && [ "$ESTADO" = "procesado" ]; then
    echo "OK: RN-12 bloqueo la edicion y el procedimiento consumio el conjunto que valido (10)"
    exit 0
fi

echo "FAIL: el conjunto validado y el consumido no coinciden (TOCTOU)" >&2
exit 1
