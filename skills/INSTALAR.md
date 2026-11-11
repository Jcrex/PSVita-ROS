# Instalar las skills de IA de PSVita-ROS en Claude Code

> **Para Claude Code:** si el usuario te pide «instala las skills» (o te pasa este fichero), sigue
> los pasos **en orden**, ejecuta cada comando, comprueba su resultado y al final informa con la tabla
> del paso 6. No inventes rutas: todo es relativo a la raíz del repo `PSVita-ROS`.
> **Para personas:** basta con ejecutar el paso 2 y reiniciar Claude Code.

## Qué se instala

| Skill | Para qué sirve | Necesita |
|---|---|---|
| `rclgd` | API y documentación de rclgd (ROS 2 nativo en Godot 4): reglas, referencia de las 17 clases, conceptos, tooling, tipos, errores; `scripts/rclgd-docs.sh` para documentarse sin la web | `git`, `python3` |
| `godot4-ros-scripting` | Escenas, nodos y scripts Godot 4 con ROS 2 (patrones de `roomba_ws`, plantillas `.gd`) | — |
| `ros2-vita-godot` | El módulo `ros2_vita` de la Vita: diferencias con rclgd, límites, flujo y reglas del repo | — |
| `vita-dual-module` | Crear módulos duales C + Rust con paridad | — |
| `vita-build-package` | Compilar y empaquetar el `.vpk` (solo PC con VitaSDK) | VitaSDK |
| `vita-deploy-logs` | Desplegar en la Vita y leer el netlog | Vita en red |

Cada skill es una carpeta `skills/<nombre>/` con un `SKILL.md` (frontmatter YAML `name` +
`description`). El instalador descubre **todas** las carpetas con `SKILL.md`, así que una skill nueva
se instala sin tocar nada.

## Paso 1 — Comprobar el repo

```bash
cd <ruta>/PSVita-ROS                      # la raíz del repo (contiene CLAUDE.md y skills/)
git status -sb                            # rama actual; sin cambios pendientes que estorben
git fetch origin && git log --oneline -1 origin/ccr-44e2db2a-mr6xqr   # rama con la migración a Godot 4
ls skills/*/SKILL.md                      # deben salir 6 ficheros
```
Si faltan `skills/rclgd`, `skills/godot4-ros-scripting` o `skills/ros2-vita-godot`, la rama local es
antigua: `git switch ccr-44e2db2a-mr6xqr` (o `git pull` si ya está fusionada en `main`).
**No cambies de rama si hay cambios sin guardar: pregunta al usuario antes.**

## Paso 2 — Instalar

Opción recomendada, para todos los proyectos del usuario:

```bash
tools/install-skills.sh            # enlaces simbólicos en ~/.claude/skills/<nombre>
```

Alternativas (elige una solo si el usuario lo pide o la recomendada falla):

| Situación | Orden |
|---|---|
| Solo para este repo | `tools/install-skills.sh --project` (en `.claude/skills/`, que no se versiona) |
| Claude Code no detecta skills enlazadas | `tools/install-skills.sh --copy` (copia; repetir tras cada `git pull`) |
| Destino distinto | `tools/install-skills.sh --dest <dir>` |
| Deshacer | `tools/install-skills.sh --uninstall` (con las mismas opciones de destino) |

El script es idempotente. Si dice `ya existe ... y no es un enlace`, hay una instalación antigua
copiada: **pregunta al usuario** antes de borrarla, luego vuelve a ejecutar.

## Paso 3 — Verificar

```bash
tools/install-skills.sh --check    # (o con --project / --dest, igual que al instalar)
```
Debe terminar en `Todo correcto`. Cada skill se valida: `SKILL.md` presente, frontmatter YAML
válido y `name` igual al nombre de la carpeta. Un fallo de YAML (p. ej. un `: ` sin comillas en
`description`) impide que Claude Code cargue esa skill: arréglalo entrecomillando la descripción.

## Paso 4 — Preparar la documentación de rclgd (una vez)

```bash
skills/rclgd/scripts/rclgd-docs.sh sync jazzy     # clon superficial en ~/.cache/rclgd-src
skills/rclgd/scripts/rclgd-docs.sh version         # esperado: rclgd 3.0.0, GODOT_VERSION "4.7.1" (o más nuevo)
skills/rclgd/scripts/rclgd-docs.sh leer RosNode | head -5
```
Si `version` muestra una versión distinta de la de `skills/rclgd/references/versiones.md`, avisa al
usuario: hay que regenerar la referencia (`rclgd-docs.sh api skills/rclgd/references/api`) y revisar
`cambios` (la rama `feature/native-msg-classes` cambia la API de tipos).

Opcional, solo si se van a generar esquemas de mensajes para la Vita (`ros2-vita-godot`):
```bash
python3 -m venv ~/.venvs/rbvenv && ~/.venvs/rbvenv/bin/pip install rosbags numpy
~/.venvs/rbvenv/bin/python tools/gen_msg_schema.py --dump geometry_msgs/msg/Twist
```

## Paso 5 — Activar

Las skills se cargan al **arrancar** Claude Code: pide al usuario que salga y vuelva a abrir `claude`
en la carpeta del repo. Después, comprobar que aparecen (en la lista de skills disponibles o con
`/skills` si esa orden existe en su versión). Prueba rápida que debe activar la skill `rclgd`:

> «Con rclgd, ¿en qué hilo corre el callback de un servidor de servicio?»

Respuesta correcta: en el hilo del executor; rellenar la respuesta y usar `call_deferred` para tocar
la escena (`skills/rclgd/references/conceptos.md`).

## Paso 6 — Informe al usuario

| Paso | Resultado |
|---|---|
| Rama y commit del repo | … |
| Destino y modo (enlace/copia) | … |
| `--check` | Todo correcto / fallos (cuáles) |
| `rclgd-docs.sh version` | rclgd x.y.z, Godot x.y.z |
| Pendiente | reiniciar Claude Code; (opcional) venv de rosbags |

## Mantenimiento

- Con enlaces simbólicos, `git pull` actualiza las skills; con `--copy`, volver a ejecutar el instalador.
- Al cambiar rclgd de versión: `skills/rclgd/references/versiones.md` explica el procedimiento.
- Batería para comprobar que una IA nueva usa bien las skills: `skills/rclgd/evals/preguntas.md`.
- Las skills también se leen en la web del proyecto, sección «Skills de IA».
