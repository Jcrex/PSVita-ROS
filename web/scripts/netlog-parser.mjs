// netlog-parser.mjs — funciones puras para interpretar el netlog UDP de
// la Vita (ver vita-app/src/netlog.c y main.c). Sin dependencias: las usa
// tanto el ingestor (netlog-ingester.mjs) como sus propios tests.

export function cleanLine(input) {
  const text = Buffer.isBuffer(input) ? input.toString('utf8') : String(input);
  let start = 0;
  while (start < text.length) {
    const code = text.charCodeAt(start);
    const isControl = code < 0x20 && code !== 0x09;
    const isReplacement = text[start] === '�';
    if (isControl || isReplacement) {
      start++;
    } else {
      break;
    }
  }
  return text.slice(start).trim();
}

export function classifyKind(text) {
  if (text.includes('FATAL')) return 'fatal';
  if (text.includes('SESION XRCE ESTABLECIDA') || text.includes('CUMPLIDO')) {
    return 'hito';
  }
  return 'normal';
}

export function isSessionStart(text) {
  return text.includes('red inicializada');
}

export function deriveStatusUpdate(text) {
  if (text.includes('SESION XRCE ESTABLECIDA')) return 'establecida';
  if (text.includes('FATAL')) return 'fatal';
  if (text.includes('saliendo (START pulsado')) return 'cerrada';
  return null;
}
