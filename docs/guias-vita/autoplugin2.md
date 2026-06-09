---
title: "Autoplugin II"
slug: autoplugin2
order: 4
description: "Gestor de plugins taiHEN con menús: instala PrincessLog (los logs de nuestra app) sin editar archivos de texto a mano."
repo: "https://github.com/theheroGAC/Autoplugin"
essential: true
---

# Autoplugin II

## Qué es

Los *plugins* de la Vita (taiHEN) se activan editando los archivos
`ur0:tai/config.txt` — proceso manual y propenso a dejar la consola sin
arrancar por un typo. **Autoplugin II** lo automatiza: descarga plugins
populares, los copia a su sitio y edita el config por ti, con copia de
seguridad.

- Repositorio: <https://github.com/theheroGAC/Autoplugin>

## Para qué lo usa este proyecto

Para instalar **PrincessLog** sin dolor: el plugin que captura la salida
`sceClibPrintf` de cualquier app y la manda por red. Nuestra app ya manda
su log por UDP propio (netlog), pero PrincessLog captura *además* los
printf de las bibliotecas (micro-ROS incluido) y los crashes tempranos,
que el netlog no puede ver.

## Instalación

1. Descarga `AutoPlugin2.vpk` desde *Releases*.
2. Sube por FTP e instala con VitaShell.
3. Abre Autoplugin desde LiveArea (necesita WiFi; con
   [iTLS-Enso](itls-enso.md) instalado las descargas van finas).

## Instalar PrincessLog con Autoplugin

1. En Autoplugin: categoría de plugins de **sistema/desarrollo**.
2. Busca `PrincessLog` y márcalo para instalar.
3. Acepta que edite el `config.txt` y reinicia.
4. Configura la IP/puerto de destino con la app de configuración de
   PrincessLog (o editando `ur0:data/PrincessLog/config.bin` según su
   README: <https://github.com/CelesteBlue-dev/PSVita-RE-tools/tree/master/PrincessLog>).
5. En la laptop: `nc -u -l -p <puerto>` para ver el stream.

## Si un plugin rompe el arranque

Mantén **L** pulsado al arrancar (taiHEN salta los plugins de usuario), o
entra en modo seguro del firmware. Después usa VitaShell para revertir el
`config.txt` (Autoplugin guarda backup).
