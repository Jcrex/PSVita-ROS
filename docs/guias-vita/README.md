# Guías de instalación — PS Vita desbloqueada

Guías de las herramientas homebrew que este proyecto usa o recomienda en
una PS Vita 1000 **ya desbloqueada** (CFW HENkaku/h-encore². Si tu consola
aún no lo está, empieza SIEMPRE por la guía canónica de la comunidad:
**<https://vita.hacks.guide/>** — está mantenida al día, en varios idiomas,
y cubre todos los firmwares).

Estas guías también se publican en la web del proyecto.

## Orden recomendado de instalación

| # | Herramienta | Para qué la usa este proyecto |
|---|---|---|
| 1 | [VitaShell](vitashell.md) | Gestor de archivos + **servidor FTP**: así llega nuestro `.vpk` a la consola (skill `vita-deploy-logs`). Imprescindible. |
| 2 | [iTLS-Enso](itls-enso.md) | TLS 1.2 moderno para el navegador/descargas nativas. Necesario para que otras herramientas descarguen por HTTPS. |
| 3 | [VitaDeploy](vitadeploy.md) | Instalador "todo en uno" de apps esenciales desde la propia consola. |
| 4 | [Autoplugin II](autoplugin2.md) | Instala/gestiona plugins (taiHEN) con menús; útil para PrincessLog (logs de nuestra app). |
| 5 | [ShaRKBR33D](sharkbr33d.md) | Actualiza HENkaku/taiHEN a la última versión con un botón. |
| 6 | [PKGj](pkgj.md) | Tienda alternativa de contenido. No es requisito del proyecto. |
| 7 | [Adrenaline](adrenaline.md) | ePSP: ejecuta el ecosistema PSP/PS1. Tampoco es requisito; documentado por completitud. |

## Requisitos comunes

- PS Vita con HENkaku/h-encore² instalado y **HENkaku activado** en la
  sesión actual (o enso para que sea permanente).
- En *Ajustes → HENkaku* marcar **"Activar apps inseguras"** — sin esto no
  se puede instalar ningún `.vpk`.
- Tarjeta de memoria con espacio libre (o SD2Vita).
- WiFi configurada (la misma red que la laptop, para FTP y para la Fase 1
  de este proyecto).

## Cómo se instala un `.vpk` (el caso de nuestra app)

1. En la Vita: abrir VitaShell → pulsar `SELECT` → se activa el modo FTP y
   muestra `ftp://IP_DE_LA_VITA:1337`.
2. Desde la laptop/PC: `curl -T vita-ros2-hello.vpk ftp://IP_DE_LA_VITA:1337/ux0:/`
3. En VitaShell: navegar a `ux0:/`, pulsar X sobre el `.vpk` → instalar.
4. Aceptar el aviso de permisos extendidos (nuestra app usa red).

> Advertencia general: instala homebrew solo desde los repositorios
> oficiales enlazados en cada guía. Un plugin mal instalado puede impedir
> el arranque (se recupera con el "safe mode" de taiHEN: mantener L al
> arrancar, o el modo seguro del firmware).
