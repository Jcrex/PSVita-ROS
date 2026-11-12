import argparse
import math
import pathlib
import shutil
import sys

import bpy


def material(nombre, rgba):
    m = bpy.data.materials.new(nombre)
    m.diffuse_color = (*rgba[:3], 1.0)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgba[:3], 1.0)
    bsdf.inputs["Roughness"].default_value = 1.0
    return m


def asignar(obj, mat):
    obj.data.materials.append(mat)
    return obj


def cubo(nombre, loc, escala, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.object
    o.name = nombre
    o.scale = escala
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return asignar(o, mat)


def ico(nombre, loc, escala, mat, subdivisiones=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisiones, radius=1.0, location=loc)
    o = bpy.context.object
    o.name = nombre
    o.scale = escala
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return asignar(o, mat)


def cilindro(nombre, loc, radio, profundidad, mat, vertices=8, rot=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radio, depth=profundidad, location=loc)
    o = bpy.context.object
    o.name = nombre
    if rot:
        o.rotation_euler = rot
    return asignar(o, mat)


def unir_y_exportar(nombre, destino):
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = nombre
    bpy.ops.object.shade_flat()
    bpy.ops.wm.obj_export(
        filepath=str(destino / (nombre + ".obj")), export_selected_objects=True,
        forward_axis="NEGATIVE_Z", up_axis="Y", export_materials=True,
        export_uv=False, export_normals=True, export_triangulated_mesh=True,
    )
    print(nombre, sum(len(p.vertices) - 2 for p in obj.data.polygons), "triángulos")


def limpiar():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


def animal(nombre, destino, color, tamaño=1.0):
    limpiar()
    piel = material("piel", color)
    oscuro = material("oscuro", (0.08, 0.07, 0.06))
    ico("cuerpo", (0, 0, 0.55 * tamaño), (0.55 * tamaño, 0.25 * tamaño, 0.3 * tamaño), piel, 2)
    ico("cabeza", (0.48 * tamaño, 0, 0.78 * tamaño), (0.25 * tamaño, 0.22 * tamaño, 0.24 * tamaño), piel, 1)
    for x in (-0.32, 0.32):
        for y in (-0.16, 0.16):
            cilindro("pata", (x * tamaño, y * tamaño, 0.25 * tamaño), 0.07 * tamaño, 0.5 * tamaño, piel)
    for y in (-0.12, 0.12):
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.09 * tamaño, radius2=0.0, depth=0.24 * tamaño,
            location=(0.5 * tamaño, y * tamaño, 1.02 * tamaño))
        asignar(bpy.context.object, piel)
    for y in (-0.15, 0.15):
        ico("ojo", (0.65 * tamaño, y * tamaño, 0.84 * tamaño), (0.025 * tamaño,) * 3, oscuro)
    cola = cilindro("cola", (-0.58 * tamaño, 0, 0.72 * tamaño), 0.045 * tamaño, 0.5 * tamaño, piel,
        rot=(0, math.radians(-45), 0))
    unir_y_exportar(nombre, destino)


def dron(destino):
    limpiar()
    gris = material("gris", (0.12, 0.16, 0.2))
    naranja = material("naranja", (0.95, 0.35, 0.06))
    negro = material("negro", (0.025, 0.03, 0.035))
    cubo("cuerpo", (0, 0, 0.35), (0.5, 0.36, 0.2), naranja)
    cubo("bateria", (-0.05, 0, 0.5), (0.3, 0.24, 0.1), gris)
    for x in (-0.45, 0.45):
        for y in (-0.45, 0.45):
            brazo = cubo("brazo", (x * 0.5, y * 0.5, 0.36), (0.7, 0.06, 0.06), gris)
            brazo.rotation_euler.z = math.atan2(y, x)
            cilindro("motor", (x, y, 0.38), 0.07, 0.12, negro)
            cilindro("helice", (x, y, 0.46), 0.28, 0.015, negro, vertices=12)
            cilindro("tren", (x * 0.65, y * 0.65, 0.15), 0.025, 0.3, gris)
    ico("camara", (0.22, 0, 0.22), (0.1, 0.1, 0.1), negro, 2)
    unir_y_exportar("dron", destino)


def pelota(destino):
    limpiar()
    roja = material("roja", (0.85, 0.08, 0.06))
    ico("pelota", (0, 0, 0.22), (0.22, 0.22, 0.22), roja, 2)
    unir_y_exportar("pelota", destino)


def persona(fbx, destino, piel=None):
    limpiar()
    bpy.ops.import_scene.fbx(filepath=str(fbx))
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    mod = obj.modifiers.new("baja_poligonizacion", "DECIMATE")
    mod.ratio = 0.25
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.shade_flat()
    bpy.ops.wm.obj_export(filepath=str(destino / "persona.obj"), export_selected_objects=True,
        forward_axis="NEGATIVE_Z", up_axis="Y", export_materials=True,
        export_normals=True, export_triangulated_mesh=True)
    print("persona", sum(len(p.vertices) - 2 for p in obj.data.polygons), "triángulos")
    if piel:
        texturas = destino.parent / "persona"
        texturas.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(piel, texturas / "survivorMaleB.png")
    mapa = "map_Kd ../persona/survivorMaleB.png\n" if (destino.parent / "persona" / "survivorMaleB.png").exists() else ""
    (destino / "persona.mtl").write_text(
        "newmtl skin\nNs 0.000000\nKa 0.000000 0.000000 0.000000\n"
        "Kd 1.000000 1.000000 1.000000\nKs 0.000000 0.000000 0.000000\n"
        "Ke 0.000000 0.000000 0.000000\nNi 1.500000\nd 1.000000\nillum 2\n" + mapa,
        encoding="utf-8",
    )


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--salida", required=True)
    ap.add_argument("--personaje")
    ap.add_argument("--piel")
    args = ap.parse_args(argv)
    destino = pathlib.Path(args.salida)
    destino.mkdir(parents=True, exist_ok=True)
    animal("perro", destino, (0.55, 0.32, 0.14), 1.0)
    animal("gato", destino, (0.35, 0.38, 0.42), 0.65)
    animal("oveja", destino, (0.82, 0.8, 0.72), 1.15)
    dron(destino)
    pelota(destino)
    if args.personaje:
        persona(pathlib.Path(args.personaje), destino, pathlib.Path(args.piel) if args.piel else None)


main()
