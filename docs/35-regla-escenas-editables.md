# 35 — Regla de escenas editables: la escena manda en lo que se ve y dónde

> Estado: implantada el 2026-11-13 en `godot/plantillas/` (mundo común) y en los proyectos `g1-sensores`,
> `rbkairos-plus`, `dron-mapeo` y `g1-unitree`. Pruebas de host verdes (§5). Decisión del usuario: mundo
> **compartido** entre los proyectos de plantillas.

## 1. El problema

Hasta ahora, `main.tscn` de cada proyecto era un único nodo con un script. Todo lo demás se creaba al arrancar,
en código: el mundo (cajas en `mundo_base.gd` y 56 modelos listados en `mundo/assets.json`), el robot, la luz, el
ambiente, la cámara y el HUD. Al abrir el proyecto en Godot, la escena principal salía **vacía**, y para mover un
edificio había que cambiar coordenadas ROS en un JSON y ejecutar el proyecto para ver el resultado.

## 2. Por qué estaba así [V]

1. **Una copia para varios proyectos.** `comun -> ../plantillas` es un enlace simbólico (doc 29 §2). Mundo y
   aplicación son de todos, y cada proyecto solo aporta su `robot.json`.
2. **El contenido depende de la plataforma y se decide al arrancar.**
   - Modelo del robot: `visual_pc` o `visual_vita`.
   - Mundo: `modelo` o `modelo_vita`.
   - En la Vita, las cajas se funden por color y los adornos no se dibujan (doc 34).

   Una escena que guardara las mallas de PC haría que la Vita las cargara también.
3. **Los sensores van montados en links del URDF**, que solo existen cuando el modelo ya está instanciado
   (`aplicacion_robot.gd`, `_buscar_link`).
4. **Motivo práctico:** muchas sesiones de IA trabajaban sin editor gráfico (la de la nube, por ejemplo), y
   editar JSON es más fácil que editar `.tscn` a mano.

Ninguno de los cuatro obliga a tener la escena vacía. El 2 solo obliga a no **guardar** mallas en la escena.

## 3. La regla

> **Lo que se ve y dónde está es una escena (`.tscn`) editable en Godot. El código solo adapta esa escena a la
> plataforma (PC o Vita) y crea lo que depende de la ejecución. Los JSON quedan para la configuración que no es
> colocar cosas.**

| Va en la escena (editor) | Va en código | Va en JSON (`robot.json`, `topics.json`) |
|---|---|---|
| Terreno, casa, edificios, coches, muebles, personas; sus colisiones y movimiento | Elegir la malla PC/Vita, fundir cajas, ocultar adornos, visibilidad por distancia | Script de control, nodo y namespace ROS |
| Luz y ambiente | Robot con su física, sensores y TF | Topics, Hz, QoS, prefijos compactos |
| Punto de salida del robot (`InicioRobot`) | Cámara de seguimiento y HUD | Sensores (tipo, link, parámetros), cámara, presupuesto |

Corolarios:

- **No se guardan mallas que la Vita no deba cargar.** Un nodo que tiene variante de Vita guarda la **ruta** y crea
  la malla al arrancar. En el editor la muestra con un hijo `Vista` sin `owner`, que no se guarda
  (`asset_mundo.gd`, `inicio_robot.gd`).
- **Si un nodo no está en la escena, el código lo crea como antes.** Así una escena antigua o mínima sigue
  funcionando (`aplicacion_robot.gd`: `Mundo`, `Ambiente`, `Luz`, `InicioRobot`; `g1-unitree/main.gd`: `Casa`,
  `Luz`, `Ambiente`).
- **Si una escena sale de otra fuente, se edita esa fuente.** `g1-unitree/casa/casa.tscn` la genera
  `docker/g1/casa.py` desde `docker/g1/casa.json`, que también usan MuJoCo y `casa/mapa.pgm`. Se ve en el editor,
  pero los cambios van en `casa.json`; si no, Godot y el simulador dejarían de coincidir.
- **Después de cambiar el mundo se pasan las pruebas de presupuesto** (§5). El límite de la Vita (ADR 0011) no lo
  vigila el editor.

## 4. Qué cambió

### 4.1 Mundo común (`godot/plantillas/mundo/`)

- **`mundo.tscn`** ya no es un nodo vacío: contiene los grupos `Terreno` (19 cajas), `Casa` (8 cajas y los
  muebles), `Ciudad`, `Bosque`, `Parque` y `Exterior`, con los 56 modelos. Lo generó una sola vez una conversión
  desde `assets.json` y las cajas que estaban escritas en `mundo_base.gd@68e75c1`. **`assets.json` se ha borrado**:
  la escena es ahora la única fuente.
- **`caja_mundo.gd`** (en un `MeshInstance3D` con `BoxMesh`): se mueve con el gizmo, el tamaño está en `mesh.size` y
  el color en el material, que comparten las cajas del mismo color («Make Unique» para cambiar una sola). `solido`
  indica si choca.
- **`asset_mundo.gd`** (`@tool`, en un `Node3D`), con estas propiedades:
  - `modelo` y `modelo_vita` (rutas);
  - `dibujar_en_vita`;
  - `lod_vita`: 0 = fracción por defecto, > 0 = esa fracción, < 0 = no reducir;
  - `radio_movimiento`, `velocidad_movimiento` y `fase_movimiento`.

  La colisión es el hijo `Colision`, un `StaticBody3D` con escala 1/escala del nodo para que su caja quede en
  metros.
- **`mundo_base.gd`** ya no construye el mundo, lo adapta:
  - pone la colisión a las cajas sólidas;
  - en el perfil ligero, funde las cajas aplicando su transformación completa (ahora se pueden girar);
  - crea la malla de cada modelo según el perfil;
  - registra los agentes que se mueven.

  Como el mundo está dentro de `main.tscn`, su `_ready()` se ejecuta antes que el de la aplicación, así que decide
  el perfil por sí mismo con `Perfil.es_ligero()` (`ros/perfil.gd`). Las pruebas pueden fijarlo antes de añadirlo
  al árbol.
- **`tools/generar-lod-vita.py`** lee y anota `mundo.tscn`, sección por sección y como texto, en lugar de
  `assets.json`. Hay que ejecutarlo con el editor cerrado.

### 4.2 Escenas principales

- `g1-sensores`, `rbkairos-plus` y `dron-mapeo` tienen ahora en `main.tscn` los nodos `Mundo` (instancia), `Ambiente`,
  `Luz` e `InicioRobot` (`plantillas/inicio_robot.gd`, `Marker3D` con vista previa de `visual_pc` en el editor).
  **`spawn_ros` se ha quitado de los tres `robot.json`**: el punto de salida es el `InicioRobot`, y R / △ devuelven
  el robot ahí.
- `g1-unitree/main.tscn` tiene `Casa` (instancia de `casa/casa.tscn`), `Luz` y `Ambiente`. El robot y su marcha
  siguen en código: el modelo depende del LOD y la marcha, del modo.
- `export_presets.cfg`: se quita `comun/mundo/assets.json` de `include_filter`. El exportador ya incluye la escena con
  `all_resources`.

## 5. Verificación [V] (host, PC CachyOS, editor `godot4-vita` dev7)

- **Mundo idéntico al de antes.** Un volcado de cada malla visible (ruta, posición, giro, escala, color) y cada caja
  de colisión, en los dos perfiles, comparado antes y después de la conversión: 136 líneas (normal) y 112 (ligero),
  **iguales**. Solo difieren en milímetros los 5 agentes que se mueven, porque avanzan un fotograma.
  `contar_dibujado()` da lo mismo: 24 644 / 8 200 triángulos.
- **Pruebas:**
  - runner: 14/14, 12/12 y 12/12;
  - `perfil_ligero.gd`: 18/18, 12/12 y 12/12;
  - `presupuesto.gd` OK en los tres, con las mismas cifras que el doc 34 (13 455–14 909 triángulos; vista inicial
    14 098, igual que `submitted_triangles` en la Vita);
  - `escena.gd` y `movimiento_g1.gd` sin fallos;
  - `rbkairos-plus` en loopback y `g1-unitree` sin ROS, sin errores.
- **Editor:** `main.tscn` de `g1-sensores` abierto con `--editor` en modo headless, sin errores de script. La vista
  previa gráfica (modelos visibles en el visor 3D) queda **por comprobar por el usuario** con el editor `.gui`.
- **`generar-lod-vita.py`** ejecutado sobre la escena nueva: deja `mundo.tscn` y los 25 `*_vita.obj` byte a byte
  iguales.
- **Falta en la Vita:** exportar y comprobar que el `.vpk` arranca igual. No debería cambiar nada: mismos nodos y
  mallas, y sin las mallas de PC cargadas.

## 6. Cómo editar (resumen para el usuario)

```fish
set G toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64.gui
$G --editor --path godot/g1-sensores        # abre main.tscn: mundo, luz, ambiente e InicioRobot visibles
```

- **Mover el punto de salida:** selecciona `InicioRobot` y muévelo; gíralo solo en Y.
- **Editar el mundo:** abre `comun/mundo/mundo.tscn`, o activa «Editable Children» en `Mundo`. Recuerda que el
  mundo es **compartido** por `g1-sensores`, `rbkairos-plus` y `dron-mapeo`.
- **Añadir un modelo:** duplica uno parecido (Ctrl+D), cambia `modelo` y ajusta la caja de `Colision`. Si tiene más
  de 250 triángulos, ejecuta `python3 tools/generar-lod-vita.py` con el editor cerrado.
- **Comprobar:**
  `$GH --headless --path godot/g1-sensores --script res://comun/pruebas/presupuesto.gd -- sin_ros lod=vita`.
