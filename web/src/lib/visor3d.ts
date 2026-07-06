// visor3d.ts — visor 3D standalone de URDF/SDF/mallas (corre en el
// NAVEGADOR; nada de esto toca la Vita).
//
// Preparación adelantada del Objetivo 3/4 (docs/07 §3, docs/08): el parser
// de URDF/SDF y la UI del visor no cambian por dónde se renderice después.
//
// Convención de ejes: ROS/URDF usan Z-arriba; three.js usa Y-arriba. Todo
// el modelo cuelga de un grupo "mundo" rotado -90° en X para compensar.
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { STLLoader } from 'three/addons/loaders/STLLoader.js';
import { OBJLoader } from 'three/addons/loaders/OBJLoader.js';
import { ColladaLoader } from 'three/addons/loaders/ColladaLoader.js';

// ---------- tipos públicos ----------

export interface ControlJoint {
  nombre: string;
  tipo: 'revolute' | 'continuous' | 'prismatic';
  lower: number;
  upper: number;
  valor: number;
  aplicar: (v: number) => void;
}

export interface ModeloCargado {
  nombre: string;
  formato: 'urdf' | 'sdf' | 'malla';
  objeto: THREE.Object3D;
  joints: ControlJoint[];
  nLinks: number;
  avisos: string[];
}

/** Archivos auxiliares (mallas) que acompañan al modelo, por nombre base. */
export type Recursos = Map<string, ArrayBuffer>;

// ---------- utilidades de parseo ----------

function nums(s: string | null | undefined, n: number, def = 0): number[] {
  const out = (s ?? '').trim().split(/\s+/).map(Number);
  while (out.length < n) out.push(def);
  return out.map((v) => (Number.isFinite(v) ? v : def));
}

/** Aplica origin URDF (xyz + rpy con orden fijo ZYX) a un Object3D. */
function aplicarOrigen(obj: THREE.Object3D, xyz: number[], rpy: number[]) {
  obj.position.set(xyz[0], xyz[1], xyz[2]);
  obj.rotation.set(rpy[0], rpy[1], rpy[2], 'ZYX');
}

function matStandard(color: THREE.ColorRepresentation, opacity = 1) {
  return new THREE.MeshStandardMaterial({
    color,
    metalness: 0.1,
    roughness: 0.75,
    transparent: opacity < 1,
    opacity,
    side: THREE.DoubleSide,
  });
}

const COLOR_DEFECTO = 0x60a5fa;

function baseName(uri: string): string {
  return uri.split(/[\\/]/).pop() ?? uri;
}

/**
 * Carga una malla desde los recursos adjuntos (STL/OBJ/DAE) y la añade a
 * `padre`. Si el archivo no está entre los recursos, deja un cubo
 * placeholder y lo anota en avisos.
 */
function cargarMalla(
  uri: string,
  escala: number[],
  material: THREE.Material,
  padre: THREE.Object3D,
  recursos: Recursos,
  avisos: string[],
) {
  const nombre = baseName(uri);
  const datos = recursos.get(nombre.toLowerCase());
  const ext = nombre.split('.').pop()?.toLowerCase();

  const aplicarEscala = (o: THREE.Object3D) => o.scale.set(escala[0], escala[1], escala[2]);

  if (!datos) {
    const ph = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.1, 0.1), matStandard(0xf59e0b, 0.55));
    padre.add(ph);
    avisos.push(`Malla "${nombre}" no adjuntada — placeholder. Arrastra el archivo junto al modelo.`);
    return;
  }
  try {
    if (ext === 'stl') {
      const geo = new STLLoader().parse(datos);
      geo.computeVertexNormals();
      const mesh = new THREE.Mesh(geo, material);
      aplicarEscala(mesh);
      padre.add(mesh);
    } else if (ext === 'obj') {
      const grupo = new OBJLoader().parse(new TextDecoder().decode(datos));
      grupo.traverse((o) => {
        if (o instanceof THREE.Mesh) o.material = material;
      });
      aplicarEscala(grupo);
      padre.add(grupo);
    } else if (ext === 'dae') {
      const dae = new ColladaLoader().parse(new TextDecoder().decode(datos), '');
      aplicarEscala(dae.scene);
      padre.add(dae.scene);
    } else {
      avisos.push(`Formato de malla no soportado: "${nombre}" (soportados: STL, OBJ, DAE).`);
    }
  } catch (e) {
    avisos.push(`Error cargando la malla "${nombre}": ${(e as Error).message}`);
  }
}

/** Crea la geometría de un <geometry> URDF/SDF ya normalizado. */
function crearGeometria(
  tipo: string,
  el: Element,
  esSdf: boolean,
): THREE.BufferGeometry | null {
  if (tipo === 'box') {
    const s = esSdf
      ? nums(el.querySelector('size')?.textContent, 3, 0.1)
      : nums(el.getAttribute('size'), 3, 0.1);
    return new THREE.BoxGeometry(s[0], s[1], s[2]);
  }
  if (tipo === 'cylinder') {
    const r = esSdf
      ? Number(el.querySelector('radius')?.textContent ?? 0.05)
      : Number(el.getAttribute('radius') ?? 0.05);
    const l = esSdf
      ? Number(el.querySelector('length')?.textContent ?? 0.1)
      : Number(el.getAttribute('length') ?? 0.1);
    // URDF/SDF: eje del cilindro en Z; three lo genera en Y → rotar la geo.
    const geo = new THREE.CylinderGeometry(r, r, l, 32);
    geo.rotateX(Math.PI / 2);
    return geo;
  }
  if (tipo === 'sphere') {
    const r = esSdf
      ? Number(el.querySelector('radius')?.textContent ?? 0.05)
      : Number(el.getAttribute('radius') ?? 0.05);
    return new THREE.SphereGeometry(r, 32, 16);
  }
  return null;
}

// ---------- URDF ----------

export function parseUrdf(xml: string, nombre: string, recursos: Recursos): ModeloCargado {
  const doc = new DOMParser().parseFromString(xml, 'text/xml');
  const robot = doc.querySelector('robot');
  if (!robot) throw new Error('El archivo no contiene un elemento <robot> (¿es un URDF?)');
  if (xml.includes('xacro:')) {
    throw new Error('Es un .xacro sin procesar: expándelo primero (xacro archivo.xacro > salida.urdf).');
  }

  const avisos: string[] = [];

  // Materiales con nombre a nivel <robot>.
  const materiales = new Map<string, THREE.Material>();
  for (const m of robot.querySelectorAll(':scope > material')) {
    const rgba = nums(m.querySelector('color')?.getAttribute('rgba'), 4, 1);
    materiales.set(
      m.getAttribute('name') ?? '',
      matStandard(new THREE.Color(rgba[0], rgba[1], rgba[2]), rgba[3]),
    );
  }

  const materialDe = (visual: Element): THREE.Material => {
    const m = visual.querySelector(':scope > material');
    if (!m) return matStandard(COLOR_DEFECTO);
    const rgba = m.querySelector('color')?.getAttribute('rgba');
    if (rgba) {
      const c = nums(rgba, 4, 1);
      return matStandard(new THREE.Color(c[0], c[1], c[2]), c[3]);
    }
    return materiales.get(m.getAttribute('name') ?? '') ?? matStandard(COLOR_DEFECTO);
  };

  // 1) Un Group por link, con sus <visual>.
  const links = new Map<string, THREE.Group>();
  for (const link of robot.querySelectorAll(':scope > link')) {
    const g = new THREE.Group();
    g.name = link.getAttribute('name') ?? `link${links.size}`;
    for (const visual of link.querySelectorAll(':scope > visual')) {
      const origen = visual.querySelector(':scope > origin');
      const holder = new THREE.Group();
      aplicarOrigen(holder, nums(origen?.getAttribute('xyz'), 3), nums(origen?.getAttribute('rpy'), 3));
      const geoEl = visual.querySelector(':scope > geometry > *');
      if (!geoEl) continue;
      const mat = materialDe(visual);
      if (geoEl.tagName === 'mesh') {
        cargarMalla(
          geoEl.getAttribute('filename') ?? '',
          nums(geoEl.getAttribute('scale'), 3, 1),
          mat,
          holder,
          recursos,
          avisos,
        );
      } else {
        const geo = crearGeometria(geoEl.tagName, geoEl, false);
        if (geo) holder.add(new THREE.Mesh(geo, mat));
      }
      g.add(holder);
    }
    links.set(g.name, g);
  }

  // 2) Joints: jointGroup (origen fijo) > motion (parte móvil) > link hijo.
  const joints: ControlJoint[] = [];
  const hijos = new Set<string>();
  for (const joint of robot.querySelectorAll(':scope > joint')) {
    const tipo = joint.getAttribute('type') ?? 'fixed';
    const padre = links.get(joint.querySelector('parent')?.getAttribute('link') ?? '');
    const hijo = links.get(joint.querySelector('child')?.getAttribute('link') ?? '');
    if (!padre || !hijo) {
      avisos.push(`Joint "${joint.getAttribute('name')}" apunta a un link inexistente.`);
      continue;
    }
    hijos.add(hijo.name);
    const origen = joint.querySelector(':scope > origin');
    const jointGroup = new THREE.Group();
    aplicarOrigen(jointGroup, nums(origen?.getAttribute('xyz'), 3), nums(origen?.getAttribute('rpy'), 3));
    const motion = new THREE.Group();
    jointGroup.add(motion);
    motion.add(hijo);
    padre.add(jointGroup);

    if (tipo === 'revolute' || tipo === 'continuous' || tipo === 'prismatic') {
      const eje = new THREE.Vector3(...nums(joint.querySelector('axis')?.getAttribute('xyz'), 3, 0));
      if (eje.lengthSq() === 0) eje.set(1, 0, 0);
      eje.normalize();
      const limite = joint.querySelector('limit');
      const lower = Number(limite?.getAttribute('lower') ?? (tipo === 'continuous' ? -Math.PI : -1));
      const upper = Number(limite?.getAttribute('upper') ?? (tipo === 'continuous' ? Math.PI : 1));
      joints.push({
        nombre: joint.getAttribute('name') ?? `joint${joints.length}`,
        tipo,
        lower,
        upper,
        valor: Math.min(Math.max(0, lower), upper),
        aplicar: (v: number) => {
          if (tipo === 'prismatic') motion.position.copy(eje).multiplyScalar(v);
          else motion.quaternion.setFromAxisAngle(eje, v);
        },
      });
    }
  }

  // 3) Links raíz (no son hijos de ningún joint) → al objeto raíz.
  const raiz = new THREE.Group();
  raiz.name = robot.getAttribute('name') ?? nombre;
  for (const [nombreLink, g] of links) if (!hijos.has(nombreLink)) raiz.add(g);
  if (raiz.children.length === 0) avisos.push('No se encontró ningún link raíz.');

  return { nombre: raiz.name, formato: 'urdf', objeto: raiz, joints, nLinks: links.size, avisos };
}

// ---------- SDF (soporte básico) ----------
//
// Visor básico: coloca cada <link> por su <pose> en el frame del modelo y
// dibuja sus <visual>. Los joints se listan pero sin articulación (la
// semántica de poses de SDF es distinta a la de URDF; se añadirá cuando
// haga falta de verdad).

export function parseSdf(xml: string, nombre: string, recursos: Recursos): ModeloCargado {
  const doc = new DOMParser().parseFromString(xml, 'text/xml');
  const modelo = doc.querySelector('sdf model, sdf world model');
  if (!modelo) throw new Error('El archivo no contiene <sdf><model> (¿es un SDF?)');

  const avisos: string[] = [];
  const raiz = new THREE.Group();
  raiz.name = modelo.getAttribute('name') ?? nombre;

  const aplicarPose = (obj: THREE.Object3D, poseEl: Element | null) => {
    const p = nums(poseEl?.textContent, 6);
    obj.position.set(p[0], p[1], p[2]);
    obj.rotation.set(p[3], p[4], p[5], 'ZYX');
  };

  let nLinks = 0;
  for (const link of modelo.querySelectorAll(':scope > link')) {
    nLinks++;
    const g = new THREE.Group();
    g.name = link.getAttribute('name') ?? `link${nLinks}`;
    aplicarPose(g, link.querySelector(':scope > pose'));
    for (const visual of link.querySelectorAll(':scope > visual')) {
      const holder = new THREE.Group();
      aplicarPose(holder, visual.querySelector(':scope > pose'));
      const geoEl = visual.querySelector(':scope > geometry > *');
      if (!geoEl) continue;
      const dif = nums(visual.querySelector('material diffuse')?.textContent, 4, -1);
      const mat =
        dif[0] >= 0
          ? matStandard(new THREE.Color(dif[0], dif[1], dif[2]), dif[3] < 0 ? 1 : dif[3])
          : matStandard(COLOR_DEFECTO);
      if (geoEl.tagName === 'mesh') {
        cargarMalla(
          geoEl.querySelector('uri')?.textContent ?? '',
          nums(geoEl.querySelector('scale')?.textContent, 3, 1),
          mat,
          holder,
          recursos,
          avisos,
        );
      } else {
        const geo = crearGeometria(geoEl.tagName, geoEl, true);
        if (geo) holder.add(new THREE.Mesh(geo, mat));
      }
      g.add(holder);
    }
    raiz.add(g);
  }

  const nJoints = modelo.querySelectorAll(':scope > joint').length;
  if (nJoints > 0) {
    avisos.push(`SDF básico: ${nJoints} joint(s) mostrados en su pose inicial (sin sliders).`);
  }

  return { nombre: raiz.name, formato: 'sdf', objeto: raiz, joints: [], nLinks, avisos };
}

// ---------- malla suelta (STL/OBJ/DAE sin robot) ----------

export function cargarMallaSuelta(nombreArchivo: string, datos: ArrayBuffer): ModeloCargado {
  const avisos: string[] = [];
  const raiz = new THREE.Group();
  raiz.name = nombreArchivo;
  const recursos: Recursos = new Map([[nombreArchivo.toLowerCase(), datos]]);
  cargarMalla(nombreArchivo, [1, 1, 1], matStandard(COLOR_DEFECTO), raiz, recursos, avisos);
  return { nombre: nombreArchivo, formato: 'malla', objeto: raiz, joints: [], nLinks: 1, avisos };
}

// ---------- escena ----------

export interface Escena {
  cargar: (modelo: ModeloCargado) => void;
  setRejilla: (v: boolean) => void;
  setEjes: (v: boolean) => void;
  setWireframe: (v: boolean) => void;
  setAutorotar: (v: boolean) => void;
  encuadrar: () => void;
}

export function crearEscena(canvas: HTMLCanvasElement): Escena {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x0d1426);

  const camera = new THREE.PerspectiveCamera(50, 1, 0.01, 200);
  camera.position.set(1.2, 0.9, 1.2);

  const controls = new OrbitControls(camera, canvas);
  controls.enableDamping = true;

  scene.add(new THREE.HemisphereLight(0xdde7ff, 0x1e2c4f, 1.1));
  const dir = new THREE.DirectionalLight(0xffffff, 1.4);
  dir.position.set(3, 5, 2);
  scene.add(dir);

  const rejilla = new THREE.GridHelper(4, 40, 0x3b82f6, 0x1e2c4f);
  (rejilla.material as THREE.Material).transparent = true;
  (rejilla.material as THREE.Material).opacity = 0.5;
  scene.add(rejilla);

  // "mundo": contenedor Z-arriba (ROS) dentro del Y-arriba de three.
  const mundo = new THREE.Group();
  mundo.rotation.x = -Math.PI / 2;
  scene.add(mundo);

  const ejes = new THREE.AxesHelper(0.5);
  mundo.add(ejes);

  let actual: THREE.Object3D | null = null;
  let autorotar = false;

  const redimensionar = () => {
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    if (canvas.width !== w || canvas.height !== h) {
      renderer.setSize(w, h, false);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
    }
  };

  const encuadrar = () => {
    if (!actual) return;
    const caja = new THREE.Box3().setFromObject(actual);
    if (caja.isEmpty()) return;
    const centro = caja.getCenter(new THREE.Vector3());
    const tam = caja.getSize(new THREE.Vector3()).length() || 1;
    controls.target.copy(centro);
    camera.position.copy(centro).add(new THREE.Vector3(0.9, 0.7, 0.9).multiplyScalar(tam));
    camera.near = tam / 100;
    camera.far = tam * 100;
    camera.updateProjectionMatrix();
  };

  renderer.setAnimationLoop(() => {
    redimensionar();
    if (autorotar && actual) actual.rotation.z += 0.004;
    controls.update();
    renderer.render(scene, camera);
  });

  return {
    cargar(modelo) {
      if (actual) mundo.remove(actual);
      actual = modelo.objeto;
      mundo.add(actual);
      for (const j of modelo.joints) j.aplicar(j.valor);
      encuadrar();
    },
    setRejilla: (v) => (rejilla.visible = v),
    setEjes: (v) => (ejes.visible = v),
    setWireframe(v) {
      actual?.traverse((o) => {
        if (o instanceof THREE.Mesh) {
          const mats = Array.isArray(o.material) ? o.material : [o.material];
          for (const m of mats) if ('wireframe' in m) (m as THREE.MeshStandardMaterial).wireframe = v;
        }
      });
    },
    setAutorotar: (v) => (autorotar = v),
    encuadrar,
  };
}
