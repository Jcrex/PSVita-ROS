// content.config.ts — colecciones de contenido (Astro 5, content layer).
//
// Las guías NO se duplican: se leen directamente de docs/guias-vita/ del
// repo (una sola fuente de verdad, también legible en GitHub). El loader
// `glob` admite rutas fuera de src/.
import { glob } from 'astro/loaders';
import { defineCollection, z } from 'astro:content';

const guias = defineCollection({
  loader: glob({
    pattern: ['*.md', '!README.md'],
    base: '../docs/guias-vita',
  }),
  schema: z.object({
    title: z.string(),
    slug: z.string(),
    order: z.number(),
    description: z.string(),
    repo: z.string().url(),
    essential: z.boolean(),
  }),
});

// El resto de la documentación del repo NO tiene frontmatter: el título se
// extrae del primer `# encabezado` del cuerpo (ver src/lib/docs.ts).
// REGLA DEL PROYECTO: todo doc nuevo en estas carpetas aparece en la web
// automáticamente en su sección — no hay paso manual que olvidar.

// docs/00-*.md ... 06-*.md — la fundación y la bitácora
const fundacion = defineCollection({
  loader: glob({ pattern: '[0-9][0-9]-*.md', base: '../docs' }),
});

// docs/adr/*.md — decisiones de arquitectura registradas
const adrs = defineCollection({
  loader: glob({ pattern: '[0-9]*.md', base: '../docs/adr' }),
});

// docs/rust/*.md — la serie de aprendizaje de Rust
const rust = defineCollection({
  loader: glob({ pattern: '*.md', base: '../docs/rust' }),
});

// READMEs técnicos del código (módulos, app, MCP)
const codigo = defineCollection({
  loader: glob({
    pattern: [
      'modules/*/README.md',
      'vita-app/README.md',
      'mcp/*/README.md',
    ],
    base: '..',
  }),
});

export const collections = { guias, fundacion, adrs, rust, codigo };
