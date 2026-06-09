---
title: "VitaDeploy"
slug: vitadeploy
order: 3
description: "Instalador todo-en-uno: apps esenciales, downgrade/upgrade de firmware y SD2Vita desde la propia consola."
repo: "https://github.com/SKGleba/VitaDeploy"
essential: false
---

# VitaDeploy

## Qué es

Una "navaja suiza" de mantenimiento: desde la propia Vita permite instalar
un paquete de apps esenciales (VitaShell, etc.), preparar una microSD con
SD2Vita como almacenamiento, y cambiar de versión de firmware (la función
por la que es famosa: updates/downgrades seguros entre firmwares
hackeables).

- Repositorio: <https://github.com/SKGleba/VitaDeploy>

## Para qué la usa este proyecto

No es una dependencia directa, pero es la forma más cómoda de dejar una
consola "recién hackeada" con el set básico instalado (VitaShell incluido)
sin pelearse con transferencias manuales. Si tu Vita ya tiene VitaShell,
puedes saltarte esta guía.

## Instalación

1. Descarga `VitaDeploy.vpk` de *Releases*.
2. Súbelo por FTP e instálalo con VitaShell.
3. Ábrelo desde LiveArea.

## Uso típico (app installer)

1. En VitaDeploy elige **"App installer"**.
2. Marca las apps que quieras (VitaShell es la importante).
3. Deja que descargue e instale (necesita WiFi; si falla por HTTPS,
   instala antes [iTLS-Enso](itls-enso.md)).

## Advertencias

- La función de **cambio de firmware** reescribe el sistema: lee su README
  y no la uses con batería baja. Para este proyecto NO hace falta tocar el
  firmware si ya estás en 3.60–3.74 con HENkaku.
- En consolas con enso instalado, VitaDeploy avisa antes de cualquier
  operación que lo afecte.
