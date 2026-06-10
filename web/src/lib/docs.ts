// docs.ts — utilidades para la sección de documentación de la web.
//
// Los markdown de docs/ no llevan frontmatter (viven primero en el repo,
// legibles en GitHub): el título y la descripción se derivan del cuerpo.
import type { CollectionEntry, CollectionKey } from 'astro:content';

type DocEntry = CollectionEntry<CollectionKey>;

/** Primer `# encabezado` del markdown (o el id como último recurso). */
export function docTitle(entry: { id: string; body?: string }): string {
  const m = entry.body?.match(/^#\s+(.+)$/m);
  return m ? m[1].replace(/\*\*/g, '').trim() : entry.id;
}

/** Primer párrafo "normal" tras el título, como descripción corta. */
export function docExcerpt(entry: { body?: string }, max = 180): string {
  if (!entry.body) return '';
  const lines = entry.body.split('\n');
  const buf: string[] = [];
  for (const raw of lines) {
    const line = raw.trim();
    // saltar encabezados, metadatos en negrita, citas, tablas, separadores
    if (
      !line ||
      line.startsWith('#') ||
      line.startsWith('>') ||
      line.startsWith('|') ||
      line.startsWith('---') ||
      line.startsWith('**')
    ) {
      if (buf.length) break;
      continue;
    }
    buf.push(line);
    if (buf.join(' ').length > max) break;
  }
  const text = buf
    .join(' ')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1') // [texto](url) -> texto
    .replace(/[`*_]/g, '');
  return text.length > max ? `${text.slice(0, max).trimEnd()}…` : text;
}

/** Slug de URL estable para un entry (aplana subdirectorios). */
export function docSlug(entry: { id: string }): string {
  return entry.id
    .toLowerCase()
    .replace(/\/readme$/i, '')
    .replace(/[/]/g, '-');
}

/** Definición de las secciones de /docs (orden de presentación). */
export const seccionesDocs: {
  key: 'fundacion' | 'adrs' | 'rust' | 'codigo';
  titulo: string;
  descripcion: string;
}[] = [
  {
    key: 'fundacion',
    titulo: 'Fundación y estado',
    descripcion:
      'La base del proyecto: visión, hardware, arquitectura micro-ROS, estrategia dual, investigación rviz2, setup del PC y la bitácora de estado.',
  },
  {
    key: 'adrs',
    titulo: 'Decisiones de arquitectura (ADRs)',
    descripcion:
      'Cada decisión técnica importante, registrada con su contexto, consecuencias y alternativas descartadas.',
  },
  {
    key: 'rust',
    titulo: 'Aprendiendo Rust',
    descripcion:
      'Serie para principiantes ligada al código real del repo: herramientas, lenguaje, FFI y embebido.',
  },
  {
    key: 'codigo',
    titulo: 'Documentación del código',
    descripcion:
      'Los READMEs técnicos de cada módulo dual, de la app de la Vita y del servidor MCP: API, diseño interno y estado.',
  },
];

export function sortDocs<T extends DocEntry>(entries: T[]): T[] {
  return [...entries].sort((a, b) => a.id.localeCompare(b.id, 'es'));
}
