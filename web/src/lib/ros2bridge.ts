// ros2bridge.ts — puente mínimo hacia un ROS2 real para el dashboard.
//
// La web no enlaza rclpy (el host que la sirve no siempre tiene ROS2:
// en la laptop y en el PC vive en contenedores docker). En vez de eso,
// el widget de topics ejecuta UN comando configurable que debe imprimir
// la salida de `ros2 topic list -t`. Ejemplos reales del proyecto:
//
//   # laptop (contenedor ROS2 Jazzy):
//   ROS2_TOPICS_CMD='docker exec rmf_unified bash -lc "source /opt/ros/jazzy/setup.bash && ros2 topic list -t"'
//   # PC (contenedores de ~/Documentos/IR2134/DOCKER):
//   ROS2_TOPICS_CMD='docker exec <contenedor> bash -lc "... ros2 topic list -t"'
//
// Sin ROS2_TOPICS_CMD el widget lo dice claramente (no inventa datos:
// regla del hito de docs/08 — datos reales o nada).
import { exec } from 'node:child_process';

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
let cache: { res: TopicsResultado; t: number } | null = null;

function parsear(salida: string): TopicInfo[] {
  // Formato `ros2 topic list -t`: "/nombre [paquete/msg/Tipo]"
  const topics: TopicInfo[] = [];
  for (const linea of salida.split('\n')) {
    const m = linea.trim().match(/^(\/\S+)\s*(?:\[(.+)\])?$/);
    if (m) topics.push({ nombre: m[1], tipo: m[2] ?? '?' });
  }
  return topics;
}

export function listarTopics(): Promise<TopicsResultado> {
  const cmd = process.env.ROS2_TOPICS_CMD;
  if (!cmd) {
    return Promise.resolve({
      configurado: false,
      ok: false,
      topics: [],
      error: 'Sin conexión a ROS2: define ROS2_TOPICS_CMD en el entorno del servidor web.',
      obtenidoEn: null,
    });
  }
  if (cache && Date.now() - cache.t < CACHE_MS) return Promise.resolve(cache.res);

  return new Promise((resolve) => {
    exec(cmd, { timeout: 15_000 }, (err, stdout, stderr) => {
      const res: TopicsResultado = err
        ? {
            configurado: true,
            ok: false,
            topics: [],
            error: (stderr || err.message).slice(0, 500),
            obtenidoEn: new Date().toISOString(),
          }
        : {
            configurado: true,
            ok: true,
            topics: parsear(stdout),
            error: null,
            obtenidoEn: new Date().toISOString(),
          };
      cache = { res, t: Date.now() };
      resolve(res);
    });
  });
}
