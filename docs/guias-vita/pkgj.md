---
title: "PKGj"
slug: pkgj
order: 6
description: "Tienda alternativa de contenido para la Vita. No es requisito del proyecto; documentada por completitud."
repo: "https://github.com/blastrock/pkgj"
essential: false
---

# PKGj

## Qué es

Un cliente que descarga e instala contenido (juegos, DLC, temas, contenido
de PSP/PSX) directamente en la consola a partir de listas de enlaces
(`tsv`). Es una de las homebrew más conocidas del ecosistema.

- Repositorio: <https://github.com/blastrock/pkgj>

## Relación con este proyecto

**Ninguna dependencia técnica.** Se documenta porque forma parte del set
estándar de una Vita hackeada y porque comparte el mismo flujo de
instalación que nuestra app (vpk por FTP), así que sirve de práctica.

> Nota legal: PKGj descarga contenido con copyright. Úsalo solo para
> contenido del que tengas licencia. Este proyecto no distribuye listas.

## Instalación

1. Descarga `pkgj.vpk` de *Releases*.
2. Sube por FTP e instala con VitaShell.
3. Al primer arranque pide configurar las URLs de las listas (`config.txt`
   en `ux0:pkgj/`); consulta el README del repositorio.

## Uso básico

- TRIANGLE abre el menú (filtros, ordenación, refrescar listas).
- X descarga; el progreso aparece en burbujas de LiveArea.
- Requiere espacio libre considerable y WiFi estable.
