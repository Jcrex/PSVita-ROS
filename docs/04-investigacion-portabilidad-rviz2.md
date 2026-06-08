# Investigación de portabilidad de rviz2 a VitaSDK

**Fecha de creación:** 2026-06-08
**Estado:** Método definido — investigación pendiente de ejecución en el PC

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

- **`rviz2`** `[abierto]`: el paquete principal. Depende de los siguientes.
- **`rviz_common`** `[abierto]`: lógica compartida, gestión de plugins, tipos de display, gestión de transformadas.
- **`rviz_rendering`** `[abierto]`: toda la capa de renderizado. Usa OGRE 1.x como motor 3D. Este es probablemente el nodo más crítico del árbol desde la perspectiva de portabilidad.
- **`rviz_default_plugins`** `[abierto]`: los plugins estándar (LaserScan, MarkerArray, PointCloud2, Map, TF, RobotModel, etc.). Dependen de `rviz_common` y `rviz_rendering`.

### Capa Qt

- **`Qt5 Widgets`** o **`Qt6 Widgets`** `[abierto]`: rviz2 usa Qt para toda su interfaz de usuario. Qt en plataformas no estándar requiere backends específicos para eventos del sistema, framebuffer o ventana nativa. VitaSDK no tiene ninguno de estos de serie.
- **`Qt5/Qt6 OpenGL`** `[abierto]`: rviz2 usa widgets OpenGL de Qt para integrar el viewport de OGRE. Separar la lógica de Qt del renderizado OpenGL es en teoría posible pero requiere refactorización profunda.

### Capa OGRE

- **OGRE 1.x** (via `rviz_rendering`) `[abierto]`: el motor de renderizado 3D que usa rviz2. OGRE tiene backends de renderizado intercambiables; existe un backend OpenGL ES que en teoría podría mapearse a `vitaGL`. Sin embargo, OGRE asume un sistema de archivos estándar, hilos POSIX completos y una cantidad de infraestructura de sistema operativo que newlib puede no proveer completamente.

### Capa ROS2

- **`rclcpp`** `[abierto]`: la biblioteca cliente de ROS2 en C++. Asume Linux, glibc, y hace uso intensivo de las capacidades POSIX completas. Es la dependencia más pesada en términos de sistema operativo.
- **`tf2`** `[abierto]`: transformadas de coordenadas. Tiene sus propias dependencias de Boost y biblioteca estándar de C++.
- **DDS (Fast DDS / Cyclone DDS)** `[abierto]`: el middleware de comunicación completo. Asume sockets POSIX, hilos, y gestión de memoria dinámica abundante. Contrasta directamente con el enfoque de micro-ROS que sustituye DDS por XRCE-DDS para plataformas limitadas.

---

## Muros previsibles (hipótesis a confirmar)

Estos son los obstáculos que el análisis de la arquitectura hace esperar, pero **ninguno es un hecho hasta que se verifique** con una compilación real y herramientas de auditoría de dependencias en el PC.

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

## Salida esperada de la investigación

Este documento se completa con hallazgos reales durante la fase de portabilidad, que ocurrirá una vez que el objetivo 1 esté validado. Cuando llegue ese momento, este documento se actualiza añadiendo:

- Los resultados de auditar cada capa marcada como `[abierto]`, con evidencia (logs de compilación, mensajes de error específicos).
- Los muros encontrados con documentación exacta: qué falla, por qué, y si tiene solución razonable.
- La decisión final: rviz2 nativo posible (y con qué adaptaciones) o Plan B activado.
- Si se activa el Plan B, el diseño inicial del "mini-rviz" pasa a otro documento de diseño.

El valor de este documento en su estado actual es fijar el **método**: saber exactamente qué hay que auditar, en qué orden, y qué decisión tomar según cada resultado posible. Sin este árbol de decisión, la investigación puede dispersarse o llegar a conclusiones prematuras.
