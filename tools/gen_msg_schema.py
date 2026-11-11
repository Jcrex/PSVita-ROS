#!/usr/bin/env python3
"""Generador de esquemas de mensajes ROS2 para la Vita (módulo msg-schema).

Equivalente en el PC de lo que `ros_babel_fish` hace en `rclgd` con la
introspección de type support: aquí se lee la definición REAL de cada mensaje
(paquete `rosbags`, store ROS2_JAZZY) y se emite un blob binario compacto `.rsch`
que el runtime de la Vita (C/Rust, sin malloc) interpreta para codificar y
decodificar CDR de CUALQUIER tipo incluido en el blob.

Uso:
    python3 -m venv /tmp/rbvenv && /tmp/rbvenv/bin/pip install rosbags
    /tmp/rbvenv/bin/python tools/gen_msg_schema.py -o schema.rsch \
        geometry_msgs/msg/Twist sensor_msgs/msg/Imu
    /tmp/rbvenv/bin/python tools/gen_msg_schema.py --dump geometry_msgs/msg/Twist

Formato del blob (little-endian), ver modules/msg-schema/include/msg_schema.h.
Las acciones y servicios se pueden añadir listando sus tipos *_Goal/_Result/
_Request/_Response como mensajes normales (pendiente de automatizar).
"""
import argparse
import struct
import sys

from rosbags.interfaces import Nodetype
from rosbags.typesys import Stores, get_typestore

MAGIC = b"RSCH"
VERSION = 1

# Primitivas -> id numérico (debe coincidir con msg_prim del header)
PRIM_IDS = {
    "bool": 0,
    "uint8": 1, "octet": 1, "byte": 1, "char": 1,
    "int8": 2,
    "uint16": 3, "int16": 4,
    "uint32": 5, "int32": 6,
    "uint64": 7, "int64": 8,
    "float32": 9, "float64": 10,
}
PRIM_SIZE = {0: 1, 1: 1, 2: 1, 3: 2, 4: 2, 5: 4, 6: 4, 7: 8, 8: 8, 9: 4, 10: 8}
PRIM_STRUCT = {0: "<B", 1: "<B", 2: "<b", 3: "<H", 4: "<h", 5: "<I", 6: "<i",
               7: "<Q", 8: "<q", 9: "<f", 10: "<d"}

KIND_PRIM, KIND_STRING, KIND_STRUCT = 0, 1, 2
ARR_NONE, ARR_FIXED, ARR_SEQ = 0, 1, 2


def typestore():
    return get_typestore(Stores.ROS2_JAZZY)


def field_shape(ts, desc):
    """(kind, prim, array, array_len, struct_name) de un descriptor de rosbags."""
    array, alen = ARR_NONE, 0
    if desc[0] == Nodetype.ARRAY:
        array, alen = ARR_FIXED, desc[1][1]
        desc = desc[1][0]
    elif desc[0] == Nodetype.SEQUENCE:
        array, alen = ARR_SEQ, desc[1][1]  # 0 = sin cota
        desc = desc[1][0]
    if desc[0] == Nodetype.NAME:
        return KIND_STRUCT, 0, array, alen, desc[1]
    name = desc[1][0]
    if name == "string":
        return KIND_STRING, 0, array, alen, None
    if name == "wstring":
        raise ValueError("wstring no soportado")
    return KIND_PRIM, PRIM_IDS[name], array, alen, None


def collect(ts, names):
    """Cierre transitivo de tipos alcanzables, en orden determinista."""
    seen, order = set(), []

    def visit(n):
        if n in seen:
            return
        seen.add(n)
        for _fname, desc in ts.fielddefs[n][1]:
            kind, _p, _a, _l, sname = field_shape(ts, desc)
            if kind == KIND_STRUCT:
                visit(sname)
        order.append(n)

    for n in sorted(names):
        visit(n)
    return sorted(order)


def build_blob(ts, names):
    types = collect(ts, names)
    index = {n: i for i, n in enumerate(types)}
    pool = bytearray()
    offs = {}

    def intern(s):
        if s not in offs:
            offs[s] = len(pool)
            pool.extend(s.encode() + b"\0")
        return offs[s]

    type_rows, field_rows = [], []
    for n in types:
        first = len(field_rows)
        for fname, desc in ts.fielddefs[n][1]:
            kind, prim, array, alen, sname = field_shape(ts, desc)
            field_rows.append(struct.pack(
                "<IBBBBII", intern(fname), kind, prim, array, 0,
                index[sname] if sname else 0, alen))
        type_rows.append(struct.pack("<III", intern(n), first, len(field_rows) - first))

    header_len = 32
    types_off = header_len
    fields_off = types_off + 12 * len(type_rows)
    strings_off = fields_off + 16 * len(field_rows)
    total = strings_off + len(pool)
    header = struct.pack("<4sHHIIIIII", MAGIC, VERSION, 0, len(type_rows), len(field_rows),
                         types_off, fields_off, strings_off, total)
    return header + b"".join(type_rows) + b"".join(field_rows) + bytes(pool), types


# ---------------------------------------------------------------------------
# Volcado canónico (lo comparan los tests de C y Rust con el visitor del test)
# ---------------------------------------------------------------------------
def fnv64(data):
    h = 0xCBF29CE484222325
    for b in data:
        h ^= b
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def _fmt_prim(prim, v):
    if prim == 0:
        return "1" if v else "0"
    if prim == 9:
        # float32: el CDR redondea a simple precisión; el objeto Python guarda doble
        return "%.17g" % struct.unpack("<f", struct.pack("<f", float(v)))[0]
    if prim == 10:
        return "%.17g" % float(v)
    return str(int(v))


def _prim_bytes(prim, seq):
    return b"".join(struct.pack(PRIM_STRUCT[prim], (int(x) if prim not in (9, 10) else float(x)))
                    for x in seq)


def dump_message(ts, typename, msg, path="", out=None):
    """Lista de líneas del volcado canónico de `msg`."""
    if out is None:
        out = []
    for fname, desc in ts.fielddefs[typename][1]:
        kind, prim, array, alen, sname = field_shape(ts, desc)
        val = getattr(msg, fname)
        p = f"{path}.{fname}" if path else fname
        if array == ARR_NONE:
            if kind == KIND_PRIM:
                out.append(f"{p}={_fmt_prim(prim, val)}")
            elif kind == KIND_STRING:
                out.append(f'{p}="{val}"')
            else:
                dump_message(ts, sname, val, p, out)
        else:
            n = len(val)
            if kind == KIND_PRIM:
                out.append(f"{p}=[{n}]#{fnv64(_prim_bytes(prim, val)):016x}")
            else:
                out.append(f"{p}=[{n}]")
                for i, el in enumerate(val):
                    if kind == KIND_STRING:
                        out.append(f'{p}[{i}]="{el}"')
                    else:
                        dump_message(ts, sname, el, f"{p}[{i}]", out)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("types", nargs="+", help="tipos, p. ej. geometry_msgs/msg/Twist")
    ap.add_argument("-o", "--output", help="fichero .rsch de salida")
    ap.add_argument("--dump", action="store_true", help="imprimir los tipos y campos incluidos")
    args = ap.parse_args()
    ts = typestore()
    blob, order = build_blob(ts, args.types)
    if args.dump:
        for n in order:
            print(n)
            for fname, desc in ts.fielddefs[n][1]:
                print("   ", fname, field_shape(ts, desc))
    if args.output:
        with open(args.output, "wb") as f:
            f.write(blob)
        print(f"{args.output}: {len(blob)} bytes, {len(order)} tipos", file=sys.stderr)


if __name__ == "__main__":
    main()
