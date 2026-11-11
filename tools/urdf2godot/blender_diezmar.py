# Diezma mallas (STL/OBJ/DAE) y las exporta a OBJ sin cambiar sus ejes.
# Lo lanza urdf2godot.py:  blender -b --factory-startup -P blender_diezmar.py -- trabajos.json
# trabajos.json = [{"entrada": ".../x.STL", "salida": ".../x.obj", "tris": 400, "escala": [1,1,1]}, ...]
# Las coordenadas se quedan en el marco del link de ROS (Z arriba): la conversión a Godot la hace la escena.
import bpy
import json
import sys


def limpiar():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


def importar(ruta):
    r = ruta.lower()
    if r.endswith(".stl"):
        bpy.ops.wm.stl_import(filepath=ruta)
    elif r.endswith(".obj"):
        bpy.ops.wm.obj_import(filepath=ruta, forward_axis="Y", up_axis="Z")
    elif r.endswith(".dae"):
        bpy.ops.wm.collada_import(filepath=ruta)
    else:
        raise SystemExit(f"formato no soportado: {ruta}")


def triangulos(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def main():
    trabajos = json.load(open(sys.argv[sys.argv.index("--") + 1]))
    informe = []
    for t in trabajos:
        limpiar()
        importar(t["entrada"])
        objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
        bpy.context.view_layer.objects.active = objs[0]
        for o in objs:
            o.select_set(True)
        if len(objs) > 1:
            bpy.ops.object.join()
        obj = bpy.context.view_layer.objects.active
        obj.scale = t.get("escala", [1, 1, 1])
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        antes = triangulos(obj)
        if t["tris"] < antes:
            mod = obj.modifiers.new("diezmar", "DECIMATE")
            mod.ratio = max(t["tris"] / antes, 0.001)
            mod.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier=mod.name)
        # Sombreado plano: con mallas muy diezmadas el suave da artefactos y la Vita ilumina por vértice.
        bpy.ops.object.shade_flat()
        despues = triangulos(obj)
        bpy.ops.wm.obj_export(
            filepath=t["salida"], export_selected_objects=True, forward_axis="Y", up_axis="Z",
            export_materials=False, export_uv=False, export_normals=True, apply_modifiers=True,
            export_triangulated_mesh=True,
        )
        informe.append({"salida": t["salida"], "antes": antes, "despues": despues})
    print("URDF2GODOT_INFORME " + json.dumps(informe))


main()
