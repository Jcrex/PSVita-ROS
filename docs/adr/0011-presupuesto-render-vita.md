# ADR 0011: Presupuesto de render y visualización sin shaders en la Vita

- **Estado:** Aceptado como diseño el 2026-11-12 — **por medir** en hardware (E-W8-0…6, doc 31 §6). Juicio de Fable pendiente.
- **Fecha:** 2026-11-12

## Contexto

La etapa «estación robótica» quiere en la Vita una visualización tipo RViz2 (TF, RobotModel, LaserScan, mapa,
Path, marcadores, odometría, pose, imagen y nube decimada) sobre Godot 4 (`godot4-vita`), tras la enmienda de
ADR 0008 §5 que delega el 3D en Godot. Hechos verificados en el código del port (detalle y líneas en
`docs/ia/workshops/posts/W8-borrador.md` §1):

1. El 3D GXM solo dibuja triángulos de `MeshInstance3D`, con color = albedo × tinte y textura con filtro POINT.
   No hay líneas, puntos, MultiMesh, color por vértice ni shaders (`rasterizer_scene_gxm_vita.inc:70,912,968`).
2. La geometría vive en un arena de 24 MiB que no libera mallas sueltas; cambiar una malla la vuelve a copiar y,
   al llenarse el arena, se reconstruye todo (`rasterizer_scene_gxm_vita.inc:187-221,1225-1230`).
3. Las superficies opacas reciben una segunda pasada de luz por vértice que duplica *draws* y no está pensada para
   mallas que cambian (`rasterizer_scene_gxm_vita.inc:602-655,996-1033`).
4. El lienzo 2D es la ruta validada en hardware (G6, G7c): baja todo a *quads* con color por primitiva y los funde
   en lotes, pero lo recalcula cada fotograma (`gxm_canvas_vita.inc:355-397`, `loader/gxm_bridge.c:46-107`).
5. Hay un núcleo efectivo para GDScript, render y XRCE (W1), y los mensajes llegan ya compactados por el relay del
   PC en datagramas de ≤ 488 B (`docs/27`).
6. Único dato de hardware del 3D: 59 FPS con 20 instancias y 5 574 triángulos (G7c, `docs/06`).

## Decisión

1. **Reparto por naturaleza del dato, en dos capas.**
   - *Rígido o estático* → **3D GXM**: instancias que se mueven por `transform` (RobotModel, ejes TF, marcadores,
     poses, mapa como quad, rejilla). Lo estático se hornea: una instancia por grupo.
   - *Denso y dinámico* (LaserScan, nube decimada, líneas y puntos de marcadores) → **2D CanvasItem** en una sola
     llamada por display (`canvas_item_add_triangle_array`, `draw_multiline_colors`).
   - *Raster* (OccupancyGrid, costmap, imagen) → **textura** actualizada a ≤ 4 Hz; una textura compuesta por capa.
   - *Texto* → 2D.
2. **Dos vistas:** «Planta 2D» (solo CanvasItem; el `transform` del nodo hace de cámara) y «Orbital 3D» (3D más
   2D superpuesto, proyectado por lotes).
3. **Color sin shaders:** textura-paleta compartida de 16×16 con UV por triángulo y un texel con alfa, que saca a
   las primitivas de visualización de la pasada de luz. Un material, una superficie y un *draw* por malla.
4. **Reglas de malla en 3D:** solo `PRIMITIVE_TRIANGLES`; prohibidos MultiMesh, GridMap, CSG, `Sprite3D`,
   `Label3D`, `surface_update_*` y las transparencias superpuestas; una malla reconstruida por mensaje solo se
   admite a ≤ 2 Hz (Path) mientras E-W8-2 no esté verde, y nunca con material opaco sin alfa.
5. **Decodificación por regla de corte:** relay si el CDR pasa de 488 B; C++ del motor (JPEG/PNG, `blit_rect`) si
   existe; GDScript si cuesta ≤ 2 ms por mensaje y ≤ 1 ms por fotograma de media; si no, C en el módulo dual
   `viz-decode`, expuesto por `ros2_vita`.
6. **Presupuesto inicial** (Viz a 30 FPS / HMI a 60 FPS): 30 000 / 15 000 triángulos; 150 / 80 instancias 3D;
   1 500 *quads* 2D; 16 MiB y 48 texturas; CPU por fotograma: 8 / 4 ms de GDScript y red, 9 / 6 ms de envío 3D,
   3 / 2 ms de lienzo. Reparto: robot 15 000 triángulos y 40 instancias; mapa y entorno 3 000 y 12; TF 1 200 y 32;
   marcadores 3 000 y 48; resto reserva.
7. **Ajustes fijos de la app:** `rendering/vita/distance_darkening=false`, `shadow_rays=0`, `light_flares=false`,
   `triangle_budget=40000`; texturas RGBA8888; cámara cenital a ≤ 20 m.
8. **El rasterizador no se parchea en la Fase 1.** El presupuesto se revisa con los gates E-W8-0…6; un gate rojo
   activa, por este orden, bajar el contenido, mover el display de capa o el parche P1.

## Alternativas descartadas

- **Parchear ya el rasterizador** (color por vértice, líneas 3D): viable con lo que vita2d ya ofrece, pero exige
  mantener un parche del motor y recompilar la plantilla; la paleta y el 2D cubren la Fase 1. Queda registrado
  (P1 actualización en sitio, P2 color y líneas, P3 MSAA).
- **vitaGL de `vita-app/`** (ADR 0007): no convive con Godot en la GPU y duplicaría toda la aplicación.
- **Solo vista 2D cenital:** deja fuera RobotModel y TF en 3D, que G7c y el G1 ya demuestran; se conserva como
  una de las dos vistas.
- **Todo lo dinámico como ArrayMesh 3D:** ruta sin validar, con consumo de arena y riesgo con la pasada de luz;
  se admite por display cuando E-W8-2 esté verde.
- **Una instancia por punto / una superficie por color:** demasiados *draws*.
- **Decodificar mensajes crudos en GDScript:** ni caben por XRCE ni caben en el fotograma.

## Consecuencias

- **Positivas:** la Fase 1 no necesita plantilla nueva (todo es GDScript + relay); cada display tiene un coste
  acotado y medible con líneas de log que ya existen; el color y las líneas quedan resueltos sin tocar el motor.
- **Negativas:** lo superpuesto en 2D no se oculta tras la geometría 3D; cada display denso necesita dibujo para
  las dos vistas; los colores se cuantizan a 256; sin MSAA las cajas finas necesitan un grosor mínimo.
- **Trabajo derivado:** capa «GXM-safe» de gdviz con estas técnicas (W4, T-W4-4); arreglos baratos de
  `godot/comun/vita_relay.gd`, `minimapa.gd`, `urdf_robot.gd` y casa horneada; proyecto `godot/w8-bench`; módulo
  `viz-decode` cuando toque recompilar la plantilla.
- **Riesgo asumido:** las cifras del presupuesto son de diseño hasta medir; el único dato real es G7c. El gate
  G8-G1 (≈ 137 *draws* con luz por vértice) es la primera comprobación.
- **Lo que no se puede verificar en el PC** (render GXM, tiempos de GDScript a 444 MHz) lleva la marca «validar en
  hardware».

---
