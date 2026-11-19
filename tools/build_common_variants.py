"""Run in Blender to derive the Common roster, tier exports, and Roblox mesh data."""

import base64
from collections import Counter
import importlib.util
import json
from math import cos, hypot, pi, sin
from pathlib import Path
import struct
import sys

import bpy
from mathutils import Vector, geometry

ROOT = Path(__file__).resolve().parents[1]
COMMON = ROOT / "Assets/Models/Dice/Common"
OUTPUT = COMMON / "Variants"
SOURCE = COMMON / "Common.blend"
BASE_SPEC = json.loads((COMMON / "asbuilt.json").read_text())
spec = importlib.util.spec_from_file_location("build_common", COMMON / "build_common.py")
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
fbx = base._load("roblox_fbx", Path(base.SKILL) / "roblox_fbx.py")

# Identify the die without taking a position away from any of the six pip layouts.
STYLES = {
    "C01_Pebble": ("#929496", "right", "#555B61", "#ADB1B4", "◆"),
    "C02_Needle": ("#ADBFCB", "left", "#273843", "#DCEBF2", "///"),
    "C03_Hammer": ("#CD8A45", "left", "#5E301B", "#FFD087", "⚒"),
    "C04_Twinshot": ("#F2E5D0", "right", "#423128", "#B18A68", "⇗⇗"),
    "C05_Longshot": ("#2DAC63", "right", "#F2F4D9", "#166547", "⊕"),
    "C06_Chill": ("#ABE1F3", "right", "#245C8C", "#58C9F1", "❄"),
    "C07_Spark": ("#F6C438", "right", "#7A4615", "#FFF398", "ϟ"),
}
LAYOUTS = {**base.LAYOUTS, 7: []}
VIEWS = {
    "three_quarter": (0.98, -1.5, 1.33),
    "front": (0, -1, 0), "back": (0, 1, 0), "left": (-1, 0, 0),
    "right": (1, 0, 0), "top": (0, 0, 1), "bottom": (0, 0, -1),
}


def material(source, name, hex_color, roughness=0.72, metallic=0):
    rgb = base._rgb(hex_color)
    linear = tuple(c / 255 / 12.92 if c < 11 else ((c / 255 + 0.055) / 1.055) ** 2.4 for c in rgb)
    mat = source.copy()
    mat.name = name
    mat.diffuse_color = (*linear, 1)
    shader = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = (*linear, 1)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    return mat


def tint(hex_color, factor):
    return "#%02X%02X%02X" % tuple(min(255, round(c * factor)) for c in base._rgb(hex_color))


def shell(source, tier):
    body = base._Mesh()
    marks = base._Mesh()
    hull = base._hull_faces()
    # Keep the actual base's edge and corner triangles and their original UVs.
    for p in source.data.polygons:
        coords = [source.data.vertices[i].co for i in p.vertices]
        if not any(all(abs(n.dot(v) - distance) < 1e-5 for v in coords) for n, distance in hull):
            continue
        face = base._tile_of(p.normal)
        poly = body.f([body.v(co) for co in coords], face)
        for loop, index in zip(poly.loops, p.loop_indices):
            loop[body.uv].uv = source.data.uv_layers.active.data[index].uv
        poly.material_index = 2 if p.normal.z > .1 else 1
    for face in base.ORDER:
        coords = list(base.OCTAGON)
        rings = []
        for u, v in LAYOUTS[tier]:
            start = len(coords)
            coords.extend(base._ring(u, v, .222, 12))
            rings.append(list(range(start, len(coords))))
        boundary = [list(range(8))] + [r[::-1] for r in rings]
        out, _, triangles, original, _, _ = geometry.delaunay_2d_cdt(coords, [], boundary, 3, 1e-8)
        assert len(out) == len(coords) and len(triangles) == 6 + 14 * len(rings)
        verts = [body.v(base._pt(face, u, v)) for u, v in coords]
        for tri in triangles:
            ids = [original[i][0] for i in tri]
            a, b, c = [Vector(coords[i]).to_3d() for i in ids]
            if (b - a).cross(c - a).z < 0:
                ids.reverse()
            body.f([verts[i] for i in ids], face).material_index = 2 if face == "top" else 0
        for (u, v), ring in zip(LAYOUTS[tier], rings):
            floor_coords = base._ring(u, v, .208, 12)
            floor = [body.v(base._pt(face, x, y, .048)) for x, y in floor_coords]
            for i in range(12):
                j = (i + 1) % 12
                body.f([verts[ring[i]], verts[ring[j]], floor[j], floor[i]], face).material_index = 1
            body.f(floor, face).material_index = 1
            # Dark insert sits inside the cup. Its hidden underside is the cup floor.
            marks.f([marks.v(base._pt(face, x, y, .046)) for x, y in floor_coords], face)
        if tier == 7:
            points = radial(10, .42, .19)
            outer = [marks.v(base._pt(face, x, y, -.001)) for x, y in points]
            inner = [marks.v(base._pt(face, x * .78, y * .78, -.013)) for x, y in points]
            center = marks.v(base._pt(face, 0, 0, -.013))
            for i in range(10):
                j = (i + 1) % 10
                marks.f([outer[i], outer[j], inner[j], inner[i]], face)
                marks.f([center, inner[i], inner[j]], face).material_index = 1
    return body, marks


def radial(count, outer, inner):
    return [(radius * cos(pi / 2 + i * 2 * pi / count), radius * sin(pi / 2 + i * 2 * pi / count))
            for i in range(count) for radius in [inner if i % 2 else outer]]


def ornaments(style, face):
    mesh = base._Mesh()

    def polygon(points, color=0, side=face):
        points = [base._pt(side, u, v, -.002 - .001 * color) for u, v in points]
        normal = Vector(base.FRAMES[side][0])
        tris = geometry.tessellate_polygon([points])
        for tri in tris:
            a, b, c = [points[i] for i in tri]
            if (b - a).cross(c - a).dot(normal) < 0:
                b, c = c, b
            mesh.f([mesh.v(v) for v in (a, b, c)], side).material_index = color

    def line(a, b, width, color=0, side=face):
        x, y = a
        u, v = b
        k = width / (2 * hypot(u - x, v - y))
        dx, dy = (y - v) * k, (u - x) * k
        polygon([(x + dx, y + dy), (x - dx, y - dy), (u - dx, v - dy), (u + dx, v + dy)], color, side)

    def polyline(path, width, color=0, side=face):
        for a, b in zip(path, path[1:]):
            line(a, b, width, color, side)

    # One strip above the outermost cup, repeated on top for the match camera.
    for side in (face, "top"):
        def badge(points, color=0):
            polygon([(x, y + .87) for x, y in points], color, side)

        def stroke(a, b, width=.022, color=0):
            line((a[0], a[1] + .87), (b[0], b[1] + .87), width, color, side)

        if style == "C01":
            badge([(-.66, -.1), (-.56, .1), (-.27, .08), (-.13, -.07), (-.44, -.025)])
            badge([(.18, .02), (.35, .105), (.68, .045), (.45, -.08)], 1)
            polyline([(-.95, .32), (-.85, .21), (-.97, .08)], .021, side=side)
        elif style == "C02":
            for x in (-.35, 0, .35):
                badge([(x - .19, -.106), (x + .14, .103), (x + .2, .115), (x - .12, -.095)], 1)
                badge([(x - .17, -.11), (x + .2, .115), (x + .095, .005), (x - .09, -.1)])
        elif style == "C03":
            stroke((-.43, -.096), (.27, .041), .052)
            badge([(.12, -.035), (.09, .068), (.44, .13), (.49, .026)])
            badge([(.09, .068), (.44, .13), (.45, .105), (.11, .045)], 1)
            badge([(-.81, -.08), (-.72, .095), (-.59, .065), (-.66, -.075)], 1)
        elif style == "C04":
            for y in (-.065, .065):
                badge([(-.61, y - .035), (.38, y + .013), (.36, y + .06),
                       (.64, y + .025), (.39, y - .05), (.4, y - .008)])
        elif style == "C05":
            ring = [(.088 * cos(i * pi / 8), .088 * sin(i * pi / 8)) for i in range(16)]
            for i, point in enumerate(ring):
                stroke(point, ring[(i + 1) % 16], .018)
            badge([(x * .018, y * .018) for x, y in radial(4, 1, 1)])
            for x, y in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                stroke((x * .10, y * .10), (x * .146, y * .131), .018)
            for x in (-1, 1):
                for y in (-1, 1):
                    stroke((x * .31, y * .115), (x * .53, y * .115), .025)
                    stroke((x * .53, y * .115), (x * .53, y * .049), .025)
        elif style == "C06":
            for i in range(6):
                angle = i * pi / 3
                x, y = cos(angle), sin(angle)
                stroke((0, 0), (.14 * x, .14 * y), .025)
                for turn in (-1, 1):
                    stroke((.083 * x, .083 * y), (.107 * x - .045 * turn * y, .107 * y + .045 * turn * x), .018)
            for x, y, scale in ((-.69, -.86, 1.0), (-.51, -.92, .72), (.71, -.9, .68)):
                points = [(x - .105 * scale, y - .07 * scale), (x + .11 * scale, y - .065 * scale),
                          (x + .02 * scale, y + .125 * scale)]
                tip = base._pt(side, x, y, -.065)
                verts = [mesh.v(base._pt(side, u, v, .015)) for u, v in points]
                raised = mesh.v(tip)
                for j in range(3):
                    mesh.f([verts[j], verts[(j + 1) % 3], raised], side).material_index = 1 if j != 1 else 0
        elif style == "C07":
            badge([(-.1, .135), (.15, .135), (.04, .02), (.18, .02),
                   (-.14, -.13), (-.062, -.018), (-.21, -.018)])
            badge([(-.1, .135), (.15, .135), (.113, .108), (-.08, .108)], 1)
            for sign in (-1, 1):
                for y in (-.064, .07):
                    badge([(sign * .26, y * .5), (sign * .54, y), (sign * .43, y * .55)])
    return mesh


def finish(builder, name, materials):
    data = bpy.data.meshes.new(name)
    builder.bm.to_mesh(data)
    builder.bm.free()
    for mat in materials:
        data.materials.append(mat)
    data.calc_loop_triangles()
    obj = bpy.data.objects.new(name, data)
    return obj


def packet(obj):
    """Blender (x,y,z) to Roblox (x,z,-y); little-endian millistuds and triangle indices."""
    mesh = obj.data
    out = bytearray(struct.pack("<HH", len(mesh.vertices), len(mesh.loop_triangles)))
    for vertex in mesh.vertices:
        x, y, z = vertex.co
        out += struct.pack("<hhh", round(x * 1000), round(z * 1000), round(-y * 1000))
    for tri in mesh.loop_triangles:
        out += struct.pack("<HHHB", *tri.vertices, tri.material_index)
    return base64.b64encode(out).decode()


def write_game_data(shells, marks, details):
    path = ROOT / "src/client/Controllers/Dice/ModelData.luau"
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = ["-- Generated by tools/build_common_variants.py.", "-- stylua: ignore", "return {", "\tLayouts = {"]
    for slots in LAYOUTS.values():
        rows.append("\t\t{ " + ", ".join(f"{{ {x:g}, {y:g} }}" for x, y in slots) + " }," if slots else "\t\t{},")
    rows.extend(["\t},", "\tBodies = {"])
    rows.extend(f'\t\t"{packet(obj)}",' for obj in shells)
    rows.extend(["\t},", "\tMarks = {"])
    rows.extend(f'\t\t"{packet(obj)}",' for obj in marks)
    rows.extend(["\t},", "\tStyles = {"])
    for (name, (body, face, dark, light, fallback)), obj in zip(STYLES.items(), details):
        rows.extend([f'\t\t{name[:3]} = {{', f'\t\t\tBody = "{body}",',
                     f'\t\t\tFace = "{face.title()}",', f'\t\t\tMark = "{fallback}",',
                     f'\t\t\tColors = {{ "{dark}", "{light}" }},', f'\t\t\tMesh = "{packet(obj)}",', "\t\t},"])
    rows.extend(["\t},", "}", ""])
    path.write_text("\n".join(rows), encoding="utf-8")


def verify_body(body, marks, tier):
    mesh = body.data
    for axis in range(3):
        coords = [v.co[axis] for v in mesh.vertices]
        assert abs(min(coords) + 1.25) < 1e-6 and abs(max(coords) - 1.25) < 1e-6
    edges = Counter(tuple(sorted(edge)) for p in mesh.polygons for edge in p.edge_keys)
    assert set(edges.values()) == {2}, (tier, Counter(edges.values()))
    assert min(t.area for t in mesh.loop_triangles) > 1e-6
    for face in base.ORDER:
        normal = Vector(base.FRAMES[face][0])
        surfaces = [p for p in marks.data.polygons if p.normal.dot(normal) > .75]
        count = 20 if tier == 7 else tier
        assert len(surfaces) == count, (face, tier, len(surfaces), count)


def export(scene, folder, name, objects):
    glb = folder / (name + ".glb")
    layer = scene.view_layers[0]
    layer.update()
    with bpy.context.temp_override(scene=scene, view_layer=layer):
        for obj in layer.objects:
            obj.select_set(obj in objects, view_layer=layer)
        fbx_path = folder / (name + ".fbx")
        bpy.ops.export_scene.fbx(filepath=str(fbx_path), **fbx.COMMON, **fbx.PRESETS["official"]["fbx"])
        roundtrip = fbx.reimport_check(str(fbx_path), objects)
        assert len(roundtrip) == len(objects)
        assert all(p["vertex_count_matches"] and p["scale_to_match_source"] == 1
                   and p["turn_to_match_source"] == "none" and p["max_vertex_error"] < 1e-4
                   for p in roundtrip.values()), roundtrip
        for obj in layer.objects:
            obj.select_set(obj in objects, view_layer=layer)
        bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", use_selection=True,
                                  use_active_scene=True,
                                  export_cameras=False, export_lights=False, export_animations=False)
    result = base.glb_check(glb)
    assert result["magic_ok"]
    assert sum(m["tris"] for m in result["meshes"]) == sum(len(o.data.loop_triangles) for o in objects)
    body = [m for m in result["meshes"] if m["node"].endswith("_Body")]
    assert len(body) == 3 and all("TEXCOORD_0" in m["attributes"] for m in body)
    assert [min(m["min"][i] for m in body) for i in range(3)] == [-1.25] * 3
    assert [max(m["max"][i] for m in body) for i in range(3)] == [1.25] * 3


def render(scene, path, direction, size=300):
    normal = Vector(direction).normalized()
    scene.camera.location = normal * 9
    scene.camera.rotation_euler = (-normal).to_track_quat("-Z", "Y").to_euler()
    if not normal.x and not normal.y:
        scene.camera.rotation_euler = (0, 0, 0) if normal.z > 0 else (pi, 0, 0)
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True, scene=scene.name)


def main(full=False):
    with bpy.data.libraries.load(str(SOURCE)) as (source, output):
        output.objects = ["Common_Body", "Common_Pips"]
    original_body, original_pips = output.objects
    assert base.core_hash({"Body": original_body, "Pips": original_pips}) == BASE_SPEC["core_hash"]
    body_source = original_body.data.materials[0]
    pip_source = original_pips.data.materials[0]
    shade = [material(body_source, f"Body shade {i}", tint("#C0C0C0", f))
             for i, f in enumerate((1.0, .79, 1.13))]
    dark = material(pip_source, "Dark inserts", "#16171B")
    star = [material(pip_source, "Star rim", "#32201A"), material(pip_source, "Star gold", "#FFD65C", .48)]
    shells, marks, details = [], [], []
    for tier in range(1, 8):
        body, face_marks = shell(original_body, tier)
        shells.append(finish(body, f"Tier {tier} Body", shade))
        marks.append(finish(face_marks, f"Tier {tier} Marks", star if tier == 7 else [dark]))
        verify_body(shells[-1], marks[-1], tier)
    for name, (_, face, ink, highlight, _) in STYLES.items():
        paint = [material(body_source, f"{name} ornament {i}", color) for i, color in enumerate((ink, highlight))]
        details.append(finish(ornaments(name[:3], face), f"{name}_Ornaments", paint))
    if not full:
        scene = bpy.data.scenes.new("Common Variant Review")
        bpy.context.window.scene = scene
        for i, (name, (body, face, _, _, _)) in enumerate(STYLES.items()):
            for row, tier in enumerate((0, 5, 6)):
                for obj in variant_objects(name, body, shells[tier], marks[tier], details[i], body_source):
                    scene.collection.objects.link(obj)
                    obj.location = (i * 3.2, row * 3.2, 0)
        return
    write_game_data(shells, marks, details)
    prior = bpy.context.window.scene
    for i, (name, (body, face, _, _, _)) in enumerate(STYLES.items()):
        folder = OUTPUT / name
        exports, previews = folder / "exports", folder / "previews"
        exports.mkdir(parents=True, exist_ok=True)
        previews.mkdir(exist_ok=True)
        scene = bpy.data.scenes.new(name)
        bpy.context.window.scene = scene
        camera = bpy.data.objects.new("Preview camera", bpy.data.cameras.new("Preview camera"))
        scene.collection.objects.link(camera)
        scene.camera = camera
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = 4.28
        scene.render.engine = "BLENDER_WORKBENCH"
        scene.display.shading.light = "STUDIO"
        scene.display.shading.color_type = "MATERIAL"
        scene.display.shading.show_shadows = False
        scene.display.shading.show_cavity = True
        scene.display.shading.cavity_type = "BOTH"
        scene.display.shading.background_type = "WORLD"
        scene.world = bpy.data.worlds.new("Preview background")
        scene.world.color = (.055, .07, .095)
        scene.view_settings.view_transform = "Standard"
        scene.render.image_settings.file_format = "PNG"
        scene.render.resolution_percentage = 100
        report = {"source": "Common.blend", "base_triangles": 2134, "budget": 2400, "tiers": {}}
        for tier, (shell_obj, mark_obj) in enumerate(zip(shells, marks), 1):
            variant = f"{name}_T{tier}"
            group = bpy.data.collections.new(f"Tier {tier}" if tier < 7 else "Tier 7 - Star")
            scene.collection.children.link(group)
            objs = variant_objects(variant, body, shell_obj, mark_obj, details[i], body_source)
            for obj in objs:
                group.objects.link(obj)
            counts = {o.name: len(o.data.loop_triangles) for o in objs}
            total = sum(counts.values())
            assert total <= report["budget"], (variant, total)
            report["tiers"][tier] = {"pips_per_face": tier if tier < 7 else 0, "stars_per_face": int(tier == 7),
                                      "triangles": total, "difference_from_base": total - 2134, "parts": counts}
            export(scene, exports, variant, objs)
            beauty = list(VIEWS["three_quarter"])
            if face == "left":
                beauty[0] *= -1
            render(scene, previews / f"T{tier}_three_quarter.png", beauty, 360 if tier == 1 else 180)
            if tier == 1:
                for label, direction in list(VIEWS.items())[1:]:
                    render(scene, previews / f"T1_{label}.png", direction)
            group.hide_viewport = group.hide_render = True
        first = scene.collection.children[0]
        first.hide_viewport = first.hide_render = False
        beauty = Vector((-.98 if face == "left" else .98, -1.5, 1.33))
        camera.location = beauty.normalized() * 9
        camera.rotation_euler = (-beauty).to_track_quat("-Z", "Y").to_euler()
        scene.render.resolution_x = scene.render.resolution_y = 720
        scene.render.filepath = "//previews/preview.png"
        bpy.data.libraries.write(str(folder / (name + ".blend")), {scene}, fake_user=True, compress=True)
        (folder / "asbuilt.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"Completed {name}: {[x['triangles'] for x in report['tiers'].values()]}", flush=True)
    bpy.context.window.scene = prior


def variant_objects(name, body, shell_obj, mark_obj, ornament_obj, source):
    body_obj = shell_obj.copy()
    body_obj.data = shell_obj.data.copy()
    body_obj.name = f"{name}_Body"
    for i, factor in enumerate((1.0, .79, 1.13)):
        body_obj.data.materials[i] = material(source, f"{name}_Body_{i}", tint(body, factor),
                                             metallic=.22 if name.startswith("C02") else 0)
    marks_obj = mark_obj.copy()
    marks_obj.name = f"{name}_{'Stars' if name.endswith('T7') else 'Pips'}"
    details_obj = ornament_obj.copy()
    details_obj.name = f"{name}_Ornaments"
    return body_obj, marks_obj, details_obj


if __name__ == "__main__":
    main(full="--review" not in sys.argv)
