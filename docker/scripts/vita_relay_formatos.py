#!/usr/bin/env python3
"""vita_relay_formatos — funciones PURAS del contrato VC/1 (rev. 2) del relay PC → Vita (sin ROS).

Es la referencia de bytes de todos los formatos de `/vita/*` (doc 36 §5; ADR 0013; sentencia W13 D4–D5). Cada
formato tiene su copia en `godot/plantillas/ros/vc1.gd` y una prueba de bytes en los dos lados
(`docker/scripts/test_vita_relay.py` y `godot/plantillas/pruebas/runner.gd`). Un formato sin prueba de bytes no
entra. El nodo ROS 2 vive en `vita_relay.py` (que reexporta todo lo de aquí).

Tamaños (D4): «límite de diseño» = ≤ MAX_BE bytes MEDIDOS CON ROSBAGS (CDR con los 4 B de encapsulación; carga
XRCE ≤ 484 B, 4 B de margen frente al límite duro de 488 B de carga, `godot/ros2_vita/xrce_transport.cpp:147,678`).
Si el gate G-W13-R0 confirma 488 B de carga también en recepción, MAX_BE sube a 492 AQUÍ y en ningún sitio más.

Contenido:
  - VC/1 (rev. 1, sin cambiar ni un byte, D5.2): scan_compacto, mapa_tesela, path_compacto, cdr_multiarray…
  - VC/1 rev. 2: cabecera común troceada `[seq & 0x7FFF, trozo, n_trozos, n, …]` (`trocear`), `relay_info`,
    presupuesto de red por módulo y perfiles (D5.7), época del mapa (D5.5), `rosout` y `diagnostics` recortados
    (tamaño CDR exacto), configuración y tope del módulo `ritmo` (D5.9).
"""
import math
import re

TESELA = 32               # celdas por lado de una tesela de mapa
MAX_BE = 488              # bytes con rosbags de todo /vita/* (D4); 492 tras G-W13-R0 verde
MAX_F32 = (MAX_BE - 16) // 4                    # 118 floats por Float32MultiArray (16 + 4N)
MAX_I16 = (MAX_BE - 16) // 2                    # 236 int16 por Int16MultiArray (16 + 2N)
MAX_U8 = MAX_BE - 16                            # 472 bytes por UInt8MultiArray (16 + N)
MASCARA_SEQ = 0x7FFF
VERSION_CONTRATO = "VC/1.2"


# ============================================================================= VC/1 (rev. 1): no cambian (D5.2)

def empaquetar_scan(ranges, angle_min, angle_increment, range_min, range_max, seq, max_rayos=180):
    """LaserScan → lista de int16. Diezma por paso fijo para que quepan ≤ max_rayos."""
    n_in = len(ranges)
    paso = max(1, math.ceil(n_in / max_rayos))
    sel = ranges[::paso][:max_rayos]
    out = [seq & MASCARA_SEQ, _i16(round(math.degrees(angle_min) * 100)),
           _i16(round(math.degrees(angle_increment * paso) * 100)), len(sel)]
    for r in sel:
        if r is None or math.isnan(r) or math.isinf(r) or r < range_min or r > range_max:
            out.append(0)
        else:
            out.append(_i16(round(r * 100)))
    return out


def desempaquetar_scan(d):
    """Inverso (lo que hará la Vita): [(ángulo_rad, distancia_m)] sin los rayos vacíos."""
    ang0, inc, n = math.radians(d[1] / 100), math.radians(d[2] / 100), d[3]
    return [(ang0 + i * inc, d[4 + i] / 100) for i in range(n) if d[4 + i] > 0]


def _i16(v):
    return max(-32768, min(32767, int(v)))


def celda_2bit(v):
    """OccupancyGrid (-1 desconocido, 0..100) → 0 desconocido, 1 libre, 2 ocupado (umbrales de map_server)."""
    if v < 0:
        return 0
    return 2 if v >= 65 else (1 if v <= 25 else 0)


def empaquetar_tesela(data, ancho, alto, tx, ty, version):
    """Una tesela de 32×32 celdas a 2 bit = 256 B + cabecera de 4 B. Celdas fuera del mapa = desconocido."""
    cuerpo = bytearray(TESELA * TESELA // 4)
    for j in range(TESELA):
        y = ty * TESELA + j
        for i in range(TESELA):
            x = tx * TESELA + i
            c = celda_2bit(data[y * ancho + x]) if (x < ancho and y < alto) else 0
            k = j * TESELA + i
            cuerpo[k >> 2] |= c << ((k & 3) * 2)
    return bytes([version & 0xFF, (version >> 8) & 0xFF, tx, ty]) + bytes(cuerpo)


def desempaquetar_tesela(b):
    """Inverso: (version, tx, ty, lista de 1024 valores 0/1/2 por filas)."""
    ver, tx, ty = b[0] | (b[1] << 8), b[2], b[3]
    celdas = [(b[4 + (k >> 2)] >> ((k & 3) * 2)) & 3 for k in range(TESELA * TESELA)]
    return ver, tx, ty, celdas


def douglas_peucker(pts, eps):
    if len(pts) < 3:
        return list(pts)
    (x0, y0), (x1, y1) = pts[0], pts[-1]
    dx, dy = x1 - x0, y1 - y0
    norma = math.hypot(dx, dy) or 1e-9
    peor, idx = -1.0, 0
    for i in range(1, len(pts) - 1):
        d = abs(dy * pts[i][0] - dx * pts[i][1] + x1 * y0 - y1 * x0) / norma
        if d > peor:
            peor, idx = d, i
    if peor <= eps:
        return [pts[0], pts[-1]]
    return douglas_peucker(pts[:idx + 1], eps)[:-1] + douglas_peucker(pts[idx:], eps)


def empaquetar_path(pts, eps=0.05, max_pts=57):
    s = douglas_peucker(pts, eps)
    while len(s) > max_pts:          # si aún sobran, ε creciente
        eps *= 1.5
        s = douglas_peucker(pts, eps)
    return [float(len(s))] + [v for p in s for v in p]


def yaw_de_quat(x, y, z, w):
    return math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))


def cdr_multiarray(n_elem, tam_elem):
    """Bytes de CDR de un *MultiArray sin dimensiones: encapsulado 4 + dim seq 4 + data_offset 4 + seq 4 + datos."""
    return 4 + 4 + 4 + 4 + n_elem * tam_elem


# ============================================================================= VC/1 rev. 2 (V6)

def trocear(elementos, por_elemento, extra=(), seq=0, max_valores=MAX_F32, max_trozos=3):
    """VC/1 rev. 2 (D5.1): lista de elementos (cada uno, lista de `por_elemento` números) → lista de trozos
    [seq & 0x7FFF, trozo, n_trozos, n, *extra, *elementos_del_trozo], con n = elementos DE ESTE trozo.
    Corta a max_trozos (estado completo). Sin elementos sale un trozo con n = 0 (estado «vacío»).
    Copia en GDScript: `vc1.gd` `trocear` (misma salida, prueba cruzada por huella MD5)."""
    cab = 4 + len(extra)
    cabe = (max_valores - cab) // por_elemento
    if cabe < 1:
        raise ValueError(f"trocear: {por_elemento} valores por elemento no caben en {max_valores} - {cab}")
    elementos = elementos[:cabe * max_trozos]
    n_trozos = max(1, -(-len(elementos) // cabe))
    out = []
    for t in range(n_trozos):
        parte = elementos[t * cabe:(t + 1) * cabe]
        out.append([seq & MASCARA_SEQ, t, n_trozos, len(parte), *extra, *[v for e in parte for v in e]])
    return out


def cabecera(d):
    """Lectura de la cabecera común (lo que hace la Vita): dict o None si no es válida."""
    if len(d) < 4:
        return None
    c = {"seq": int(d[0]), "trozo": int(d[1]), "n_trozos": int(d[2]), "n": int(d[3])}
    if c["n_trozos"] < 1 or c["trozo"] < 0 or c["trozo"] >= c["n_trozos"] or c["n"] < 0:
        return None
    return c


def huella(valores):
    """Huella común Python ↔ GDScript: MD5 de los enteros unidos por comas (como `_md5` de pruebas/runner.gd)."""
    import hashlib
    return hashlib.md5(",".join(str(int(v)) for v in valores).encode()).hexdigest()


# ----------------------------------------------------------------------------- relay_info (D5.8)

def relay_info(modulos):
    """String latched de saludo: «VC/1.2;scan,pose,…». Los módulos en el orden en que se activaron."""
    return VERSION_CONTRATO + ";" + ",".join(m for m in modulos if m != "nucleo")


def leer_relay_info(s):
    """Inverso: (versión, [módulos]) o None si no es un saludo VC/1."""
    if not s.startswith("VC/1") or ";" not in s:
        return None
    ver, _, mods = s.partition(";")
    return ver, [m for m in mods.split(",") if m]


# ----------------------------------------------------------------------------- presupuesto de red (D5.7)

# Presupuesto declarado por módulo: (ciclos/s, bytes por ciclo, datagramas por ciclo). Tabla de doc 36 §5.3.
# «marcadores» incluye marcadores (3 trozos) + marcador_puntos (≤ 4/s) + marcador_texto (≤ 2/s): 21 dgr/s.
PRESUPUESTO = {"nucleo": (1, 24, 1), "scan": (10, 384, 1), "pose": (30, 40, 1), "joints": (25, 132, 1),
               "mapa": (20, 276, 1), "path": (2, 476, 1), "rosout": (10, 270, 1), "diag": (10, 160, 1),
               "marcadores": (5, 3 * 472 + 384 + 40, 4.2), "pose_cov": (2, 44, 1), "poses": (2, 464, 1),
               "tf": (10, 288, 1), "costmap": (10, 276, 1), "camara": (3, 3000, 7), "det2d": (5, 472, 1),
               "det3d": (5, 464, 1), "nube": (5, 3 * 480, 3),
               "ritmo": (1, 10000, 30)}                # tope declarado del módulo ritmo (≤ 10 KB/s, ≤ 30 dgr/s)
KB_MAX = 100.0            # docs/27:42-43
DGR_MAX = 200.0

_HMI = ["scan", "pose", "joints", "mapa", "path", "rosout", "diag"]
PERFILES = {
    "hmi": _HMI,
    "viz": _HMI + ["marcadores", "pose_cov", "poses", "tf", "costmap"],
    "percepcion": _HMI + ["camara", "det2d", "det3d", "nube"],
    "todo": [m for m in PRESUPUESTO if m != "nucleo"],   # se ofrece para que el relay lo RECHACE (65,9 KB/s, 229 dgr/s)
}
# Módulos que el nodo sabe hacer hoy (V6). El resto llega con V8–V11 (doc 36 §10).
IMPLEMENTADOS = {"scan", "pose", "joints", "mapa", "path", "rosout", "diag", "ritmo"}
FASE = {"marcadores": "V8", "pose_cov": "V9", "poses": "V9", "tf": "V9", "camara": "V10", "det2d": "V10",
        "det3d": "V10", "nube": "V10", "costmap": "V11"}


def expandir_modulos(lista):
    """Nombres de módulo o de perfil (hmi, viz, percepcion, todo) → lista ordenada sin repetidos.
    ValueError con el nombre desconocido."""
    out = []
    for x in lista:
        x = x.strip()
        if not x:
            continue
        for m in PERFILES.get(x, [x]):
            if m not in PRESUPUESTO or m == "nucleo":
                raise ValueError(f"módulo desconocido «{m}» (válidos: {', '.join(k for k in PRESUPUESTO if k != 'nucleo')};"
                                 f" perfiles: {', '.join(PERFILES)})")
            if m not in out:
                out.append(m)
    return out


def comprobar_presupuesto(modulos, kb_max=KB_MAX, dgr_max=DGR_MAX):
    """Lanza ValueError (el relay no arranca) si la suma nominal se pasa; dice qué módulo pesa más.
    Devuelve (KB/s, datagramas/s) nominales."""
    modulos = ["nucleo", *[m for m in modulos if m != "nucleo"]]   # relay_bw siempre
    kb = sum(PRESUPUESTO[m][0] * PRESUPUESTO[m][1] for m in modulos) / 1000.0
    dgr = sum(PRESUPUESTO[m][0] * PRESUPUESTO[m][2] for m in modulos)
    if kb > kb_max or dgr > dgr_max:
        # El que más pesa en la dimensión que se pasa (datagramas si se pasan; si no, bytes). A igualdad, el pedido
        # más tarde (los extras van detrás del perfil hmi): con «todo» sale «ritmo», no «pose» (núcleo del HMI).
        col = 2 if dgr > dgr_max else 1
        peor = max(reversed(modulos[1:]), key=lambda m: PRESUPUESTO[m][0] * PRESUPUESTO[m][col])
        raise ValueError(f"presupuesto {kb:.1f} KB/s, {dgr:.0f} dgr/s > {kb_max:.0f}/{dgr_max:.0f}: sobra «{peor}»")
    return kb, dgr


def resolver_modulos(lista):
    """Lo que hace el relay al arrancar: expande perfiles, comprueba el tope de red y que cada módulo exista ya.
    Devuelve (módulos, KB/s, dgr/s). ValueError = el relay NO arranca (y el mensaje dice por qué)."""
    mods = expandir_modulos(lista)
    if not mods:
        raise ValueError("sin módulos")
    kb, dgr = comprobar_presupuesto(mods)
    faltan = [m for m in mods if m not in IMPLEMENTADOS]
    if faltan:
        raise ValueError("módulos aún sin implementar: " + ", ".join(f"{m} ({FASE.get(m, '?')})" for m in faltan))
    return mods, kb, dgr


# ----------------------------------------------------------------------------- época del mapa (D5.5)

def epoca_mapa(geo_anterior, geo, version):
    """geo = (resolución, ancho, alto, ox, oy). La época (`version` de mapa_meta y de cada tesela) SOLO sube cuando
    cambia la geometría; un OccupancyGrid con la misma geometría reenvía las teselas cambiadas con la misma época.
    Devuelve (versión, cambió)."""
    if geo_anterior != geo:
        return (version + 1) & 0xFFFF, True
    return version, False


# ----------------------------------------------------------------------------- V9: pose_cov, poses y tf (doc 36 §5.3)
# Copia en GDScript: `godot/plantillas/ros/vc1.gd` (empaquetar_pose_cov, diezmar, empaquetar_poses, empaquetar_tf,
# leer_*); prueba de bytes en los dos lados con `huella_f32_bits` (bits float32 = lo que viaja en Float32MultiArray):
# `test_vita_relay.py` (HUELLA_POSE_COV / _POSES / _TF) y `godot/plantillas/pruebas/visor_tf.gd`.

MAX_POSES = 36            # 4 + 3·36 = 112 floats → 464 B
MAX_TF = 8                # 4 + 8·8 = 68 floats → 288 B (lista blanca de ≤ 8 marcos dinámicos, D3)
MAX_TF_ESTATICOS = 16     # 4 + 8·16 = 132 floats → 544 B, fiable + TRANSIENT_LOCAL (≤ 1 100 B de la tabla §5.3)


def huella_f32_bits(valores):
    """Huella de los bits float32 de cada valor (MD5 de los enteros sin signo unidos por comas). V9; distinta de
    `huella_f32` (V8, MD5 del hex de los bytes): se renombró al fusionar V8 y V9 porque la de V8 la tapaba."""
    import struct
    return huella(struct.unpack("<I", struct.pack("<f", float(v)))[0] for v in valores)


def empaquetar_pose_cov(x, y, yaw, cov):
    """PoseWithCovariance → <p>/pose_cov = [x, y, yaw, σxx, σxy, σyy, σyaw]: las VARIANZAS cov[0], cov[1], cov[7] y
    cov[35] de la matriz 6×6 por filas (lo que espera `displays/2d/covarianza.gd`). 7 floats = 44 B."""
    return [x, y, yaw, cov[0], cov[1], cov[7], cov[35]]


def diezmar(lista, max_n):
    """Diezmado por paso fijo (como el scan): lista[::ceil(n / max_n)][:max_n]."""
    paso = max(1, math.ceil(len(lista) / max_n))
    return list(lista[::paso][:max_n])


def empaquetar_poses(xyyaw, seq, max_n=MAX_POSES):
    """[(x, y, yaw), …] (PoseArray o ParticleCloud) → UN trozo de <p>/poses con la cabecera común."""
    return trocear([list(p) for p in diezmar(xyyaw, max_n)], 3, seq=seq, max_valores=4 + 3 * max_n, max_trozos=1)[0]


def empaquetar_tf(items, seq, max_n=MAX_TF):
    """[(idx, x, y, z, qx, qy, qz, qw), …] → UN trozo de <p>/tf (o tf_estatico con max_n=MAX_TF_ESTATICOS)."""
    return trocear([list(e) for e in items[:max_n]], 8, seq=seq, max_valores=4 + 8 * max_n, max_trozos=1)[0]


def leer_poses(d):
    """Inverso de empaquetar_poses (lo que hace la Vita): [(x, y, yaw)] o [] si la cabecera no vale."""
    c = cabecera(d)
    if c is None:
        return []
    return [tuple(d[4 + 3 * i:7 + 3 * i]) for i in range(min(c["n"], (len(d) - 4) // 3))]


class TablaTf:
    """Módulo tf del relay (D3; doc 36 §5.3), puro: lista blanca de ≤ MAX_TF hijos dinámicos (de /tf) y ≤
    MAX_TF_ESTATICOS estáticos (de /tf_static). Cada par «padre>hijo» recibe un índice fijo por orden de llegada
    (el de <p>/tf_marcos); un hijo que cambia de padre ocupa un índice nuevo y el viejo deja de mandarse."""

    def __init__(self, lista, max_dinamicos=MAX_TF, max_estaticos=MAX_TF_ESTATICOS):
        self.lista = [f.lstrip("/") for f in lista if f.strip()]
        self.max_dinamicos = max_dinamicos
        self.max_estaticos = max_estaticos
        self.pares = []            # «padre>hijo» en orden de índice
        self.dinamicos = {}        # hijo -> (idx, valores) último valor
        self.estaticos = {}        # hijo -> (idx, valores)
        self.cambio_marcos = False
        self.cambio_estaticos = False

    def _indice(self, padre, hijo):
        par = f"{padre}>{hijo}"
        if par not in self.pares:
            self.pares.append(par)
            self.cambio_marcos = True
        return self.pares.index(par)

    def dinamico(self, padre, hijo, t, q):
        """Un TransformStamped de /tf. True si entra (hijo en la lista blanca y con hueco)."""
        padre, hijo = padre.lstrip("/"), hijo.lstrip("/")
        if hijo not in self.lista or (hijo not in self.dinamicos and len(self.dinamicos) >= self.max_dinamicos):
            return False
        self.dinamicos[hijo] = (self._indice(padre, hijo), [*t, *q])
        return True

    def estatico(self, padre, hijo, t, q):
        """Un TransformStamped de /tf_static. True si entra (con hueco)."""
        padre, hijo = padre.lstrip("/"), hijo.lstrip("/")
        if hijo not in self.estaticos and len(self.estaticos) >= self.max_estaticos:
            return False
        v = (self._indice(padre, hijo), [*t, *q])
        if self.estaticos.get(hijo) != v:
            self.estaticos[hijo] = v
            self.cambio_estaticos = True
        return True

    def texto_marcos(self):
        return ",".join(self.pares)

    def trozo_tf(self, seq):
        return empaquetar_tf([[i, *v] for (i, v) in self.dinamicos.values()], seq, self.max_dinamicos)

    def trozo_estatico(self, seq=0):
        return empaquetar_tf([[i, *v] for (i, v) in self.estaticos.values()], seq, self.max_estaticos)


# Los módulos de V9 ya existen en el nodo (vita_relay.py). Bloque aditivo: no se toca la línea de IMPLEMENTADOS.
IMPLEMENTADOS.update({"pose_cov", "poses", "tf"})


# ----------------------------------------------------------------------------- tamaños CDR exactos (rosbags)

def _cdr_str(off, s):
    """Avanza `off` (relativo al inicio tras la encapsulación) por un string CDR: alinear 4 + longitud + bytes + NUL."""
    off = (off + 3) & ~3
    return off + 4 + len(s.encode("utf-8")) + 1


def cdr_log(nombre, texto, archivo="", funcion=""):
    """Bytes con rosbags de rcl_interfaces/msg/Log: stamp 8, level u8, name, msg, file, function, line u32."""
    off = 8 + 1
    for s in (nombre, texto, archivo, funcion):
        off = _cdr_str(off, s)
    off = ((off + 3) & ~3) + 4
    return 4 + off


def cdr_diag(frame_id, nombre, mensaje, hardware_id, pares):
    """Bytes con rosbags de diagnostic_msgs/msg/DiagnosticArray con UN estado: header (stamp 8 + frame_id),
    secuencia de estados (1), level u8, name, message, hardware_id, values[] (key, value)."""
    off = _cdr_str(8, frame_id)
    off = ((off + 3) & ~3) + 4                       # longitud de status[]
    off += 1                                         # level (byte)
    for s in (nombre, mensaje, hardware_id):
        off = _cdr_str(off, s)
    off = ((off + 3) & ~3) + 4                       # longitud de values[]
    for k, v in pares:
        off = _cdr_str(off, k)
        off = _cdr_str(off, v)
    return 4 + off


def _recortar_hasta(texto, cabe):
    """Recorta `texto` (por caracteres) hasta que `cabe(texto)` sea cierto. Siempre termina (el vacío cabe)."""
    while texto and not cabe(texto):
        texto = texto[:max(0, min(len(texto) - 1, len(texto) * 9 // 10))]
    return texto


# ----------------------------------------------------------------------------- rosout (doc 36 §5.3; 36a §4.8.2)

NIVEL_WARN = 30           # rcl_interfaces/msg/Log: 10 DEBUG, 20 INFO, 30 WARN, 40 ERROR, 50 FATAL
MAX_CAR_LOG = 200
MAX_CAR_NOMBRE_LOG = 60   # [decisión V6] el formato no lo fija; un nombre de nodo largo no debe comerse el texto


def compactar_log(nivel, nombre, texto, minimo=NIVEL_WARN):
    """/rosout → <p>/rosout: None si el nivel es < minimo; si no, (nombre, texto) recortados con `file` y
    `function` vacíos y `line` = 0, de forma que el Log entero ocupe ≤ MAX_BE con rosbags (UTF-8 incluido)."""
    if nivel < minimo:
        return None
    nombre = nombre[:MAX_CAR_NOMBRE_LOG]
    texto = texto[:MAX_CAR_LOG]
    nombre = _recortar_hasta(nombre, lambda n: cdr_log(n, "") <= MAX_BE)
    texto = _recortar_hasta(texto, lambda t: cdr_log(nombre, t) <= MAX_BE)
    return nombre, texto


# ----------------------------------------------------------------------------- diagnostics (36a §4.8.1)

MAX_CAR_DIAG = 40
MAX_PARES_DIAG = 3
REPASO_DIAG_S = 1.0       # cada estado se repite como mucho a 1 Hz (best effort no tiene historial)


def compactar_estado(nivel, nombre, mensaje, pares):
    """DiagnosticStatus → (nivel, nombre, mensaje, pares) de un DiagnosticArray de UN estado: textos ≤ 40
    caracteres, ≤ 3 pares, `hardware_id` vacío [decisión V6: el widget no lo enseña] y ≤ MAX_BE con rosbags."""
    nombre = nombre[:MAX_CAR_DIAG]
    mensaje = mensaje[:MAX_CAR_DIAG]
    pares = [(k[:MAX_CAR_DIAG], v[:MAX_CAR_DIAG]) for k, v in list(pares)[:MAX_PARES_DIAG]]
    while pares and cdr_diag("", nombre, mensaje, "", pares) > MAX_BE:   # UTF-8 multibyte: fuera pares
        pares.pop()
    mensaje = _recortar_hasta(mensaje, lambda m: cdr_diag("", nombre, m, "", pares) <= MAX_BE)
    nombre = _recortar_hasta(nombre, lambda n: cdr_diag("", n, mensaje, "", pares) <= MAX_BE)
    return int(nivel), nombre, mensaje, pares


class PlanDiag:
    """Planificador puro de <p>/diagnostics: un estado por tic (≤ 10 Hz); primero los que CAMBIAN de nivel o de
    mensaje y, si no hay, un repaso circular en el que cada estado se repite como mucho cada REPASO_DIAG_S."""

    def __init__(self, repaso_s=REPASO_DIAG_S):
        self.repaso_s = repaso_s
        self.estados = {}          # nombre -> estado compacto
        self.enviado = {}          # nombre -> instante del último envío
        self.cambiados = []        # nombres pendientes por cambio, en orden de llegada
        self._giro = 0

    def actualizar(self, estado):
        nombre = estado[1]
        viejo = self.estados.get(nombre)
        self.estados[nombre] = estado
        if (viejo is None or viejo[0] != estado[0] or viejo[2] != estado[2]) and nombre not in self.cambiados:
            self.cambiados.append(nombre)

    def siguiente(self, ahora):
        if self.cambiados:
            nombre = self.cambiados.pop(0)
            self.enviado[nombre] = ahora
            return self.estados[nombre]
        nombres = list(self.estados)
        for i in range(len(nombres)):
            nombre = nombres[(self._giro + i) % len(nombres)]
            if ahora - self.enviado.get(nombre, -1e9) >= self.repaso_s:
                self._giro = (self._giro + i + 1) % len(nombres)
                self.enviado[nombre] = ahora
                return self.estados[nombre]
        return None


# ----------------------------------------------------------------------------- ritmo (D5.9)

RITMO_HZ_MAX = 30.0       # datagramas/s declarados del módulo (PRESUPUESTO["ritmo"])
RITMO_BPS_MAX = 10000     # bytes/s declarados del módulo
_NOMBRE_RITMO = re.compile(r"^[a-z0-9_]+$")


def parsear_ritmo(entradas):
    """Entradas «nombre=/topic@hz» (sin «:» para que pasen por `-p ritmo:='[…]'` de ROS) → [(nombre, topic, hz)].
    El tipo se descubre en el grafo. ValueError si algo no vale o si la suma de Hz pasa de RITMO_HZ_MAX."""
    out = []
    for e in entradas:
        e = e.strip()
        if not e:
            continue
        m = re.match(r"^([^=]+)=(/[^@]+)@([0-9.]+)$", e)
        if not m:
            raise ValueError(f"ritmo: «{e}» no es nombre=/topic@hz")
        nombre, topic, hz = m.group(1), m.group(2), float(m.group(3))
        if not _NOMBRE_RITMO.match(nombre):
            raise ValueError(f"ritmo: nombre «{nombre}» (solo a-z, 0-9 y _)")
        if not 0 < hz <= RITMO_HZ_MAX:
            raise ValueError(f"ritmo: {nombre} a {hz} Hz (0 < hz ≤ {RITMO_HZ_MAX:.0f})")
        if any(nombre == o[0] for o in out):
            raise ValueError(f"ritmo: nombre repetido «{nombre}»")
        out.append((nombre, topic, hz))
    total = sum(o[2] for o in out)
    if total > RITMO_HZ_MAX:
        raise ValueError(f"ritmo: {total:.0f} Hz en total > {RITMO_HZ_MAX:.0f} declarados")
    return out


class CuboBytes:
    """Tope de bytes por ventana de 1 s (módulo ritmo): `permitir(n, ahora)` dice si cabe y lo descuenta."""

    def __init__(self, bps=RITMO_BPS_MAX):
        self.bps = bps
        self._t0 = None
        self._usado = 0

    def permitir(self, nbytes, ahora):
        if self._t0 is None or ahora - self._t0 >= 1.0:
            self._t0 = ahora
            self._usado = 0
        if self._usado + nbytes > self.bps:
            return False
        self._usado += nbytes
        return True


# ============================================================================= marcadores (V8)
# Doc 36 §5.3 y 36a §4.7.4; sentencia W13 D14. El relay aplica él la semántica de RViz (ADD/MODIFY, DELETE,
# DELETEALL por ns, lifetime con el reloj de recepción, recrear si cambia el tipo, frame_locked, rechazo de NaN) y
# publica el ESTADO COMPLETO (un DELETE perdido en best effort no deja fantasmas en la Vita):
#   <p>/marcadores       Float32MultiArray BE 5 Hz  cab. común + [clave, tipo, x, y, z, yaw, sx, sy, sz, color]·n,
#                        n ≤ 11 por trozo, ≤ 33 marcadores (3 trozos de ≤ 472 B). Pose en el marco fijo (ejes ROS).
#   <p>/marcador_puntos  Float32MultiArray BE ≤ 4/s cab. común + [clave, tipo, color, ancho] + xyz·n, n ≤ 36 por
#                        trozo (≤ 480 B); un marcador de líneas/puntos/listas por ciclo de trozos.
#   <p>/marcador_texto   String FIABLE ≤ 2/s  «clave|x|y|z|texto» (texto ≤ 80 car.).
# clave = (id ⊕ fnv1a32(ns)) & 0xFFFFFF (exacta en float32); color = índice de PaletaViz + 256 · alfa (0–15).
# Copia en GDScript: `godot/plantillas/ros/vc1.gd` (bloque «marcadores»); prueba de bytes cruzada en
# `test_vita_relay.py` (test_marcadores) y `godot/plantillas/pruebas/visor_marcadores.gd`.

POR_MARCADOR = 10
MAX_MARCADORES = 33               # 3 trozos × 11
MAX_TROZOS_MARCADORES = 3
EXTRA_PUNTOS = 4                  # [clave, tipo, color, ancho]
MAX_TROZOS_PUNTOS = 3             # [decisión V8] ≤ 3 × 36 = 108 puntos por marcador; el resto se corta
MAX_CAR_TEXTO_MARCADOR = 80
# Marker.type (visualization_msgs Jazzy)
M_ARROW, M_CUBE, M_SPHERE, M_CYLINDER, M_LINE_STRIP, M_LINE_LIST, M_CUBE_LIST, M_SPHERE_LIST, M_POINTS, \
    M_TEXT, M_MESH, M_TRIANGLE_LIST, M_ARROW_STRIP = range(13)
SOLIDOS_COMPACTOS = (M_ARROW, M_CUBE, M_SPHERE, M_CYLINDER, M_MESH)   # la Vita los dibuja en 3D (MESH = cubo)
TIPOS_PUNTOS = (M_LINE_STRIP, M_LINE_LIST, M_CUBE_LIST, M_SPHERE_LIST, M_POINTS, M_ARROW_STRIP)   # 2D en la Vita


def hash_ns(ns):
    """FNV-1a de 32 bit del ns en UTF-8 (determinista: el `hash()` de Python cambia en cada proceso)."""
    h = 0x811C9DC5
    for b in ns.encode("utf-8"):
        h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
    return h


def clave_marcador(ns, ident):
    """Clave compacta de (ns, id): 24 bit, exacta en float32. Dos pares pueden chocar (raro; se pisan)."""
    return (int(ident) ^ hash_ns(ns)) & 0xFFFFFF


def color_marcador(indice, alfa):
    """Índice de PaletaViz (0–255) + 256 · alfa cuantizado a 0–15 (≤ 4 095: exacto en float32)."""
    return max(0, min(255, int(indice))) + 256 * max(0, min(15, int(alfa * 15 + 0.5)))


# --- PaletaViz (copia de `_calcular` de godot/plantillas/visor/paleta_viz.gd): índice del color más cercano en RGB

def _c8(r, g, b):
    return (r / 255.0, g / 255.0, b / 255.0)


_NOMBRADOS = [(1.0, 1.0, 1.0), (0.0, 0.0, 0.0), (0.9, 0.1, 0.1), (0.1, 0.8, 0.2), (0.15, 0.35, 1.0),
              (1.0, 1.0, 0.0), (0.0, 1.0, 1.0), (1.0, 0.0, 1.0), (1.0, 0.647059, 0.0), (0.745098, 0.745098, 0.745098),
              _c8(85, 178, 76), _c8(222, 213, 17), _c8(178, 23, 46), _c8(40, 23, 176),
              (1.0, 0.1, 0.0), (0.1, 1.0, 0.0)]


def color_paleta(i):
    if i < 16:
        return _NOMBRADOS[i]
    if i < 232:
        k = i - 16
        return ((k // 36) / 5.0, ((k // 6) % 6) / 5.0, (k % 6) / 5.0)
    v = (i - 232) / 22.0
    return (v, v, v)


_PALETA = [color_paleta(i) for i in range(255)]   # sin el 255 (transparente), como PaletaViz.indice


def indice_paleta(r, g, b):
    """= PaletaViz.indice(Color(r, g, b)): el primero de distancia mínima (el alfa se ignora)."""
    mejor, dmin = 0, float("inf")
    for i, (pr, pg, pb) in enumerate(_PALETA):
        d = (pr - r) ** 2 + (pg - g) ** 2 + (pb - b) ** 2
        if d < dmin:
            mejor, dmin = i, d
    return mejor


# --- formatos

def empaquetar_marcadores(elementos, seq):
    """Estado completo: lista de [clave, tipo, x, y, z, yaw, sx, sy, sz, color] → ≤ 3 trozos (≤ 33 marcadores).
    Sin marcadores sale UN trozo con n = 0 (la Vita borra todo)."""
    return trocear(elementos[:MAX_MARCADORES], POR_MARCADOR, (), seq, MAX_F32, MAX_TROZOS_MARCADORES)


def empaquetar_puntos(clave, tipo, color, ancho, puntos, seq):
    """Un marcador de líneas/puntos: puntos [x, y, z] (marco fijo, ejes ROS) → ≤ 3 trozos de ≤ 36 puntos."""
    return trocear([list(p) for p in puntos], 3, (clave, tipo, color, ancho), seq, MAX_F32, MAX_TROZOS_PUNTOS)


def texto_marcador(clave, x, y, z, texto):
    """«clave|x|y|z|texto», posiciones con 3 decimales (mm) y texto ≤ 80 caracteres (puede llevar «|»)."""
    return f"{int(clave)}|{x:.3f}|{y:.3f}|{z:.3f}|{texto[:MAX_CAR_TEXTO_MARCADOR]}"


def leer_texto_marcador(s):
    p = s.split("|", 4)
    if len(p) != 5:
        return None
    try:
        return int(p[0]), float(p[1]), float(p[2]), float(p[3]), p[4]
    except ValueError:
        return None


def huella_f32(valores):
    """Huella de bytes Python = GDScript: MD5 del hex de los float32 little-endian (PackedFloat32Array)."""
    import hashlib
    import struct
    return hashlib.md5(struct.pack(f"<{len(valores)}f", *valores).hex().encode()).hexdigest()


# --- transformaciones (ejes ROS): t = ((x, y, z), (qx, qy, qz, qw))

def _qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)


def _qrot(q, v):
    x, y, z, w = q
    r = _qmul(_qmul(q, (v[0], v[1], v[2], 0.0)), (-x, -y, -z, w))
    return (r[0], r[1], r[2])


def _qnorm(q):
    n = math.sqrt(sum(c * c for c in q))
    return tuple(c / n for c in q) if n > 1e-6 else (0.0, 0.0, 0.0, 1.0)   # cuaternión nulo = identidad (T14)


def componer(t1, t2):
    """t1 ∘ t2 (t2 expresado en el marco de t1)."""
    p = _qrot(t1[1], t2[0])
    return ((t1[0][0] + p[0], t1[0][1] + p[1], t1[0][2] + p[2]), _qnorm(_qmul(t1[1], t2[1])))


def aplicar_t(t, p):
    q = _qrot(t[1], p)
    return (t[0][0] + q[0], t[0][1] + q[1], t[0][2] + q[2])


IDENTIDAD = ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0))


def _finitos(*vals):
    return all(isinstance(v, (int, float)) and math.isfinite(v) for v in vals)


class EstadoMarcadores:
    """Semántica de RViz2 Jazzy (`marker_common.cpp:195-310`, `marker_base.cpp:84-115`) sin ROS. `m` es un
    visualization_msgs/Marker (o algo con los mismos atributos). `resolver(frame)` → t del marco en el fijo o None.
    `ciclo()` da el estado completo (≤ max_marcadores, por orden de llegada) para los tres formatos."""

    def __init__(self, max_marcadores=MAX_MARCADORES):
        self.max = max_marcadores
        self.tabla = {}           # (ns, id) -> entrada
        self.rechazados = 0       # NaN/Inf (marker_common.cpp:195-213)
        self.sin_tf = 0           # marcadores omitidos en el último ciclo por no tener TF
        self.cortados = 0         # marcadores que no cupieron en el último ciclo (> max)
        self.ignorados = 0        # TRIANGLE_LIST: no viaja a la Vita [decisión V8]

    def aplicar(self, m, ahora):
        accion = int(m.action)
        if accion == 3:                                                  # DELETEALL (con ns: solo ese ns)
            for k in [k for k in self.tabla if not m.ns or k[0] == m.ns]:
                del self.tabla[k]
            return
        k = (m.ns, int(m.id))
        if accion == 2:                                                  # DELETE
            self.tabla.pop(k, None)
            return
        if accion not in (0, 1):                                         # 0 ADD = 1 MODIFY
            return
        p, o, s = m.pose.position, m.pose.orientation, m.scale
        pts = [(q.x, q.y, q.z) for q in m.points]
        if not (_finitos(p.x, p.y, p.z, o.x, o.y, o.z, o.w, s.x, s.y, s.z)
                and all(_finitos(*q) for q in pts)):
            self.rechazados += 1
            return
        viejo = self.tabla.get(k)
        if viejo is not None and viejo["tipo"] != int(m.type):          # cambia el tipo: se recrea (:282-287)
            del self.tabla[k]
        vida = m.lifetime.sec + m.lifetime.nanosec * 1e-9
        c = m.color
        self.tabla[k] = {
            "tipo": int(m.type), "frame": m.header.frame_id.lstrip("/"), "locked": bool(m.frame_locked),
            "pose": ((p.x, p.y, p.z), _qnorm((o.x, o.y, o.z, o.w))), "escala": (s.x, s.y, s.z),
            "color": (c.r, c.g, c.b, c.a), "puntos": pts, "texto": m.text,
            "expira": ahora + vida if vida > 1e-4 else None, "fijo": None}

    def caducar(self, ahora):
        for k in [k for k, e in self.tabla.items() if e["expira"] is not None and ahora > e["expira"]]:
            del self.tabla[k]

    def ciclo(self, ahora, resolver):
        """→ (elementos de <p>/marcadores, {clave: (tipo, color, ancho, puntos)}, {clave: (x, y, z, texto)})."""
        self.caducar(ahora)
        marc, puntos, textos = [], {}, {}
        self.sin_tf = self.cortados = self.ignorados = 0
        for (ns, ident), e in self.tabla.items():
            if e["tipo"] == M_TRIANGLE_LIST or e["tipo"] > M_ARROW_STRIP:
                self.ignorados += 1
                continue
            if e["fijo"] is None or e["locked"]:                         # sin frame_locked: se resuelve UNA vez
                t = resolver(e["frame"])
                if t is None:
                    self.sin_tf += 1
                    continue
                e["fijo"] = t
            if len(marc) >= self.max:
                self.cortados += 1
                continue
            t = componer(e["fijo"], e["pose"])
            clave = clave_marcador(ns, ident)
            r, g, b, a = e["color"]
            col = color_marcador(indice_paleta(r, g, b), a)
            (x, y, z), q = t
            yaw = yaw_de_quat(*q)
            sx, sy, sz = e["escala"]
            tipo = e["tipo"]
            if tipo == M_ARROW and len(e["puntos"]) >= 2:               # flecha por 2 puntos → flecha por pose (yaw)
                a0, a1 = aplicar_t(t, e["puntos"][0]), aplicar_t(t, e["puntos"][1])
                d = (a1[0] - a0[0], a1[1] - a0[1], a1[2] - a0[2])
                x, y, z = a0
                yaw = math.atan2(d[1], d[0])
                sx, sy, sz = math.sqrt(d[0] ** 2 + d[1] ** 2 + d[2] ** 2), sy / 2.0, sy / 2.0
            elif tipo in TIPOS_PUNTOS:
                puntos[clave] = (tipo, col, float(sx), [aplicar_t(t, p) for p in e["puntos"]])
            elif tipo == M_TEXT:
                textos[clave] = (x, y, z, e["texto"])
            marc.append([clave, tipo, x, y, z, yaw, sx, sy, sz, col])
        return marc, puntos, textos


class PlanRonda:
    """Reparto de un canal lento (puntos a 4/s, textos a 2/s): primero lo que CAMBIA, después un repaso circular.
    `actualizar({clave: valor})` (lo ausente se olvida); `siguiente()` → (clave, valor) o None."""

    def __init__(self):
        self.datos = {}
        self.cambiados = []
        self._giro = 0

    def actualizar(self, nuevos):
        for k in [k for k in self.datos if k not in nuevos]:
            del self.datos[k]
        self.cambiados = [k for k in self.cambiados if k in nuevos]
        for k, v in nuevos.items():
            if self.datos.get(k) != v and k not in self.cambiados:
                self.cambiados.append(k)
            self.datos[k] = v

    def siguiente(self):
        if self.cambiados:
            k = self.cambiados.pop(0)
            return k, self.datos[k]
        if not self.datos:
            return None
        claves = list(self.datos)
        k = claves[self._giro % len(claves)]
        self._giro = (self._giro + 1) % len(claves)
        return k, self.datos[k]


IMPLEMENTADOS |= {"marcadores"}    # V8


# ============================================================================= V11: costmap por teselas de 4 bit
# Doc 36 §5.3 y 36a §4.6.2 (sentencia W13 D5): `<p>/costmap_meta` (Float32MultiArray F+TL, como mapa_meta pero con
# teselas de 32×16) + `<p>/costmap_tesela` (UInt8MultiArray BE ≤ 10/s): [ver_lo, ver_hi, tx, ty] + 32×16 celdas a
# 4 bit (celda k = j·32 + i en el byte k >> 1, nibble BAJO para k par) = 260 B (276 con rosbags). Niveles:
# 0 desconocido, 1 libre (transparente), 2–13 degradado, 14 inscrito (99), 15 letal (100), como la LUT de 16 colores
# `PaletaViz.lut16_costmap()` (índices [255, 0, 8, 16, …, 88, 98, 99, 100] de la paleta costmap de RViz). El relay
# baja la resolución por MÁXIMO a ≥ 10 cm (un obstáculo no desaparece al reducir). Época = `epoca_mapa` (D5.5).
# Copia en GDScript: `godot/plantillas/ros/vc1.gd` (bloque «costmap»); prueba de bytes en los dos lados con la huella
# de enteros `huella` (HUELLA_COSTMAP en `test_vita_relay.py` y `godot/plantillas/pruebas/visor_costmap.gd`).

TESELA_X_COSTMAP = 32
TESELA_Y_COSTMAP = 16
RES_MIN_COSTMAP = 0.10            # m/celda: por debajo, el relay reduce por máximo (36a §4.6.2)
LUT16_COSTMAP = (255, 0, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 98, 99, 100)   # nivel → valor de la paleta


def celda_costmap_4bit(v):
    """OccupancyGrid de costmap (-1, 0..100) → nivel de 4 bit (el más cercano de LUT16_COSTMAP; 1–98 → 2–13)."""
    v = int(v)
    if v < 0:
        return 0
    if v == 0:
        return 1
    if v >= 100:
        return 15                 # letal (y los ilegales > 100, que Nav2 no publica)
    if v == 99:
        return 14                 # inscrito
    if v >= 93:
        return 13                 # 98
    return 2 + max(0, min(10, (v + 4) // 8 - 1))


def factor_costmap(res, res_min=RES_MIN_COSTMAP):
    """Celdas originales por celda reducida (≥ 1): la resolución que viaja es ≥ res_min."""
    if res <= 0:
        return 1
    return max(1, math.ceil(res_min / res - 1e-6))


def reducir_costmap(data, ancho, alto, f):
    """Rejilla (fila 0 abajo, -1 desconocido) → rejilla f veces más gruesa por MÁXIMO (lo conocido gana a -1).
    Devuelve (datos, ancho, alto). Con f = 1, una copia."""
    if f <= 1:
        return list(data[:ancho * alto]), ancho, alto
    w2, h2 = -(-ancho // f), -(-alto // f)
    out = [-1] * (w2 * h2)
    for y in range(alto):
        fila = y * ancho
        base = (y // f) * w2
        for x in range(ancho):
            v = data[fila + x]
            k = base + x // f
            if v > out[k]:
                out[k] = v
    return out, w2, h2


def empaquetar_tesela_costmap(data, ancho, alto, tx, ty, epoca):
    """Tesela de 32×16 celdas a 4 bit = 4 B de cabecera + 256 B. Celdas fuera del costmap = 0 (desconocido)."""
    cuerpo = bytearray(TESELA_X_COSTMAP * TESELA_Y_COSTMAP // 2)
    for j in range(TESELA_Y_COSTMAP):
        y = ty * TESELA_Y_COSTMAP + j
        for i in range(TESELA_X_COSTMAP):
            x = tx * TESELA_X_COSTMAP + i
            c = celda_costmap_4bit(data[y * ancho + x]) if (x < ancho and y < alto) else 0
            k = j * TESELA_X_COSTMAP + i
            cuerpo[k >> 1] |= c << ((k & 1) * 4)
    return bytes([epoca & 0xFF, (epoca >> 8) & 0xFF, tx, ty]) + bytes(cuerpo)


def desempaquetar_tesela_costmap(b):
    """Inverso: (época, tx, ty, lista de 512 niveles 0–15 por filas)."""
    ver, tx, ty = b[0] | (b[1] << 8), b[2], b[3]
    n = TESELA_X_COSTMAP * TESELA_Y_COSTMAP
    return ver, tx, ty, [(b[4 + (k >> 1)] >> ((k & 1) * 4)) & 15 for k in range(n)]


def teselas_costmap(ancho, alto):
    """(teselas_x, teselas_y) de un costmap (ya reducido)."""
    return -(-ancho // TESELA_X_COSTMAP), -(-alto // TESELA_Y_COSTMAP)


def meta_costmap(res, ancho, alto, ox, oy, epoca):
    """`<p>/costmap_meta` = [res, ancho, alto, ox, oy, teselas_x, teselas_y, época] (como mapa_meta)."""
    ntx, nty = teselas_costmap(ancho, alto)
    return [float(res), float(ancho), float(alto), float(ox), float(oy), float(ntx), float(nty), float(epoca)]


class EstadoCostmap:
    """El módulo `costmap` sin ROS (para probarlo): rejilla original, reducida, época y cola de teselas.
    - `grid(data, ancho, alto, res, ox, oy)`: OccupancyGrid completo → meta (lista) si la época es nueva, si no None.
      Con la misma geometría solo se encolan las teselas que cambian (D5.5).
    - `update(x, y, w, h, datos)`: map_msgs/OccupancyGridUpdate (coordenadas de la rejilla ORIGINAL) → parche; marca
      las teselas tocadas que cambian, sin tocar la época. Fuera de límites o sin rejilla: se ignora (como RViz).
    - `siguiente(pos)`: bytes de la próxima tesela (primero las cambiadas, las cercanas a `pos` (x, y) antes; si no
      hay, un repaso circular para quien se conecte tarde) o None sin costmap."""

    def __init__(self, res_min=RES_MIN_COSTMAP):
        self.res_min = res_min
        self.orig = None              # (data, ancho, alto)
        self.f = 1
        self.red = None               # (data reducida, ancho, alto)
        self.res = 0.0
        self.ox = self.oy = 0.0
        self.epoca = 0
        self.geo = None
        self.firma = {}               # (tx, ty) -> bytes del cuerpo enviado o encolado
        self.cola = []
        self.repaso = -1
        self.ignorados = 0

    def _firmar(self, todas):
        ntx, nty = teselas_costmap(self.red[1], self.red[2])
        cambiadas = []
        for (tx, ty) in todas:
            if tx >= ntx or ty >= nty:
                continue
            b = empaquetar_tesela_costmap(self.red[0], self.red[1], self.red[2], tx, ty, self.epoca)[4:]
            if self.firma.get((tx, ty)) != b:
                self.firma[(tx, ty)] = b
                cambiadas.append((tx, ty))
        self.cola = cambiadas + [t for t in self.cola if t not in cambiadas]
        return cambiadas

    def grid(self, data, ancho, alto, res, ox, oy):
        self.f = factor_costmap(res, self.res_min)
        self.orig = (list(data[:ancho * alto]), ancho, alto)
        self.red = reducir_costmap(self.orig[0], ancho, alto, self.f)
        self.res = res * self.f
        self.ox, self.oy = float(ox), float(oy)
        geo = (float(self.res), int(self.red[1]), int(self.red[2]), self.ox, self.oy)
        self.epoca, nueva = epoca_mapa(self.geo, geo, self.epoca)
        self.geo = geo
        if nueva:
            self.firma = {}
            self.cola = []
            self.repaso = -1
        ntx, nty = teselas_costmap(self.red[1], self.red[2])
        self._firmar([(tx, ty) for ty in range(nty) for tx in range(ntx)])
        return meta_costmap(self.res, self.red[1], self.red[2], self.ox, self.oy, self.epoca) if nueva else None

    def update(self, x, y, w, h, datos):
        if self.orig is None or w <= 0 or h <= 0 or x < 0 or y < 0:
            self.ignorados += 1
            return []
        data, ancho, alto = self.orig
        if x + w > ancho or y + h > alto or len(datos) < w * h:
            self.ignorados += 1
            return []
        for j in range(h):
            data[(y + j) * ancho + x:(y + j) * ancho + x + w] = list(datos[j * w:(j + 1) * w])
        f = self.f
        rd, w2, _ = self.red
        x0, x1, y0, y1 = x // f, (x + w - 1) // f, y // f, (y + h - 1) // f
        for cy in range(y0, y1 + 1):                    # recalcula por máximo solo las celdas reducidas tocadas
            for cx in range(x0, x1 + 1):
                m = -1
                for yy in range(cy * f, min(alto, cy * f + f)):
                    fila = yy * ancho
                    for xx in range(cx * f, min(ancho, cx * f + f)):
                        if data[fila + xx] > m:
                            m = data[fila + xx]
                rd[cy * w2 + cx] = m
        tocadas = [(tx, ty) for ty in range(y0 // TESELA_Y_COSTMAP, y1 // TESELA_Y_COSTMAP + 1)
                   for tx in range(x0 // TESELA_X_COSTMAP, x1 // TESELA_X_COSTMAP + 1)]
        return self._firmar(tocadas)

    def siguiente(self, pos=None):
        if self.red is None:
            return None
        ntx, nty = teselas_costmap(self.red[1], self.red[2])
        if self.cola:
            if pos is not None and len(self.cola) > 1:
                px = (pos[0] - self.ox) / (self.res * TESELA_X_COSTMAP)
                py = (pos[1] - self.oy) / (self.res * TESELA_Y_COSTMAP)
                self.cola.sort(key=lambda t: (t[0] + 0.5 - px) ** 2 + (t[1] + 0.5 - py) ** 2)
            tx, ty = self.cola.pop(0)
        else:
            self.repaso = (self.repaso + 1) % (ntx * nty)
            tx, ty = self.repaso % ntx, self.repaso // ntx
        return empaquetar_tesela_costmap(self.red[0], self.red[1], self.red[2], tx, ty, self.epoca)


IMPLEMENTADOS |= {"costmap"}      # V11
