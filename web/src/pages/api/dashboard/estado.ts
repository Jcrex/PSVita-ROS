// /api/dashboard/estado — snapshot de salud para el widget "sesión XRCE":
// estado del receptor netlog, IP de la Vita, último paquete y los hitos
// XRCE detectados en los propios logs. El widget lo sondea cada pocos s.
import type { APIRoute } from 'astro';
import { netlog } from '../../../lib/netlog';

export const prerender = false;

export const GET: APIRoute = () => {
  return new Response(JSON.stringify({ ...netlog.estado, ahora: new Date().toISOString() }), {
    headers: { 'content-type': 'application/json', 'cache-control': 'no-cache' },
  });
};
