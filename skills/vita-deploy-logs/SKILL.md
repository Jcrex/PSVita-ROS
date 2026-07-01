---
name: vita-deploy-logs
description: Use when deploying a built .vpk to a real PS Vita over FTP and capturing its runtime logs — drives the upload/install/launch loop and network log capture.
---

## Cuándo usar esta skill

Invocar esta skill cuando se tenga un `.vpk` construido (con la skill `vita-build-package`) y se quiera desplegarlo en una PS Vita real para probarlo y capturar sus logs de ejecución. Cubre el ciclo completo: subida por FTP, instalación, lanzamiento y lectura de logs por red.

---

## Precondiciones

Antes de comenzar, verificar que se cumplen todas las condiciones siguientes:

1. **La PS Vita tiene VitaShell instalado** y está en **modo FTP activo**. Para activar el modo FTP en VitaShell: abrir VitaShell → pulsar `Select`. La consola muestra su dirección IP y puerto (normalmente `:1337`).

2. **La Vita y el PC están en la misma red local.** Anotar la IP de la Vita (p. ej. `192.168.1.XXX`) y el puerto FTP (p. ej. `1337`). Estos valores se usan en todos los comandos de subida.

3. **El `.vpk` existe y tiene tamaño mayor que cero** (verificado con la skill `vita-build-package`).

4. **`curl` está disponible en el PC** o se tiene un cliente FTP alternativo.

---

## Paso 1 — Subir el `.vpk` a la Vita por FTP

Usar `curl` para transferir el archivo al almacenamiento de la Vita:

```bash
curl -T <app>.vpk "ftp://<vita-ip>:1337/ux0:/<app>.vpk"
```

- `ux0:` es la tarjeta de memoria (o almacenamiento interno según el modelo).
- Reemplazar `<vita-ip>` con la IP que muestra VitaShell y `<app>.vpk` con el nombre del archivo.

Si se prefiere un cliente FTP gráfico (FileZilla, etc.), conectar a `<vita-ip>:1337` sin credenciales (acceso anónimo) y copiar el `.vpk` a `ux0:/`.

**Nota de estado — validar en hardware:** la velocidad de transferencia por WiFi varía; archivos grandes pueden tardar varios segundos. Confirmar que la transferencia completa antes de continuar.

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

### Método de captura de logs

La PS Vita (homebrew) no tiene salida de consola accesible directamente. Los logs de ejecución se capturan por red redirigiendo `sceClibPrintf` (o un wrapper equivalente) a un socket UDP hacia el PC. Este es el método habitual en el ecosistema homebrew (estilo PrincessLog).

**Validado en hardware (2026-07-01):** `vita-ros2-hello` ya implementa esto
en `vita-app/src/netlog.c` (socket UDP propio, sin PrincessLog): cada
llamada a `LOG(...)` en `main.c` manda la línea por `sceClibPrintf` (local)
y por UDP a `NETLOG_IP:NETLOG_PORT` (por defecto `192.168.1.108:9999`, la
laptop — ver `vita-app/CMakeLists.txt`).

**En la máquina cuya IP quedó baked-in como `NETLOG_IP`**, antes de lanzar
la app, poner a escuchar el receptor de logs — usar el script del repo
(colorea FATAL/hitos y opcionalmente guarda a archivo):

```bash
tools/netlog-listen.sh 9999              # solo pantalla
tools/netlog-listen.sh 9999 sesion.log   # además guarda una copia
```

Equivalente manual: `socat -u UDP-RECV:<puerto> STDOUT` (o `nc -u -l
<puerto>` si no hay `socat`).

**En la Vita**, lanzar la app desde la LiveArea. Los mensajes aparecerán en
la terminal en tiempo real. Si no aparece nada, lo más probable no es un
problema de logging sino que **`net_udp_init()` o la sesión XRCE fallaron
antes de mandar el primer log** (revisar que la Vita esté en la misma red
WiFi que la máquina que escucha, y que el agente micro-ROS esté arriba en
`AGENT_IP:AGENT_PORT`).

Backup sin red: **PrincessLog** (plugin taiHEN, ver
`docs/guias-vita/autoplugin2.md`) captura los mismos `sceClibPrintf` a un
archivo en la tarjeta, legible desde VitaShell aunque la Vita no tenga
WiFi o el listener UDP no esté escuchando.

---

## Bucle de iteración

El ciclo completo de desarrollo embebido en la Vita sigue este flujo:

```
[Editar código en el PC]
       ↓
[vita-build-package] → produce <app>.vpk
       ↓
[vita-deploy-logs: subir] → curl -T ... ftp://...
       ↓
[vita-deploy-logs: instalar] → VitaShell en la Vita
       ↓
[vita-deploy-logs: lanzar + leer logs] → tools/netlog-listen.sh <puerto>
       ↓
[Analizar logs, identificar el problema]
       ↓
[Volver al inicio]
```

Cada iteración completa este ciclo. No saltarse el paso de lectura de logs: en hardware embebido, la diferencia entre "compila" y "funciona" es frecuentemente visible solo en los logs de ejecución.

---

## Nota de estado general

La instalación por USB/VitaShell se validó en hardware el 2026-07-01
(primer `.vpk` real instalado en la Vita 1000 del proyecto). La captura de
logs por UDP (`tools/netlog-listen.sh`) usa el mecanismo ya implementado
en `vita-app/src/netlog.c`, pero su recepción real sobre WiFi (Vita y
listener en la misma red) todavía no se confirmó en esta sesión — sigue
marcada **"validar en hardware"** hasta que se vea una línea de log
llegar. Si al lanzar la app no llega nada, lo primero a revisar es la
conectividad WiFi de la Vita, no la skill en sí.
