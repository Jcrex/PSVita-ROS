# Guía de pruebas del stack Vita ↔ ROS2 (estación `docker/`)

> Antes `docs/09-guia-pruebas-stack.md`; renumerada el 2026-11-01 (auditoría) porque el 09 estaba
> duplicado. Desde 2026-10-30 el contenedor ROS2 por defecto es la estación propia del repo
> (`docker/`, ver `docker/README.md`); la de IR2134 (`rmf_unified`) sigue valiendo con variables.

Esta guía describe, paso a paso, cómo probar los programas de la web y la
conexión real con la PS Vita, repartiendo el trabajo entre las dos
máquinas del proyecto (ver tabla de roles en `CLAUDE.md`).

## Roles de las dos máquinas

| Máquina | IP | Qué corre aquí |
|---|---|---|
| **Laptop** (taller) | 192.168.1.108 | Contenedor ROS2, micro-ROS Agent, bridge zenoh y la web. Es la máquina que está en la misma WiFi que la Vita y "ve" su tráfico UDP. |
| **PC** (desarrollo, CachyOS) | 192.168.1.65 | Solo compila el `.vpk` (VitaSDK/cargo-vita, `tools/env-devpc.sh`) y lo despliega por FTP. No hace falta tenerlo encendido para una sesión en vivo con la Vita ya instalada. |

La sesión de pruebas con la Vita real (agente + web + logs) se hace
**en la laptop**. El PC solo entra en juego cuando hay que recompilar y
volver a subir el `.vpk`.

## 1. En la laptop: levantar todo el stack con un solo comando

`tools/vita-stack.sh` existe justamente para no tener que acordarse a mano
de arrancar cada pieza (ROS2, agent, bridge, web) en su propia terminal:

```bash
tools/vita-stack.sh all       # ros2 + micro-ROS agent + bridge zenoh + web
```

Internamente, en orden:

1. **`ros2 up`** — levanta la estación ROS2 Jazzy del repo (`vita_station`,
   delega en `docker/vita-ros.sh up`; con `ROS2_DOCKER_DIR=~/Documentos/IR2134/DOCKER
   ROS2_CONTENEDOR=rmf_unified AGENT_NOMBRE=microros-agent` usa el `rmf.sh` de IR2134).
2. **`agent up`** — lanza el micro-ROS Agent (`vita_agent`, servicio del compose de
   `docker/`; imagen `microros/micro-ros-agent:jazzy`) escuchando UDP en el puerto 8888 con
   red e IPC del host. `--ipc=host` es imprescindible: sin él,
   `ros2 topic echo` nunca recibe datos aunque el topic aparezca emparejado
   en `ros2 topic list` (ver el muro documentado en
   `docs/06-bitacora-estado.md` y en `docs/05-setup-entorno-cachyos.md §3`).
3. **`bridge up`** — dentro del mismo contenedor ROS2, arranca
   `zenoh-bridge-ros2dds --rest-http-port 8000` para que el dashboard web
   pueda leer el grafo de topics por HTTP en vez de hacer `docker exec`.
4. **`web up`** — `docker compose up -d --build` en `web/`, sirve en
   `http://localhost:4321`.

Otros comandos del mismo script:

```bash
tools/vita-stack.sh status        # resumen de qué está arriba y qué no
tools/vita-stack.sh down           # para agent+bridge+web (deja el ros2)
tools/vita-stack.sh agent logs     # logs del micro-ROS agent
tools/vita-stack.sh bridge logs    # logs del bridge zenoh
tools/vita-stack.sh netlog         # primer plano: netlog UDP de la Vita (puerto 9999)
```

> `netlog` (en terminal) y el dashboard web (`/dashboard` o `/monitor`)
> son **alternativos, no simultáneos**: ambos abren el mismo puerto UDP
> 9999, solo uno puede escucharlo a la vez. Si `netlog-listen.sh` está
> corriendo, el widget del dashboard lo indica en vez de romperse.

Variables de entorno que puede hacer falta ajustar (todas con default
razonable, ver cabecera de `tools/vita-stack.sh`):
`ROS2_DOCKER_DIR`, `ROS2_CONTENEDOR`, `AGENT_IMAGEN`, `AGENT_NOMBRE`,
`AGENT_PUERTO`, `ZENOH_REST_PUERTO`, `NETLOG_PUERTO`.

## 2. Encender la Vita y lanzar la app

- La Vita debe estar en la misma red WiFi que la laptop.
- Desde la LiveArea, lanzar la app instalada (`vita-ros2-hello`).
- La app manda su netlog UDP a la IP grabada en el binario al compilar
  (por defecto la laptop, `192.168.1.108` — ver `vita-app/CMakeLists.txt`)
  y abre la sesión XRCE contra el Agent en el puerto 8888.

## 3. Verificar en la web (desde la laptop)

Abrir `http://localhost:4321/dashboard` (o `/monitor`, la vista previa
más simple) y comprobar en vivo:

- El log UDP de la Vita: `red inicializada`, `SESION XRCE ESTABLECIDA`,
  `entidades creadas`.
- El widget de salud XRCE: IP de la Vita, último paquete, hitos
  detectados en el propio stream.
- El widget de topics (vía el bridge zenoh, necesita `ZENOH_REST_URL`
  apuntando a `http://<laptop>:8000`): debe listar `/vita_hello`.

Para el criterio bidireccional completo, desde una terminal:

```bash
docker/vita-ros.sh echo /vita_hello     # ros2 topic echo dentro de vita_station
docker/vita-ros.sh monitor              # frecuencia de /vita_hello y /cmd_vel; publica /pc_hello a 1 Hz

# a mano, dentro de la estación (docker/vita-ros.sh shell):
ros2 topic pub /pc_hello std_msgs/msg/String 'data: hola'
```

El netlog de la Vita (en la web o en `netlog-listen.sh`) debe mostrar
`/pc_hello recibido` seguido de `criterio 2 CUMPLIDO`.

## 4. En el PC: solo si hay que recompilar y volver a desplegar el `.vpk`

Aquí no se levanta nada del stack ROS2 — solo el toolchain de Vita:

```bash
source tools/env-devpc.sh        # VitaSDK/cargo-vita/cmake locales a toolchains/
tools/run-parity-tests.sh        # opcional: valida C+Rust en host antes de tocar la Vita
```

A partir de ahí, compilar `vita-app/` (CMake+VitaSDK o `cargo-vita`, ver
`vita-app/README.md`) y desplegar por FTP a la Vita, o hacerlo desde la
web con el taller (`/taller/compilador`, requiere `TALLER_ENABLED=1`).
El taller solo tiene sentido activarlo **en el PC** (ejecuta procesos
locales: cmake, gdb, curl FTP) — nunca en la laptop ni en despliegues
públicos.

## Resumen del flujo

| Paso | Dónde | Comando |
|---|---|---|
| 1. Levantar ros2+agent+bridge+web | Laptop | `tools/vita-stack.sh all` |
| 2. Lanzar la app | Vita (LiveArea) | — |
| 3. Ver logs y topics en vivo | Laptop (navegador) | `http://localhost:4321/dashboard` |
| 4. Probar bidireccional | Laptop (terminal) | `docker/vita-ros.sh echo` / `monitor` (estación `vita_station`) |
| 5. Recompilar `.vpk` si hace falta | PC | `source tools/env-devpc.sh` + build + deploy FTP |
