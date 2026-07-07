// netlog-parser.mjs — funciones puras para interpretar el netlog UDP de
// la Vita (ver vita-app/src/netlog.c y main.c). Sin dependencias: las usa
// tanto el ingestor (netlog-ingester.mjs) como sus propios tests.

// Limpia un datagrama del netlog. La Vita emite texto ASCII plano (ver
// vita-app/src/netlog.c: vsnprintf), pero al 9999 también llega basura:
//  - ruido binario al arrancar la app (visto en hardware), pegado al
//    principio de una línea real;
//  - paquetes 100% binarios de OTROS dispositivos de la red. Caso real:
//    la app TP-Link Kasa sondea sus enchufes por broadcast UDP al MISMO
//    puerto 9999 (payload XOR "autokey" — descifrado en la depuración de
//    2026-07-07: {"system":{"get_sysinfo":{}},"emeter":{"get_realtime":{}}}),
//    y decodificado como UTF-8 salía en el monitor como "Ѵ���…" cada 25 s.
// Estrategia: quitar controles (salvo \t y \n) y U+FFFD en cualquier
// posición, y después descartar la línea entera si menos del 70 % de lo
// que queda es ASCII imprimible — una línea real de la Vita es ~100 %.
export function cleanLine(input) {
  const text = Buffer.isBuffer(input) ? input.toString('utf8') : String(input);
  let limpio = '';
  for (const ch of text) {
    const code = ch.codePointAt(0);
    const esControl = (code < 0x20 && code !== 0x09 && code !== 0x0a) || code === 0x7f;
    if (esControl || code === 0xfffd) continue;
    limpio += ch;
  }
  limpio = limpio.trim();
  if (limpio === '') return '';

  const chars = [...limpio];
  const legibles = chars.filter((ch) => {
    const code = ch.codePointAt(0);
    return (code >= 0x20 && code <= 0x7e) || code === 0x09 || code === 0x0a;
  }).length;
  return legibles / chars.length >= 0.7 ? limpio : '';
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
