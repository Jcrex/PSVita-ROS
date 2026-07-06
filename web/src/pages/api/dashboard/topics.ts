// /api/dashboard/topics — lista de topics del grafo ROS2 vía el puente
// configurable (ROS2_TOPICS_CMD). Ver src/lib/ros2bridge.ts.
import type { APIRoute } from 'astro';
import { listarTopics } from '../../../lib/ros2bridge';

export const prerender = false;

export const GET: APIRoute = async () => {
  const res = await listarTopics();
  return new Response(JSON.stringify(res), {
    status: res.configurado ? 200 : 501,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-cache' },
  });
};
