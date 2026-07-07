import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanLine,
  classifyKind,
  isSessionStart,
  deriveStatusUpdate,
} from './netlog-parser.mjs';

test('cleanLine quita bytes de control/ruido binario al inicio', () => {
  const noisy =
    Buffer.from([0x01, 0x02, 0xff, 0xfe]).toString('utf8') +
    '[vita-ros2] red inicializada; agente=192.168.1.108:8888';
  assert.equal(
    cleanLine(noisy),
    '[vita-ros2] red inicializada; agente=192.168.1.108:8888',
  );
});

test('cleanLine no toca una línea ya limpia', () => {
  assert.equal(
    cleanLine('[vita-ros2] entidades creadas: pub /vita_hello, sub /pc_hello'),
    '[vita-ros2] entidades creadas: pub /vita_hello, sub /pc_hello',
  );
});

test('cleanLine recorta espacios y saltos de línea sobrantes', () => {
  assert.equal(cleanLine('  hola  \n'), 'hola');
});

test('cleanLine acepta Buffer directamente', () => {
  assert.equal(cleanLine(Buffer.from('hola')), 'hola');
});

test('classifyKind detecta FATAL', () => {
  assert.equal(
    classifyKind('[vita-ros2] FATAL: uxr_create_session fallo'),
    'fatal',
  );
});

test('classifyKind detecta hitos (sesión establecida y criterio cumplido)', () => {
  assert.equal(
    classifyKind('[vita-ros2] *** SESION XRCE ESTABLECIDA: incognita dura OK ***'),
    'hito',
  );
  assert.equal(
    classifyKind('[vita-ros2] criterio 2 de la Fase 1 CUMPLIDO (rx desde PC)'),
    'hito',
  );
});

test('classifyKind por defecto es normal', () => {
  assert.equal(
    classifyKind('[vita-ros2] entidades creadas: pub /vita_hello, sub /pc_hello'),
    'normal',
  );
});

test('isSessionStart detecta el arranque de una sesión nueva', () => {
  assert.equal(
    isSessionStart('[vita-ros2] red inicializada; agente=192.168.1.108:8888'),
    true,
  );
  assert.equal(
    isSessionStart('[vita-ros2] entidades creadas: pub /vita_hello, sub /pc_hello'),
    false,
  );
});

test('deriveStatusUpdate detecta sesión establecida, fatal y salida limpia', () => {
  assert.equal(
    deriveStatusUpdate('[vita-ros2] *** SESION XRCE ESTABLECIDA: incognita dura OK ***'),
    'establecida',
  );
  assert.equal(
    deriveStatusUpdate('[vita-ros2] FATAL: uxr_create_session fallo'),
    'fatal',
  );
  assert.equal(
    deriveStatusUpdate('[vita-ros2] saliendo (START pulsado tras 42 mensajes)'),
    'cerrada',
  );
});

test('deriveStatusUpdate devuelve null si la línea no marca cambio de estado', () => {
  assert.equal(
    deriveStatusUpdate('[vita-ros2] entidades creadas: pub /vita_hello, sub /pc_hello'),
    null,
  );
});
