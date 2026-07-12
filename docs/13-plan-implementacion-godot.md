# 13 — Plan de implementación: migración del teleop a Godot

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Objetivo:** replicar la app teleop nativa como app Godot en la Vita
(spec: `docs/12-migracion-godot.md`), reutilizando el código C/Rust
existente vía un módulo custom del engine.

**Arquitectura:** módulo Godot 3.5 `microros` (C++, en este repo) que se
compila dentro del fork godot-vita con `custom_modules=`; linkea los
módulos duales + XRCE v2.4.3 + el glue de `vita-app/src/` y expone el
singleton `MicroROS` a GDScript. UI = escena Godot dedicada con stub para
la laptop.

**Tech stack:** Godot 3.5-rc5 (fork vita), scons, VitaSDK (solo PC),
GDScript, C/C++, microxrcedds_client v2.4.3.

## Global constraints

- Docs, comentarios y commits en español; prefijos convencionales
  (`feat(godot):`, `docs(godot):`, ...).
- **No tocar** `vita-app/` ni `modules/` (solo se reutilizan; cero
  reescritura de C/C++/Rust).
- Tag XRCE **v2.4.3** exacto (empareja con `microros/micro-ros-agent:jazzy`).
- En la laptop **no se compila nada nativo**: todo código C/C++ nuevo va
  marcado "validar en el PC". Las Tareas 1-6 son de laptop; 7-9 de PC.
- Rutas de máquina: fork en
  `~/Proyectos/Godot/godot-vita-3.5-rc5-vita1`, editor x11 en
  `~/Proyectos/Godot/godot_v3.5-rc5-vita.x11.64` (mismas rutas asumidas en
  el PC; sobreescribibles con `GODOT_VITA_SRC`).
- Branch de trabajo: `godot-migration` (ya creada; el spec docs/12 está
  commiteado en ella).

---

### Tarea 1: versionar el proyecto Godot existente

**Files:**
- Create: `godot/.gitignore`
- Modify: `.gitignore` (raíz)
- Commit: todo `godot/` salvo lo ignorado

**Interfaces:**
- Produce: el proyecto Godot bajo control de versiones; las Tareas 2-3
  crean archivos dentro de `godot/`.

- [ ] **Paso 1: escribir `godot/.gitignore`**

```gitignore
# Caché de imports del editor (se regenera sola)
.import/
# Template compilado por scripts/build-vita-template.sh (artefacto binario)
build/
# Capturas de video del editor (no son documentación del repo)
videos/
```

- [ ] **Paso 2: añadir al `.gitignore` de la raíz** (después del bloque
  "Build artefacts"):

```gitignore
# Objetos que scons (custom_modules) deja junto a las fuentes C
*.o
*.os
```

- [ ] **Paso 3: añadir y verificar**

Run: `git add godot/ .gitignore && git status --short`
Esperado: aparecen `godot/project.godot`, `export_presets.cfg`, escenas,
imágenes e iconos; **no** aparece nada de `godot/.import/` ni
`godot/videos/`.

- [ ] **Paso 4: commit**

```bash
git commit -m "feat(godot): versionar el proyecto Godot existente

Proyecto 3.5 con preset de export PlayStation Vita ya probado en
hardware por el usuario. Se ignoran .import/ (cache), videos/ y build/.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Tarea 2: módulo `microros` (puente C++ del engine)

**Files:**
- Create: `godot/modules/microros/config.py`
- Create: `godot/modules/microros/SCsub`
- Create: `godot/modules/microros/register_types.h`
- Create: `godot/modules/microros/register_types.cpp`
- Create: `godot/modules/microros/micro_ros_gd.h`
- Create: `godot/modules/microros/micro_ros_gd.cpp`

**Interfaces:**
- Consume: `vita_uxr_transport_init(uxrCustomTransport*, vita_transport_args*)`
  (`vita-app/src/uxr_glue.h`); `netlog_init(const char*, uint16_t)` /
  `netlog_printf(fmt, ...)` / `netlog_shutdown()` (`netlog.h`);
  `teleop_init(teleop_estado*)` / `teleop_update(teleop_estado*, const
  teleop_entrada*, double, teleop_twist*)` (`teleop.h`);
  `config_ip_parse(const char*, config_ip*)` (`config.h`);
  `net_udp_init() -> net_udp_status` / `net_udp_shutdown()` (`net_udp.h`).
- Produce: singleton GDScript `MicroROS` con métodos `setup(agent_ip:
  String, netlog_ip: String) -> bool`, `connect_agent() -> bool`,
  `is_session_active() -> bool`, `teleop_step(input: Dictionary, dt:
  float) -> Dictionary` (claves de entrada: `lx ly rx ry` float [-1,1] y
  `up down left right l r cross triangle` bool; claves de salida: `lin_x
  lin_y ang_z vel_lineal vel_lateral` float y `published` bool),
  `spin(ms: int)`, `netlog(msg: String)`, `shutdown()`. La Tarea 3 lo
  consume desde GDScript.

**Nota:** nada de esto compila en la laptop (headers de Godot + libs
cross-compiladas). Verificación real en la Tarea 7 (PC). En laptop solo se
verifica coherencia de símbolos contra los headers (paso 7).

- [ ] **Paso 1: escribir `godot/modules/microros/config.py`**

```python
# config.py — el módulo solo existe en builds de Vita (docs/12): en la
# plataforma vita no hay GDNative y el código nativo va dentro del engine.
def can_build(env, platform):
    return platform == "vita"


def configure(env):
    pass
```

- [ ] **Paso 2: escribir `godot/modules/microros/SCsub`**

```python
#!/usr/bin/env python
# SCsub — módulo puente MicroROS (docs/12). Se compila DENTRO del engine
# godot-vita con:  scons platform=vita custom_modules=<repo>/godot/modules
#
# Selección de implementación de los módulos duales (espejo de VITA_IMPL
# del CMakeLists de vita-app):
#   microros_impl=c     (defecto) impl-c de los módulos duales
#   microros_impl=rust  staticlib paraguas de vita-app/rust-modules
import os

Import("env")
Import("env_modules")

module_dir = Dir(".").srcnode().abspath
repo_root = os.path.normpath(os.path.join(module_dir, "..", "..", ".."))
xrce_prefix = os.path.join(repo_root, "vita-app", "third_party", "xrce-vita")

env_microros = env_modules.Clone()
env_microros.Append(CPPPATH=[
    os.path.join(repo_root, "modules", "mem-pool", "include"),
    os.path.join(repo_root, "modules", "net-udp", "include"),
    os.path.join(repo_root, "modules", "microros-transport", "include"),
    os.path.join(repo_root, "vita-app", "src"),
    os.path.join(xrce_prefix, "include"),
])

# Fuentes C++ del módulo
env_microros.add_source_files(env.modules_sources, "*.cpp")

# Código C reutilizado TAL CUAL (docs/12: cero reescritura). Los .o se
# generan junto a las fuentes; el .gitignore de la raíz los excluye.
reutilizadas = [
    os.path.join(repo_root, "vita-app", "src", "uxr_glue.c"),
    os.path.join(repo_root, "vita-app", "src", "netlog.c"),
    os.path.join(repo_root, "vita-app", "src", "teleop.c"),
    os.path.join(repo_root, "vita-app", "src", "config.c"),
]

impl = ARGUMENTS.get("microros_impl", "c")
if impl == "rust":
    rust_lib = os.path.join(repo_root, "vita-app", "rust-modules", "target",
                            "armv7-sony-vita-newlibeabihf", "release",
                            "libvita_modules_rust.a")
    env.Append(LIBS=[File(rust_lib)])
else:
    reutilizadas += [
        os.path.join(repo_root, "modules", "mem-pool", "impl-c",
                     "mem_pool.c"),
        os.path.join(repo_root, "modules", "net-udp", "impl-c",
                     "net_udp.c"),
        os.path.join(repo_root, "modules", "microros-transport", "impl-c",
                     "microros_transport.c"),
    ]

env_microros.add_source_files(env.modules_sources, reutilizadas)

# Libs XRCE cross-compiladas por vita-app/scripts/build-xrce-client-vita.sh
# y stubs de red: el engine va con -DNO_NETWORK (detect.py) y no los linkea.
env.Append(LIBS=[
    File(os.path.join(xrce_prefix, "lib", "libmicroxrcedds_client.a")),
    File(os.path.join(xrce_prefix, "lib", "libmicrocdr.a")),
    "SceNet_stub",
    "SceNetCtl_stub",
])
```

- [ ] **Paso 3: escribir `godot/modules/microros/register_types.h`**

```cpp
/* register_types.h — registro del módulo microros en el engine. */
#ifndef MICROROS_REGISTER_TYPES_H
#define MICROROS_REGISTER_TYPES_H

void register_microros_types();
void unregister_microros_types();

#endif /* MICROROS_REGISTER_TYPES_H */
```

- [ ] **Paso 4: escribir `godot/modules/microros/register_types.cpp`**

```cpp
/* register_types.cpp — crea el singleton MicroROS y lo expone a GDScript
 * (Engine.get_singleton("MicroROS")). Godot llama a estas funciones al
 * arrancar/cerrar el engine. */
#include "register_types.h"

#include "core/class_db.h"
#include "core/engine.h"

#include "micro_ros_gd.h"

static MicroROS *microros_ptr = nullptr;

void register_microros_types() {
	ClassDB::register_class<MicroROS>();
	microros_ptr = memnew(MicroROS);
	Engine::get_singleton()->add_singleton(
			Engine::Singleton("MicroROS", MicroROS::get_singleton()));
}

void unregister_microros_types() {
	if (microros_ptr) {
		memdelete(microros_ptr);
		microros_ptr = nullptr;
	}
}
```

- [ ] **Paso 5: escribir `godot/modules/microros/micro_ros_gd.h`**

```cpp
/**
 * micro_ros_gd.h — Singleton `MicroROS` expuesto a GDScript.
 *
 * Puente delgado (docs/12): NO contiene lógica propia. Reutiliza:
 *   - vita-app/src/uxr_glue.c   (transporte custom XRCE sobre net-udp)
 *   - vita-app/src/netlog.c     (log UDP a la laptop, puerto 9999)
 *   - vita-app/src/teleop.c     (mapeo mandos -> Twist, testeado en host)
 *   - vita-app/src/config.c     (validación de IPs)
 *   - modules/{mem-pool,net-udp,microros-transport} (variante C o Rust)
 *
 * Espejo de vita-app/src/main.c sin /vita_hello ni /pc_hello (docs/12:
 * el alcance es el teleop). Solo compila para platform=vita (config.py).
 * VALIDAR EN EL PC: en la laptop no hay headers de Godot ni libs cross.
 */
#ifndef MICRO_ROS_GD_H
#define MICRO_ROS_GD_H

#include "core/dictionary.h"
#include "core/object.h"
#include "core/ustring.h"

#include <uxr/client/client.h>

#include "teleop.h"
#include "uxr_glue.h"

#define MICROROS_AGENT_PORT 8888
#define MICROROS_NETLOG_PORT 9999
#define MICROROS_STREAM_BUFFER_SIZE 4096
#define MICROROS_STREAM_HISTORY 4

class MicroROS : public Object {
	GDCLASS(MicroROS, Object);

	static MicroROS *singleton;

	/* Estado de red/sesión (espejo de main.c). */
	bool net_ok;
	bool netlog_ok;
	bool session_ok;
	/* El transporte guarda el puntero a la IP: debe vivir lo que la
	 * sesión (en main.c era una variable de main(); aquí, un miembro). */
	CharString agent_ip;
	uxrCustomTransport transport;
	vita_transport_args targs;
	uxrSession session;
	uxrStreamId stream_out;
	uxrObjectId cmdvel_dw_id;
	uint8_t output_stream_buf[MICROROS_STREAM_BUFFER_SIZE *
			MICROROS_STREAM_HISTORY];

	/* Estado del teleop (la lógica vive en teleop.c). */
	teleop_estado teleop;

protected:
	static void _bind_methods();

public:
	static MicroROS *get_singleton();

	/* Valida IPs (config.c), levanta net-udp y el netlog. */
	bool setup(const String &p_agent_ip, const String &p_netlog_ip);
	/* Transporte + sesión XRCE + entidades DDS de /cmd_vel. */
	bool connect_agent();
	bool is_session_active() const;
	/* Una vuelta del teleop: dict de mandos -> teleop.c -> publica el
	 * Twist. Devuelve {lin_x, lin_y, ang_z, vel_lineal, vel_lateral,
	 * published}. */
	Dictionary teleop_step(const Dictionary &p_input, float p_dt);
	/* Atiende la sesión XRCE (heartbeats/ACKs) hasta p_ms milisegundos. */
	void spin(int p_ms);
	void netlog(const String &p_msg);
	void shutdown();

	MicroROS();
	~MicroROS();
};

#endif /* MICRO_ROS_GD_H */
```

- [ ] **Paso 6: escribir `godot/modules/microros/micro_ros_gd.cpp`**

```cpp
/* micro_ros_gd.cpp — implementación del puente (ver micro_ros_gd.h).
 * VALIDAR EN EL PC (Tarea 7 de docs/13). */
#include "micro_ros_gd.h"

#include <ucdr/microcdr.h>

#include "config.h"
#include "net_udp.h"
#include "netlog.h"

MicroROS *MicroROS::singleton = nullptr;

MicroROS *MicroROS::get_singleton() {
	return singleton;
}

/* Godot normaliza los sticks a [-1,+1] (joypad_vita.cpp: raw/255*2-1);
 * teleop.c espera el rango crudo de sceCtrl 0..255 con centro ~128.
 * Esta es la conversión inversa exacta. */
static uint8_t eje_a_crudo(float v) {
	int crudo = (int)((v + 1.0f) * 127.5f + 0.5f);
	if (crudo < 0) {
		crudo = 0;
	}
	if (crudo > 255) {
		crudo = 255;
	}
	return (uint8_t)crudo;
}

static float dict_f(const Dictionary &d, const char *k) {
	return d.has(k) ? (float)d[k] : 0.0f;
}

static bool dict_b(const Dictionary &d, const char *k) {
	return d.has(k) ? (bool)d[k] : false;
}

bool MicroROS::setup(const String &p_agent_ip, const String &p_netlog_ip) {
	/* Validación con config.c (misma regla que la app nativa). */
	config_ip ip;
	if (!config_ip_parse(p_agent_ip.utf8().get_data(), &ip)) {
		ERR_PRINT("MicroROS.setup: IP del agente invalida");
		return false;
	}
	if (!config_ip_parse(p_netlog_ip.utf8().get_data(), &ip)) {
		ERR_PRINT("MicroROS.setup: IP del netlog invalida");
		return false;
	}
	agent_ip = p_agent_ip.utf8();

	if (!net_ok) {
		if (net_udp_init() != NET_UDP_OK) {
			ERR_PRINT("MicroROS.setup: net_udp_init fallo");
			return false;
		}
		net_ok = true;
	}
	/* Como en main.c: sin netlog se sigue (WARN), no es fatal — pero se
	 * comprueba el retorno (lección del bug de main.c:100). */
	netlog_ok = netlog_init(p_netlog_ip.utf8().get_data(),
			MICROROS_NETLOG_PORT);
	if (!netlog_ok) {
		WARN_PRINT("MicroROS.setup: netlog_init fallo; sin logs UDP");
	}
	netlog_printf("[godot-teleop] setup ok; agente=%s:%d\n",
			agent_ip.get_data(), MICROROS_AGENT_PORT);
	return true;
}

bool MicroROS::connect_agent() {
	if (session_ok) {
		return true;
	}
	if (!net_ok) {
		ERR_PRINT("MicroROS.connect_agent: llama primero a setup()");
		return false;
	}
	targs.agent_ip = agent_ip.get_data();
	targs.agent_port = MICROROS_AGENT_PORT;
	if (!vita_uxr_transport_init(&transport, &targs)) {
		netlog_printf("[godot-teleop] FATAL: transporte no abre "
				"(agente accesible?)\n");
		return false;
	}

	/* Session key distinta de la app nativa (0xCAFE0001) para no chocar
	 * si el agente conserva una sesión anterior de la otra app. */
	uxr_init_session(&session, &transport.comm, 0xCAFE0002);
	if (!uxr_create_session(&session)) {
		netlog_printf("[godot-teleop] FATAL: uxr_create_session fallo "
				"(agente v2.4.3?)\n");
		uxr_close_custom_transport(&transport);
		return false;
	}
	stream_out = uxr_create_output_reliable_stream(&session,
			output_stream_buf, sizeof output_stream_buf,
			MICROROS_STREAM_HISTORY);

	/* Entidades DDS de /cmd_vel: mismos XML que main.c (prefijo rt/ y
	 * tipo dds_ o ros2 no ve el topic como propio). */
	uxrObjectId participant_id = uxr_object_id(0x01, UXR_PARTICIPANT_ID);
	const char *participant_xml =
			"<dds><participant><rtps><name>vita_node</name></rtps>"
			"</participant></dds>";
	uint16_t req[4];
	req[0] = uxr_buffer_create_participant_xml(&session, stream_out,
			participant_id, 0, participant_xml, UXR_REPLACE);

	uxrObjectId cmdvel_topic_id = uxr_object_id(0x01, UXR_TOPIC_ID);
	const char *cmdvel_topic_xml =
			"<dds><topic><name>rt/cmd_vel</name>"
			"<dataType>geometry_msgs::msg::dds_::Twist_</dataType>"
			"</topic></dds>";
	req[1] = uxr_buffer_create_topic_xml(&session, stream_out,
			cmdvel_topic_id, participant_id, cmdvel_topic_xml,
			UXR_REPLACE);

	uxrObjectId publisher_id = uxr_object_id(0x01, UXR_PUBLISHER_ID);
	req[2] = uxr_buffer_create_publisher_xml(&session, stream_out,
			publisher_id, participant_id, "", UXR_REPLACE);

	cmdvel_dw_id = uxr_object_id(0x01, UXR_DATAWRITER_ID);
	const char *cmdvel_dw_xml =
			"<dds><data_writer><topic><kind>NO_KEY</kind>"
			"<name>rt/cmd_vel</name>"
			"<dataType>geometry_msgs::msg::dds_::Twist_</dataType>"
			"</topic></data_writer></dds>";
	req[3] = uxr_buffer_create_datawriter_xml(&session, stream_out,
			cmdvel_dw_id, publisher_id, cmdvel_dw_xml, UXR_REPLACE);

	uint8_t status[4];
	if (!uxr_run_session_until_all_status(&session, 3000, req, status, 4)) {
		netlog_printf("[godot-teleop] FATAL: agente rechazo entidades "
				"(status: %d %d %d %d)\n",
				status[0], status[1], status[2], status[3]);
		uxr_delete_session(&session);
		uxr_close_custom_transport(&transport);
		return false;
	}

	teleop_init(&teleop);
	session_ok = true;
	netlog_printf("[godot-teleop] *** SESION XRCE ESTABLECIDA ***\n");
	return true;
}

bool MicroROS::is_session_active() const {
	return session_ok;
}

Dictionary MicroROS::teleop_step(const Dictionary &p_input, float p_dt) {
	teleop_entrada in;
	in.lx = eje_a_crudo(dict_f(p_input, "lx"));
	in.ly = eje_a_crudo(dict_f(p_input, "ly"));
	in.rx = eje_a_crudo(dict_f(p_input, "rx"));
	in.ry = eje_a_crudo(dict_f(p_input, "ry"));
	in.arriba = dict_b(p_input, "up");
	in.abajo = dict_b(p_input, "down");
	in.izquierda = dict_b(p_input, "left");
	in.derecha = dict_b(p_input, "right");
	in.l = dict_b(p_input, "l");
	in.r = dict_b(p_input, "r");
	in.cruz = dict_b(p_input, "cross");
	in.triangulo = dict_b(p_input, "triangle");

	teleop_twist tw;
	teleop_update(&teleop, &in, (double)p_dt, &tw);

	bool published = false;
	if (session_ok) {
		/* geometry_msgs/Twist en CDR: 6 doubles = 48 bytes (main.c). */
		ucdrBuffer ub;
		if (uxr_prepare_output_stream(&session, stream_out, cmdvel_dw_id,
				&ub, 6 * 8)) {
			ucdr_serialize_double(&ub, tw.lin_x);
			ucdr_serialize_double(&ub, tw.lin_y);
			ucdr_serialize_double(&ub, tw.lin_z);
			ucdr_serialize_double(&ub, tw.ang_x);
			ucdr_serialize_double(&ub, tw.ang_y);
			ucdr_serialize_double(&ub, tw.ang_z);
			published = true;
		}
	}

	Dictionary out;
	out["lin_x"] = tw.lin_x;
	out["lin_y"] = tw.lin_y;
	out["ang_z"] = tw.ang_z;
	out["vel_lineal"] = teleop.vel_lineal;
	out["vel_lateral"] = teleop.vel_lateral;
	out["published"] = published;
	return out;
}

void MicroROS::spin(int p_ms) {
	if (session_ok) {
		uxr_run_session_time(&session, p_ms);
	}
}

void MicroROS::netlog(const String &p_msg) {
	netlog_printf("%s\n", p_msg.utf8().get_data());
}

void MicroROS::shutdown() {
	if (session_ok) {
		uxr_delete_session(&session);
		uxr_close_custom_transport(&transport);
		session_ok = false;
	}
	if (netlog_ok) {
		netlog_shutdown();
		netlog_ok = false;
	}
	if (net_ok) {
		net_udp_shutdown();
		net_ok = false;
	}
}

void MicroROS::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "agent_ip", "netlog_ip"),
			&MicroROS::setup);
	ClassDB::bind_method(D_METHOD("connect_agent"),
			&MicroROS::connect_agent);
	ClassDB::bind_method(D_METHOD("is_session_active"),
			&MicroROS::is_session_active);
	ClassDB::bind_method(D_METHOD("teleop_step", "input", "dt"),
			&MicroROS::teleop_step);
	ClassDB::bind_method(D_METHOD("spin", "ms"), &MicroROS::spin);
	ClassDB::bind_method(D_METHOD("netlog", "msg"), &MicroROS::netlog);
	ClassDB::bind_method(D_METHOD("shutdown"), &MicroROS::shutdown);
}

MicroROS::MicroROS() {
	singleton = this;
	net_ok = false;
	netlog_ok = false;
	session_ok = false;
	teleop_init(&teleop);
}

MicroROS::~MicroROS() {
	shutdown();
	singleton = nullptr;
}
```

- [ ] **Paso 7: verificación de símbolos en laptop** (lo único comprobable
  aquí):

Run:
```bash
grep -o 'vita_uxr_transport_init\|netlog_init\|netlog_printf\|netlog_shutdown\|teleop_init\|teleop_update\|config_ip_parse\|net_udp_init\|net_udp_shutdown\|NET_UDP_OK' \
  godot/modules/microros/micro_ros_gd.cpp | sort -u
```
Esperado: las 10 cadenas, y cada una existe en su header de
`vita-app/src/` o `modules/*/include/` (comparar firmas a mano).

- [ ] **Paso 8: commit**

```bash
git add godot/modules/
git commit -m "feat(godot): modulo microros — puente MicroROS para GDScript

Modulo custom del engine (custom_modules): linkea los modulos duales
(variante C o Rust via microros_impl=), XRCE v2.4.3 y el glue de
vita-app/src (uxr_glue, netlog, teleop, config) sin tocarlos. Expone
setup/connect_agent/teleop_step/spin/netlog a GDScript. Solo compila
para platform=vita — validar en el PC (Tarea 7 de docs/13).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Tarea 3: escena teleop + GDScript con stub

**Files:**
- Create: `godot/scenes/teleop/teleop.gd`
- Create: `godot/scenes/teleop/Teleop.tscn`
- Modify: `godot/project.godot` (main scene)

**Interfaces:**
- Consume: el singleton `MicroROS` de la Tarea 2 (vía
  `Engine.has_singleton("MicroROS")` / `Engine.get_singleton`), con la API
  exacta del bloque Interfaces de la Tarea 2.
- Produce: `res://scenes/teleop/Teleop.tscn` como main scene del proyecto.

- [ ] **Paso 1: escribir `godot/scenes/teleop/teleop.gd`**

```gdscript
extends Control
# teleop.gd — UI del teleop Godot (docs/12). La lógica del mapeo vive en
# vita-app/src/teleop.c dentro del singleton nativo MicroROS; aquí solo se
# leen los mandos, se llama a teleop_step() a ~20 Hz y se pinta el estado.
# En la laptop (editor sin el módulo) corre MicroROSStub para probar la UI.

const PUB_PERIODO := 0.05        # ~20 Hz, la cadencia de la app nativa
const REINTENTO_PERIODO := 3.0   # backoff del reintento de conexión (docs/12)
const IP_DEFECTO := "192.168.1.108"   # la laptop (agente + netlog)
const CONFIG_PATH := "user://vitaros.cfg"

# Índices de botones según platform/vita/joypad_vita.cpp (pad_mapping):
const BTN_CROSS := 0
const BTN_TRIANGLE := 3
const BTN_L := 6      # gatillo L de la Vita
const BTN_R := 7      # gatillo R de la Vita
const BTN_START := 11
const BTN_UP := 12
const BTN_DOWN := 13
const BTN_LEFT := 14
const BTN_RIGHT := 15

var ros = null                   # singleton MicroROS (Vita) o stub (laptop)
var es_stub := false
var acumulado := 0.0
var auto_reintento := false      # tras un Conectar fallido, reintenta solo
var reintento_t := 0.0

onready var ip_agente: LineEdit = $VBox/FilaIP/IpAgente
onready var ip_netlog: LineEdit = $VBox/FilaIP/IpNetlog
onready var btn_conectar: Button = $VBox/FilaIP/BtnConectar
onready var lbl_estado: Label = $VBox/Estado
onready var lbl_twist: Label = $VBox/Twist
onready var lbl_escalas: Label = $VBox/Escalas
onready var consola: RichTextLabel = $VBox/Consola


# Stub de laptop: misma interfaz que el singleton nativo. El "mapeo" de
# aquí es SOLO un apaño visual para desarrollar la UI; el real es teleop.c.
class MicroROSStub:
	func setup(_agent_ip: String, _netlog_ip: String) -> bool:
		return true

	func connect_agent() -> bool:
		return true

	func is_session_active() -> bool:
		return true

	func teleop_step(entrada: Dictionary, _dt: float) -> Dictionary:
		return {
			"lin_x": -entrada.get("ly", 0.0) * 0.5,
			"lin_y": 0.0,
			"ang_z": -entrada.get("lx", 0.0) * 0.5,
			"vel_lineal": 0.5,
			"vel_lateral": 0.5,
			"published": false,
		}

	func spin(_ms: int) -> void:
		pass

	func netlog(msg: String) -> void:
		print("[stub-netlog] ", msg)

	func shutdown() -> void:
		pass


func _ready() -> void:
	if Engine.has_singleton("MicroROS"):
		ros = Engine.get_singleton("MicroROS")
	else:
		ros = MicroROSStub.new()
		es_stub = true
		log_linea("modo SIMULADO (sin modulo nativo): UI ok, no se publica")
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)  # si no existe, se quedan los defectos
	ip_agente.text = cfg.get_value("red", "agent_ip", IP_DEFECTO)
	ip_netlog.text = cfg.get_value("red", "netlog_ip", IP_DEFECTO)
	btn_conectar.connect("pressed", self, "_on_conectar")
	_pinta_estado()


func _on_conectar() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("red", "agent_ip", ip_agente.text)
	cfg.set_value("red", "netlog_ip", ip_netlog.text)
	cfg.save(CONFIG_PATH)
	if not ros.setup(ip_agente.text, ip_netlog.text):
		log_linea("setup() fallo: IP invalida o red no disponible")
		_pinta_estado()
		return
	log_linea("conectando al agente %s:8888..." % ip_agente.text)
	if ros.connect_agent():
		log_linea("*** SESION XRCE ESTABLECIDA ***")
		auto_reintento = false
	else:
		log_linea("connect_agent() fallo (agente accesible? v2.4.3?); "
				+ "reintento cada %.0f s" % REINTENTO_PERIODO)
		auto_reintento = true
		reintento_t = 0.0
	_pinta_estado()


func _process(delta: float) -> void:
	# START sale de la app, como en la app nativa.
	if Input.is_joy_button_pressed(0, BTN_START):
		ros.shutdown()
		get_tree().quit()
		return
	# Reintento automático con backoff (docs/12 §manejo de errores). Ojo:
	# connect_agent() bloquea unos segundos mientras negocia — el frame se
	# congela durante el intento, aceptable en pantalla de conexión.
	if auto_reintento and not ros.is_session_active():
		reintento_t += delta
		if reintento_t >= REINTENTO_PERIODO:
			reintento_t = 0.0
			log_linea("reintentando conexion...")
			if ros.connect_agent():
				log_linea("*** SESION XRCE ESTABLECIDA ***")
				auto_reintento = false
			_pinta_estado()
	acumulado += delta
	if acumulado < PUB_PERIODO:
		return
	var resultado: Dictionary = ros.teleop_step(_leer_mandos(), acumulado)
	acumulado = 0.0
	ros.spin(5)  # atiende heartbeats/ACKs de la sesión XRCE
	lbl_twist.text = "cmd_vel  lin.x %+.2f  lin.y %+.2f  ang.z %+.2f" % [
		resultado.get("lin_x", 0.0), resultado.get("lin_y", 0.0),
		resultado.get("ang_z", 0.0),
	]
	lbl_escalas.text = "vel_lineal %.1f   vel_lateral %.1f" % [
		resultado.get("vel_lineal", 0.0), resultado.get("vel_lateral", 0.0),
	]


func _leer_mandos() -> Dictionary:
	# En la Vita el pad es el joypad 0 (joypad_vita.cpp). En la laptop,
	# fallback de teclado para probar la UI sin mando: flechas = cruceta,
	# Q/E = L/R, X = cruz, T = triángulo.
	var entrada := {
		"lx": Input.get_joy_axis(0, JOY_ANALOG_LX),
		"ly": Input.get_joy_axis(0, JOY_ANALOG_LY),
		"rx": Input.get_joy_axis(0, JOY_ANALOG_RX),
		"ry": Input.get_joy_axis(0, JOY_ANALOG_RY),
		"up": Input.is_joy_button_pressed(0, BTN_UP),
		"down": Input.is_joy_button_pressed(0, BTN_DOWN),
		"left": Input.is_joy_button_pressed(0, BTN_LEFT),
		"right": Input.is_joy_button_pressed(0, BTN_RIGHT),
		"l": Input.is_joy_button_pressed(0, BTN_L),
		"r": Input.is_joy_button_pressed(0, BTN_R),
		"cross": Input.is_joy_button_pressed(0, BTN_CROSS),
		"triangle": Input.is_joy_button_pressed(0, BTN_TRIANGLE),
	}
	if es_stub:
		entrada.up = entrada.up or Input.is_key_pressed(KEY_UP)
		entrada.down = entrada.down or Input.is_key_pressed(KEY_DOWN)
		entrada.left = entrada.left or Input.is_key_pressed(KEY_LEFT)
		entrada.right = entrada.right or Input.is_key_pressed(KEY_RIGHT)
		entrada.l = entrada.l or Input.is_key_pressed(KEY_Q)
		entrada.r = entrada.r or Input.is_key_pressed(KEY_E)
		entrada.cross = entrada.cross or Input.is_key_pressed(KEY_X)
		entrada.triangle = entrada.triangle or Input.is_key_pressed(KEY_T)
	return entrada


func _pinta_estado() -> void:
	if es_stub:
		lbl_estado.text = "SIMULADO (laptop, sin modulo nativo)"
		lbl_estado.modulate = Color.yellow
	elif ros.is_session_active():
		lbl_estado.text = "CONECTADO (sesion XRCE activa)"
		lbl_estado.modulate = Color.green
	else:
		lbl_estado.text = "SIN SESION - pulsa Conectar"
		lbl_estado.modulate = Color.red


func log_linea(msg: String) -> void:
	consola.add_text(msg + "\n")
	ros.netlog("[godot-ui] " + msg)
```

- [ ] **Paso 2: escribir `godot/scenes/teleop/Teleop.tscn`**

```
[gd_scene load_steps=2 format=2]

[ext_resource path="res://scenes/teleop/teleop.gd" type="Script" id=1]

[node name="Teleop" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource( 1 )

[node name="VBox" type="VBoxContainer" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0
margin_left = 16.0
margin_top = 16.0
margin_right = -16.0
margin_bottom = -16.0
custom_constants/separation = 8

[node name="Titulo" type="Label" parent="VBox"]
text = "PSVita-ROS — Teleop (Godot)"

[node name="FilaIP" type="HBoxContainer" parent="VBox"]
custom_constants/separation = 8

[node name="LblAgente" type="Label" parent="VBox/FilaIP"]
text = "Agente:"

[node name="IpAgente" type="LineEdit" parent="VBox/FilaIP"]
rect_min_size = Vector2( 200, 0 )
text = "192.168.1.108"

[node name="LblNetlog" type="Label" parent="VBox/FilaIP"]
text = "Netlog:"

[node name="IpNetlog" type="LineEdit" parent="VBox/FilaIP"]
rect_min_size = Vector2( 200, 0 )
text = "192.168.1.108"

[node name="BtnConectar" type="Button" parent="VBox/FilaIP"]
text = "Conectar"

[node name="Estado" type="Label" parent="VBox"]
text = "SIN SESION - pulsa Conectar"

[node name="Twist" type="Label" parent="VBox"]
text = "cmd_vel  lin.x +0.00  lin.y +0.00  ang.z +0.00"

[node name="Escalas" type="Label" parent="VBox"]
text = "vel_lineal 0.5   vel_lateral 0.5"

[node name="Consola" type="RichTextLabel" parent="VBox"]
size_flags_vertical = 3
scroll_following = true
```

- [ ] **Paso 3: cambiar la main scene en `godot/project.godot`**

Reemplazar la línea
`run/main_scene="res://Primera-scena-silvia/escena-principal.tscn"` por:

```ini
run/main_scene="res://scenes/teleop/Teleop.tscn"
```

- [ ] **Paso 4: chequeo de parseo del GDScript** (laptop, sin abrir editor):

Run:
```bash
"$HOME/Proyectos/Godot/godot_v3.5-rc5-vita.x11.64" --path godot \
  --check-only -s res://scenes/teleop/teleop.gd; echo "exit=$?"
```
Esperado: `exit=0` y sin `SCRIPT ERROR` en la salida. (Si el binario exige
display y no hay, este paso lo hace el usuario desde el editor.)

- [ ] **Paso 5: prueba manual en el editor** (usuario o sesión con
  display): abrir el proyecto, F5 → la escena arranca en modo SIMULADO
  (label amarillo), las flechas/teclas mueven los valores de `cmd_vel`,
  el botón Conectar loguea en la consola. Guardar → `user://vitaros.cfg`
  persiste las IPs entre ejecuciones.

- [ ] **Paso 6: commit**

```bash
git add godot/scenes/ godot/project.godot
git commit -m "feat(godot): escena teleop dedicada con stub para la laptop

UI del teleop en GDScript: estado de conexion visible, IPs editables y
persistentes (user://vitaros.cfg), indicadores de /cmd_vel y consola.
El mapeo real vive en teleop.c via MicroROS.teleop_step(); en el editor
de la laptop (sin modulo) corre MicroROSStub. START sale de la app.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Tarea 4: script de build del template (PC)

**Files:**
- Create: `godot/scripts/build-vita-template.sh` (ejecutable)

**Interfaces:**
- Consume: el SCsub de la Tarea 2 (`custom_modules=`, `microros_impl=`);
  `vita-app/scripts/build-xrce-client-vita.sh` (genera
  `vita-app/third_party/xrce-vita/`).
- Produce: `~/.local/share/godot/templates/3.5.rc5/vita_release.zip`
  instalado (lo que `find_export_template("vita_release.zip")` del
  exportador busca) y copia en `godot/build/vita_release.zip`.

- [ ] **Paso 1: escribir `godot/scripts/build-vita-template.sh`**

```bash
#!/usr/bin/env bash
# build-vita-template.sh — compila el export template de Godot para la
# Vita CON el módulo microros dentro (docs/12). SOLO EN EL PC (VitaSDK).
#
# Uso:
#   ./build-vita-template.sh [c|rust]     # defecto: c
#
# Requiere: VITASDK exportado, scons, zip, y el fork godot-vita
# (GODOT_VITA_SRC o la ruta por defecto de abajo).
#
# El engine (scons) deja bin/vita_template/ con eboot.bin + module/ +
# sce_sys/ (ver platform/vita/SCsub del fork); eso, zipeado, ES el
# template que el exportador busca como vita_release.zip en
# ~/.local/share/godot/templates/3.5.rc5/.
set -euo pipefail

IMPL="${1:-c}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FORK="${GODOT_VITA_SRC:-$HOME/Proyectos/Godot/godot-vita-3.5-rc5-vita1}"
TEMPLATES_DIR="${GODOT_TEMPLATES_DIR:-$HOME/.local/share/godot/templates/3.5.rc5}"

[ -n "${VITASDK:-}" ] || { echo "ERROR: VITASDK no exportado"; exit 1; }
[ -d "$FORK/platform/vita" ] || {
    echo "ERROR: fork godot-vita no encontrado en $FORK"
    echo "       (exporta GODOT_VITA_SRC con la ruta correcta)"
    exit 1
}
case "$IMPL" in c|rust) ;; *) echo "ERROR: impl '$IMPL' (usa c|rust)"; exit 1;; esac

# 1) Dependencias cross-compiladas (XRCE v2.4.3 + microcdr)
if [ ! -f "$REPO/vita-app/third_party/xrce-vita/lib/libmicroxrcedds_client.a" ]; then
    echo "== third_party ausente: compilando microxrcedds_client v2.4.3 =="
    (cd "$REPO/vita-app" && ./scripts/build-xrce-client-vita.sh)
fi

# 2) Variante Rust: staticlib paraguas primero (mismo comando que el
#    CMakeLists de vita-app)
if [ "$IMPL" = "rust" ]; then
    echo "== cargo build (vita_modules_rust -> staticlib armv7 Vita) =="
    (cd "$REPO/vita-app/rust-modules" && cargo +nightly rustc --release \
        --crate-type staticlib -Zbuild-std=std,panic_abort \
        --target armv7-sony-vita-newlibeabihf)
fi

# 3) Engine + módulo
echo "== scons platform=vita (custom_modules, microros_impl=$IMPL) =="
(cd "$FORK" && scons platform=vita target=release \
    custom_modules="$REPO/godot/modules" microros_impl="$IMPL" -j"$(nproc)")

# 4) Empaquetar e instalar como template local (backup del original)
OUT="$REPO/godot/build"
mkdir -p "$OUT" "$TEMPLATES_DIR"
rm -f "$OUT/vita_release.zip"
(cd "$FORK/bin/vita_template" && zip -r -q "$OUT/vita_release.zip" .)
if [ -f "$TEMPLATES_DIR/vita_release.zip" ] && \
   [ ! -f "$TEMPLATES_DIR/vita_release.zip.orig" ]; then
    cp "$TEMPLATES_DIR/vita_release.zip" "$TEMPLATES_DIR/vita_release.zip.orig"
fi
cp "$OUT/vita_release.zip" "$TEMPLATES_DIR/vita_release.zip"

echo "OK: template (impl=$IMPL) instalado en $TEMPLATES_DIR/vita_release.zip"
echo "Siguiente: editor Godot > Proyecto > Exportar > PlayStation Vita -> .vpk"
```

- [ ] **Paso 2: hacerlo ejecutable y chequear sintaxis**

Run: `chmod +x godot/scripts/build-vita-template.sh && bash -n godot/scripts/build-vita-template.sh && echo SINTAXIS-OK`
Esperado: `SINTAXIS-OK`.

- [ ] **Paso 3: commit**

```bash
git add godot/scripts/
git commit -m "feat(godot): script de build del template custom de Vita (PC)

scons platform=vita custom_modules=godot/modules sobre el fork
godot-vita; empaqueta bin/vita_template como vita_release.zip y lo
instala en ~/.local/share/godot/templates/3.5.rc5/ (con backup del
original). Acepta c|rust como impl de los modulos duales. Validar en
el PC.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Tarea 5: README de godot/ + publicación en la web

**Files:**
- Create: `godot/README.md`
- Modify: `web/src/content.config.ts` (colección `codigo`)
- Modify: `web/Dockerfile` (COPY del README)

**Interfaces:**
- Produce: `godot/README.md` publicado en la sección "código" de la web
  (regla del proyecto: toda doc se publica en su sección).

- [ ] **Paso 1: escribir `godot/README.md`**

```markdown
# godot/ — la app de la Vita en Godot

Subproyecto de la branch `godot-migration` (diseño en
`docs/12-migracion-godot.md`, plan en `docs/13-plan-implementacion-godot.md`):
replica la app teleop nativa de `vita-app/` como proyecto Godot 3.5,
reutilizando **sin reescribir** los módulos duales C/Rust, el cliente
XRCE v2.4.3 y el glue de `vita-app/src/`.

## Piezas

| Ruta | Qué es |
|---|---|
| `project.godot` | Proyecto Godot 3.5 (GLES2, 940×544, preset de export "PlayStation Vita") |
| `modules/microros/` | Módulo C++ del engine: expone el singleton `MicroROS` a GDScript. Se compila **dentro** del fork godot-vita vía `custom_modules=` (en la Vita no hay GDNative) |
| `scenes/teleop/` | La escena teleop: UI de conexión, IPs editables persistentes, indicadores de `/cmd_vel`. Con stub para correr en el editor de la laptop sin hardware |
| `scripts/build-vita-template.sh` | (Solo PC) compila el export template custom con el módulo dentro y lo instala en `~/.local/share/godot/templates/3.5.rc5/` |

## Flujo de trabajo

- **Laptop:** editor Godot x11 (`~/Proyectos/Godot/godot_v3.5-rc5-vita.x11.64`)
  para escenas y GDScript. La escena corre en modo SIMULADO (stub).
- **PC (VitaSDK):** `scripts/build-vita-template.sh` una vez por cambio
  nativo; después, exportar el `.vpk` desde el editor y subirlo por FTP
  (guías en `docs/guias-vita/`). El template solo se recompila si cambia
  código C/C++/Rust.

## Estado

Ver la bitácora (`docs/06-bitacora-estado.md`) y los hitos G1-G4 de
`docs/12-migracion-godot.md`.
```

- [ ] **Paso 2: añadir el README a la colección `codigo`** en
  `web/src/content.config.ts` — el patrón queda:

```ts
const codigo = defineCollection({
  loader: glob({
    pattern: [
      'modules/*/README.md',
      'vita-app/README.md',
      'mcp/*/README.md',
      'godot/README.md',
    ],
    base: '..',
  }),
});
```

- [ ] **Paso 3: añadir el COPY al `web/Dockerfile`** (tras la línea
  `COPY mcp/ /app/mcp/`):

```dockerfile
COPY godot/README.md /app/godot/README.md
```

- [ ] **Paso 4: verificar que la web compila y recoge el README**

Run: `cd web && pnpm build 2>&1 | tail -20`
Esperado: build sin errores; ninguna advertencia de colección `codigo`.

- [ ] **Paso 5: commit**

```bash
git add godot/README.md web/src/content.config.ts web/Dockerfile
git commit -m "docs(godot): README del subproyecto + publicacion en la web

Se añade godot/README.md a la coleccion codigo y al Dockerfile (regla
del proyecto: toda doc publicada en su seccion).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Tarea 6: bitácora, sanity final y push (cierra G1)

**Files:**
- Modify: `docs/06-bitacora-estado.md`

**Interfaces:**
- Produce: branch `godot-migration` publicada en origin, lista para
  `git pull` en el PC.

- [ ] **Paso 1: sanity — los parity tests siguen verdes** (no se tocó
  nada, pero es la puerta del repo):

Run: `tools/run-parity-tests.sh 2>&1 | tail -5`
Esperado: mismo resultado verde de siempre.

- [ ] **Paso 2: actualizar la bitácora** — en
  `docs/06-bitacora-estado.md`: actualizar la línea "Última
  actualización" y añadir al listado de acontecimientos (tras el bloque
  más reciente) este bloque:

```markdown
- **(2026-07-13, en la laptop) Branch `godot-migration` — G1 (esqueleto
  Godot) COMPLETO:** existe un fork de Godot 3.5-rc5 con plataforma Vita
  nativa ya probado por el usuario en su consola (editor x11 +
  `vita_template_3.5.rc5.tpz`), y se decidió replicar la app teleop en
  Godot **sin reescribir nada de C/Rust** (diseño: docs/12; plan:
  docs/13). Clave técnica: en la Vita no hay GDNative
  (`platform/vita/detect.py` del fork lo deshabilita), así que el código
  nativo entra como **módulo custom del engine** vía `custom_modules=`
  — `godot/modules/microros/` linkea los módulos duales + XRCE v2.4.3 +
  el glue de `vita-app/src/` y expone el singleton `MicroROS` a
  GDScript. En la branch quedaron: el proyecto Godot versionado, el
  módulo completo (validar en el PC), la escena teleop con stub (corre
  en el editor de la laptop en modo SIMULADO), el script
  `godot/scripts/build-vita-template.sh` (PC) y el README publicado en
  la web. **Siguiente paso exacto:** en el PC, `git pull`, correr
  `godot/scripts/build-vita-template.sh` (Tarea 7 de docs/13), exportar
  el `.vpk` y verificar en hardware (Tarea 8).
```

- [ ] **Paso 3: commit y push**

```bash
git add docs/06-bitacora-estado.md
git commit -m "docs(bitacora): G1 de la migracion Godot completo en laptop

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push -u origin godot-migration
```
Esperado: branch visible en GitHub (`github.com/Jcrex/PSVita-ROS`).

---

### Tarea 7 (PC): compilar el template custom — hito G2

**Files:** ninguno nuevo (build). Correcciones que surjan → commits
`fix(godot):` sobre la branch.

**Interfaces:**
- Consume: Tareas 2 y 4 (`SCsub`, `build-vita-template.sh`).
- Produce: `~/.local/share/godot/templates/3.5.rc5/vita_release.zip` con
  el módulo dentro.

- [ ] **Paso 1: traer la branch**

```bash
git fetch && git checkout godot-migration && git pull
```

- [ ] **Paso 2: compilar** (primera vez: el engine entero, tarda)

```bash
source ~/.bashrc   # VITASDK
./godot/scripts/build-vita-template.sh c
```
Esperado: termina con `OK: template (impl=c) instalado en ...`.
Errores de compilación del módulo se corrigen aquí (son la "validación en
el PC" del código de la Tarea 2) y se commitean como `fix(godot): ...`.

- [ ] **Paso 3: comprobar que el singleton está en el template**

```bash
unzip -l ~/.local/share/godot/templates/3.5.rc5/vita_release.zip
arm-vita-eabi-nm -C "${GODOT_VITA_SRC:-$HOME/Proyectos/Godot/godot-vita-3.5-rc5-vita1}/bin/"godot.*.elf 2>/dev/null | grep "MicroROS::connect_agent" | head -3
```
Esperado: el zip contiene `eboot.bin`, `module/`, `sce_sys/`; el `nm`
muestra símbolos `MicroROS::*`.

- [ ] **Paso 4: commitear cualquier fix y push**

```bash
git push
```

---

### Tarea 8 (PC + laptop): exportar, desplegar y verificar en hardware — hito G3

**Interfaces:**
- Consume: template de la Tarea 7; escena de la Tarea 3.
- Produce: teleop Godot controlando el robot real por `/cmd_vel`.

- [ ] **Paso 1 (PC): exportar el `.vpk`** — abrir el editor Godot sobre
  `godot/`, Proyecto → Exportar → preset "PlayStation Vita" → exportar a
  `godot/build/psvita-ros-godot.vpk`. (El preset ya existe en
  `export_presets.cfg`.)

- [ ] **Paso 2 (PC): subir por FTP e instalar** — flujo documentado en
  `docs/guias-vita/vitashell.md` (modo FTP de VitaShell, instalar el
  `.vpk`).

- [ ] **Paso 3 (laptop): levantar la infraestructura de verificación**

```bash
docker run -it --rm --net=host microros/micro-ros-agent:jazzy udp4 --port 8888 -v6
tools/netlog-listen.sh 9999          # en otra terminal
# dentro del contenedor ROS2 Jazzy (robotnik_dev):
ros2 topic echo /cmd_vel
```

- [ ] **Paso 4 (Vita): lanzar la app** — la escena teleop aparece (¡con
  pantalla, no negra!), editar la IP si hace falta, pulsar Conectar.
Esperado: label "CONECTADO (sesion XRCE activa)" en verde; el netlog de
la laptop muestra `[godot-teleop] *** SESION XRCE ESTABLECIDA ***`; el
agente crea participante/topic/datawriter; `ros2 topic echo /cmd_vel`
muestra Twists al mover el stick; el robot responde con el mapeo de
`docs/09-objetivo2-control-robot.md`.

- [ ] **Paso 5: cerrar el hito** — actualizar `docs/06-bitacora-estado.md`
  (bloque "G3 CERRADO — teleop Godot en hardware") y
  `web/src/data/fases.ts`; commit `docs(bitacora): G3 cerrado ...` y push.

**Nota (riesgo conocido):** si el `LineEdit` no despliega teclado en la
Vita, la IP igualmente persiste desde `user://vitaros.cfg` y el defecto
(192.168.1.108) es la laptop; la edición cómoda se resolvería después con
botones +/- por octeto (como `config_ui.c`) — no bloquea G3.

---

### Tarea 9 (PC): variante Rust del template — hito G4

- [ ] **Paso 1: compilar la variante Rust**

```bash
./godot/scripts/build-vita-template.sh rust
```
Esperado: `cargo +nightly` produce `libvita_modules_rust.a`, scons
relinkea, `OK: template (impl=rust) instalado`.

- [ ] **Paso 2: re-exportar el `.vpk`, redesplegar y repetir la
  verificación de la Tarea 8** (misma sesión de agente/netlog/echo).
Esperado: mismo comportamiento que la variante C.

- [ ] **Paso 3: cerrar G4** — bitácora + push. La migración queda
  completa; decidir ahí si `godot-migration` se mergea a `main`
  (skill superpowers:finishing-a-development-branch).
