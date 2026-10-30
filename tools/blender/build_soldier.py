"""Builds an enemy's body parts in Blender and exports them as one glTF for
Grivet: assets/models/soldier_military.glb (riflemen, rushers),
assets/models/soldier_civilian.glb (machete gangs: T-shirt, shorts, sandals) or
assets/models/soldier_police.glb (the player's squadmate: police uniform).

Run headless (no window):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P tools/blender/build_soldier.py -- <out.glb> [--outfit civilian|police]

One object per Mannequin part (pelvis, torso, head, upper_arm_l ...), each in
its part's own frame (origin at its joint, limbs hanging down), so the game
swaps them in for the code-built parts and ragdolls, hit zones and poses all
keep working. Flesh and cloth are metaballs (overlapping blobs melt into one
seamless surface), decimated to a game budget; plates, pouches, helmet and
boots are bevelled hard pieces. Vertex colours carry a material CLASS, not a
colour (each channel 0 or 1, so sRGB/linear can't blur it); Mannequin repaints
the classes from the EnemyProfile (camo, gear colour, skin...).

Coordinates below are Godot's (x right, y up, -z forward); g() converts.
"""
import math
import sys

import bpy
import bmesh
from mathutils import Vector

out = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "soldier_military.glb"

OUTFIT = sys.argv[sys.argv.index("--outfit") + 1] if "--outfit" in sys.argv else "military"

# Material classes -> vertex colour code (see Mannequin.BODY_CLASSES). The
# civilian outfit reuses them: cloth = T-shirt, gear = shorts, gear_dark = hair,
# boots = sandal sole, sole = sandal strap.
CLASSES = {
    "cloth": (1, 0, 0), "gear": (0, 1, 0), "gear_dark": (0, 1, 1), "skin": (0, 0, 1),
    "gloves": (1, 1, 0), "boots": (1, 0, 1), "sole": (1, 1, 1), "eye": (0, 0, 0),
}
# Triangle budget per part (the whole soldier lands near 7k).
BUDGET = {"pelvis": 450, "torso": 1100, "head": 900, "upper_arm": 320, "lower_arm": 380, "thigh": 420, "shin": 520}
RESOLUTION = 0.009  # metaball surface sampling (m): smoother when smaller, then decimated
# A metaball's surface sits inside its element's radius (where the summed field
# reaches the threshold): elements are inflated by this so the surface lands on
# the radii given below (calibrated by measuring the exported parts).
RADIUS_GAIN = float(sys.argv[sys.argv.index("--gain") + 1]) if "--gain" in sys.argv else 1.5


def g(x, y, z):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((x, -z, y))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def colorize(obj, class_of):
    """Face-corner colour attribute 'Col': each face takes ONE class, from
    class_of(face centre, Godot coords). Per vertex, a triangle spanning two
    classes blended their codes and showed as white seams."""
    mesh = obj.data
    attribute = mesh.color_attributes.get("Col") or mesh.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    mesh.color_attributes.active_color = attribute
    for polygon in mesh.polygons:
        p = polygon.center
        code = CLASSES[class_of(Vector((p.x, p.z, -p.y)))]
        for loop in polygon.loop_indices:
            attribute.data[loop].color = (code[0], code[1], code[2], 1.0)


def organic(name, elements, budget, class_of=None, hems=()):
    """Metaball object from elements [(kind, godot centre, radius or (rx, ry, rz), class)];
    converted to a mesh, decimated to `budget` triangles, coloured by nearest
    element (or by class_of(godot position), e.g. a sleeve ending at a height).
    `hems` are Godot heights cut into the mesh after decimating, so a class
    edge there runs straight round the limb (coloured per face, a sleeve or
    boot top ending between decimated faces came out zigzag)."""
    ball = bpy.data.metaballs.new("mb_" + name)
    ball.resolution = RESOLUTION
    ball.render_resolution = RESOLUTION
    ball.threshold = 0.6
    obj = bpy.data.objects.new("mb_" + name, ball)
    bpy.context.collection.objects.link(obj)
    for kind, center, size, _klass in elements:
        element = ball.elements.new(type="BALL" if kind == "ball" else "ELLIPSOID")
        element.co = g(*center)
        element.stiffness = 2.0
        if kind == "ball":
            element.radius = size * RADIUS_GAIN
        else:
            rx, ry, rz = size
            r = max(rx, ry, rz)
            element.radius = r * RADIUS_GAIN
            # Blender axes: x, -z (godot) -> y, y (godot) -> z.
            element.size_x, element.size_y, element.size_z = rx / r, rz / r, ry / r
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    faces = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if faces > budget:
        decimate = obj.modifiers.new("decimate", "DECIMATE")
        decimate.ratio = budget / faces
        bpy.ops.object.modifier_apply(modifier=decimate.name)
    if hems:
        mesh = bmesh.new()
        mesh.from_mesh(obj.data)
        for y in hems:
            geom = mesh.verts[:] + mesh.edges[:] + mesh.faces[:]
            bmesh.ops.bisect_plane(mesh, geom=geom, plane_co=g(0, y, 0), plane_no=(0, 0, 1))
        bmesh.ops.triangulate(mesh, faces=mesh.faces[:])
        mesh.to_mesh(obj.data)
        mesh.free()

    colorize(obj, class_of or (lambda p: _nearest(elements, p)))
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    obj.select_set(False)
    return obj


def _nearest(elements, p):
    """The class of the element whose (scaled) centre is nearest p."""
    best, best_d = elements[0][3], 1e9
    for kind, center, size, klass in elements:
        radii = (size, size, size) if kind == "ball" else size
        d = Vector(((p.x - center[0]) / radii[0], (p.y - center[1]) / radii[1], (p.z - center[2]) / radii[2])).length
        if d < best_d:
            best, best_d = klass, d
    return best


def hard(kind, center, size, klass, rotation=(0, 0, 0), bevel=0.006):
    """A bevelled hard piece (box / cylinder / sphere / half-sphere / torus) in one class."""
    loc = g(*center)
    if kind == "box":
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
        bpy.context.object.scale = (size[0], size[2], size[1])
    elif kind == "cylinder":  # size: (radius x, height, radius z); axis along Godot Y
        bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=1.0, depth=1.0, location=loc)
        bpy.context.object.scale = (size[0], size[2], size[1])
    elif kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=14, ring_count=8, radius=1.0, location=loc)
        bpy.context.object.scale = (size[0], size[2], size[1])
    elif kind == "dome":  # helmet shell: the top half of a sphere, thickened
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=1.0, location=loc)
        obj = bpy.context.object
        mesh = bmesh.new()
        mesh.from_mesh(obj.data)
        bmesh.ops.delete(mesh, geom=[v for v in mesh.verts if v.co.z < -0.12], context="VERTS")
        mesh.to_mesh(obj.data)
        mesh.free()
        obj.scale = (size[0], size[2], size[1])
        solidify = obj.modifiers.new("solidify", "SOLIDIFY")
        solidify.thickness = 0.1
        bevel = 0.0
    elif kind == "torus":  # size: (major radius, minor radius, depth scale)
        bpy.ops.mesh.primitive_torus_add(major_segments=16, minor_segments=5, major_radius=size[0], minor_radius=size[1], location=loc)
        bpy.context.object.scale = (1.0, size[2], 1.0)
    obj = bpy.context.object
    rx, ry, rz = (math.radians(a) for a in rotation)
    obj.rotation_euler = (rx, -rz, ry)  # Godot -> Blender axes
    if bevel > 0.0:
        modifier = obj.modifiers.new("bevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        modifier.limit_method = "ANGLE"
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for modifier in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    colorize(obj, lambda p: klass)
    for polygon in obj.data.polygons:
        polygon.use_smooth = kind != "box"
    obj.select_set(False)
    return obj


def join(base, pieces):
    bpy.ops.object.select_all(action="DESELECT")
    for piece in pieces:
        piece.select_set(True)
    base.select_set(True)
    bpy.context.view_layer.objects.active = base
    bpy.ops.object.join()
    base.select_set(False)
    return base


def taper(y_top, y_bottom, r_top, r_bottom, klass, steps=7, depth=1.0, x=0.0, z=0.0):
    """A limb as a chain of blending balls from (y_top, r_top) to (y_bottom, r_bottom)."""
    out = []
    for i in range(steps):
        t = i / (steps - 1)
        r = r_top + (r_bottom - r_top) * t
        out.append(("ellipsoid", (x, y_top + (y_bottom - y_top) * t, z), (r, r * 1.05, r * depth), klass))
    return out


def military():
    """Rifleman / rusher: uniform, plate carrier, helmet, knee pads, gloves, boots."""
    # --- pelvis (origin: hips) -------------------------------------------------------------
    pelvis = organic("pelvis", [
        ("ellipsoid", (0, 0.05, 0), (0.16, 0.12, 0.122), "cloth"),
        ("ellipsoid", (0, -0.07, 0.01), (0.155, 0.08, 0.118), "cloth"),
    ], BUDGET["pelvis"])
    join(pelvis, [hard("torus", (0, 0.08, 0), (0.168, 0.024, 0.78), "gear_dark"),
                  hard("box", (0, 0.08, -0.137), (0.05, 0.04, 0.02), "gear"),
                  hard("box", (-0.16, 0.02, 0.03), (0.05, 0.09, 0.07), "gear"),
                  hard("box", (0.16, 0.02, 0.03), (0.05, 0.09, 0.07), "gear")])

    # --- torso (origin: spine, same as hips) ------------------------------------------------------
    torso = organic("torso", [
        ("ellipsoid", (0, 0.05, 0), (0.165, 0.11, 0.115), "cloth"),  # waist, down into the belt
        ("ellipsoid", (0, 0.16, 0), (0.172, 0.12, 0.118), "cloth"),
        ("ellipsoid", (0, 0.29, 0), (0.185, 0.13, 0.124), "cloth"),
        ("ellipsoid", (0, 0.41, 0), (0.205, 0.12, 0.132), "cloth"),
        ("ellipsoid", (-0.162, 0.45, 0), (0.076, 0.066, 0.078), "cloth"),
        ("ellipsoid", (0.162, 0.45, 0), (0.076, 0.066, 0.078), "cloth"),
        ("ellipsoid", (-0.085, 0.5, 0), (0.085, 0.045, 0.07), "cloth"),  # trapezius
        ("ellipsoid", (0.085, 0.5, 0), (0.085, 0.045, 0.07), "cloth"),
        ("ellipsoid", (0, 0.535, 0), (0.07, 0.05, 0.065), "cloth"),
    ], BUDGET["torso"])
    torso_gear = [hard("box", (0, 0.36, -0.118), (0.3, 0.3, 0.05), "gear", bevel=0.012),
                  hard("box", (0, 0.37, 0.118), (0.3, 0.32, 0.05), "gear", bevel=0.012),
                  hard("cylinder", (0, 0.25, 0), (0.168, 0.11, 0.138), "gear", bevel=0.0),
                  hard("box", (-0.11, 0.52, 0), (0.06, 0.03, 0.27), "gear"),
                  hard("box", (0.11, 0.52, 0), (0.06, 0.03, 0.27), "gear"),
                  hard("box", (-0.09, 0.4, 0.168), (0.08, 0.16, 0.05), "gear_dark"),
                  hard("cylinder", (-0.11, 0.56, 0.17), (0.006, 0.22, 0.006), "gloves", bevel=0.0)]
    for x in (-0.085, 0.0, 0.085):
        torso_gear.append(hard("box", (x, 0.29, -0.158), (0.065, 0.11, 0.045), "gear_dark"))
    join(torso, torso_gear)

    # --- head (origin: neck) -----------------------------------------------------------------------
    head = organic("head", [
        ("ellipsoid", (0, 0.02, 0), (0.05, 0.06, 0.05), "skin"),  # neck
        ("ellipsoid", (0, 0.15, 0.004), (0.083, 0.098, 0.098), "skin"),  # skull
        ("ellipsoid", (0, 0.085, -0.025), (0.064, 0.05, 0.072), "skin"),  # jaw
        ("ellipsoid", (0, 0.13, -0.097), (0.016, 0.03, 0.022), "skin"),  # nose
        ("ellipsoid", (0, 0.163, -0.086), (0.06, 0.016, 0.02), "skin"),  # brow
        ("ellipsoid", (-0.086, 0.13, 0.01), (0.014, 0.026, 0.02), "skin"),  # ears
        ("ellipsoid", (0.086, 0.13, 0.01), (0.014, 0.026, 0.02), "skin"),
    ], BUDGET["head"])
    join(head, [hard("sphere", (-0.032, 0.147, -0.088), (0.009, 0.009, 0.006), "eye", bevel=0.0),
                hard("sphere", (0.032, 0.147, -0.088), (0.009, 0.009, 0.006), "eye", bevel=0.0),
                hard("dome", (0, 0.16, 0.008), (0.127, 0.115, 0.135), "gear"),
                hard("torus", (0, 0.168, 0.008), (0.127, 0.012, 1.06), "gear_dark"),
                hard("box", (0, 0.225, -0.118), (0.05, 0.035, 0.03), "gear_dark", rotation=(20, 0, 0)),
                hard("box", (0.09, 0.12, 0.02), (0.016, 0.07, 0.014), "gear_dark"),
                hard("box", (-0.09, 0.12, 0.02), (0.016, 0.07, 0.014), "gear_dark")])

    # --- limbs, both sides (origins: shoulder, elbow, hip, knee) -----------------------------------------
    for side, suffix in ((-1.0, "_l"), (1.0, "_r")):
        organic("upper_arm" + suffix, [("ellipsoid", (-side * 0.02, -0.035, 0), (0.08, 0.072, 0.078), "cloth")]  # deltoid, leaning into the torso
                + taper(-0.07, -0.29, 0.066, 0.05, "cloth", depth=0.94), BUDGET["upper_arm"])

        organic("lower_arm" + suffix, [("ellipsoid", (0, 0.0, 0), (0.054, 0.052, 0.05), "cloth"),
                                       ("ellipsoid", (0, -0.08, 0), (0.062, 0.085, 0.058), "cloth")]
                + taper(-0.04, -0.24, 0.056, 0.04, "cloth", depth=0.88)
                + [("ellipsoid", (0, -0.29, -0.005), (0.04, 0.056, 0.032), "gloves"),
                   ("ellipsoid", (0, -0.33, -0.02), (0.034, 0.031, 0.026), "gloves")], BUDGET["lower_arm"],
                class_of=lambda p: "gloves" if p.y < -0.255 else "cloth", hems=(-0.255,))

        thigh = organic("thigh" + suffix, taper(0.03, -0.42, 0.102, 0.07, "cloth", steps=8, depth=0.96), BUDGET["thigh"])
        join(thigh, [hard("box", (side * 0.09, -0.24, 0), (0.03, 0.12, 0.095), "cloth")])

        shin = organic("shin" + suffix, [("ellipsoid", (0, 0.0, 0), (0.07, 0.07, 0.068), "cloth"),
                                         ("ellipsoid", (0, -0.13, 0.015), (0.08, 0.11, 0.08), "cloth")]  # calf
                       + taper(-0.05, -0.34, 0.076, 0.056, "cloth", depth=0.95)
                       + [("ellipsoid", (0, -0.4, 0), (0.058, 0.062, 0.058), "boots"),
                          ("ellipsoid", (0, -0.445, -0.06), (0.054, 0.036, 0.104), "boots")], BUDGET["shin"],
                       class_of=lambda p: "boots" if p.y < -0.33 else "cloth", hems=(-0.33,))
        join(shin, [hard("sphere", (0, -0.005, -0.058), (0.07, 0.078, 0.036), "gear", bevel=0.0)])
        join(shin, [hard("box", (0, -0.47, -0.045), (0.1, 0.02, 0.245), "sole", bevel=0.004)])


def civilian():
    """Machete gang member: T-shirt, shorts, bare arms and legs, rubber sandals.
    The bilum, its strap and the odd headband are added by Mannequin in code."""
    organic("pelvis", [("ellipsoid", (0, 0.05, 0), (0.158, 0.12, 0.118), "gear"),
                       ("ellipsoid", (0, -0.07, 0.01), (0.152, 0.08, 0.114), "gear")], BUDGET["pelvis"])
    organic("torso", [
        ("ellipsoid", (0, 0.05, 0), (0.16, 0.11, 0.11), "cloth"),  # waist, over the shorts
        ("ellipsoid", (0, 0.16, 0), (0.165, 0.12, 0.112), "cloth"),
        ("ellipsoid", (0, 0.29, 0), (0.178, 0.13, 0.118), "cloth"),
        ("ellipsoid", (0, 0.41, 0), (0.198, 0.12, 0.125), "cloth"),
        ("ellipsoid", (-0.16, 0.45, 0), (0.073, 0.064, 0.074), "cloth"),
        ("ellipsoid", (0.16, 0.45, 0), (0.073, 0.064, 0.074), "cloth"),
        ("ellipsoid", (-0.083, 0.5, 0), (0.082, 0.044, 0.068), "cloth"),  # trapezius
        ("ellipsoid", (0.083, 0.5, 0), (0.082, 0.044, 0.068), "cloth"),
        ("ellipsoid", (0, 0.535, 0), (0.065, 0.05, 0.06), "cloth"),
    ], BUDGET["torso"])
    head = organic("head", HEAD, BUDGET["head"])
    join(head, [hard("sphere", (-0.032, 0.147, -0.088), (0.009, 0.009, 0.006), "eye", bevel=0.0),
                hard("sphere", (0.032, 0.147, -0.088), (0.009, 0.009, 0.006), "eye", bevel=0.0),
                hard("dome", (0, 0.168, 0.008), (0.093, 0.09, 0.105), "gear_dark")])  # short tight hair
    for side, suffix in ((-1.0, "_l"), (1.0, "_r")):
        # Short sleeve over the shoulder, bare arm below it.
        organic("upper_arm" + suffix, [("ellipsoid", (-side * 0.02, -0.035, 0), (0.078, 0.07, 0.076), "cloth"),  # deltoid, leaning into the torso
                                       ("ellipsoid", (0, -0.09, 0), (0.072, 0.054, 0.068), "cloth")]
                + taper(-0.06, -0.29, 0.062, 0.047, "skin", depth=0.92), BUDGET["upper_arm"],
                class_of=lambda p: "cloth" if p.y > -0.13 else "skin", hems=(-0.13,))
        organic("lower_arm" + suffix, [("ellipsoid", (0, 0.0, 0), (0.05, 0.05, 0.047), "skin"),
                                       ("ellipsoid", (0, -0.08, 0), (0.058, 0.085, 0.054), "skin")]
                + taper(-0.04, -0.24, 0.053, 0.038, "skin", depth=0.88)
                + [("ellipsoid", (0, -0.29, -0.005), (0.037, 0.055, 0.03), "skin"),
                   ("ellipsoid", (0, -0.33, -0.02), (0.031, 0.03, 0.024), "skin")], BUDGET["lower_arm"])
        # Shorts to above the knee, bare leg below.
        organic("thigh" + suffix, taper(0.03, -0.25, 0.106, 0.09, "gear", steps=5, depth=0.97)
                + taper(-0.28, -0.42, 0.08, 0.064, "skin", steps=4, depth=0.93), BUDGET["thigh"],
                class_of=lambda p: "gear" if p.y > -0.27 else "skin", hems=(-0.27,))
        shin = organic("shin" + suffix, [("ellipsoid", (0, 0.0, 0), (0.07, 0.07, 0.068), "skin"),
                                         ("ellipsoid", (0, -0.13, 0.018), (0.074, 0.11, 0.076), "skin")]  # calf
                       + taper(0.0, -0.36, 0.07, 0.05, "skin", depth=0.93)
                       + [("ellipsoid", (0, -0.425, -0.05), (0.045, 0.03, 0.1), "skin")], BUDGET["shin"])
        join(shin, [hard("box", (0, -0.455, -0.045), (0.095, 0.014, 0.25), "boots", bevel=0.004),
                    hard("box", (0, -0.44, -0.12), (0.008, 0.03, 0.05), "sole", rotation=(30, 0, 0), bevel=0.0)])


def police():
    """Police officer (the player's side): light-blue short-sleeved shirt with
    pockets and dark epaulettes, navy trousers and duty belt, black boots, a
    navy beret pulled down to the right with a badge, a dark shoulder patch.
    Classes: cloth = shirt, gear = trousers, gear_dark = beret, belt,
    epaulettes, patch; gloves = badge and buckle metal; hands are skin."""
    pelvis = organic("pelvis", [("ellipsoid", (0, 0.05, 0), (0.16, 0.12, 0.12), "gear"),
                                ("ellipsoid", (0, -0.07, 0.01), (0.154, 0.08, 0.116), "gear")], BUDGET["pelvis"])
    join(pelvis, [hard("torus", (0, 0.08, 0), (0.163, 0.022, 0.78), "gear_dark"),
                  hard("box", (0, 0.08, -0.13), (0.055, 0.04, 0.016), "gloves"),
                  hard("box", (0.15, 0.05, 0.04), (0.05, 0.08, 0.06), "gear_dark"),
                  hard("box", (-0.15, 0.05, 0.04), (0.05, 0.08, 0.06), "gear_dark")])
    torso = organic("torso", [
        ("ellipsoid", (0, 0.05, 0), (0.162, 0.11, 0.112), "cloth"),  # waist, tucked into the belt
        ("ellipsoid", (0, 0.16, 0), (0.168, 0.12, 0.115), "cloth"),
        ("ellipsoid", (0, 0.29, 0), (0.182, 0.13, 0.121), "cloth"),
        ("ellipsoid", (0, 0.41, 0), (0.202, 0.12, 0.128), "cloth"),
        ("ellipsoid", (-0.162, 0.45, 0), (0.075, 0.065, 0.076), "cloth"),
        ("ellipsoid", (0.162, 0.45, 0), (0.075, 0.065, 0.076), "cloth"),
        ("ellipsoid", (-0.084, 0.5, 0), (0.084, 0.045, 0.07), "cloth"),  # trapezius
        ("ellipsoid", (0.084, 0.5, 0), (0.084, 0.045, 0.07), "cloth"),
        ("ellipsoid", (0, 0.535, 0), (0.066, 0.05, 0.062), "cloth"),
    ], BUDGET["torso"])
    shirt = []
    for x in (-0.085, 0.085):
        shirt.append(hard("box", (x, 0.36, -0.13), (0.075, 0.08, 0.012), "cloth", bevel=0.003))  # breast pocket
        shirt.append(hard("box", (x, 0.405, -0.134), (0.08, 0.022, 0.012), "cloth", bevel=0.003))  # flap
    for x in (-0.13, 0.13):
        shirt.append(hard("box", (x, 0.525, 0), (0.05, 0.012, 0.12), "gear_dark", rotation=(0, 0, -12 if x > 0 else 12)))  # epaulette
    shirt.append(hard("box", (-0.085, 0.43, -0.142), (0.07, 0.016, 0.006), "boots", bevel=0.0))  # name tag
    join(torso, shirt)
    head = organic("head", HEAD, BUDGET["head"])
    join(head, [hard("sphere", (-0.032, 0.147, -0.088), (0.009, 0.009, 0.006), "eye", bevel=0.0),
                hard("sphere", (0.032, 0.147, -0.088), (0.009, 0.009, 0.006), "eye", bevel=0.0),
                hard("dome", (0, 0.165, 0.008), (0.092, 0.088, 0.104), "gear_dark"),  # short hair under it
                hard("torus", (0, 0.19, 0.006), (0.094, 0.012, 1.1), "gear_dark"),  # beret band
                hard("sphere", (0.025, 0.215, 0.0), (0.118, 0.042, 0.122), "gear_dark", rotation=(0, 0, -14)),  # crown, down to the right
                hard("box", (-0.04, 0.205, -0.098), (0.026, 0.032, 0.008), "gloves", rotation=(-10, 0, 0))])  # badge
    for side, suffix in ((-1.0, "_l"), (1.0, "_r")):
        arm = organic("upper_arm" + suffix, [("ellipsoid", (-side * 0.02, -0.035, 0), (0.08, 0.072, 0.078), "cloth"),  # deltoid, leaning into the torso
                                             ("ellipsoid", (0, -0.09, 0), (0.074, 0.056, 0.07), "cloth")]
                      + taper(-0.06, -0.29, 0.062, 0.047, "skin", depth=0.92), BUDGET["upper_arm"],
                      class_of=lambda p: "cloth" if p.y > -0.14 else "skin", hems=(-0.14,))
        join(arm, [hard("box", (side * 0.074, -0.065, 0), (0.01, 0.07, 0.058), "gear_dark", bevel=0.003),  # shoulder patch
                   hard("box", (side * 0.08, -0.068, 0), (0.004, 0.03, 0.032), "gloves", bevel=0.0)])  # its emblem
        organic("lower_arm" + suffix, [("ellipsoid", (0, 0.0, 0), (0.05, 0.05, 0.047), "skin"),
                                       ("ellipsoid", (0, -0.08, 0), (0.058, 0.085, 0.054), "skin")]
                + taper(-0.04, -0.24, 0.053, 0.038, "skin", depth=0.88)
                + [("ellipsoid", (0, -0.29, -0.005), (0.038, 0.055, 0.031), "skin"),
                   ("ellipsoid", (0, -0.33, -0.02), (0.032, 0.03, 0.025), "skin")], BUDGET["lower_arm"])
        organic("thigh" + suffix, taper(0.03, -0.42, 0.1, 0.07, "gear", steps=8, depth=0.96), BUDGET["thigh"])
        shin = organic("shin" + suffix, [("ellipsoid", (0, 0.0, 0), (0.07, 0.07, 0.068), "gear"),
                                         ("ellipsoid", (0, -0.13, 0.015), (0.076, 0.11, 0.077), "gear")]
                       + taper(-0.05, -0.34, 0.072, 0.056, "gear", depth=0.95)
                       + [("ellipsoid", (0, -0.4, 0), (0.055, 0.06, 0.056), "boots"),
                          ("ellipsoid", (0, -0.445, -0.06), (0.052, 0.034, 0.1), "boots")], BUDGET["shin"],
                       class_of=lambda p: "boots" if p.y < -0.35 else "gear", hems=(-0.35,))
        join(shin, [hard("box", (0, -0.47, -0.045), (0.098, 0.018, 0.24), "sole", bevel=0.004)])


# The face and neck, shared by both outfits.
HEAD = [
    ("ellipsoid", (0, 0.02, 0), (0.05, 0.06, 0.05), "skin"),  # neck
    ("ellipsoid", (0, 0.15, 0.004), (0.083, 0.098, 0.098), "skin"),  # skull
    ("ellipsoid", (0, 0.085, -0.025), (0.064, 0.05, 0.072), "skin"),  # jaw
    ("ellipsoid", (0, 0.13, -0.097), (0.016, 0.03, 0.022), "skin"),  # nose
    ("ellipsoid", (0, 0.163, -0.086), (0.06, 0.016, 0.02), "skin"),  # brow
    ("ellipsoid", (-0.086, 0.13, 0.01), (0.014, 0.026, 0.02), "skin"),  # ears
    ("ellipsoid", (0.086, 0.13, 0.01), (0.014, 0.026, 0.02), "skin"),
]


reset()
{"civilian": civilian, "police": police}.get(OUTFIT, military)()

# Leftover metaball data and anything not a part goes before export.
parts = ["pelvis", "torso", "head"] + [p + s for p in ("upper_arm", "lower_arm", "thigh", "shin") for s in ("_l", "_r")]
for obj in list(bpy.data.objects):
    if obj.name not in parts:
        bpy.data.objects.remove(obj, do_unlink=True)
total = 0
for name in parts:
    obj = bpy.data.objects[name]
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    total += tris
    lo = [min(v.co[i] for v in obj.data.vertices) for i in range(3)]
    hi = [max(v.co[i] for v in obj.data.vertices) for i in range(3)]
    print("PART %-12s %5d tris  godot x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % (
        name, tris, lo[0], hi[0], lo[2], hi[2], -hi[1], -lo[1]))
print("TOTAL %d tris" % total)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=False, export_apply=True, export_yup=True,
                          export_vertex_color="ACTIVE", export_normals=True, export_materials="NONE")
print("EXPORTED", out)
