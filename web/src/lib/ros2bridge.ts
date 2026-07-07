// ros2bridge.ts — puente hacia un ROS2 real para el dashboard, vía Zenoh.
//
// Antes esto ejecutaba `docker exec <contenedor> ros2 topic list -t` desde
// el propio proceso del servidor web. Eso solo funciona con la web corriendo
// FUERA de docker (con acceso al CLI/socket de docker del host): dentro de
// su propio contenedor no hay cliente ros2 ni forma de llegar al docker del
// host, así que el widget quedaba sin configurar en el despliegue real.
//
// Sustituido por `zenoh-bridge-ros2dds` (ya validado en
// ~/Documentos/IR2134/DOCKER, imagen `rmf_unified`, ver su Dockerfile):
// arrancado con `--rest-http-port` expone el grafo ROS2 como una API HTTP
// normal, así que este módulo solo hace un fetch() — funciona igual dentro
// o fuera de docker, sin depender de nada de docker.
//
//   tools/vita-stack.sh bridge up         # arranca el bridge con REST en :8000
//   ZENOH_REST_URL=http://192.168.1.108:8000   # env del servidor web
//
// Sin ZENOH_REST_URL el widget lo dice claramente (no inventa datos: regla
// del hito de docs/08 — datos reales o nada).

export interface TopicInfo {
  nombre: string;
  tipo: string;
}

export interface TopicsResultado {
  configurado: boolean;
  ok: boolean;
  topics: TopicInfo[];
  error: string | null;
  obtenidoEn: string | null;
}

const CACHE_MS = 4000;
const TIMEOUT_MS = 5000;
let cache: { res: TopicsResultado; t: number } | null = null;

// El admin space de zenoh-bridge-ros2dds expone bajo @/<id>/ros2/route/**
// un objeto (RoutePublisher/RouteSubscriber) por cada topic descubierto,
// con campos `ros2_name` / `ros2_type` (ver README del proyecto:
// https://github.com/eclipse-zenoh/zenoh-plugin-ros2dds#admin-space). La
// API REST envuelve cada resultado en `{key, value, ...}` y a veces
// serializa `value` como string JSON anidado; recorremos el árbol de forma
// recursiva y defensiva para no depender de la forma exacta del envoltorio
// — no hay bridge real disponible en la laptop para fijar el formato con
// un test de verdad (validar contra el bridge real en el PC/hardware).
function extraerTopics(json: unknown): TopicInfo[] {
  const vistos = new Map<string, string>();

  function recorrer(nodo: unknown): void {
    if (Array.isArray(nodo)) {
      for (const item of nodo) recorrer(item);
      return;
    }
    if (!nodo || typeof nodo !== 'object') return;
    const obj = nodo as Record<string, unknown>;
    if (typeof obj.ros2_name === 'string' && typeof obj.ros2_type === 'string') {
      if (!vistos.has(obj.ros2_name)) vistos.set(obj.ros2_name, obj.ros2_type);
    }
    for (const v of Object.values(obj)) {
      if (typeof v === 'string' && (v.startsWith('{') || v.startsWith('['))) {
        try {
          recorrer(JSON.parse(v));
        } catch {
          // no era JSON anidado, se ignora
        }
      } else {
        recorrer(v);
      }
    }
  }

  recorrer(json);
  return [...vistos.entries()]
    .map(([nombre, tipo]) => ({ nombre, tipo }))
    .sort((a, b) => a.nombre.localeCompare(b.nombre));
}

export async function listarTopics(): Promise<TopicsResultado> {
  const base = process.env.ZENOH_REST_URL;
  if (!base) {
    return {
      configurado: false,
      ok: false,
      topics: [],
      error: 'Sin conexión a ROS2: define ZENOH_REST_URL (arranca antes tools/vita-stack.sh bridge up).',
      obtenidoEn: null,
    };
  }
  if (cache && Date.now() - cache.t < CACHE_MS) return cache.res;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const resp = await fetch(`${base.replace(/\/$/, '')}/@/local/ros2/route/**`, {
      signal: controller.signal,
      headers: { accept: 'application/json' },
    });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const json = await resp.json();
    const res: TopicsResultado = {
      configurado: true,
      ok: true,
      topics: extraerTopics(json),
      error: null,
      obtenidoEn: new Date().toISOString(),
    };
    cache = { res, t: Date.now() };
    return res;
  } catch (err) {
    const res: TopicsResultado = {
      configurado: true,
      ok: false,
      topics: [],
      error: (err instanceof Error ? err.message : String(err)).slice(0, 500),
      obtenidoEn: new Date().toISOString(),
    };
    cache = { res, t: Date.now() };
    return res;
  } finally {
    clearTimeout(timeout);
  }
}
