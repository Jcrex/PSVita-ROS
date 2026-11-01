---
name: vita-deploy-logs
description: "Use when deploying a built .vpk to a real PS Vita over FTP (tools/deploy-vpk-ftp.sh) and capturing its runtime logs — Godot 4 apps via the docker/ station agent and ROS 2 topics; Fase 1 apps via UDP netlog."
---

## Cuándo usar esta skill

Invocar esta skill cuando se tenga un `.vpk` construido (con la skill `vita-build-package`) y se quiera desplegarlo en una PS Vita real para probarlo y capturar sus logs de ejecución. Cubre el ciclo completo: subida por FTP, instalación, lanzamiento y lectura de logs por red.

---

## Precondiciones

Antes de comenzar, verificar que se cumplen todas las condiciones siguientes:

1. **La PS Vita tiene VitaShell instalado** y está en **modo FTP activo**. Para activar el modo FTP en VitaShell: abrir VitaShell → pulsar `Select`. La consola muestra su dirección IP y puerto (normalmente `:1337`).

2. **La Vita y el PC están en la misma red local.** La Vita del proyecto suele estar en
   `192.168.1.94`, FTP en el puerto `1337` (comprobar en la pantalla de VitaShell: la IP la da el DHCP).

3. **El `.vpk` existe y tiene tamaño mayor que cero** (verificado con la skill `vita-build-package`).

4. **`curl` está disponible en el PC** o se tiene un cliente FTP alternativo.

---

## Paso 1 — Subir el `.vpk` a la Vita por FTP

**Preferido:** `tools/deploy-vpk-ftp.sh <app>.vpk [vita-ip] [destino]` (p. ej.
`tools/deploy-vpk-ftp.sh build/g6-hmi.vpk 192.168.1.94`; destino por defecto `ux0:/<nombre>.vpk`). Busca la Vita si no se da la IP, mide el ping,
comprueba que el FTP responde, sube con aborto por enlace caído, **descarga de vuelta y compara el sha256**
(reintenta 3 veces). Motivo: en hardware (2026-10-30) una subida de 22 MB llegó cortada (~2 MB) con `curl` sin
error y el listado FTP mostrando el tamaño completo; con la Vita lejos del router el ping iba a 55–190 ms.
Acercarla al router lo resolvió (sospecha de WiFi débil, no confirmada del todo).

A mano, con `curl` (sin verificación):

```bash
curl -T <app>.vpk "ftp://<vita-ip>:1337/ux0:/<app>.vpk"
```

- `ux0:` es la tarjeta de memoria (o almacenamiento interno según el modelo).
- Reemplazar `<vita-ip>` con la IP que muestra VitaShell y `<app>.vpk` con el nombre del archivo.

Si se prefiere un cliente FTP gráfico (FileZilla, etc.), conectar a `<vita-ip>:1337` sin credenciales (acceso anónimo) y copiar el `.vpk` a `ux0:/`.

**Si no se conoce la IP:** buscar el puerto 1337 en la LAN (sin nmap):
`for i in $(seq 2 254); do (timeout 1 bash -c "echo > /dev/tcp/192.168.1.$i/1337" 2>/dev/null && echo 192.168.1.$i) & done; wait`

**Si `curl` se queda colgado hasta el timeout (visto en hardware, 2026-10-30):** el TCP conecta pero VitaShell
no envía el saludo `220` ⇒ el servidor FTP está congelado (pantalla apagada/en espera, VitaShell en segundo plano;
ping de ~140 ms = WiFi en ahorro de energía). No es un problema de red del PC. Arreglo: en la Vita cancelar el
modo FTP y volver a activarlo con `Select`, con VitaShell en primer plano y la espera automática desactivada
(Ajustes → Ahorro de energía). Comprobar antes de subir: `curl -s --max-time 8 ftp://<vita-ip>:1337/ux0:/` debe
listar carpetas. Un `.vpk` de Godot 4 (~22 MB) sube en menos de un minuto.

**Nota:** con `curl` a mano no hay garantía de que el archivo llegue entero; por eso se prefiere
`tools/deploy-vpk-ftp.sh`, que compara el sha256 tras la subida.

---

## Paso 2 — Instalar desde VitaShell

Una vez transferido el `.vpk`:

1. En VitaShell, navegar a `ux0:/`.
2. Seleccionar el archivo `.vpk`.
3. Pulsar `X` para instalar. VitaShell ejecuta la instalación y añade la app a la LiveArea.
4. Salir de VitaShell.

Si ya existe una versión anterior instalada con el mismo ID de título, VitaShell preguntará si sobreescribir. Confirmar que sí para actualizar.

---

## Paso 3 — Lanzar la app y capturar logs

La Vita (homebrew) no tiene consola accesible. Cómo se ve lo que pasa depende del flujo:

| Flujo | Dónde mirar |
|---|---|
| **Godot 4** (`godot/g5-xrce`, `g6-hmi`, `g7-imu`…; vivo) | Agente micro-ROS de la estación `docker/` + topics ROS 2 |
| **Fase 1** (`vita-app/`) y `tools/hwprobe/` | Netlog UDP al puerto 9999 |

### Godot 4 — agente de la estación y topics

Las apps Godot 4 **no mandan netlog**. Se depuran desde el lado ROS 2, con la estación `docker/`
en la máquina cuya IP está en `ros/agent_ip` del `project.godot` (hoy el PC, `192.168.1.65`):

```bash
docker/vita-ros.sh up              # agente micro-ROS (UDP 8888) + estación
docker/vita-ros.sh logs agent      # log del agente en vivo
docker/vita-ros.sh monitor         # frecuencia/último valor de /vita_hello y /cmd_vel; publica /pc_hello
docker/vita-ros.sh topics          # ros2 topic list -t
docker/vita-ros.sh echo /cmd_vel   # ros2 topic echo <topic>
```

- **Verbosidad del agente:** `AGENT_VERBOSE` en `docker/.env` (por defecto `4`; `6` muestra cada
  `create_*` y cada `write`). Cambiarla y volver a hacer `up`.
- Señal de vida en el log del agente: `create_client` → `session established` → `create_participant`
  /`create_publisher`… Si no aparece `create_client`, la Vita no llega al agente (IP/puerto en
  `project.godot`, misma WiFi). Si aparece pero no hay datos en ROS 2, mirar la discovery del
  grafo (`docker/README.md`).
- Tráfico crudo: `docker/vita-ros.sh sniff 192.168.1.94`.
- La red de la Vita la inicia el cargador del `.vpk`, no Godot: dentro del motor la inicialización
  falla con `SCE_KERNEL_ERROR_UID_RL_OVERFLOW` (`docs/06`, bloque G5).

### Fase 1 y hwprobe — netlog UDP 9999

`vita-app/src/netlog.c` (socket UDP propio, sin PrincessLog) manda cada `LOG(...)` por
`sceClibPrintf` y por UDP a `NETLOG_IP:NETLOG_PORT` (por defecto `192.168.1.108:9999`, la laptop;
`vita-app/CMakeLists.txt`). `tools/hwprobe/` usa el mismo `netlog.c`. **Validado en hardware el
2026-07-01** (`docs/06`: el netlog mostró `*** SESION XRCE ESTABLECIDA ***` en 4 lanzamientos).

En la máquina cuya IP quedó como `NETLOG_IP`, antes de lanzar la app:

```bash
tools/netlog-listen.sh 9999              # solo pantalla
tools/netlog-listen.sh 9999 sesion.log   # además guarda una copia
```

El script **filtra el ruido binario** (el enchufe TP-Link Kasa `192.168.1.51` hace broadcast al
9999 cada ~25 s): descarta líneas con menos del 70 % de ASCII imprimible, como
`web/scripts/netlog-parser.mjs`. Con `socat`/`nc` a mano ese ruido sí aparece.

Si no llega nada, lo más probable es que `net_udp_init()` o la sesión XRCE fallaran antes del
primer log: revisar WiFi común y que el agente esté en `AGENT_IP:AGENT_PORT`.

Backup sin red: **PrincessLog** (plugin taiHEN, `docs/guias-vita/autoplugin2.md`) guarda los
mismos `sceClibPrintf` en la tarjeta, legibles desde VitaShell.

---

## Bucle de iteración

El ciclo completo de desarrollo embebido en la Vita sigue este flujo:

```
[Editar código en el PC]
       ↓
[vita-build-package] → produce <app>.vpk
       ↓
[vita-deploy-logs: subir] → tools/deploy-vpk-ftp.sh <app>.vpk 192.168.1.94
       ↓
[vita-deploy-logs: instalar] → VitaShell en la Vita
       ↓
[vita-deploy-logs: lanzar + leer logs] → docker/vita-ros.sh logs agent / monitor
                                         (Fase 1: tools/netlog-listen.sh 9999)
       ↓
[Analizar logs, identificar el problema]
       ↓
[Volver al inicio]
```

Cada iteración completa este ciclo. No saltarse el paso de lectura de logs: en hardware embebido, la diferencia entre "compila" y "funciona" es frecuentemente visible solo en los logs de ejecución.

---

## Nota de estado general

- Instalación por VitaShell: validada en hardware (2026-07-01, primer `.vpk` en la Vita 1000).
- Netlog UDP (Fase 1): validado en hardware el 2026-07-01 y usado en vivo por el monitor web
  desde el 2026-07-07.
- Flujo Godot 4 (`deploy-vpk-ftp.sh` + estación `docker/`): validado en hardware en G4–G6
  (2026-10-30). Si al lanzar la app no se ve nada, revisar primero la WiFi de la Vita.
