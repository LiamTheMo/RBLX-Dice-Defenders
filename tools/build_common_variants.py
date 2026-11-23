"""Run in Blender to derive the Common roster, tier exports, and Roblox mesh data."""

import base64
from collections import Counter
import importlib.util
from itertools import groupby
import json
from math import atan2, ceil, cos, floor, hypot, pi, sin
from pathlib import Path
from random import Random
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

# (top albedo hex sampled from the v1 sheets' flat orthographic faces, fallback glyph, ink for the baked top art)
STYLES = {
    "C01_Pebble": ("#D0CDD4", "◆", "#45434C"),
    "C02_Needle": ("#CDD2DE", "///", "#2A3140"),
    "C03_Hammer": ("#D9A24A", "⚒", "#4A2A10"),
    "C04_Twinshot": ("#EFE6D6", "⇗⇗", "#4A3F36"),
    "C05_Longshot": ("#4C9A1F", "⊕", "#F4EBC6"),
    "C06_Chill": ("#BEDCF5", "❄", "#1B5A9C"),
    "C07_Spark": ("#FFE020", "ϟ", "#5A3806"),
}
# Face shades shared by the Blender materials and the game's vertex colours (Visuals.luau bodyPalette):
# flat sides, bevel/cups, top chamfer. The top face keeps the pure albedo.
SHADES = (0.957, 0.855, 1.0)
ICE_FACETS = ("#48A6E8", "#A9E1FB")  # crystal facets; Visuals.luau iceChips palette must match
TEXTURE_SIZE = 128
BUDGET = 3000  # 16-gon pips with 6 per face cost ~2900 tris (the 2400 single die budget fits 21 pips, not 36)
STAR_RADIUS, STAR_INNER_RADIUS = .32, .14  # star about one pip wide, a smidge bigger (owner 2026-11-22)
LAYOUTS = {**base.LAYOUTS, 7: []}
VIEWS = {
    "three_quarter": (0.9, -1.25, 1.0),
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


def shell(source, tier, layouts=LAYOUTS, *, inset_star=False, mark_depth=.006, mark_rim=False, star_size=(.322, .142), pip_segments=16):  # unified pip look: 16-gon, flush (owner 2026-11-22)
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
            coords.extend(radial(10, *star_size) if star_socket else base._ring(u, v, .222, pip_segments))
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
            floor_coords = radial(10, *(radius - .002 for radius in star_size)) if star_socket else base._ring(u, v, .208, pip_segments)
            floor = [body.v(base._pt(face, x, y, .048)) for x, y in floor_coords]
            for i in range(len(ring)):
                j = (i + 1) % len(ring)
                body.f([verts[ring[i]], verts[ring[j]], floor[j], floor[i]], face).material_index = 1
            body.f(floor, face).material_index = 1
            # A shallower insert follows the taper at its depth, leaving a hairline around the rim.
            insert = floor_coords if mark_depth == .046 or star_socket else base._ring(u, v, .219, pip_segments)
            if mark_rim:
                outer = [marks.v(base._pt(face, x, y, mark_depth)) for x, y in insert]
                inner = [marks.v(base._pt(face, u + (x - u) * .86, v + (y - v) * .86, mark_depth))
                         for x, y in insert]
                for i in range(len(outer)):
                    j = (i + 1) % len(outer)
                    marks.f([outer[i], outer[j], inner[j], inner[i]], face).material_index = 1
                marks.f(inner, face)
            else:
                marks.f([marks.v(base._pt(face, x, y, mark_depth)) for x, y in insert], face)
        if tier == 7 and not inset_star:
            points = radial(10, STAR_RADIUS, STAR_INNER_RADIUS)
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


def placed(polygon, line, cx=0.0, cy=0.0, scale=1.0, turn=0.0):
    """Wrap polygon/line so art can be drawn in a local frame (y up): rotate by turn, scale, then move to (cx, cy)."""
    c, s = cos(turn), sin(turn)

    def at(p):
        return (cx + scale * (p[0] * c - p[1] * s), cy + scale * (p[0] * s + p[1] * c))
    return (lambda pts, shade=168: polygon([at(p) for p in pts], shade),
            lambda a, b, width, shade=168: line(at(a), at(b), width * scale, shade))


def disc(polygon, x, y, r, shade=168, n=16):
    polygon([(x + r * cos(i * 2 * pi / n), y + r * sin(i * 2 * pi / n)) for i in range(n)], shade)


def stroke(polygon, line, points, width, shade=168):
    """Polyline with round joints, so bends leave no wedge gaps."""
    for a, b in zip(points, points[1:]):
        line(a, b, width, shade)
    for x, y in points:
        disc(polygon, x, y, width / 2, shade, 10)


def arrow(polygon, a, b, shade, head=.24, shaft=.10, neck=.40):
    direction = (Vector(b) - Vector(a)).normalized()
    across = Vector((-direction.y, direction.x))
    start, tip = Vector(a), Vector(b)
    base_ = tip - direction * neck
    polygon([start - across * shaft, base_ - across * shaft, base_ - across * head, tip,
             base_ + across * head, base_ + across * shaft, start + across * shaft], shade)


def flake(polygon, line, cx, cy, arms, bar, twig, shade=0, twig_shade=10, hub=.0):
    """Snowflake. arms = [(angle, reach)]; twigs sit at .52 and .78 of each arm, .46 and .30 of its length."""
    for angle, reach in arms:
        x, y = cos(angle), sin(angle)
        line((cx, cy), (cx + reach * x, cy + reach * y), bar, shade)
        disc(polygon, cx + reach * x, cy + reach * y, bar / 2, shade, 8)
        for side in (-1, 1):
            for at, length in ((.52, .46), (.78, .30)):
                a = angle + side * .85
                px, py = cx + reach * at * x, cy + reach * at * y
                line((px, py), (px + reach * length * cos(a), py + reach * length * sin(a)), twig, twig_shade)
    if hub:
        polygon([(cx + hub * cos(i * pi / 3 + pi / 6), cy + hub * sin(i * pi / 3 + pi / 6)) for i in range(6)], shade)


def six_arms(reach, start=0.0):
    return [(start + i * pi / 3, reach) for i in range(6)]


# ---- Common top emblems: ONE shared texture per style (owner 2026-11-22), the same on all 7 tiers. -----------
# Drawn large and bold round the centre; each tier's pips simply sit on top, so strokes avoid being hidden whole.

def pebble(P, L):
    """Chiselled stone: soft corner facets and a crack network radiating from the centre."""
    P([(-1.0, 1.0), (-.46, 1.0), (-1.0, .46)], 214)
    P([(1.0, -1.0), (.46, -1.0), (1.0, -.46)], 214)

    def crack(start, end, width, forks, seed):
        rnd = Random(seed)
        (x0, y0), (x1, y1) = start, end
        dx, dy = x1 - x0, y1 - y0
        length = hypot(dx, dy)
        nx, ny = -dy / length, dx / length
        n = max(2, round(length / .24))
        points = [(x0, y0)] + [(x0 + dx * i / n + nx * rnd.uniform(-.06, .06),
                                y0 + dy * i / n + ny * rnd.uniform(-.06, .06)) for i in range(1, n)] + [(x1, y1)]
        stroke(P, L, points, width, 35)
        for at, side, size in forks:
            px, py = points[min(n - 1, max(1, round(at * n)))]
            a = atan2(dy, dx) + side * .75
            stroke(P, L, [(px, py), (px + size * cos(a), py + size * sin(a))], width * .62, 35)

    for deg, forks in ((20, ((.6, 1, .30),)), (82, ((.55, -1, .28),)), (140, ((.6, 1, .30),)),
                       (205, ((.55, -1, .30),)), (265, ((.6, 1, .28),)), (328, ((.55, -1, .30),))):
        a = deg * pi / 180
        crack((0, 0), (.97 * cos(a), .97 * sin(a)), .2, forks, deg)


def needle(P, L):
    """Three tapered claw slashes."""
    p, _ = placed(P, L, 0, 0, 1, -.5)
    for x in (-.52, 0, .52):
        left = [(x + .14 * (2 * (i / 12) - 1) - .13 * (i / 12) ** .65, -1 + 2 * i / 12) for i in range(13)]
        right = [(x + .14 * (2 * (i / 12) - 1) + .13 * (i / 12) ** .65, -1 + 2 * i / 12) for i in reversed(range(13))]
        p(left + right, 30)


def hammer(P, L):
    """Hammer: dark head + wood handle, head toward the top right."""
    p, ln = placed(P, L, 0, 0, 1, -.6)
    ln((0, -.92), (0, .55), .27, 35)
    ln((-.06, -.86), (-.06, .52), .07, 150)  # lit left edge of the handle
    disc(p, 0, -.92, .135, 35, 10)
    p([(-.5, .45), (.5, .45), (.53, .92), (-.47, .92)], 22)
    p([(-.47, .92), (.53, .92), (.52, .80), (-.48, .80)], 165)  # lit top bevel
    p([(-.5, .45), (-.47, .92), (-.37, .92), (-.40, .45)], 150)


def twinshot(P, L):
    """Two arrows flanking the diagonal."""
    p, _ = placed(P, L, 0, 0, 1, -pi / 4)
    for x in (-.53, .53):
        arrow(p, (x, -.88), (x, .88), 40)


def longshot(P, L):
    """Reticle: ring, ticks down the axes, corner brackets."""
    points = [(.58 * cos(i * pi / 16), .58 * sin(i * pi / 16)) for i in range(32)]
    for i, point in enumerate(points):
        L(point, points[(i + 1) % 32], .13, 0)
    for x, y in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        L((x * .62, y * .62), (x, y), .14, 0)
    disc(P, 0, 0, .1, 0)
    for x in (-1, 1):
        for y in (-1, 1):
            L((x * .62, y * .98), (x * 1.02, y * .98), .13, 0)
            L((x * .98, y * 1.02), (x * .98, y * .62), .13, 0)


def chill(P, L):
    """Big snowflake."""
    flake(P, L, 0, 0, six_arms(.93), .15, .105, hub=.30)


def spark(P, L):
    """Bold bolt with thin burst shards either side."""
    for side in (-1, 1):
        for slope in (-.70, -.27, .27, .70):
            y = slope * .78
            P([(side * .78, y - .07), (side * 1.0, slope), (side * .78, y + .07)], 135)
    P([(-.12, .99), (.38, .99), (.12, .28), (.40, .28), (-.28, -.99), (-.12, -.16), (-.40, -.16)], 10)
    P([(-.12, .99), (.38, .99), (.33, .86), (-.17, .84)], 120)


ART = {"C01": pebble, "C02": needle, "C03": hammer, "C04": twinshot, "C05": longshot, "C06": chill, "C07": spark}


def top_texture(style, draw_art=None, *, palette=None):
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

    (draw_art or ART[style])(polygon, line)

    if palette is not None:
        return bytes(
            round(sum(palette[pixels[(2 * y + dy) * size + 2 * x + dx]][channel]
                      for dx in (0, 1) for dy in (0, 1)) / 4)
            for y in range(TEXTURE_SIZE) for x in range(TEXTURE_SIZE) for channel in range(3)
        )

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


def painted_material(source, name, body, mask, ink="#000000", path=None):
    """Top face: body colour lerped toward ink by (1 - shade/255), exactly as Visuals.topTexture does in game."""
    mat = material(source, name, body)
    image = bpy.data.images.new(name, TEXTURE_SIZE, TEXTURE_SIZE, alpha=False)
    rgb, ink_rgb = base._rgb(body), base._rgb(ink)
    rgba = []
    for row in range(TEXTURE_SIZE - 1, -1, -1):  # Blender stores the bottom row first.
        for shade in mask[row * TEXTURE_SIZE:(row + 1) * TEXTURE_SIZE]:
            k = shade / 255
            rgba.extend((*((c * k + i * (1 - k)) / 255 for c, i in zip(rgb, ink_rgb)), 1))
    image.pixels.foreach_set(rgba)
    image.update()
    if path:
        path.parent.mkdir(parents=True, exist_ok=True)
        image.filepath_raw = str(path)
        image.file_format = "PNG"
        image.save()
    image.pack()
    shader = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.extension = "EXTEND"
    mat.node_tree.nodes.active = tex
    mat.node_tree.links.new(tex.outputs["Color"], shader.inputs["Base Color"])
    return mat


def ice_accents():
    """A few big flat faceted ice blades on the top-back and bottom corners only (the sheet's clustered crystals).
    Each blade lies along one cube edge on the corner chamfer, two-peaked, never more than ~.2 stud off the cube,
    and clear of every pip (|u|,|v| <= .77) and of the snowflake."""
    mesh = base._Mesh()

    def blade(corner, axis, length, width, height, lean):
        s = Vector(corner)
        o0, o1 = [i for i in range(3) if i != axis]
        n, t, e = Vector(), Vector(), Vector()
        n[o0], n[o1] = s[o0], s[o1]
        t[o0], t[o1] = s[o0], -s[o1]
        e[axis] = -s[axis]
        n.normalize()
        t.normalize()
        c = Vector()
        c[axis], c[o0], c[o1] = s[axis] * 1.25, s[o0] * 1.15, s[o1] * 1.15
        c -= n * .05  # base sinks into the chamfer
        p = [c - e * .04, c + e * .3 * length + t * width, c + e * .3 * length - t * width, c + e * length]
        apex = [c + e * .22 * length + n * (height + .05) + t * lean * width * .3,
                c + e * .78 * length + n * (height * .45 + .05) - t * lean * width * .3]
        v = [mesh.v(q) for q in p + apex]
        inside = c + e * .45 * length
        for k, tri in enumerate(((0, 1, 4), (0, 4, 2), (4, 1, 5), (4, 5, 2), (1, 3, 5), (2, 5, 3))):
            pts = [v[i] for i in tri]
            if (pts[1].co - pts[0].co).cross(pts[2].co - pts[0].co).dot(sum((q.co for q in pts), Vector()) / 3 - inside) < 0:
                pts.reverse()
            mesh.f(pts, "right").material_index = k % 2

    for corner, edges in (((-1, 1, 1), ((0, .8, .30, .22, 1), (2, .55, .26, .18, -1))),
                          ((1, 1, 1), ((0, .6, .26, .18, -1), (2, .85, .30, .24, 1))),
                          ((1, -1, -1), ((2, .85, .30, .24, -1), (0, .60, .28, .20, 1))),
                          ((-1, -1, -1), ((0, .8, .30, .22, -1), (2, .5, .24, .16, 1))),
                          ((1, 1, -1), ((1, .65, .28, .20, 1), (2, .5, .24, .16, -1)))):
        for axis, length, width, height, lean in edges:
            blade(corner, axis, length * 1.15, width, height, lean)
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
    for (name, (body, fallback, ink)), mask in zip(STYLES.items(), masks):
        rows.extend([f'\t\t{name[:3]} = {{', f'\t\t\tBody = "{body}",',
                     f'\t\t\tMark = "{fallback}",', f'\t\t\tInk = "{ink}",', f'\t\t\tTexture = "{texture_packet(mask)}",', "\t\t},"])
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


def preview_setup(scene):
    """Cycles preview: soft sky light plus one sun, so a face renders near its albedo like the sheets (the old
    Workbench studio light dimmed every face to ~0.4-0.85x and tinted the bevel)."""
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 3
    scene.view_settings.view_transform = "Standard"
    world = scene.world = bpy.data.worlds.new("Preview sky")
    world.use_nodes = True
    nodes, links = world.node_tree.nodes, world.node_tree.links
    nodes.clear()
    sky = nodes.new("ShaderNodeBackground")
    sky.inputs["Color"].default_value = (.82, .83, .88, 1)
    sky.inputs["Strength"].default_value = .62
    backdrop = nodes.new("ShaderNodeBackground")
    backdrop.inputs["Color"].default_value = (.60, .62, .70, 1)  # camera sees a soft lavender-grey, like the sheets
    backdrop.inputs["Strength"].default_value = 1
    ray = nodes.new("ShaderNodeLightPath")
    mix = nodes.new("ShaderNodeMixShader")
    out = nodes.new("ShaderNodeOutputWorld")
    links.new(ray.outputs["Is Camera Ray"], mix.inputs["Fac"])
    links.new(sky.outputs["Background"], mix.inputs[1])
    links.new(backdrop.outputs["Background"], mix.inputs[2])
    links.new(mix.outputs["Shader"], out.inputs["Surface"])
    sun = bpy.data.objects.new("Preview sun", bpy.data.lights.new("Preview sun", "SUN"))
    sun.data.energy, sun.data.angle = 2.4, .35
    sun.location = (0, 0, 5)
    sun.rotation_euler = (.75, .35, -.75)
    scene.collection.objects.link(sun)


def main(full=False):
    with bpy.data.libraries.load(str(SOURCE)) as (source, output):
        output.objects = ["Common_Body", "Common_Pips"]
    original_body, original_pips = output.objects
    assert base.core_hash({"Body": original_body, "Pips": original_pips}) == BASE_SPEC["core_hash"]
    body_source = original_body.data.materials[0]
    pip_source = original_pips.data.materials[0]
    shade = [material(body_source, f"Body shade {i}", tint("#C0C0C0", f))
             for i, f in enumerate((*SHADES, 1.0))]
    dark = material(pip_source, "Pips", "#0E0E0E")  # Common_Pips colour (dice_params COLOURS)
    star = [dark, dark]  # tier-7 star is black like every Common pip (owner 2026-11-22)
    shells, marks = [], []
    for tier in range(1, 8):
        body, face_marks = shell(original_body, tier)
        shells.append(finish(body, f"Tier {tier} Body", shade))
        marks.append(finish(face_marks, f"Tier {tier} Marks", star if tier == 7 else [dark]))
        verify_body(shells[-1], marks[-1], tier)
    masks = [top_texture(name[:3]) for name in STYLES]  # one texture per style, shared by all 7 tiers
    painted = [painted_material(body_source, f"{name}_TopDesign", body, mask, ink,
                                OUTPUT / name / "textures" / f"{name}_Top.png" if full else None)
               for (name, (body, _, ink)), mask in zip(STYLES.items(), masks)]
    ice = finish(ice_accents(), "C06_IceChips", [
        material(body_source, "Ice facet blue", ICE_FACETS[0], .35),
        material(body_source, "Ice facet cyan", ICE_FACETS[1], .35),
    ])
    if not full:
        scene = bpy.data.scenes.new("Common Variant Review")
        bpy.context.window.scene = scene
        for i, (name, (body, _, _)) in enumerate(STYLES.items()):
            for row, tier in enumerate((0, 5, 6)):
                for obj in variant_objects(name, body, shells[tier], marks[tier], painted[i], ice, body_source):
                    scene.collection.objects.link(obj)
                    obj.location = (i * 3.2, row * 3.2, 0)
        return
    write_game_data(shells, marks, masks, ice)
    prior = bpy.context.window.scene
    for i, (name, (body, _, _)) in enumerate(STYLES.items()):
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
        preview_setup(scene)
        scene.render.image_settings.file_format = "PNG"
        scene.render.resolution_percentage = 100
        report = {"source": "Common.blend", "base_triangles": 2134, "budget": BUDGET,
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
            assert total <= BUDGET, (variant, total)
            report["tiers"][tier] = {"pips_per_face": tier if tier < 7 else 0, "stars_per_face": int(tier == 7),
                                      "triangles": total, "difference_from_base": total - 2134, "parts": counts}
            export(scene, exports, variant, objs)
            render(scene, previews / f"T{tier}_three_quarter.png", VIEWS["three_quarter"], 512)
            render(scene, previews / f"T{tier}_top.png", VIEWS["top"], 512)
            if tier == 1:
                for label, direction in list(VIEWS.items())[1:]:
                    if label != "top":
                        render(scene, previews / f"T1_{label}.png", direction, 360)
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
    for i, factor in enumerate(SHADES):
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
