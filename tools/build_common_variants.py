"""Run in Blender to derive the Common roster, tier exports, and Roblox mesh data."""

import base64
from collections import Counter
import importlib.util
from itertools import groupby
import json
from math import ceil, cos, floor, hypot, pi, sin
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

STYLES = {
    "C01_Pebble": ("#929496", "◆"),
    "C02_Needle": ("#ADBFCB", "///"),
    "C03_Hammer": ("#CD8A45", "⚒"),
    "C04_Twinshot": ("#F2E5D0", "⇗⇗"),
    "C05_Longshot": ("#2DAC63", "⊕"),
    "C06_Chill": ("#ABE1F3", "❄"),
    "C07_Spark": ("#F6C438", "ϟ"),
}
TEXTURE_SIZE = 128
LAYOUTS = {**base.LAYOUTS, 7: []}
VIEWS = {
    "three_quarter": (0.78, -1.1, 1.8),
    "front": (0, -1, 0), "back": (0, 1, 0), "left": (-1, 0, 0),
    "right": (1, 0, 0), "top": (0, 0, 1), "bottom": (0, 0, -1),
}


def linear_channel(c):
    return c / 255 / 12.92 if c < 11 else ((c / 255 + 0.055) / 1.055) ** 2.4


def material(source, name, hex_color, roughness=0.72, metallic=0):
    linear = tuple(map(linear_channel, base._rgb(hex_color)))
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


def shell(source, tier, layouts=LAYOUTS, *, inset_star=False, mark_depth=.046):
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
    star_socket = tier == 7 and inset_star
    for face in base.ORDER:
        coords = list(base.OCTAGON)
        rings = []
        slots = [(0, 0)] if star_socket else layouts[tier]
        for u, v in slots:
            start = len(coords)
            coords.extend(radial(10, .57, .26) if star_socket else base._ring(u, v, .222, 12))
            rings.append(list(range(start, len(coords))))
        boundary = [list(range(8))] + [r[::-1] for r in rings]
        out, _, triangles, original, _, _ = geometry.delaunay_2d_cdt(coords, [], boundary, 3, 1e-8)
        assert len(out) == len(coords) and len(triangles) == 6 + sum(len(ring) + 2 for ring in rings)
        verts = [body.v(base._pt(face, u, v)) for u, v in coords]
        for tri in triangles:
            ids = [original[i][0] for i in tri]
            a, b, c = [Vector(coords[i]).to_3d() for i in ids]
            if (b - a).cross(c - a).z < 0:
                ids.reverse()
            panel = body.f([verts[i] for i in ids], face)
            if face == "top":
                panel.material_index = 3
                for loop in panel.loops:
                    x, y, _ = loop.vert.co
                    loop[body.uv].uv = (0.5 + x / 2.5, 0.5 + y / 2.5)
        for (u, v), ring in zip(slots, rings):
            floor_coords = radial(10, .568, .258) if star_socket else base._ring(u, v, .208, 12)
            floor = [body.v(base._pt(face, x, y, .048)) for x, y in floor_coords]
            for i in range(len(ring)):
                j = (i + 1) % len(ring)
                body.f([verts[ring[i]], verts[ring[j]], floor[j], floor[i]], face).material_index = 1
            body.f(floor, face).material_index = 1
            # A shallower insert follows the taper at its depth, leaving a hairline around the rim.
            insert = floor_coords if mark_depth == .046 or star_socket else base._ring(u, v, .219, 12)
            marks.f([marks.v(base._pt(face, x, y, mark_depth)) for x, y in insert], face)
        if tier == 7 and not inset_star:
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


def top_texture(style, draw_art=None):
    """Rasterize original face artwork in the same top view used by both exporters."""
    size = TEXTURE_SIZE * 2
    pixels = bytearray([255]) * size**2

    def polygon(points, shade=168):
        coords = [Vector(((.5 + x / 2.5) * size, (.5 - y / 2.5) * size, 0)) for x, y in points]
        for tri in geometry.tessellate_polygon([coords]):
            a, b, c = (coords[i] for i in tri)
            if (b - a).cross(c - a).z < 0:
                b, c = c, b
            edges = ((a, b), (b, c), (c, a))
            for y in range(max(0, floor(min(a.y, b.y, c.y))), min(size, ceil(max(a.y, b.y, c.y)))):
                for x in range(max(0, floor(min(a.x, b.x, c.x))), min(size, ceil(max(a.x, b.x, c.x)))):
                    if all((q.x - p.x) * (y + .5 - p.y) >= (q.y - p.y) * (x + .5 - p.x) for p, q in edges):
                        pixels[y * size + x] = shade

    def line(a, b, width, shade=168):
        x, y = a
        u, v = b
        k = width / (2 * hypot(u - x, v - y))
        dx, dy = (y - v) * k, (u - x) * k
        polygon([(x + dx, y + dy), (x - dx, y - dy), (u - dx, v - dy), (u + dx, v + dy)], shade)

    def arrow(a, b):
        direction = (Vector(b) - Vector(a)).normalized()
        across = Vector((-direction.y, direction.x))
        start, tip = Vector(a), Vector(b)
        neck = tip - direction * .40
        polygon([start, start + direction * .12 - across * .10, neck - across * .10,
                 neck - across * .24, tip, neck + across * .24, neck + across * .10,
                 start + direction * .12 + across * .10], 156)

    if draw_art:
        draw_art(polygon, line)
    elif style == "C01":
        polygon([(-.91, .29), (-.63, .78), (-.12, .90), (.06, .68),
                 (-.06, .31), (-.46, .05), (-.79, -.03)], 211)
        polygon([(.15, -.49), (.63, -.18), (.89, -.31), (.78, -.74), (.26, -.90), (-.11, -.76)], 206)
        for a, b in zip([(-.91, .29), (-.58, .20), (-.28, -.14), (.12, -.22), (.39, -.50)],
                        [(-.58, .20), (-.28, -.14), (.12, -.22), (.39, -.50), (.78, -.74)]):
            line(a, b, .085, 166)
        line((-.28, -.14), (-.49, -.50), .055, 186)
        line((.12, -.22), (.43, .16), .061, 186)
    elif style == "C02":
        for shift in (-.40, 0, .40):
            x, y = shift, -shift * .6
            polygon([(x - .48, y - .61), (x - .05, y + .23),
                     (x + .48, y + .65), (x + .11, y - .13)], 158)
    elif style == "C03":
        line((-.66, -.74), (.31, .37), .28, 167)
        polygon([(-.11, .39), (.23, .81), (.42, .83), (.86, .40),
                 (.80, .21), (.49, -.13), (.33, -.04)], 147)
        polygon([(-.11, .39), (.23, .81), (.42, .83), (.52, .72), (.32, .67), (.01, .30)], 188)
    elif style == "C04":
        arrow((-.84, -.48), (.43, .84))
        arrow((-.43, -.84), (.84, .48))
    elif style == "C05":
        ring = [(.58 * cos(i * pi / 16), .58 * sin(i * pi / 16)) for i in range(32)]
        for i, point in enumerate(ring):
            line(point, ring[(i + 1) % len(ring)], .115, 151)
        for x, y in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            line((x * .42, y * .42), (x * .83, y * .83), .095, 151)
        for x in (-1, 1):
            for y in (-1, 1):
                line((x * .62, y * .84), (x * .84, y * .84), .08, 188)
                line((x * .84, y * .84), (x * .84, y * .62), .08, 188)
    elif style == "C06":
        for i in range(6):
            x, y = cos(i * pi / 3), sin(i * pi / 3)
            line((0, 0), (.83 * x, .83 * y), .116, 151)
            for side in (-1, 1):
                line((.47 * x, .47 * y), (.64 * x - .20 * side * y, .64 * y + .20 * side * x), .09, 177)
    elif style == "C07":
        polygon([(-.19, .84), (.58, .84), (.18, .22), (.64, .22), (-.51, -.86),
                 (-.19, -.16), (-.66, -.16)], 147)
        polygon([(-.19, .84), (.58, .84), (.45, .67), (-.28, .67)], 183)
        for points in [[(-.85, .35), (-.73, .66), (-.6, .42)], [(.63, -.41), (.86, -.18), (.79, -.48)]]:
            polygon(points, 195)

    result = bytes(round(sum(pixels[(2 * y + dy) * size + 2 * x + dx]
                             for dx in (0, 1) for dy in (0, 1)) / 4)
                   for y in range(TEXTURE_SIZE) for x in range(TEXTURE_SIZE))
    assert 1000 < sum(p != 255 for p in result) < TEXTURE_SIZE**2 // 2
    for offset in (0, len(result) - TEXTURE_SIZE):
        assert all(p == 255 for p in result[offset:offset + TEXTURE_SIZE])
    return result


def texture_packet(mask):
    packed = bytearray()
    for shade, pixels in groupby(mask):
        count = sum(1 for _ in pixels)
        while count:
            run = min(count, 256)
            packed.extend((run - 1, shade))
            count -= run
    assert sum(n + 1 for n in packed[::2]) == len(mask)
    return base64.b64encode(packed).decode()


def painted_material(source, name, body, mask):
    mat = material(source, name, body)
    image = bpy.data.images.new(name, TEXTURE_SIZE, TEXTURE_SIZE, alpha=False)
    rgb = base._rgb(body)
    rgba = []
    for row in range(TEXTURE_SIZE - 1, -1, -1):  # Blender stores the bottom row first.
        for shade in mask[row * TEXTURE_SIZE:(row + 1) * TEXTURE_SIZE]:
            rgba.extend((*(c * shade / 65025 for c in rgb), 1))
    image.pixels.foreach_set(rgba)
    image.update()
    image.pack()
    shader = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.extension = "EXTEND"
    mat.node_tree.nodes.active = tex
    mat.node_tree.links.new(tex.outputs["Color"], shader.inputs["Base Color"])
    return mat


def ice_accents():
    mesh = base._Mesh()
    for x, y, scale in ((-.69, -.86, 1.0), (-.51, -.92, .72), (.71, -.9, .68)):
        points = [(x - .105 * scale, y - .07 * scale), (x + .11 * scale, y - .065 * scale),
                  (x + .02 * scale, y + .125 * scale)]
        verts = [mesh.v(base._pt("right", u, v, .015)) for u, v in points]
        tip = mesh.v(base._pt("right", x, y, -.065))
        for j in range(3):
            mesh.f([verts[j], verts[(j + 1) % 3], tip], "right").material_index = int(j != 1)
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


def write_game_data(shells, marks, masks, ice):
    path = ROOT / "src/client/Controllers/Dice/ModelData.luau"
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = ["-- Generated by tools/build_common_variants.py.", "-- stylua: ignore", "return {",
            f"\tTextureSize = {TEXTURE_SIZE},", f'\tIce = "{packet(ice)}",', "\tLayouts = {"]
    for slots in LAYOUTS.values():
        rows.append("\t\t{ " + ", ".join(f"{{ {x:g}, {y:g} }}" for x, y in slots) + " }," if slots else "\t\t{},")
    rows.extend(["\t},", "\tBodies = {"])
    rows.extend(f'\t\t"{packet(obj)}",' for obj in shells)
    rows.extend(["\t},", "\tMarks = {"])
    rows.extend(f'\t\t"{packet(obj)}",' for obj in marks)
    rows.extend(["\t},", "\tStyles = {"])
    for (name, (body, fallback)), mask in zip(STYLES.items(), masks):
        rows.extend([f'\t\t{name[:3]} = {{', f'\t\t\tBody = "{body}",',
                     f'\t\t\tMark = "{fallback}",', f'\t\t\tTexture = "{texture_packet(mask)}",', "\t\t},"])
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
    assert len(body) == 4 and all("TEXCOORD_0" in m["attributes"] for m in body)
    assert [min(m["min"][i] for m in body) for i in range(3)] == [-1.25] * 3
    assert [max(m["max"][i] for m in body) for i in range(3)] == [1.25] * 3
    assert b'"baseColorTexture"' in glb.read_bytes()


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
             for i, f in enumerate((1.0, .79, 1.13, 1.13))]
    dark = material(pip_source, "Dark inserts", "#16171B")
    star = [material(pip_source, "Star rim", "#32201A"), material(pip_source, "Star gold", "#FFD65C", .48)]
    shells, marks = [], []
    for tier in range(1, 8):
        body, face_marks = shell(original_body, tier)
        shells.append(finish(body, f"Tier {tier} Body", shade))
        marks.append(finish(face_marks, f"Tier {tier} Marks", star if tier == 7 else [dark]))
        verify_body(shells[-1], marks[-1], tier)
    masks = [top_texture(name[:3]) for name in STYLES]
    painted = [painted_material(body_source, f"{name}_TopDesign", tint(body, 1.13), mask)
               for (name, (body, _)), mask in zip(STYLES.items(), masks)]
    ice = finish(ice_accents(), "C06_IceChips", [
        material(body_source, "Ice facet blue", "#245C8C"),
        material(body_source, "Ice facet cyan", "#58C9F1"),
    ])
    if not full:
        scene = bpy.data.scenes.new("Common Variant Review")
        bpy.context.window.scene = scene
        for i, (name, (body, _)) in enumerate(STYLES.items()):
            for row, tier in enumerate((0, 5, 6)):
                for obj in variant_objects(name, body, shells[tier], marks[tier], painted[i], ice, body_source):
                    scene.collection.objects.link(obj)
                    obj.location = (i * 3.2, row * 3.2, 0)
        return
    write_game_data(shells, marks, masks, ice)
    prior = bpy.context.window.scene
    for i, (name, (body, _)) in enumerate(STYLES.items()):
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
        scene.display.shading.color_type = "TEXTURE"
        scene.display.shading.show_shadows = False
        scene.display.shading.show_cavity = True
        scene.display.shading.cavity_type = "BOTH"
        scene.display.shading.background_type = "WORLD"
        scene.world = bpy.data.worlds.new("Preview background")
        scene.world.color = (.055, .07, .095)
        scene.view_settings.view_transform = "Standard"
        scene.render.image_settings.file_format = "PNG"
        scene.render.resolution_percentage = 100
        report = {"source": "Common.blend", "base_triangles": 2134, "budget": 2400,
                  "top_texture_pixels": [TEXTURE_SIZE, TEXTURE_SIZE], "tiers": {}}
        for tier, (shell_obj, mark_obj) in enumerate(zip(shells, marks), 1):
            variant = f"{name}_T{tier}"
            group = bpy.data.collections.new(f"Tier {tier}" if tier < 7 else "Tier 7 - Star")
            scene.collection.children.link(group)
            objs = variant_objects(variant, body, shell_obj, mark_obj, painted[i], ice, body_source)
            for obj in objs:
                group.objects.link(obj)
            counts = {o.name: len(o.data.loop_triangles) for o in objs}
            total = sum(counts.values())
            assert total <= report["budget"], (variant, total)
            report["tiers"][tier] = {"pips_per_face": tier if tier < 7 else 0, "stars_per_face": int(tier == 7),
                                      "triangles": total, "difference_from_base": total - 2134, "parts": counts}
            export(scene, exports, variant, objs)
            render(scene, previews / f"T{tier}_three_quarter.png", VIEWS["three_quarter"], 360 if tier == 1 else 180)
            if tier == 1:
                for label, direction in list(VIEWS.items())[1:]:
                    render(scene, previews / f"T1_{label}.png", direction)
            group.hide_viewport = group.hide_render = True
        first = scene.collection.children[0]
        first.hide_viewport = first.hide_render = False
        beauty = Vector(VIEWS["three_quarter"])
        camera.location = beauty.normalized() * 9
        camera.rotation_euler = (-beauty).to_track_quat("-Z", "Y").to_euler()
        scene.render.resolution_x = scene.render.resolution_y = 720
        scene.render.filepath = "//previews/preview.png"
        bpy.data.libraries.write(str(folder / (name + ".blend")), {scene}, fake_user=True, compress=True)
        (folder / "asbuilt.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"Completed {name}: {[x['triangles'] for x in report['tiers'].values()]}", flush=True)
    bpy.context.window.scene = prior


def variant_objects(name, body, shell_obj, mark_obj, painted, ice, source):
    body_obj = shell_obj.copy()
    body_obj.data = shell_obj.data.copy()
    body_obj.name = f"{name}_Body"
    for i, factor in enumerate((1.0, .79, 1.13)):
        body_obj.data.materials[i] = material(source, f"{name}_Body_{i}", tint(body, factor),
                                             metallic=.22 if name.startswith("C02") else 0)
    body_obj.data.materials[3] = painted
    marks_obj = mark_obj.copy()
    marks_obj.name = f"{name}_{'Stars' if name.endswith('T7') else 'Pips'}"
    if name.startswith("C06"):
        chips = ice.copy()
        chips.name = f"{name}_IceChips"
        return body_obj, marks_obj, chips
    return body_obj, marks_obj


if __name__ == "__main__":
    main(full="--review" not in sys.argv)
