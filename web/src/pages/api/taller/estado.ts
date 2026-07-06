// /api/taller/estado — snapshot del taller: si está activo, qué job corre,
// los .vpk existentes y el historial persistido de builds.
import type { APIRoute } from 'astro';
import { listarBuildJobs } from '../../../lib/db';
import { infoVpks, taller, tallerActivo } from '../../../lib/taller';

export const prerender = false;

export const GET: APIRoute = () => {
  const activo = tallerActivo();
  return new Response(
    JSON.stringify({
      activo,
      corriendo: taller.corriendo
        ? { id: taller.corriendo.id, tipo: taller.corriendo.tipo, titulo: taller.corriendo.titulo }
        : null,
      vpks: activo ? infoVpks() : [],
      historial: activo ? listarBuildJobs(15) : [],
    }),
    { headers: { 'content-type': 'application/json', 'cache-control': 'no-cache' } },
  );
};
