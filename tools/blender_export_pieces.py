"""Rebuild the Chess 3D procedural piece set in Blender and export pieces.glb.

The script creates one object per piece (Pawn, Knight, Bishop, Rook, Queen,
King) from the same profile curves the game uses, so you can refine the
models in Blender and load the result back into the game as a PieceSet.

Run it from a terminal:

    blender --background --python tools/blender_export_pieces.py -- [output.glb] [segments]

or open it in Blender's Text Editor and press "Run Script" (the pieces are
added to a "ChessPieces" collection in the current scene and exported next
to the .blend file, or to your home folder if the file is unsaved).

Conventions (they match the game and PieceSet.from_glb):
  * one square = 1 Blender unit; each piece stands on Z = 0, centered on its
    own origin, with its front toward -Y (which becomes +Z in glTF / Godot);
  * objects are named after the piece; keep those names when you edit;
  * materials are named "body", "felt" and "accent" - the game swaps them
    for its own white / black / felt materials by name.

Geometry is built with plain Python (no bpy) in the game's coordinate system
(X right, Y up, Z front) and only converted to Blender meshes at the end, so
`build_all_pieces()` can be tested without Blender.
"""

import json
import math
import os
import sys

# --- PROFILE DATA BEGIN (generated from pieces/piece_profiles.gd by
#     tools/sync_blender_profiles.gd - edit the .gd file, not this block) ---
DATA = json.loads(r'''
{
  "segments": 32,
  "pieces": {
    "pawn": {
      "base_radius": 0.27,
      "height": 0.74,
      "profile": [[0.27,0.02],[0.27,0.065],[0.245,0.095],[0.2,0.115],[0.2,0.135],[0.165,0.16],[0.125,0.215],[0.098,0.3],[0.085,0.4],[0.082,0.44],[0.15,0.458],[0.16,0.475],[0.15,0.492],[0.085,0.505],[0.075,0.52],[0.0803,0.5192],[0.1031,0.5443],[0.1183,0.5745],[0.1248,0.6077],[0.1222,0.6415],[0.1106,0.6733],[0.0909,0.7008],[0.0646,0.722],[0.0335,0.7354],[0.0,0.74]],
      "felt": [[0.0,0.0],[0.25,0.0],[0.27,0.02]]
    },
    "knight": {
      "base_radius": 0.31,
      "height": 0.97,
      "profile": [[0.31,0.02],[0.31,0.07],[0.285,0.105],[0.235,0.125],[0.235,0.15],[0.245,0.195],[0.23,0.22],[0.0,0.22]],
      "felt": [[0.0,0.0],[0.29,0.0],[0.31,0.02]]
    },
    "bishop": {
      "base_radius": 0.31,
      "height": 1.09,
      "profile": [[0.31,0.02],[0.31,0.07],[0.285,0.105],[0.235,0.125],[0.235,0.15],[0.195,0.18],[0.14,0.26],[0.105,0.4],[0.088,0.56],[0.085,0.61],[0.165,0.628],[0.175,0.645],[0.165,0.662],[0.09,0.675],[0.082,0.7],[0.115,0.735],[0.145,0.79],[0.15,0.83],[0.135,0.89],[0.1,0.95],[0.06,0.99],[0.03,1.005],[0.021,1.0086],[0.0344,1.0209],[0.0414,1.0377],[0.0406,1.0559],[0.0322,1.072],[0.0177,1.0831],[0.0,1.087]],
      "felt": [[0.0,0.0],[0.29,0.0],[0.31,0.02]]
    },
    "rook": {
      "base_radius": 0.31,
      "height": 0.82,
      "profile": [[0.31,0.02],[0.31,0.07],[0.285,0.105],[0.235,0.125],[0.235,0.15],[0.2,0.18],[0.185,0.25],[0.175,0.4],[0.17,0.54],[0.215,0.575],[0.245,0.6],[0.245,0.7],[0.17,0.7],[0.17,0.65],[0.0,0.65]],
      "felt": [[0.0,0.0],[0.29,0.0],[0.31,0.02]]
    },
    "queen": {
      "base_radius": 0.34,
      "height": 1.22,
      "profile": [[0.34,0.02],[0.34,0.075],[0.315,0.11],[0.26,0.13],[0.26,0.158],[0.215,0.19],[0.155,0.28],[0.118,0.45],[0.098,0.65],[0.092,0.77],[0.18,0.79],[0.192,0.808],[0.18,0.826],[0.1,0.84],[0.09,0.87],[0.105,0.92],[0.14,0.99],[0.2,1.06],[0.2,1.075],[0.16,1.075],[0.11,1.1],[0.05,1.118],[0.0,1.122]],
      "felt": [[0.0,0.0],[0.32,0.0],[0.34,0.02]]
    },
    "king": {
      "base_radius": 0.35,
      "height": 1.41,
      "profile": [[0.35,0.02],[0.35,0.075],[0.325,0.11],[0.268,0.13],[0.268,0.158],[0.222,0.19],[0.16,0.285],[0.122,0.46],[0.102,0.68],[0.097,0.81],[0.188,0.83],[0.2,0.848],[0.188,0.866],[0.105,0.88],[0.095,0.91],[0.11,0.96],[0.15,1.04],[0.195,1.1],[0.195,1.118],[0.15,1.125],[0.09,1.15],[0.045,1.16],[0.0,1.162]],
      "felt": [[0.0,0.0],[0.33,0.0],[0.35,0.02]]
    }
  },
  "rook_merlons": {
    "count": 6,
    "inner": 0.17,
    "outer": 0.245,
    "bottom": 0.7,
    "top": 0.82,
    "fill": 0.62
  },
  "bishop_slit": {
    "angle_deg": 50.0,
    "width": 0.032,
    "origin": [0.0,0.87,0.02]
  },
  "queen_pearls": {
    "count": 8,
    "radius": 0.036,
    "ring_radius": 0.18,
    "height": 1.095,
    "top_radius": 0.052,
    "top_height": 1.165
  },
  "king_cross": {
    "upright": [0.055,0.26,0.05],
    "upright_y": 1.28,
    "bar": [0.17,0.055,0.05],
    "bar_y": 1.31
  },
  "knight_head": {
    "outline": [[0.19,0.2],[0.215,0.36],[0.205,0.52],[0.165,0.68],[0.095,0.82],[0.035,0.9],[0.03,0.97],[-0.035,0.905],[-0.1,0.86],[-0.19,0.76],[-0.265,0.645],[-0.3,0.57],[-0.28,0.51],[-0.22,0.498],[-0.14,0.535],[-0.08,0.555],[-0.105,0.44],[-0.16,0.32],[-0.19,0.2]],
    "depth": 0.217,
    "bevel": 0.028
  }
}
''')
# --- PROFILE DATA END ---

MATERIALS = ["body", "felt", "accent"]
MATERIAL_COLORS = {
    "body": (0.85, 0.80, 0.70, 1.0),
    "felt": (0.07, 0.22, 0.12, 1.0),
    "accent": (0.10, 0.09, 0.08, 1.0),
}
BODY, FELT, ACCENT = 0, 1, 2
PIECE_ORDER = ["pawn", "knight", "bishop", "rook", "queen", "king"]
SMOOTH_ANGLE_DEG = 40.0


class Geometry:
    """A polygon soup: vertices (x, y, z) in game coordinates, faces as
    vertex-index lists, and one material index per face."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.materials = []

    def add_vert(self, x, y, z):
        self.verts.append((float(x), float(y), float(z)))
        return len(self.verts) - 1

    def add_face(self, indices, material):
        # Skip faces that collapsed to a line or a point.
        if len(set(indices)) >= 3:
            self.faces.append(list(indices))
            self.materials.append(material)

    def bounds(self):
        xs, ys, zs = zip(*self.verts)
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


def add_lathe(geo, profile, segments, material):
    """Revolve (radius, height) points around the Y axis."""
    rings = []
    for radius, height in profile:
        if radius < 1e-9:
            rings.append([geo.add_vert(0.0, height, 0.0)])
        else:
            ring = []
            for j in range(segments):
                a = 2.0 * math.pi * j / segments
                ring.append(geo.add_vert(radius * math.cos(a), height, radius * math.sin(a)))
            rings.append(ring)
    for lower, upper in zip(rings, rings[1:]):
        for j in range(segments):
            k = (j + 1) % segments
            a = lower[j % len(lower)]
            b = lower[k % len(lower)]
            c = upper[k % len(upper)]
            d = upper[j % len(upper)]
            if len(lower) == 1 and len(upper) == 1:
                continue
            if len(lower) == 1:
                geo.add_face([a, c, d], material)
            elif len(upper) == 1:
                geo.add_face([a, b, c], material)
            else:
                geo.add_face([a, b, c, d], material)


def add_ball(geo, center, radius, segments, rings, material):
    profile = []
    for i in range(rings + 1):
        t = -math.pi / 2.0 + math.pi * i / rings
        profile.append((max(0.0, math.cos(t)) * radius, center[1] + math.sin(t) * radius))
    start = len(geo.verts)
    add_lathe(geo, profile, segments, material)
    for i in range(start, len(geo.verts)):
        x, y, z = geo.verts[i]
        geo.verts[i] = (x + center[0], y, z + center[2])


def add_box(geo, center, size, material):
    hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    cx, cy, cz = center
    v = [geo.add_vert(cx + sx * hx, cy + sy * hy, cz + sz * hz)
         for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    for quad in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        geo.add_face([v[i] for i in quad], material)


def add_arc_block(geo, r_in, r_out, y0, y1, a0, a1, steps, material):
    """A block bent around the Y axis (one rook merlon)."""
    cols = []
    for k in range(steps + 1):
        a = a0 + (a1 - a0) * k / steps
        c, s = math.cos(a), math.sin(a)
        cols.append((
            geo.add_vert(c * r_in, y0, s * r_in), geo.add_vert(c * r_out, y0, s * r_out),
            geo.add_vert(c * r_out, y1, s * r_out), geo.add_vert(c * r_in, y1, s * r_in)))
    for p, q in zip(cols, cols[1:]):
        geo.add_face([p[1], q[1], q[2], p[2]], material)  # outer wall
        geo.add_face([p[0], p[3], q[3], q[0]], material)  # inner wall
        geo.add_face([p[3], p[2], q[2], q[3]], material)  # top
        geo.add_face([p[0], q[0], q[1], p[1]], material)  # bottom
    geo.add_face(list(cols[0]), material)
    geo.add_face(list(reversed(cols[-1])), material)


def add_beveled_extrusion(geo, outline, depth, bevel, material):
    """Extrude an (x, y) outline along Z with chamfered faces (the knight)."""
    pts = [tuple(p) for p in outline]
    area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:] + pts[:1]))
    if area < 0:
        pts.reverse()  # make it counter-clockwise
    n = len(pts)

    def edge_normal(i):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % n]
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy) or 1.0
        return dy / length, -dx / length

    inset = []
    for i in range(n):
        px, py = edge_normal((i - 1) % n)
        nx, ny = edge_normal(i)
        ax, ay = px + nx, py + ny
        length = math.hypot(ax, ay)
        if length < 1e-9:
            ax, ay = nx, ny
        else:
            ax, ay = ax / length, ay / length
        miter = min(1.0 / max(0.5, ax * nx + ay * ny), 2.0)
        inset.append((pts[i][0] - ax * bevel * miter, pts[i][1] - ay * bevel * miter))

    half = depth / 2.0
    wall = half - bevel
    front_face = [geo.add_vert(x, y, half) for x, y in inset]
    front_wall = [geo.add_vert(x, y, wall) for x, y in pts]
    back_wall = [geo.add_vert(x, y, -wall) for x, y in pts]
    back_face = [geo.add_vert(x, y, -half) for x, y in inset]
    geo.add_face(front_face, material)
    geo.add_face(list(reversed(back_face)), material)
    for i in range(n):
        j = (i + 1) % n
        geo.add_face([front_face[i], front_wall[i], front_wall[j], front_face[j]], material)
        geo.add_face([front_wall[i], back_wall[i], back_wall[j], front_wall[j]], material)
        geo.add_face([back_wall[i], back_face[i], back_face[j], back_wall[j]], material)


def build_piece(name, segments=None):
    """Geometry for one piece, in game coordinates (Y up, front toward +Z).
    The bishop's mitre slit is cut later with a Blender boolean."""
    segments = segments or DATA["segments"]
    piece = DATA["pieces"][name]
    geo = Geometry()
    add_lathe(geo, piece["felt"], segments, FELT)
    add_lathe(geo, piece["profile"], segments, BODY)

    if name == "rook":
        m = DATA["rook_merlons"]
        slot = 2.0 * math.pi / m["count"]
        width = slot * m["fill"]
        for i in range(m["count"]):
            mid = slot * (i + 0.5)
            add_arc_block(geo, m["inner"], m["outer"], m["bottom"], m["top"],
                          mid - width / 2.0, mid + width / 2.0, 3, BODY)
    elif name == "queen":
        q = DATA["queen_pearls"]
        for i in range(q["count"]):
            a = 2.0 * math.pi * i / q["count"]
            add_ball(geo, (math.cos(a) * q["ring_radius"], q["height"], math.sin(a) * q["ring_radius"]),
                     q["radius"], 10, 5, BODY)
        add_ball(geo, (0.0, q["top_height"], 0.0), q["top_radius"], 12, 6, BODY)
    elif name == "king":
        k = DATA["king_cross"]
        add_box(geo, (0.0, k["upright_y"], 0.0), k["upright"], BODY)
        add_box(geo, (0.0, k["bar_y"], 0.0), k["bar"], BODY)
    elif name == "knight":
        h = DATA["knight_head"]
        add_beveled_extrusion(geo, h["outline"], h["depth"], h["bevel"], BODY)
    return geo


def bishop_slit_box():
    """The slab that is cut out of the bishop's head, as a box Geometry."""
    slit = DATA["bishop_slit"]
    angle = math.radians(slit["angle_deg"])
    along = (0.0, math.sin(angle), math.cos(angle))    # direction the slit runs
    across = (0.0, math.cos(angle), -math.sin(angle))  # normal of the slab
    ox, oy, oz = slit["origin"]
    length, half_w, half_x = 0.6, slit["width"] / 2.0, 0.5
    geo = Geometry()
    v = []
    for sx in (-1, 1):
        for t in (0.0, length):
            for sw in (-1, 1):
                v.append(geo.add_vert(
                    ox + sx * half_x,
                    oy + along[1] * t + across[1] * sw * half_w,
                    oz + along[2] * t + across[2] * sw * half_w))
    for quad in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        geo.add_face([v[i] for i in quad], ACCENT)
    return geo


def build_all_pieces(segments=None):
    """{"Pawn": Geometry, ...} for the whole set (no Blender needed)."""
    return {name.capitalize(): build_piece(name, segments) for name in PIECE_ORDER}


# ---------------------------------------------------------------- Blender ---

def to_blender(v):
    """Game / glTF coordinates (Y up, +Z front) -> Blender (Z up, -Y front)."""
    return (v[0], -v[2], v[1])


def _make_object(bpy, bmesh, name, geo, materials, collection):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([to_blender(v) for v in geo.verts], [], geo.faces)
    for material in materials:
        mesh.materials.append(material)
    for polygon, index in zip(mesh.polygons, geo.materials):
        polygon.material_index = index
    mesh.update()

    # Weld the seams between the parts and make every face point outward.
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    return obj


def _shade_smooth(mesh):
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    angle = math.radians(SMOOTH_ANGLE_DEG)
    if hasattr(mesh, "set_sharp_from_angle"):    # Blender 4.1+
        mesh.set_sharp_from_angle(angle=angle)
    elif hasattr(mesh, "use_auto_smooth"):       # Blender 2.8 - 4.0
        mesh.use_auto_smooth = True
        mesh.auto_smooth_angle = angle


def _cut_bishop_slit(bpy, bmesh, bishop, materials, collection):
    cutter = _make_object(bpy, bmesh, "BishopSlitCutter", bishop_slit_box(), materials, collection)
    modifier = bishop.modifiers.new("MitreSlit", "BOOLEAN")
    modifier.operation = "DIFFERENCE"
    modifier.object = cutter
    bpy.context.view_layer.objects.active = bishop
    bpy.ops.object.select_all(action="DESELECT")
    bishop.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def create_in_blender(segments=None):
    """Creates the piece objects in a "ChessPieces" collection; returns them."""
    import bmesh
    import bpy

    collection = bpy.data.collections.get("ChessPieces")
    if collection is None:
        collection = bpy.data.collections.new("ChessPieces")
        bpy.context.scene.collection.children.link(collection)
    for old in list(collection.objects):
        bpy.data.objects.remove(old, do_unlink=True)

    materials = []
    for material_name in MATERIALS:
        material = bpy.data.materials.get(material_name) or bpy.data.materials.new(material_name)
        material.diffuse_color = MATERIAL_COLORS[material_name]
        materials.append(material)

    objects = []
    for index, name in enumerate(PIECE_ORDER):
        obj = _make_object(bpy, bmesh, name.capitalize(), build_piece(name, segments), materials, collection)
        if name == "bishop":
            _cut_bishop_slit(bpy, bmesh, obj, materials, collection)
        _shade_smooth(obj.data)
        obj.location = (index - 2.5, 0.0, 0.0)  # lay the set out in a row
        objects.append(obj)
    return objects


def export_glb(objects, path):
    import bpy

    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)


def main():
    import bpy

    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if args:
        path = os.path.abspath(args[0])
    else:
        folder = os.path.dirname(bpy.data.filepath) if bpy.data.filepath else os.path.expanduser("~")
        path = os.path.join(folder, "pieces.glb")
    segments = int(args[1]) if len(args) > 1 else None

    if bpy.app.background:
        # A fresh background session only holds the default cube, camera and light.
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj, do_unlink=True)

    objects = create_in_blender(segments)
    export_glb(objects, path)
    print("Exported %d pieces to %s" % (len(objects), path))


if __name__ == "__main__":
    main()
