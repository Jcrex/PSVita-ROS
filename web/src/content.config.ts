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

export const collections = { guias };
