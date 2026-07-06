// /api/taller/vpk?variante=c|rust — descarga el .vpk compilado.
import type { APIRoute } from 'astro';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { Readable } from 'node:stream';
import { rutaVpk, tallerActivo, VARIANTES, type Variante } from '../../../lib/taller';

export const prerender = false;

export const GET: APIRoute = ({ url }) => {
  if (!tallerActivo()) return new Response('taller desactivado', { status: 403 });
  const variante = url.searchParams.get('variante') as Variante;
  if (!VARIANTES.includes(variante)) return new Response('variante inválida', { status: 400 });
  const ruta = rutaVpk(variante);
  if (!existsSync(ruta)) return new Response('no existe: compílalo primero', { status: 404 });

  return new Response(Readable.toWeb(createReadStream(ruta)) as ReadableStream, {
    headers: {
      'content-type': 'application/octet-stream',
      'content-length': String(statSync(ruta).size),
      'content-disposition': `attachment; filename="vita-ros2-hello-${variante}.vpk"`,
    },
  });
};
