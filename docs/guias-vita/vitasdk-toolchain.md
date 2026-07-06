---
title: "Tutorial del SDK: de cero a .vpk"
slug: vitasdk-toolchain
order: 8
description: "Cómo funciona VitaSDK de punta a punta: toolchain, cmake, vita-elf-create, fself, param.sfo y el empaquetado del .vpk — explicado con la app real de este proyecto."
repo: "https://github.com/vitasdk"
essential: false
---

# Tutorial del SDK de la Vita: de cero a `.vpk`

## Qué es esta guía

Las demás guías de esta sección explican cómo **instalar** homebrew ya
construido. Esta explica lo contrario: **cómo se construye** un homebrew
con VitaSDK, herramienta a herramienta, usando como ejemplo real la app de
este proyecto (`vita-app/`, la que mete a la Vita en un grafo ROS2).

Al terminar deberías poder responder: ¿qué hace exactamente cada paso entre
`main.c` y el `.vpk` que instala VitaShell?

> Complementos en la sección de documentación: el setup completo del PC
> (`05-setup-entorno-cachyos`), y las decisiones registradas
> `adr/0001` (toolchain) y `adr/0004` (empaquetado del `.vpk`).

---

## 1. La plataforma: qué es (y qué no es) la Vita para un compilador

- CPU **ARM Cortex-A9 de 32 bits** (armv7, hard-float). El triple del
  toolchain es `arm-vita-eabi`.
- **No es Linux.** No hay glibc ni syscalls POSIX: la libc es **newlib**
  y el sistema se llama a través de los módulos del kernel de Sony
  (`sceKernel*`, `sceNet*`, `sceDisplay*`, ...), expuestos por los headers
  y stubs de VitaSDK (`vitasdk/include/psp2/…`, `lib*_stub.a`).
- Los binarios de usuario son **estáticos y position-dependent**: nada de
  `.so` ni código PIC (este proyecto se comió ese muro: ver §6).

Consecuencia práctica: cualquier librería de PC que asuma Linux/POSIX
(sockets, hilos, `mmap`...) necesita adaptación. En este proyecto, por
ejemplo, el cliente XRCE se compila con un perfil "custom transport only"
y la capa de red la ponemos nosotros con `sceNet` (módulo `net-udp`).

## 2. El toolchain: qué te instala VitaSDK

VitaSDK es un toolchain GCC completo + headers/stubs de la consola + las
herramientas de empaquetado. Las piezas que usarás sin darte cuenta:

| Pieza | Qué es |
|---|---|
| `arm-vita-eabi-gcc/g++` | GCC cruzado (en este repo: gcc 15, VitaSDK v2.540) |
| `arm-vita-eabi-ld`, `ar`, ... | binutils del triple `arm-vita-eabi` |
| `$VITASDK/arm-vita-eabi/include` | headers de newlib + `psp2/` (la API de Sony) |
| `$VITASDK/arm-vita-eabi/lib` | newlib + `*_stub.a` (stubs de los módulos del sistema) |
| `share/vita.toolchain.cmake` | toolchain file para CMake |
| `share/vita.cmake` | macros de empaquetado (`vita_create_self`, `vita_create_vpk`) |
| `vita-elf-create`, `vita-make-fself`, `vita-mksfoex`, `vita-pack-vpk` | el pipeline del §4 |

En este repo **no se instala en `/usr/local`**: vive en `toolchains/vitasdk/`
(gitignorado) y se activa por sesión:

```bash
source tools/env-devpc.fish   # (o tools/env-devpc.sh en bash/zsh)
# exporta VITASDK y mete el toolchain + cmake portable al PATH
```

Un "hola mundo" compilable a mano, para ver el triple en acción:

```bash
arm-vita-eabi-gcc -Wl,-q -o hola.elf hola.c
```

El flag `-Wl,-q` (keep relocations) es **obligatorio**: el paso siguiente
(`vita-elf-create`) necesita las relocaciones para generar el formato
ejecutable de la consola. `vita.cmake` lo añade solo; si enlazas a mano y
lo olvidas, el error aparece un paso después.

## 3. CMake: el toolchain file y las macros de Vita

Con CMake nunca invocas `arm-vita-eabi-gcc` a mano. Dos archivos hacen la
magia:

1. **`vita.toolchain.cmake`** — le dice a CMake qué compilador usar y
   dónde buscar librerías. Se pasa en la configuración:

   ```bash
   cmake -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake -B build
   ```

2. **`vita.cmake`** — se incluye en el `CMakeLists.txt` del proyecto y
   aporta las macros de empaquetado:

   ```cmake
   include("${VITASDK}/share/vita.cmake" REQUIRED)

   add_executable(mi-app src/main.c)          # → mi-app (ELF normal)
   vita_create_self(eboot.bin mi-app)         # → eboot.bin (velf + fself)
   vita_create_vpk(mi-app.vpk MIAPP00001 eboot.bin
       VERSION "01.00" NAME "Mi App")         # → mi-app.vpk
   ```

El `CMakeLists.txt` real de `vita-app/` es exactamente esto más nuestras
librerías (módulos duales C o Rust según `-DVITA_IMPL`, y el cliente XRCE
cross-compilado). El flujo completo del proyecto:

```bash
source tools/env-devpc.fish
cd vita-app
./scripts/build-xrce-client-vita.sh   # una vez: microcdr + cliente XRCE
cmake -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake \
      -DVITA_IMPL=rust -B build-rust
cmake --build build-rust              # → build-rust/vita-ros2-hello.vpk
```

## 4. El pipeline de empaquetado, herramienta a herramienta

Esto es lo que las macros de `vita.cmake` ejecutan por ti (y lo que
tendrías que hacer a mano sin ellas). Cuatro transformaciones:

```
main.c ──gcc──▶ app.elf ──vita-elf-create──▶ app.velf ──vita-make-fself──▶ eboot.bin
                                                        vita-mksfoex ──▶ param.sfo
                                            vita-pack-vpk ──▶ app.vpk  (zip de todo)
```

### 4.1 `vita-elf-create` — de ELF a VELF

```bash
vita-elf-create app.elf app.velf
```

Convierte el ELF de GCC al formato ejecutable de la Vita: resuelve los
**stubs** (cada `sceNetSocket()` que llamaste se convierte en una entrada
de import de un módulo del kernel, con su NID — el hash que identifica la
función) y reescribe las relocaciones al formato propio de Sony. Por esto
hacía falta `-Wl,-q`: sin relocaciones en el ELF no puede trabajar.

Es también la herramienta que **rechaza código PIC** (ver §6).

### 4.2 `vita-make-fself` — firmar el ejecutable

```bash
vita-make-fself -s app.velf eboot.bin
```

Envuelve el VELF en un **fSELF** ("fake signed ELF"): el contenedor firmado
que el kernel hackeado (HENkaku/h-encore) acepta. `-s` = safe/unsafe según
los permisos que necesite la app. El resultado se llama siempre
`eboot.bin`: es el nombre que la consola busca al lanzar una app.

### 4.3 `vita-mksfoex` — los metadatos (`param.sfo`)

```bash
vita-mksfoex -s TITLE_ID=VROS00001 "Vita ROS2 Hello" param.sfo
```

Genera el `param.sfo`, la ficha de la app para el LiveArea: título visible
y **TITLE_ID** — 9 caracteres exactos (4 letras + 5 dígitos, p. ej.
`VROS00001`), único por app: es la clave de instalación (dos `.vpk` con el
mismo TITLE_ID se sobreescriben mutuamente, así se actualiza una app).

### 4.4 `vita-pack-vpk` — el zip final

```bash
vita-pack-vpk -s param.sfo -b eboot.bin app.vpk
```

Un `.vpk` **es un zip** con otra extensión. El mínimo instalable son dos
archivos; lo demás es opcional (iconos y fondos del LiveArea):

```
app.vpk
├── eboot.bin          # el ejecutable (fSELF)
└── sce_sys/
    ├── param.sfo      # metadatos (TITLE_ID, nombre, versión)
    ├── icon0.png      # icono 128×128 (opcional)
    └── livearea/      # fondo/botón de la LiveArea (opcional)
```

Puedes comprobarlo: `unzip -l vita-app/build-rust/vita-ros2-hello.vpk`.
VitaShell lo descomprime en `ux0:app/<TITLE_ID>/` al instalar.

## 5. Enlazar con el sistema: stubs y módulos

En la Vita no enlazas "librerías del sistema" sino **stubs**: librerías
`.a` diminutas que solo declaran los imports. Ejemplo real de
`vita-app/CMakeLists.txt`:

```cmake
target_link_libraries(vita-ros2-hello
    SceNet_stub SceNetCtl_stub    # sockets + info de red
    SceSysmodule_stub             # cargar módulos del sistema en runtime
    SceCtrl_stub                  # botones (salir con START)
)
```

Y en el código, antes de usar la red, hay que **cargar el módulo** y
arrancarla (cosas que en Linux "ya están"):

```c
sceSysmoduleLoadModule(SCE_SYSMODULE_NET);
sceNetInit(&params);       /* con un buffer de memoria que le das tú */
sceNetCtlInit();
```

Ese baile completo está en `modules/net-udp/impl-c/net_udp.c` (rama
`#ifdef __vita__`), con su equivalente Rust en `impl-rust/src/lib.rs`.

## 6. Los muros reales que este proyecto ya se comió (aprende gratis)

1. **`vita-elf-create: Invalid relocation type 25!`** — el código era PIC
   (relocaciones GOT `R_ARM_BASE_PREL`, típicas de libs compiladas con
   `-fPIC`). El homebrew es estático y position-dependent: recompila la
   librería sin PIC (aquí: `UCLIENT_PIC=OFF`/`UCDR_PIC=OFF` para el
   cliente XRCE). Si una dependencia te da este error, busca su flag de
   PIC — casi todas lo tienen.
2. **Superbuilds que ignoran el toolchain.** El superbuild de eProsima no
   reenviaba `CMAKE_TOOLCHAIN_FILE` a sus sub-proyectos y compilaba para
   el host. Solución: compilar cada sub-proyecto con su propio
   `cmake -DCMAKE_TOOLCHAIN_FILE=…` encadenado por `CMAKE_PREFIX_PATH`
   (así funciona `vita-app/scripts/build-xrce-client-vita.sh`).
3. **Rust también compila para la Vita**: el target
   `armv7-sony-vita-newlibeabihf` (tier 3) viene en rustc nightly y
   funciona con `-Zbuild-std`. Los `.a` de Rust se enlazan en el mismo
   CMake que los de C.
4. **La versión de tus dependencias importa más que tu código**: el mayor
   bloqueo de la Fase 1 no fue la consola, fue un cliente XRCE v3.0.0
   hablando con un agente v2.4.3 que lo ignoraba en silencio.

## 7. Práctica guiada con este repo

En el PC de desarrollo (con `toolchains/` ya instalado — si no, primero
`05-setup-entorno-cachyos` en la documentación):

```bash
# 1. Activar el entorno (por sesión de shell)
source tools/env-devpc.fish

# 2. Ver el toolchain
arm-vita-eabi-gcc --version
echo $VITASDK

# 3. Dependencias cross-compiladas de la app (una vez)
cd vita-app && ./scripts/build-xrce-client-vita.sh

# 4. Configurar y compilar la variante Rust
cmake -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake \
      -DVITA_IMPL=rust -B build-rust
cmake --build build-rust

# 5. Inspeccionar el resultado
unzip -l build-rust/vita-ros2-hello.vpk

# 6. A la consola: FTP con VitaShell (o USB) e instalar
curl -T build-rust/vita-ros2-hello.vpk ftp://<IP-de-la-vita>:1337/ux0:/
```

> Desde la web del proyecto también puedes lanzar los pasos 4-6 sin
> terminal: sección **Taller → Compilador** (solo disponible cuando la web
> corre en el propio PC de desarrollo).

## 8. Chuleta final

| Quiero... | Herramienta / flag |
|---|---|
| Compilar C/C++ para la Vita | `arm-vita-eabi-gcc` (vía toolchain file de CMake) |
| Mantener relocaciones para el empaquetado | `-Wl,-q` (lo pone `vita.cmake`) |
| ELF → formato Vita (resolver NIDs/stubs) | `vita-elf-create` |
| Firmar para kernel hackeado | `vita-make-fself` → `eboot.bin` |
| Metadatos LiveArea / TITLE_ID | `vita-mksfoex` → `param.sfo` |
| Empaquetar instalable | `vita-pack-vpk` → `.vpk` (es un zip) |
| Llamar al sistema (red, botones...) | headers `psp2/*.h` + `Sce*_stub` + `sceSysmoduleLoadModule` |
| Rust en la Vita | nightly + `armv7-sony-vita-newlibeabihf` + `-Zbuild-std` |
