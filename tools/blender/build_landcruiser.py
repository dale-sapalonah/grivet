"""Builds the police Land Cruiser (ten-seat troop carrier style) in Blender and
exports it as assets/models/police_landcruiser.glb for PoliceTruck.

Run headless (no window):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P tools/blender/build_landcruiser.py -- assets/models/police_landcruiser.glb

Two objects: "Body" (everything painted, vertex colours are the real colours)
and "Glass". Bevelled panels and rounded roof edges, wheel arches cut into the
body with flares over them, round-shouldered tyres, tube bull bar and snorkel,
door seams, handles and a beltline crease. The light bar's lenses, the
lettering and the collision box stay in Godot (PoliceTruck). No maker's badge.

Coordinates below are Godot's (x right, y up, -z forward); g() converts.
Same dimensions as PoliceTruck: 5.2 long, 1.9 wide, roof at 2.08.
"""
import math
import sys

import bpy
import bmesh
from mathutils import Vector

out = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "police_landcruiser.glb"

LENGTH = 5.2
WIDTH = 1.9
HALF = LENGTH * 0.5
COWL_Z = -1.05
BONNET_TOP = 1.28
ROOF_TOP = 2.08
WHEELS_Z = (-HALF + 0.95, HALF - 1.05)

NAVY = (0.1, 0.16, 0.42)
BLACK = (0.05, 0.05, 0.055)
STEEL = (0.5, 0.52, 0.55)
WHITE = (0.95, 0.96, 0.97)
CHECK_BLUE = (0.1, 0.24, 0.66)
TYRE = (0.035, 0.035, 0.035)
LAMP = (0.92, 0.92, 0.88)
AMBER = (1.0, 0.55, 0.1)
RED = (0.65, 0.08, 0.05)
SEAM = (0.04, 0.06, 0.15)
GLASS = (0.04, 0.05, 0.07)


def g(x, y, z):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((x, -z, y))


def colorize(obj, color):
    mesh = obj.data
    attribute = mesh.color_attributes.get("Col") or mesh.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    mesh.color_attributes.active_color = attribute
    for loop in attribute.data:
        loop.color = (color[0], color[1], color[2], 1.0)


def finish(obj, color, bevel=0.0, segments=3, smooth_angle=0.7):
    """Bevel (rounded edges), apply everything, paint, smooth by angle."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    if bevel > 0.0:
        modifier = obj.modifiers.new("bevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = segments
        modifier.limit_method = "ANGLE"
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for modifier in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    colorize(obj, color)
    bpy.ops.object.shade_smooth_by_angle(angle=smooth_angle)
    obj.select_set(False)
    return obj


def box(center, size, color, bevel=0.02, segments=2, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=g(*center))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    rx, ry, rz = (math.radians(a) for a in rotation)
    obj.rotation_euler = (rx, -rz, ry)
    return finish(obj, color, bevel, segments)


def cylinder(center, radius, depth, color, axis="x", bevel=0.0, segments=3, vertices=24):
    """A cylinder along Godot's x, y or z axis."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=g(*center))
    obj = bpy.context.object
    # Blender's cylinder runs along its Z (Godot y).
    if axis == "x":
        obj.rotation_euler = (0, math.radians(90), 0)
    elif axis == "z":
        obj.rotation_euler = (math.radians(90), 0, 0)
    return finish(obj, color, bevel, segments)


def tube(a, b, radius, color):
    """A round tube from Godot point a to b (bull bar, snorkel)."""
    start, end = g(*a), g(*b)
    direction = end - start
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius, depth=direction.length, location=(start + end) * 0.5)
    obj = bpy.context.object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction.normalized())
    obj.rotation_mode = "XYZ"
    return finish(obj, color)


def sphere(center, radius, color):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=radius, location=g(*center))
    return finish(bpy.context.object, color)


def cut_arches(obj):
    """Wheel arches: cylinders subtracted from the lower body."""
    for z in WHEELS_Z:
        bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.52, depth=WIDTH + 0.4, location=g(0, 0.42, z))
        cutter = bpy.context.object
        cutter.rotation_euler = (0, math.radians(90), 0)
        modifier = obj.modifiers.new("arch", "BOOLEAN")
        modifier.operation = "DIFFERENCE"
        modifier.solver = "EXACT"
        modifier.object = cutter
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        bpy.data.objects.remove(cutter, do_unlink=True)


def join(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name
    joined.select_set(False)
    return joined


def build():
    body = []
    glass = []
    # --- The shell: lower body with arches cut, bonnet, tall body ----------------
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=g(0, 0.83, 0))
    lower = bpy.context.object
    lower.scale = (WIDTH, LENGTH, 0.62)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    cut_arches(lower)
    body.append(finish(lower, NAVY, bevel=0.06, segments=3))
    bonnet_length = HALF + COWL_Z
    body.append(box((0, (BONNET_TOP + 1.12) * 0.5, -HALF + bonnet_length * 0.5 - 0.02),
                    (WIDTH - 0.06, BONNET_TOP - 1.12, bonnet_length), NAVY, bevel=0.07, segments=3))
    body.append(box((0, BONNET_TOP + 0.02, -HALF + 0.6), (1.0, 0.06, 0.95), NAVY, bevel=0.03))  # bonnet bulge
    cab_length = HALF - COWL_Z
    body.append(box((0, (ROOF_TOP + 1.12) * 0.5, (HALF + COWL_Z) * 0.5), (WIDTH - 0.04, ROOF_TOP - 1.12, cab_length),
                    NAVY, bevel=0.12, segments=4))
    # Beltline crease and door seams: the subtle contours of the panels.
    for side in (-1.0, 1.0):
        x = side * (WIDTH * 0.5 - 0.005)
        body.append(box((x, 1.18, 0.1), (0.03, 0.035, LENGTH - 0.5), NAVY, bevel=0.012))
        for z in (COWL_Z + 0.02, COWL_Z + 1.0, COWL_Z + 1.95):
            body.append(box((side * (WIDTH * 0.5 + 0.004), 1.3, z), (0.012, 1.05, 0.012), SEAM, bevel=0.0))
        body.append(box((side * (WIDTH * 0.5 + 0.015), 1.24, COWL_Z + 0.85), (0.03, 0.03, 0.14), BLACK, bevel=0.01))  # handles
        body.append(box((side * (WIDTH * 0.5 + 0.015), 1.24, COWL_Z + 1.8), (0.03, 0.03, 0.14), BLACK, bevel=0.01))
    # --- Fender flares, side steps, mirrors -------------------------------------
    for side in (-1.0, 1.0):
        x = side * (WIDTH * 0.5 + 0.03)
        for z in WHEELS_Z:
            # A rounded flare following the arch: a squashed half ring.
            bpy.ops.mesh.primitive_torus_add(major_segments=24, minor_segments=8, major_radius=0.56, minor_radius=0.07,
                                             location=g(x, 0.42, z))
            flare = bpy.context.object
            flare.rotation_euler = (0, math.radians(90), 0)
            flare.scale = (1.0, 1.0, 0.7)
            mesh = bmesh.new()
            bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
            mesh.from_mesh(flare.data)
            bmesh.ops.delete(mesh, geom=[v for v in mesh.verts if v.co.z < 0.05], context="VERTS")  # top half only
            mesh.to_mesh(flare.data)
            mesh.free()
            body.append(finish(flare, BLACK))
        body.append(box((side * (WIDTH * 0.5 + 0.08), 0.5, -0.05), (0.22, 0.05, 2.0), BLACK, bevel=0.015))  # side step
        body.append(tube((side * (WIDTH * 0.5 - 0.02), 1.5, COWL_Z + 0.1), (side * (WIDTH * 0.5 + 0.12), 1.56, COWL_Z + 0.12), 0.015, BLACK))
        body.append(box((side * (WIDTH * 0.5 + 0.13), 1.58, COWL_Z + 0.12), (0.06, 0.16, 0.14), BLACK, bevel=0.025))  # mirror
    # --- Snorkel: a tube up the right windscreen pillar, its head over the roof ---
    x = WIDTH * 0.5 + 0.07
    body.append(tube((x, 1.0, COWL_Z - 0.3), (x, 1.3, COWL_Z - 0.12), 0.055, BLACK))
    body.append(tube((x, 1.3, COWL_Z - 0.12), (x, 2.22, COWL_Z + 0.06), 0.055, BLACK))
    body.append(box((x, 2.28, COWL_Z + 0.02), (0.13, 0.12, 0.22), BLACK, bevel=0.04))
    # --- Front: grille with slats, round lamps, bumper, tube bull bar ---------------
    body.append(box((0, 1.0, -HALF - 0.005), (1.1, 0.34, 0.03), BLACK, bevel=0.01))
    for y in (0.9, 0.98, 1.06, 1.14):
        body.append(box((0, y, -HALF - 0.02), (1.0, 0.025, 0.02), STEEL, bevel=0.0))
    for side in (-1.0, 1.0):
        body.append(cylinder((side * 0.66, 1.02, -HALF - 0.01), 0.12, 0.05, BLACK, axis="z", bevel=0.01))
        body.append(cylinder((side * 0.66, 1.02, -HALF - 0.035), 0.1, 0.02, LAMP, axis="z", bevel=0.005))
        body.append(box((side * 0.86, 0.86, -HALF - 0.01), (0.13, 0.07, 0.04), AMBER, bevel=0.01))
        body.append(box((side * 0.78, 1.0, HALF + 0.01), (0.17, 0.32, 0.04), RED, bevel=0.012))  # tail lamps
    body.append(box((0, 0.62, -HALF - 0.16), (WIDTH + 0.12, 0.26, 0.2), BLACK, bevel=0.04))  # bar base and bumper
    front = -HALF - 0.21
    for x in (-0.95, -0.42, 0.42, 0.95):
        body.append(tube((x, 0.72, front), (x, 1.3, front), 0.035, BLACK))
    body.append(tube((-0.95, 1.3, front), (0.95, 1.3, front), 0.035, BLACK))
    body.append(tube((-0.95, 1.05, front), (0.95, 1.05, front), 0.03, BLACK))
    for x in (-0.95, 0.95):
        body.append(sphere((x, 1.3, front), 0.036, BLACK))  # rounded corners of the hoop
    for x in (-0.22, 0.22):
        body.append(cylinder((x, 1.12, front - 0.05), 0.1, 0.1, BLACK, axis="z", bevel=0.02))  # spotlights
        body.append(cylinder((x, 1.12, front - 0.1), 0.085, 0.01, LAMP, axis="z"))
    body.append(box((0, 0.58, HALF + 0.06), (WIDTH + 0.02, 0.16, 0.12), BLACK, bevel=0.03))  # rear bumper
    # --- Wheels: round-shouldered tyres, steel rims, hubs ------------------------
    for side in (-1.0, 1.0):
        for z in WHEELS_Z:
            x = side * (WIDTH * 0.5 - 0.08)
            body.append(cylinder((x, 0.42, z), 0.42, 0.32, TYRE, bevel=0.08, segments=4, vertices=28))
            body.append(cylinder((x + side * 0.01, 0.42, z), 0.24, 0.31, STEEL, bevel=0.02, vertices=20))
            body.append(cylinder((x + side * 0.16, 0.42, z), 0.07, 0.03, BLACK, vertices=12))
    # --- Checker band, door emblem, light bar base -------------------------------
    square = 0.1
    for side in (-1.0, 1.0):
        x = side * (WIDTH * 0.5 + 0.003)
        z = COWL_Z + 0.95
        i = 0
        while z < HALF - 0.15:
            for row in range(2):
                white = (i + row) % 2 == 0
                body.append(box((x, 1.26 + row * square, z), (0.008, square, square), WHITE if white else CHECK_BLUE, bevel=0.0))
            z += square
            i += 1
        body.append(cylinder((x, 1.0, COWL_Z + 0.55), 0.13, 0.012, WHITE, vertices=24))
        body.append(cylinder((x + side * 0.004, 1.0, COWL_Z + 0.55), 0.08, 0.012, (0.75, 0.12, 0.1), vertices=20))
    body.append(box((0, ROOF_TOP + 0.03, COWL_Z + 0.35), (1.4, 0.06, 0.3), BLACK, bevel=0.02))
    # --- Glass, a touch proud of the panels --------------------------------------
    glass.append(box((0, 1.66, COWL_Z - 0.02), (WIDTH - 0.14, 0.6, 0.03), GLASS, bevel=0.02, rotation=(-6, 0, 0)))
    for side in (-1.0, 1.0):
        x = side * (WIDTH * 0.5 - 0.01)
        glass.append(box((x, 1.68, COWL_Z + 0.5), (0.03, 0.48, 0.8), GLASS, bevel=0.03))
        glass.append(box((x, 1.68, COWL_Z + 1.5), (0.03, 0.48, 0.8), GLASS, bevel=0.03))
        glass.append(box((x, 1.68, COWL_Z + 2.55), (0.03, 0.48, 1.0), GLASS, bevel=0.03))
    glass.append(box((0, 1.68, HALF + 0.0), (1.5, 0.48, 0.03), GLASS, bevel=0.03))
    join(body, "Body")
    join(glass, "Glass")


bpy.ops.wm.read_factory_settings(use_empty=True)
build()
for obj in list(bpy.data.objects):
    if obj.name not in ("Body", "Glass"):
        bpy.data.objects.remove(obj, do_unlink=True)
total = 0
for name in ("Body", "Glass"):
    tris = sum(len(p.vertices) - 2 for p in bpy.data.objects[name].data.polygons)
    total += tris
    print("PART %-6s %6d tris" % (name, tris))
print("TOTAL %d tris" % total)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=False, export_apply=True, export_yup=True,
                          export_vertex_color="ACTIVE", export_normals=True, export_materials="NONE")
print("EXPORTED", out)
