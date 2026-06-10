# Guía de setup del entorno de desarrollo en CachyOS

**Fecha de creación:** 2026-06-08
**Estado:** EJECUTADA en el PC el 2026-06-10 — ver nota de instalación real

> **Nota de instalación real (2026-06-10):** el entorno se instaló **dentro
> del repo, en `toolchains/`** (gitignorado), no en las rutas globales que
> describe esta guía. Diferencias respecto al texto original:
>
> - `VITASDK` = `<repo>/toolchains/vitasdk` (toolchain v2.540 descargado a
>   mano; `bootstrap-vitasdk.sh` falla sin sudo porque hace `sudo mkdir`).
> - rustup vive en `toolchains/rustup` y cargo en `toolchains/cargo`
>   (`RUSTUP_HOME`/`CARGO_HOME` locales, nightly 1.98.0 + `rust-src`,
>   `cargo-vita` 0.2.2). No se tocó `~/.rustup` ni `~/.cargo`.
> - Se añadió un **cmake 4.3.3 portable** en `toolchains/cmake` (el PC no
>   tenía cmake y pacman requiere sudo).
> - No se editó ningún perfil de shell: el entorno se carga por sesión con
>   `source tools/env-devpc.fish` (fish) o `source tools/env-devpc.sh`
>   (bash/zsh).
> - La imagen `microros/micro-ros-agent:jazzy` **sí existe** en Docker Hub y
>   está descargada en el PC (la duda del paso 3 queda resuelta).
>
> Los pasos 4 (registro del MCP) y 5 (skills) siguen pendientes.

---

## Antes de empezar

Esta guía describe exactamente qué hay que instalar y configurar en el **PC de desarrollo** (CachyOS, IP 192.168.1.65) para poder trabajar en el proyecto PS Vita ↔ ROS2. Todos los comandos de esta guía se ejecutan en el PC, no en la laptop-taller.

**Lo que esta guía NO hace:**
- No instala ni reconfigura ROS2 Jazzy ni Gazebo. Esos ya están resueltos vía Docker en el PC y fuera del alcance de este setup.
- No modifica la configuración global del sistema más allá de las variables de entorno necesarias.

Ejecutar los pasos en el orden indicado. Verificar cada paso antes de continuar con el siguiente.

---

## 1. VitaSDK: el toolchain de compilación cruzada para la Vita

VitaSDK se instala mediante `vdpm`, el gestor de paquetes del SDK.

### Instalación

```bash
# Obtener vdpm (gestor de paquetes de VitaSDK)
git clone https://github.com/vitasdk/vdpm.git
cd vdpm
./bootstrap-vitasdk.sh
```

El script `bootstrap-vitasdk.sh` descarga y compila el toolchain completo, incluyendo `arm-vita-eabi-gcc`, los headers del sistema de la Vita, newlib y las herramientas de empaquetado (`vita-elf-create`, `vita-make-fself`, `vita-mksfoex`, `vita-pack-vpk`). El destino de instalación por defecto es `/usr/local/vitasdk`.

### Variables de entorno

Añadir al perfil del shell (`.bashrc`, `.zshrc` o equivalente):

```bash
export VITASDK=/usr/local/vitasdk
export PATH=$VITASDK/bin:$PATH
```

Recargar el perfil:

```bash
source ~/.zshrc    # o ~/.bashrc según el shell
```

### Verificación

```bash
arm-vita-eabi-gcc --version
```

La salida debe mostrar la versión del compilador GCC cruzado. Si el comando no se encuentra, revisar que `$VITASDK/bin` está en el `PATH`.

---

## 2. Rust para la Vita: target `armv7-sony-vita-newlibeabihf`

El soporte de Rust para la PS Vita usa un target de Tier 3, lo que significa que requiere el toolchain nightly y compilar la biblioteca estándar desde el código fuente (`-Z build-std`).

### Instalación del toolchain nightly

```bash
rustup toolchain install nightly
rustup default nightly    # opcional; o usar '+nightly' por proyecto
```

### Componente `rust-src`

El componente `rust-src` es necesario para `-Z build-std`:

```bash
rustup component add rust-src --toolchain nightly
```

### `cargo-vita`

`cargo-vita` es el subcomando de Cargo que envuelve el workflow de compilación para la Vita: invoca el build con las flags correctas, empaqueta el `.vpk` y gestiona el deploy. Se instala como herramienta de Cargo:

```bash
cargo install cargo-vita
```

### Target `armv7-sony-vita-newlibeabihf`

Este target no se instala con `rustup target add` porque es Tier 3 y no tiene builds preconstruidos. En su lugar, se especifica en `.cargo/config.toml` del proyecto y se construye sobre la marcha con `-Z build-std`:

```toml
# .cargo/config.toml en el directorio del proyecto Rust
[build]
target = "armv7-sony-vita-newlibeabihf"

[unstable]
build-std = ["core", "alloc"]
```

La variable de entorno `VITASDK` debe estar exportada para que el linker de Rust encuentre las bibliotecas de newlib del SDK.

### Verificación

```bash
cargo vita --help
```

La salida debe mostrar la ayuda de los subcomandos de `cargo-vita`. Si el comando no se encuentra, verificar que `~/.cargo/bin` está en el `PATH`.

---

## 3. micro-ROS Agent en Docker

El micro-ROS Agent actúa como puente entre el cliente XRCE-DDS de la Vita y el grafo ROS2 Jazzy. Se ejecuta en Docker para mantener el entorno limpio.

### Arrancar el agente

```bash
docker run -it --rm --net=host microros/micro-ros-agent:jazzy udp4 --port 8888
```

- `--net=host`: el contenedor usa directamente la red del host, lo que permite recibir tráfico UDP de la Vita en la misma red WiFi sin traducción de puertos.
- `udp4`: transporte UDP sobre IPv4.
- `--port 8888`: puerto en el que el agente escucha conexiones del cliente. Este debe coincidir con el puerto configurado en el módulo `microros-transport` de la Vita.

> **Nota:** verificar la disponibilidad del tag `jazzy` en Docker Hub antes de usarlo: `docker pull microros/micro-ros-agent:jazzy`. Si el tag no existe (micro-ROS puede no tener una release exactamente nombrada "jazzy"), usar el tag de la distribución ROS2 más cercana soportada por micro-ROS, o compilar el agente manualmente desde el repositorio oficial. El tag definitivo se registra en el ADR `0002-microros-transporte-udp-propio.md`.

### Verificar que el agente está activo

Con el contenedor corriendo, abrir otra terminal y ejecutar:

```bash
ros2 node list
```

Cuando la Vita se conecte, el agente expondrá el nodo de la Vita en el grafo y `ros2 node list` lo mostrará.

---

## 4. MCP `ros2-introspection`

El MCP `ros2-introspection` da a Claude Code visibilidad en tiempo real del grafo ROS2: lista de topics, tipos de mensajes, definiciones de interfaces y muestras de datos. Se usa para generar código de publisher/subscriber para la Vita con los tipos correctos, sin necesidad de consultar documentación manualmente.

### Instalación

Las instrucciones detalladas de instalación, requisitos de Python y configuración del entorno ROS2 están en:

```
mcp/ros2-introspection/README.md
```

El MCP está escrito en Python sobre `rclpy` y requiere que el entorno ROS2 Jazzy (o el contenedor Docker de ROS2) esté activo cuando se use. Seguir las instrucciones del README para el registro del MCP en la configuración de Claude Code del PC.

---

## 5. Skills de Claude Code

Las skills del proyecto automatizan los workflows más repetitivos del desarrollo:

- **`vita-dual-module`**: genera el scaffold completo de un módulo dual (header C-ABI, `impl-c/`, `impl-rust/`, tests de paridad, CMakeLists).
- **`vita-build-package`**: compila y empaqueta la app homebrew (C/C++ con CMake+VitaSDK o Rust con `cargo-vita`), produciendo el `.vpk` listo para instalar.
- **`vita-deploy-logs`**: sube el `.vpk` a la Vita por FTP (via VitaShell), instala y lanza la app, y captura logs por red.

### Cómo copiarlas a la configuración de Claude Code del PC

Las skills están en el directorio `skills/` del repositorio del proyecto. Una vez sincronizado el repositorio al PC (mediante `tools/sync-to-devpc.sh`), copiar el directorio de cada skill al directorio de skills de Claude Code:

```bash
# Asumiendo que Claude Code usa ~/.claude/skills/ para skills de proyecto
# (verificar la ruta exacta con la documentación de Claude Code)
cp -r skills/vita-dual-module   ~/.claude/skills/
cp -r skills/vita-build-package ~/.claude/skills/
cp -r skills/vita-deploy-logs   ~/.claude/skills/
```

Reiniciar Claude Code para que detecte las nuevas skills.

---

## 6. Sincronización del repositorio desde la laptop

El repositorio se ha preparado en la laptop-taller y se transfiere al PC mediante el script de sincronización incluido:

```bash
# Desde la laptop, para enviar la fundación al PC
./tools/sync-to-devpc.sh
```

El script usa `rsync` sobre el recurso SMB (o SSH si se prefiere) hacia la IP del PC (192.168.1.65). La transferencia la dispara el usuario manualmente; el PC es siempre la fuente de verdad del desarrollo a partir de este punto.

---

## Resumen del orden de setup

| Paso | Herramienta | Verificación |
|------|-------------|--------------|
| 1 | VitaSDK vía `vdpm` | `arm-vita-eabi-gcc --version` |
| 2 | Rust nightly + `rust-src` + `cargo-vita` | `cargo vita --help` |
| 3 | micro-ROS Agent en Docker (udp4, puerto 8888) | Contenedor arranca sin error |
| 4 | MCP `ros2-introspection` | Seguir `mcp/ros2-introspection/README.md` |
| 5 | Skills de Claude Code | Skills disponibles en Claude Code |

Una vez completados estos pasos, el entorno está listo para comenzar la Fase 1: compilar los módulos duales `net-udp`, `microros-transport` y `mem-pool`, y validar la incógnita dura del transporte XRCE-DDS sobre `sceNet`.
