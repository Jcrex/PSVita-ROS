# Visión y objetivos del proyecto PS Vita ↔ ROS2

**Fecha de creación:** 2026-06-08
**Estado:** Fundación aprobada

---

## Propósito

Este proyecto es un experimento de largo plazo que tiene como meta convertir una PS Vita 1000 en un cliente y nodo real del ecosistema ROS2 Jazzy. La consola, mediante homebrew desarrollado con VitaSDK, se incorpora al grafo de comunicación de ROS2 como un participante legítimo: capaz de publicar y suscribirse a topics, interactuar con otros nodos y, en fases avanzadas, visualizar información del robot directamente en su pantalla.

El proyecto no es un prototipo desechable. Desde su inicio está diseñado con vocación de publicarse: la arquitectura, las decisiones técnicas, los módulos de código y las herramientas que se desarrollen deben ser lo suficientemente rigurosos y documentados como para ser útiles a la comunidad de desarrollo embebido y robótica. Esto implica mantener estándares de calidad elevados en cada fase, documentar los muros encontrados con la misma seriedad que los logros, y construir sobre bases sólidas antes de avanzar.

---

## Los 6 objetivos

El proyecto se estructura en torno a seis objetivos concretos, abordados de forma secuencial. No se diseña en detalle el siguiente objetivo hasta que el anterior esté validado.

1. **Recibir y enviar topics de ROS2.** La Vita se convierte en un nodo del grafo mediante micro-ROS (cliente Micro XRCE-DDS) comunicado vía WiFi/UDP con un agente que lo conecta al ecosistema Jazzy. Este es el cimiento de todo lo demás y el foco de la Fase 1.

2. **Controlar un robot desde la Vita usando joysticks, botones y pantallas táctiles.** Con la conectividad ROS2 establecida, la Vita actúa como mando de control avanzado: los dos sticks analógicos, la cruceta, los botones frontales, la pantalla táctil delantera (OLED) y el panel táctil trasero generan mensajes `geometry_msgs/Twist` u otros tipos adecuados que el robot recibe y ejecuta.

3. **Compilar una app de ROS2 (rviz2) en la consola y que sea funcional.** El objetivo no es solo mostrar algo en pantalla sino lograr que rviz2, o un subconjunto suficiente de él, compile y ejecute sobre VitaSDK de forma nativa. Este es un reto de ingeniería de portabilidad de primer orden.

4. **Recibir topics y visualizar robots, mapas y otros topics en rviz2 como en un PC.** Una vez que existe una capacidad de visualización en la Vita, esta debe consumir el mismo tipo de información que rviz2 consume en un ordenador de desarrollo: transformadas TF, mallas de robot, mapas de ocupación, nubes de puntos y marcadores. La consola se vuelve un panel de control visualizador portátil.

5. **Aprovechar el hardware propio de la Vita para una app nativa de control y gestión.** La cámara frontal y trasera publican imágenes por ROS2; el giroscopio y acelerómetro envían datos de orientación e inercia; el panel táctil trasero ofrece una superficie de interacción sin igual para interfaces de operador. El objetivo es una aplicación nativa que explote estos sensores de forma integrada.

6. **Desarrollar un conjunto de herramientas para estandarizar el desarrollo ROS2 → PS Vita y publicarlo.** El toolkit incluye las skills de Claude Code, el MCP de introspección de ROS2, los CMake modules para el toolchain dual, la infraestructura de tests de paridad y la documentación de arquitectura. La meta final es que otro desarrollador pueda replicar el entorno y comenzar su propio proyecto ROS2 en PS Vita partiendo de esta base.

---

## Restricciones transversales

Estas restricciones aplican a todas las fases del proyecto sin excepción:

**Doble implementación Rust + C/C++ con C/C++ como respaldo permanente.** Todo módulo que toque hardware, memoria o el sistema embebido de la Vita se implementa en ambos lenguajes. El contrato entre implementaciones es un header C (`.h`) que define la interfaz pública. La implementación Rust compila a `staticlib` con `#[no_mangle] extern "C"` y debe superar la misma batería de tests de paridad que la implementación C/C++. Esto garantiza que en cualquier momento sea posible sustituir la implementación Rust por la C/C++ sin cambiar nada más. C/C++ no es el segundo idioma: es el respaldo permanente y equivalente.

**Proyecto secuencial por objetivos.** Los objetivos se abordan en orden. No se comienza el diseño detallado del objetivo N+1 hasta que el objetivo N esté completado y validado. Esto evita acumular deuda técnica sobre supuestos no verificados.

**La laptop no instala nada.** El equipo portátil utilizado como taller de preparación produce únicamente artefactos de texto: documentación, specs, skills, código del MCP y scripts. Toda compilación, instalación y ejecución ocurre en el PC de desarrollo (CachyOS). La laptop emite la fundación una vez y el PC es siempre la fuente de verdad del desarrollo.

---

## Marco de fases

**Fase 0 — Fundación (esta fase):** Establece la capa meta del proyecto. Produce la documentación de arquitectura, las decisiones técnicas registradas (ADRs), las skills de Claude Code para automatizar workflows repetitivos, el MCP `ros2-introspection` para dar visibilidad del grafo ROS2 en tiempo real, y la guía de setup del entorno en el PC. No se escribe aún código que corra en la Vita.

**Fase 1 — Objetivo 1 (micro-ROS):** Arranca sobre la fundación. La tarea central es validar la incógnita dura: ¿levanta el cliente micro-ROS en la Vita y mantiene sesión con el agente usando el transporte UDP propio sobre `sceNet`? El criterio de éxito concreto es que la Vita publique en un topic visible con `ros2 topic echo` en el PC y reciba un topic publicado desde el PC.

**Objetivos 3 a 6 — Incógnitas documentadas, no diseñadas aún:** Los objetivos restantes están enunciados y su viabilidad técnica ha sido estudiada a nivel de hipótesis (ver `docs/04-investigacion-portabilidad-rviz2.md`), pero no tienen diseño detallado. Se mantendrán como incógnitas abiertas documentadas hasta que el trabajo secuencial llegue a ellos. Esto es intencional: diseñar en detalle algo que no se ha validado aún introduce complejidad prematura y puede construirse sobre supuestos que la práctica invalidará.
