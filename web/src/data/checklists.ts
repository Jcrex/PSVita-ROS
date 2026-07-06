// checklists.ts — pasos accionables por guía (el checklist interactivo).
// Cada paso refleja la sección "Instalación"/"Uso" de la guía markdown.
export interface ChecklistStep {
  id: string;
  text: string;
}

export const checklists: Record<string, ChecklistStep[]> = {
  vitashell: [
    { id: 'descargar', text: 'Descargar VitaShell.vpk desde Releases del repo' },
    { id: 'subir', text: 'Subir el .vpk a la consola (FTP o VitaDeploy)' },
    { id: 'instalar', text: 'Instalar el .vpk y aceptar permisos extendidos' },
    { id: 'ftp', text: 'Probar el modo FTP (SELECT) desde la laptop' },
    { id: 'ip-fija', text: 'Asignar IP fija a la Vita en el router' },
  ],
  'itls-enso': [
    { id: 'descargar', text: 'Descargar iTLS-Enso.vpk desde Releases' },
    { id: 'instalar', text: 'Subir por FTP e instalar con VitaShell' },
    { id: 'modulos', text: 'Abrir la app e instalar los módulos TLS' },
    { id: 'boot', text: 'Enganchar al arranque (boot) y reiniciar' },
    { id: 'verificar', text: 'Verificar que https://github.com carga en el navegador' },
  ],
  vitadeploy: [
    { id: 'descargar', text: 'Descargar VitaDeploy.vpk desde Releases' },
    { id: 'instalar', text: 'Subir por FTP e instalar con VitaShell' },
    { id: 'apps', text: 'Ejecutar el App installer con las apps esenciales' },
  ],
  autoplugin2: [
    { id: 'descargar', text: 'Descargar AutoPlugin2.vpk desde Releases' },
    { id: 'instalar', text: 'Subir por FTP e instalar con VitaShell' },
    { id: 'princesslog', text: 'Instalar PrincessLog desde Autoplugin' },
    { id: 'config', text: 'Configurar IP/puerto de PrincessLog hacia la laptop' },
    { id: 'probar', text: 'Probar la recepción con nc -u -l -p <puerto>' },
  ],
  sharkbr33d: [
    { id: 'descargar', text: 'Descargar ShaRKBR33D.vpk desde Releases' },
    { id: 'instalar', text: 'Subir por FTP e instalar con VitaShell' },
    { id: 'actualizar', text: 'Ejecutar la actualización de HENkaku/taiHEN y reiniciar' },
  ],
  pkgj: [
    { id: 'descargar', text: 'Descargar pkgj.vpk desde Releases' },
    { id: 'instalar', text: 'Subir por FTP e instalar con VitaShell' },
    { id: 'config', text: 'Configurar las listas (config.txt) según el README' },
  ],
  adrenaline: [
    { id: 'descargar', text: 'Descargar Adrenaline.vpk desde Releases' },
    { id: 'instalar', text: 'Subir por FTP e instalar con VitaShell' },
    { id: 'asistente', text: 'Completar el asistente del primer arranque (base 6.61)' },
  ],
  // Tutorial del SDK (práctica guiada de la sección 7 de la guía).
  'vitasdk-toolchain': [
    { id: 'entorno', text: 'Activar el entorno con source tools/env-devpc.fish' },
    { id: 'toolchain', text: 'Verificar arm-vita-eabi-gcc --version y $VITASDK' },
    { id: 'xrce', text: 'Cross-compilar las dependencias (build-xrce-client-vita.sh)' },
    { id: 'cmake', text: 'Configurar con el toolchain file y -DVITA_IMPL' },
    { id: 'build', text: 'Compilar y obtener el .vpk (cmake --build)' },
    { id: 'inspeccionar', text: 'Inspeccionar el .vpk con unzip -l (eboot.bin + param.sfo)' },
    { id: 'deploy', text: 'Enviar a la Vita por FTP e instalar con VitaShell' },
  ],
};
