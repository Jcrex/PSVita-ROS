# Investigación de portabilidad de rviz2 a VitaSDK

**Fecha de creación:** 2026-06-08
**Estado:** **Investigación EJECUTADA (2026-07-10, en el PC)** — decisión:
rviz2 nativo NO es portable; **Plan B activado** (mini-rviz con vitaGL).
Decisión formal y evidencia citada en `docs/adr/0006-decision-rviz2-vs-mini-rviz.md`;
logs completos en `auditoria/` (gitignored). Ejecutada según la Etapa A de
`docs/10-plan-objetivos-3-4.md`.

---

## La pregunta

**¿Es portable rviz2 nativamente a VitaSDK, o hay que desarrollar un visualizador propio?**

Esta es la pregunta abierta que corresponde a los objetivos 3 y 4 del proyecto: compilar rviz2 en la Vita y usarlo para visualizar el estado de un robot como se haría en un PC. La respuesta no se puede dar desde la teoría; debe provenir de un análisis sistemático del árbol de dependencias de rviz2 contra las capacidades reales de VitaSDK y newlib.

Este documento fija el **método de investigación** y el árbol de decisión a seguir. No contiene afirmaciones sobre lo que es o no portable: todo está marcado como `[abierto]` hasta que se audite en el PC con herramientas reales. Los "muros previsibles" son hipótesis, no hechos confirmados.

La investigación se ejecutará durante una fase posterior del proyecto, una vez que el objetivo 1 (micro-ROS) esté validado. Registrar el método aquí sirve para que cuando llegue el momento, el trabajo esté estructurado y no se parta de cero.

---

## Árbol de dependencias a auditar

rviz2 tiene un árbol de dependencias sustancial. El análisis debe recorrer ese árbol de arriba a abajo para encontrar en qué nivel exacto aparece el primer muro infranqueable. Cada capa se marca como `[abierto]` hasta que se audite.

### Capa de rviz2 propiamente dicha

- **`rviz2`** `[NO PORTABLE — por cascada]`: el paquete principal. Cae porque caen todas sus dependencias (ver abajo).
- **`rviz_common`** `[NO PORTABLE — por cascada + dlopen]`: lógica compartida y gestión de plugins. La carga de displays usa `pluginlib` → `dlopen`, y **newlib no tiene `dlfcn.h`** (verificado compilando `rcutils/src/shared_library.c`: `fatal error: dlfcn.h: No such file or directory`). Sin carga dinámica, la arquitectura de plugins de rviz2 no existe.
- **`rviz_rendering`** `[NO PORTABLE — OGRE + ament]`: hereda el muro de OGRE (abajo) y el del build system ament (abajo).
- **`rviz_default_plugins`** `[NO PORTABLE — por cascada]`: dependen de `rviz_common` y `rviz_rendering`.

### Capa Qt

- **`Qt5/Qt6 Widgets`** `[NO PORTABLE — no existe port]`: verificado 2026-07-10: `qt5.tar.xz` en vitasdk/packages devuelve **HTTP 404** y ni `qt` ni `ogre` figuran en el listado real del repositorio (API de GitHub). La hipótesis del backend de ventanas queda confirmada como hallazgo: la Vita no tiene X11/Wayland/EGLFS y nadie ha portado uno para Qt.
- **`Qt5/Qt6 OpenGL`** `[NO PORTABLE — por cascada]`: sin Qt base no hay widgets OpenGL que auditar.

### Capa OGRE

- **OGRE 1.12.13** (la versión de `rviz_rendering` en Jazzy) `[NO PORTABLE — configure no completa]`: verificado 2026-07-10 con `cmake -DCMAKE_TOOLCHAIN_FILE=.../vita.toolchain.cmake -DOGRE_BUILD_RENDERSYSTEM_GLES2=ON`. El CMake de OGRE **no reconoce la plataforma** (solo define rutas de recursos para WIN32/APPLE/UNIX de escritorio): aborta con `install FILES given no DESTINATION!` y `Variable OGRE_MEDIA_PATH does not exist`. Además no encuentra NINGUNA dependencia para el target: `Could NOT find OpenGL (missing: OPENGL_opengl_LIBRARY OPENGL_glx_LIBRARY ...)` (no hay GLX/EGL de sistema; vitaGL no se anuncia a CMake como OpenGL), ni ZLIB/Freetype/FreeImage en el sysroot. El backend GLES2 nunca llega a auditarse porque el configure muere antes.

### Capa ROS2

- **`rcutils`** (base C de todo) `[NO PORTABLE — ament + glibc + dlopen]`: verificado 2026-07-10 (rama `jazzy`):
  - Configure: muere en `find_package(ament_cmake_python)` — **todo paquete ROS2 exige el build system ament (Python) instalado para el target**; no existe para newlib.
  - Compilación a mano de fuentes representativas con `arm-vita-eabi-gcc`: `shared_library.c` → falta `dlfcn.h` (newlib no tiene carga dinámica); `process.c` → `'program_invocation_name' undeclared` (símbolo exclusivo de glibc); `time_unix.c` → falta `rcutils/logging_macros.h`, que **se genera en build con Python/empy** (`resource/logging_macros.h.em`) — hasta los headers dependen de ament. En cambio `filesystem.c`, `error_handling.c` y `allocator.c` compilan sin errores: el muro no es "el C de ROS2", es el SO asumido (glibc+dlopen) y el build system.
- **`rclcpp`** `[NO PORTABLE — por cascada]`: si `rcutils` no compila, caen `rmw` → `rcl` → `rclcpp`.
- **`tf2`** `[NO PORTABLE — por cascada]`: mismo build system ament + rclcpp.
- **DDS (Fast DDS / Cyclone DDS)** `[NO AUDITADO — innecesario]`: con toda la capa superior caída no aporta nada auditarlo; la hipótesis (POSIX completo + hilos + memoria dinámica abundante) queda como registrada. El proyecto ya sustituye DDS por XRCE-DDS desde la Fase 1, validado en hardware.

---

## Muros previsibles (hipótesis — CONFIRMADAS el 2026-07-10)

Estos eran los obstáculos que el análisis de la arquitectura hacía esperar. La auditoría del 2026-07-10 los confirmó todos (con matices: el muro más temprano no fue newlib en sí, sino **el build system ament**, que exige Python para el target antes siquiera de llegar a compilar C). Evidencia textual arriba y en ADR 0006.

**newlib versus glibc.** La diferencia más profunda y omnipresente. `rclcpp`, Qt, OGRE y prácticamente todas las dependencias de rviz2 asumen glibc de forma implícita o explícita. Incluso si las dependencias directas parecen portables, sus dependencias transitivas pueden requerir funciones, macros o comportamientos específicos de glibc que newlib no implementa. El alcance exacto de este muro solo se conoce compilando con el toolchain de VitaSDK y observando los errores.

**Qt sobre VitaSDK.** Qt requiere un sistema de ventanas (X11, Wayland, un backend nativo) o un framebuffer gestionable. La Vita no tiene ninguno de estos de serie; `vita2d` y `vitaGL` ofrecen acceso directo al framebuffer pero no siguiendo ningún protocolo que Qt reconozca. Portar un backend mínimo de Qt para la Vita sería un proyecto en sí mismo, independiente del resto.

**OGRE sobre `vitaGL`/GLES.** `vitaGL` implementa OpenGL ES, que es el subconjunto de OpenGL diseñado para plataformas móviles y embebidas. OGRE tiene un backend GLES2, pero eso no significa que compile con newlib ni que las rutas de código para carga de recursos, gestión de plugins y sistema de archivos funcionen sobre la Vita. Este punto requiere auditoría específica del backend GLES2 de OGRE.

**`rclcpp` + DDS pesados versus micro-ROS.** `rclcpp` con DDS completo es el polo opuesto de micro-ROS en el espectro de peso de la comunicación ROS2. Si el análisis concluye que `rclcpp` + DDS son imposibles de portar (lo cual es la expectativa), entonces cualquier parte de rviz2 que dependa de `rclcpp` para comunicarse con el grafo necesitaría ser reemplazada por una capa equivalente sobre micro-ROS.

---

## Árbol de decisión

El método de investigación sigue un árbol de decisión explícito:

```
¿Compila rclcpp con VitaSDK/newlib?
├─ SÍ → auditar tf2, DDS, Qt
└─ NO → documentar el muro exacto (símbolo, función, cabecera)
         → activar Plan B: visualizador propio con vitaGL

¿Compila Qt5/Qt6 con VitaSDK/newlib?
├─ SÍ → auditar el backend de ventana en la Vita
└─ NO → documentar el muro exacto
         → activar Plan B (Qt no es necesario en el Plan B)

¿Compila rviz_rendering (OGRE GLES2) con VitaSDK/newlib?
├─ SÍ → auditar la integración con vitaGL
└─ NO → documentar el muro exacto
         → activar Plan B: usar vitaGL directamente

¿Funciona el conjunto completo en la plataforma real?
├─ SÍ → objetivo 3 y 4 desbloqueados con rviz2 nativo
└─ NO (cualquier muro) → Plan B: mini-rviz propio
```

Cuando una dependencia clave no es portable, el resultado del análisis no es "es imposible" y parar. Es **documentar el muro exacto**: qué símbolo falla, en qué archivo, en qué fase del build, con qué mensaje de error. Esa información es valiosa tanto para el proyecto como para la comunidad; es exactamente el tipo de resultado que merece publicarse.

### Plan B: visualizador propio ("mini-rviz")

Si el análisis concluye que rviz2 nativo no es portable de forma razonable, el Plan B es desarrollar un visualizador propio para la Vita usando `vitaGL` (OpenGL ES). Este visualizador no intenta replicar toda la funcionalidad de rviz2; se centra en los tipos de mensajes más útiles para un operador de robot en movilidad:

- **`visualization_msgs/MarkerArray`**: formas geométricas básicas (cubos, esferas, cilindros, flechas) para visualizar el estado del robot y su entorno.
- **`nav_msgs/OccupancyGrid`**: mapa de ocupación 2D, el resultado más común de SLAM. Renderizable como textura.
- **`tf2_msgs/TFMessage`**: transformadas de coordenadas para posicionar los elementos del robot en el espacio.
- **`sensor_msgs/PointCloud2` reducido**: una versión reducida de la nube de puntos, limitada en número de puntos para no saturar el ancho de banda ni la GPU de la Vita.

Este "mini-rviz" estaría alimentado por el cliente micro-ROS de la Vita y sería una app nativa que aprovecha los sensores de la consola para aumentar la experiencia de operación.

---

## Resultado de la investigación (2026-07-10, en el PC)

La auditoría se ejecutó tal como este documento la fijó (Etapa A de `docs/10-plan-objetivos-3-4.md`), en el PC de desarrollo con VitaSDK v2.540 / gcc 15.2.0 / cmake 4.3.3. Resumen del recorrido del árbol de decisión:

- **¿Compila rclcpp con VitaSDK/newlib?** → **NO.** Ni siquiera `rcutils` (su base C) supera el configure: `find_package(ament_cmake_python)` no existe para el target. Aislando el build system, el C choca con `dlfcn.h` inexistente (newlib no tiene dlopen), `program_invocation_name` (glibc) y headers generados por Python/empy.
- **¿Compila Qt con VitaSDK/newlib?** → **NO EXISTE port** (404 en vitasdk/packages, ausente del listado del repositorio; sin backend de ventanas posible).
- **¿Compila rviz_rendering (OGRE GLES2)?** → **NO.** El configure de OGRE 1.12.13 aborta: plataforma no reconocida (`OGRE_MEDIA_PATH does not exist`) y cero dependencias encontradas para el target (`Could NOT find OpenGL ...GLX...`).
- **¿Funciona el conjunto completo?** → No aplica: los tres muros anteriores lo impiden.

**Decisión final: Plan B activado** — mini-rviz propio con vitaGL, alimentado por el cliente micro-ROS/XRCE ya validado en hardware (Fase 1 y Objetivo 2). Formalizada en `docs/adr/0006-decision-rviz2-vs-mini-rviz.md`; el diseño fino del mini-rviz va en `docs/11-diseno-mini-rviz.md` (Etapa B0 del plan). Los logs crudos de la auditoría (`log-rcutils-configure.txt`, `log-rcutils-manual.txt`, `log-ogre-configure.txt`) quedan en `auditoria/` en el PC (carpeta gitignored; si se pierde, los comandos exactos para regenerarlos están en la Etapa A del plan).

El valor del documento pasó de fijar el método a **registrar la respuesta del Objetivo 3 con evidencia**: rviz2 nativo no es portable a la Vita, y ahora se sabe exactamente por qué (ament/Python, dlopen, glibc, Qt inexistente, OGRE sin soporte de plataforma), no por intuición.
