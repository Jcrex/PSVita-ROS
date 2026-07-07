#!/bin/sh
# docker-entrypoint.sh — arranca los dos procesos del contenedor de la web.
#
# El ingestor UDP del netlog (best-effort, no crítico para el dashboard)
# corre en un bucle que lo reinicia si muere, con una pausa corta para no
# entrar en un bucle de reinicio a toda velocidad si el fallo es
# persistente (p. ej. el puerto 9999 ocupado). El servidor Astro es el
# proceso principal: `exec` lo convierte en PID 1, así que recibe
# directamente las señales de `docker stop`/`docker compose down` para un
# apagado limpio. El bucle del ingestor no recibe esa señal explícita,
# pero muere igualmente cuando el contenedor se detiene (todo el
# namespace de procesos se destruye junto con él).
#
# Sin `set -e`: el ingestor SIEMPRE sale con código distinto de cero al
# morir (p. ej. 143 por SIGTERM), y ese código no está protegido por un
# if/while/&&/||. Con `set -e` activo, ese fallo mataría el subshell del
# bucle entero en el primer reinicio (nunca llegaría al echo/sleep/vuelta
# al bucle) — justo lo contrario de lo que este script quiere lograr.

(
  while true; do
    node scripts/netlog-ingester.mjs
    echo "[docker-entrypoint] netlog-ingester salió (código $?); reintentando en 2s..." >&2
    sleep 2
  done
) &

exec node dist/server/entry.mjs
