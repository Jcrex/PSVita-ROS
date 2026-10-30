#!/usr/bin/env bash
# deploy-vpk-ftp.sh — sube un .vpk a la Vita por el FTP de VitaShell y COMPRUEBA que llegó entero.
#
# Uso:  tools/deploy-vpk-ftp.sh <archivo.vpk> [ip_vita] [destino]
#   ip_vita: si se omite, se busca el puerto 1337 en la LAN 192.168.1.0/24
#   destino: por defecto ux0:/<nombre>.vpk
#
# Por qué existe (visto en hardware, 2026-10-30): una subida de 22 MB llegó cortada (~2 MB) aunque
# curl terminó sin error y el listado FTP mostraba el tamaño completo. Ni el código de salida ni
# el tamaño del listado son fiables, así que aquí se descarga el archivo de vuelta y se compara
# el sha256. Sospecha: WiFi débil (Vita lejos del router) — por eso se mide el ping antes.
set -euo pipefail
VPK="${1:?uso: $0 <archivo.vpk> [ip_vita] [destino]}"
IP="${2:-}"
DEST="${3:-ux0:/$(basename "$VPK")}"
PORT=1337
INTENTOS="${INTENTOS:-3}"
[[ -s "$VPK" ]] || { echo "ERROR: no existe $VPK"; exit 1; }

if [[ -z "$IP" ]]; then
    echo "Buscando la Vita (puerto $PORT) en 192.168.1.0/24..."
    IP="$(for i in $(seq 2 254); do (timeout 1 bash -c "echo > /dev/tcp/192.168.1.$i/$PORT" 2>/dev/null && echo "192.168.1.$i") & done; wait)"
    IP="$(echo "$IP" | head -1)"
    [[ -n "$IP" ]] || { echo "ERROR: ninguna IP con el puerto $PORT abierto (¿FTP de VitaShell activo?)"; exit 1; }
fi
URL="ftp://$IP:$PORT/$DEST"
echo "Vita: $IP"

# Calidad del enlace: en la misma LAN lo normal son pocos ms. >50 ms o pérdidas = WiFi débil
# o en ahorro de energía (más riesgo de que se corte la subida).
PING="$(ping -c 5 -W 1 "$IP" 2>/dev/null | tail -2 | tr '\n' ' ')"
echo "Ping: $PING"

# El FTP de VitaShell puede aceptar el TCP y no contestar nunca (servidor congelado).
curl -s --max-time 8 "ftp://$IP:$PORT/ux0:/" | grep -q . || {
    echo "ERROR: el FTP no responde (sin saludo 220). En la Vita: cancelar el modo FTP y reactivarlo con Select."
    exit 1
}

WANT="$(sha256sum "$VPK" | cut -d' ' -f1)"
SIZE="$(stat -c %s "$VPK")"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
for n in $(seq 1 "$INTENTOS"); do
    echo "Intento $n/$INTENTOS: subiendo $(basename "$VPK") ($SIZE bytes) a $DEST"
    T0=$(date +%s)
    # --speed-limit/--speed-time: aborta si baja de 1 KB/s durante 30 s (enlace caído) en vez de colgarse.
    if curl -sS --speed-limit 1024 --speed-time 30 -T "$VPK" "$URL"; then
        echo "  subido en $(( $(date +%s) - T0 )) s; verificando (descarga de vuelta)..."
        if curl -sS --speed-limit 1024 --speed-time 30 -o "$TMP" "$URL"; then
            GOT="$(sha256sum "$TMP" | cut -d' ' -f1)"
            if [[ "$GOT" == "$WANT" ]]; then
                echo "OK: $DEST verificado (sha256 ${WANT:0:16}…, $SIZE bytes). Instalar desde VitaShell con X."
                exit 0
            fi
            echo "  NO coincide: llegaron $(stat -c %s "$TMP") de $SIZE bytes"
        else
            echo "  falló la descarga de verificación"
        fi
    else
        echo "  la subida falló o se cortó"
    fi
done
echo "ERROR: $INTENTOS intentos sin una copia íntegra. Acercar la Vita al router y repetir."
exit 1
