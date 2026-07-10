# ADR 0006: rviz2 nativo descartado — se activa el Plan B (mini-rviz con vitaGL)

- **Estado:** Aceptado
- **Fecha:** 2026-07-10

## Contexto

Los Objetivos 3 y 4 del proyecto (`docs/00-vision-y-objetivos.md`) piden
compilar rviz2 (o un subconjunto funcional) en la PS Vita y visualizar en
la consola lo que rviz2 visualiza en un PC. `docs/04-investigacion-portabilidad-rviz2.md`
fijó el método: auditar el árbol de dependencias de rviz2 (rclcpp/DDS,
Qt, OGRE) contra VitaSDK/newlib **con compilaciones reales**, no desde la
teoría, y decidir según un árbol de decisión explícito.

La auditoría se ejecutó el 2026-07-10 en el PC de desarrollo (CachyOS,
VitaSDK v2.540, gcc 15.2.0, cmake 4.3.3), según la Etapa A de
`docs/10-plan-objetivos-3-4.md`. Los logs completos quedaron en
`auditoria/` (gitignored); la evidencia citada abajo está copiada
textualmente de ellos y volcada también en docs/04.

## Evidencia

**Capa ROS2 (`rcutils`, rama `jazzy` — la base C de todo `rclcpp`):**

1. El configure muere antes de compilar nada:
   `find_package(ament_cmake_python)` no existe para el target. Todo
   paquete ROS2 (incluido el más básico) exige el build system **ament**,
   que a su vez exige Python + un workspace colcon instalado *para el
   target*. No existe ni puede existir "ament para newlib" sin portar
   antes Python a la Vita.
2. Aislando el código C del build system (compilación a mano con
   `arm-vita-eabi-gcc`):
   - `src/shared_library.c` → `fatal error: dlfcn.h: No such file or
     directory`. **newlib no tiene carga dinámica de bibliotecas**, y el
     sistema entero de plugins de rviz2 (`pluginlib`, con el que se cargan
     TODOS los displays) se basa en `dlopen`.
   - `src/process.c` → `'program_invocation_name' undeclared`: símbolo
     exclusivo de glibc.
   - `src/time_unix.c` → `fatal error: rcutils/logging_macros.h`: ese
     header **no existe en el repo**, se genera en build con Python/empy
     (`resource/logging_macros.h.em`) — hasta los headers dependen de
     ament.
   - En cambio `filesystem.c`, `error_handling.c` y `allocator.c` SÍ
     compilan: el muro no es "el C de ROS2", es el sistema operativo
     asumido (glibc + dlopen) y el build system.
3. Cascada: si `rcutils` no compila, caen `rmw`, `rcl`, `rclcpp`, `tf2` y
   cualquier DDS completo (Fast DDS exige POSIX completo + hilos +
   memoria dinámica abundante). Este era exactamente el contraste que
   motivó micro-ROS/XRCE-DDS en la Fase 1.

**Capa Qt:**

- No existe port de Qt en el ecosistema VitaSDK: la descarga
  `qt5.tar.xz` de vitasdk/packages devuelve **HTTP 404** y ni `qt` ni
  `ogre` aparecen en el listado real del repositorio
  (`api.github.com/repos/vitasdk/packages/contents`, consultado
  2026-07-10). Qt además requiere un backend de ventanas/eventos
  (X11/Wayland/EGLFS) que la Vita no tiene; portarlo sería un proyecto
  independiente completo.

**Capa OGRE (v1.12.13, la que usa `rviz_rendering` en Jazzy):**

- `cmake -S ogre -B build-ogre -DCMAKE_TOOLCHAIN_FILE=.../vita.toolchain.cmake
  -DOGRE_BUILD_RENDERSYSTEM_GLES2=ON` (con
  `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` para cmake 4.x) **no completa el
  configure**: el CMake de OGRE solo define las rutas de
  recursos/instalación para plataformas que reconoce (WIN32/APPLE/UNIX
  de escritorio) y con el triplet de la Vita termina en
  `install FILES given no DESTINATION!` y
  `Variable OGRE_MEDIA_PATH does not exist`.
- Además no encuentra NINGUNA dependencia para el target: `Could NOT
  find OpenGL (missing: OPENGL_opengl_LIBRARY OPENGL_glx_LIBRARY ...)`
  (la Vita no tiene GLX/EGL de sistema; vitaGL no se anuncia como
  OpenGL de CMake), ni ZLIB/Freetype/FreeImage en el sysroot.

## Decisión

**Se descarta portar rviz2 nativo a la Vita. Se activa el Plan B de
docs/04: un visualizador propio ("mini-rviz") con vitaGL**, alimentado
por el cliente micro-ROS/XRCE ya validado en hardware, según la
arquitectura de `docs/10-plan-objetivos-3-4.md` §2 (etapas B–E):

- Los datos (deserialización CDR de `/tf`, `/joint_states`, markers,
  mapa; árbol TF; matemáticas 3D) van en **módulos duales C+Rust**
  testeables en host.
- El render va con **vitaGL** (OpenGL ES) directamente, sin OGRE ni Qt.
- El modelo del robot se convierte en el PC/web (URDF → formato binario
  VBM) porque la Vita no parsea XML/DAE.

El Objetivo 3 queda **respondido** (era una pregunta de investigación:
"¿es portable?" → no, con evidencia) y el Objetivo 4 se cumple con el
mini-rviz.

## Consecuencias

**Positivas:**

- Camino desbloqueado sin dependencias externas gigantes: vitaGL está
  empaquetado en vitasdk/packages (verificado HTTP 200 el 2026-07-07).
- Coherencia con la Fase 1: misma filosofía que sustituir DDS por
  XRCE-DDS — en la consola solo corre lo mínimo, el peso queda en el PC.
- La lógica de visualización (viz-math, msg-cdr, tf-tree) es dual y
  testeable en la laptop; solo el dibujo final es código Vita.

**Negativas / lo que el mini-rviz NO tendrá:**

- Ni sistema de plugins ni displays arbitrarios: un conjunto fijo
  (grid, ejes/TF, modelo del robot, markers básicos, OccupancyGrid
  acotado, PointCloud2 reducido como extensión futura).
- Ni panel de propiedades estilo Qt: la configuración de la escena será
  declarativa (JSON) y editable desde la web del proyecto.
- Topes duros dictados por XRCE/RAM: mapas acotados (fragmentación de
  buffers), nº de transforms/markers limitado, mallas "cocidas" con tope
  de vértices.
- El resultado no es "rviz2 en la Vita" literal: es la visualización que
  rviz2 daría, con un motor propio. Esto se comunica así en la web.

## Alternativas consideradas

**Portar rviz2 entero (descartada):** exigiría, en cadena: Python+ament
para newlib, un port de Qt con backend de ventanas propio, un port de
OGRE a una plataforma que su build no reconoce, y sustituir Fast DDS por
otra cosa — cuatro proyectos mayores que el nuestro, cada uno sin
garantía.

**Compilar solo `rviz_rendering` + escena sin Qt (descartada):**
`rviz_rendering` depende de OGRE (muro propio) y de ament (muro
compartido con todo ROS2). Incluso su subconjunto útil (los meshes de
primitivas) es trivial de reimplementar con vitaGL comparado con el
coste de arrastrar OGRE.

**Streaming de vídeo del rviz2 del PC a la Vita (descartada como
objetivo, posible como juguete futuro):** no cumple el espíritu del
Objetivo 4 (la Vita sería un monitor tonto, no un nodo ROS2 que
entiende los datos) y añade latencia/ancho de banda sin quitar ninguna
incógnita.
