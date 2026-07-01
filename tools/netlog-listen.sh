#!/usr/bin/env bash
# netlog-listen.sh — escucha el log UDP que manda vita-app (src/netlog.c) y lo
# muestra en vivo con timestamp y color (FATAL en rojo, hitos en verde).
#
# Uso:
#   tools/netlog-listen.sh [puerto] [archivo_de_salida]
#
# Debe correr en la máquina cuya IP quedó "baked-in" como NETLOG_IP al
# compilar el .vpk (por defecto la laptop, 192.168.1.108 — ver
# vita-app/CMakeLists.txt). La Vita debe estar en la misma red WiFi.
set -euo pipefail

PORT="${1:-9999}"
LOGFILE="${2:-}"

echo "Escuchando netlog UDP en 0.0.0.0:${PORT}... (Ctrl+C para salir)"
if [ -n "$LOGFILE" ]; then
    echo "Guardando copia sin color en: $LOGFILE"
fi

listen() {
    if command -v socat >/dev/null 2>&1; then
        socat -u UDP-RECV:"${PORT}" STDOUT
    elif command -v nc >/dev/null 2>&1; then
        nc -u -l "${PORT}"
    else
        echo "Necesitas 'socat' o 'nc' instalado en esta máquina." >&2
        exit 1
    fi
}

listen | while IFS= read -r line; do
    ts="$(date '+%H:%M:%S')"
    case "$line" in
        *FATAL*) color="\033[31m" ;;                 # rojo: fallo
        *"SESION XRCE ESTABLECIDA"*) color="\033[1;32m" ;; # verde brillante: hito
        *"CUMPLIDO"*) color="\033[32m" ;;            # verde: criterio pasado
        *) color="\033[0m" ;;
    esac
    formatted="[$ts] $line"
    printf '%b%s\033[0m\n' "$color" "$formatted"
    if [ -n "$LOGFILE" ]; then
        printf '%s\n' "$formatted" >> "$LOGFILE"
    fi
done
