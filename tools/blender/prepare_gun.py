"""Prepares a downloaded gun (or grenade) model for Grivet: metres, muzzle
along the game's forward (-Z in Godot; +Y here) with the top up, the moving
parts as their own objects (named for the game: Magazine, Pump, Slide, Pin)
and everything else joined into Body, a PBR material made from the pack's
texture maps (shrunk; DirectX normals flipped to OpenGL), exported as GLB.

Skinned guns (Stein Games' Classic Weapons Pack: one mesh weighted to bones
MAGAZINE, SLIDE, ...) are split by each vertex's strongest bone; the
skeleton goes. Godot builds mesh LODs on import, so soldiers far away draw
fewer triangles.

Run headless (no window):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P tools/blender/prepare_gun.py -- <in.fbx> <out.glb> --forward -Y [--up Z] [--textures <dir>] [--texture 1024] [--part Magazine=Magazine,MAGAZINE,BULLET] [--part Pump=Fore_Stock] [--skip FRAME_LOD0] [--center]

--forward / --up: the muzzle direction and the top of the gun in the source
file (after import). --part Name=a,b: objects or bone groups a, b become one
object Name. --skip: source objects dropped. --center: the model's middle at the origin. Texture maps are found by name
in --textures: *Base_Color* / *_C (colour), *Metallic*, *Roughness*,
*Normal* / *_N (normal; DirectX unless the name has "OpenGL"), *RMAO*
(R roughness, G metallic, B occlusion).

The source files stay outside the repository (see Docs/AssetLicences.md).
"""
import os
import sys

import bpy
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
source, out = args[0], args[1]


def _option(name, default=""):
    return args[args.index(name) + 1] if name in args else default


FORWARD = _option("--forward", "+Y")
UP = _option("--up", "+Z")
TEXTURES = _option("--textures")
TEXTURE = int(_option("--texture", "1024"))
PARTS = {}
SKIP = set()
for i, arg in enumerate(args):
    if arg == "--part":
        name, members = args[i + 1].split("=")
        PARTS[name] = members.split(",")
    elif arg == "--skip":
        SKIP.update(args[i + 1].split(","))


def _axis(text):
    vector = Vector((0, 0, 0))
    vector["XYZ".index(text[-1].upper())] = -1.0 if text.startswith("-") else 1.0
    return vector


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=source)
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)
for obj in list(bpy.data.objects):
    if obj.name in SKIP or obj.type not in ("MESH", "ARMATURE"):
        bpy.data.objects.remove(obj, do_unlink=True)

# Meshes keep their rest shape: no armature deform, no parent transforms left.
for obj in bpy.data.objects:
    if obj.type == "MESH":
        for modifier in list(obj.modifiers):
            if modifier.type == "ARMATURE":
                obj.modifiers.remove(modifier)
        matrix = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = matrix
for obj in [o for o in bpy.data.objects if o.type == "ARMATURE"]:
    bpy.data.objects.remove(obj, do_unlink=True)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.select_all(action="DESELECT")

# Turn the gun so the muzzle is +Y and the top +Z (glTF/Godot: -Z and +Y).
forward = _axis(FORWARD)
up = _axis(UP)
side = forward.cross(up)
turn = Matrix((side, forward, up)).to_4x4()  # rows: source axes onto X, Y, Z
for obj in bpy.data.objects:
    obj.data.transform(turn)
    obj.data.update()
# --center: the whole model's bounding-box centre to the origin (grenades).
if "--center" in args:
    corners = [Vector(c) for o in bpy.data.objects for c in o.bound_box]
    middle = sum(corners, Vector()) / len(corners)
    low = Vector([min(c[i] for c in corners) for i in range(3)])
    high = Vector([max(c[i] for c in corners) for i in range(3)])
    for obj in bpy.data.objects:
        obj.data.transform(Matrix.Translation(-(low + high) / 2))
        obj.data.update()


def _split_by_groups(obj, wanted):
    """Moves the vertices whose strongest group is in `wanted` into a new object."""
    names = {g.index: g.name for g in obj.vertex_groups}
    picked = []
    for v in obj.data.vertices:
        if v.groups and names[max(v.groups, key=lambda g: g.weight).group] in wanted:
            picked.append(v.index)
    if not picked:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    for index in picked:
        obj.data.vertices[index].select = True
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_linked(delimit=set())  # whole pieces, no torn faces
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    created = [o for o in bpy.context.selected_objects if o != obj]
    return created[0] if created else None


def _join(objects, name):
    objects = [o for o in objects if o is not None]
    if not objects:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name
    return joined


made = {}
for part, members in PARTS.items():
    pieces = []
    for obj in list(bpy.data.objects):
        if obj.name in members:
            pieces.append(obj)
        elif obj.vertex_groups and any(g.name in members for g in obj.vertex_groups):
            pieces.append(_split_by_groups(obj, set(members)))
    made[part] = _join(pieces, part + "_part")
rest = [o for o in bpy.data.objects if o not in made.values()]
_join(rest, "Body")
for part, obj in made.items():
    if obj is not None:
        obj.name = part
for obj in bpy.data.objects:
    obj.vertex_groups.clear()
    # Pivot at the part's centre, so the game can move it from there.
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if obj.name != "Body":
        bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")

# --- Material ------------------------------------------------------------------


def _find(*keys):
    if not TEXTURES:
        return None
    for name in sorted(os.listdir(TEXTURES)):
        stem = os.path.splitext(name)[0].lower()
        if any(stem.endswith(k.lower()) or k.lower() in stem for k in keys):
            return os.path.join(TEXTURES, name)
    return None


def _image(path, color=True, flip_green=False):
    image = bpy.data.images.load(path)
    if image.size[0] > TEXTURE or image.size[1] > TEXTURE:
        image.scale(TEXTURE, TEXTURE)
    if flip_green:
        pixels = list(image.pixels)
        for i in range(1, len(pixels), 4):
            pixels[i] = 1.0 - pixels[i]
        image.pixels = pixels
    image.colorspace_settings.name = "sRGB" if color else "Non-Color"
    image.pack()
    return image


material = bpy.data.materials.new("Gun")
material.use_nodes = True
nodes = material.node_tree.nodes
links = material.node_tree.links
shader = nodes["Principled BSDF"]
color = _find("base_color", "_c")
if color:
    node = nodes.new("ShaderNodeTexImage")
    node.image = _image(color)
    links.new(node.outputs["Color"], shader.inputs["Base Color"])
rmao = _find("rmao")
if rmao:
    node = nodes.new("ShaderNodeTexImage")
    node.image = _image(rmao, color=False)
    split = nodes.new("ShaderNodeSeparateColor")
    links.new(node.outputs["Color"], split.inputs["Color"])
    links.new(split.outputs["Red"], shader.inputs["Roughness"])
    links.new(split.outputs["Green"], shader.inputs["Metallic"])
else:
    for key, socket in (("metallic", "Metallic"), ("roughness", "Roughness")):
        path = _find(key)
        if path:
            node = nodes.new("ShaderNodeTexImage")
            node.image = _image(path, color=False)
            links.new(node.outputs["Color"], shader.inputs[socket])
normal = _find("normal", "_n")
if normal:
    node = nodes.new("ShaderNodeTexImage")
    node.image = _image(normal, color=False, flip_green="opengl" not in normal.lower())
    mapper = nodes.new("ShaderNodeNormalMap")
    links.new(node.outputs["Color"], mapper.inputs["Color"])
    links.new(mapper.outputs["Normal"], shader.inputs["Normal"])
if not color:
    shader.inputs["Base Color"].default_value = (0.05, 0.05, 0.055, 1.0)
    shader.inputs["Metallic"].default_value = 0.6
    shader.inputs["Roughness"].default_value = 0.45
for obj in bpy.data.objects:
    obj.data.materials.clear()
    obj.data.materials.append(material)

# --- Report and export -----------------------------------------------------------

for obj in bpy.data.objects:
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    low = Vector([min(c[i] for c in corners) for i in range(3)])
    high = Vector([max(c[i] for c in corners) for i in range(3)])
    # In Godot's frame (x, z, -y).
    print("PART %-9s tris %6d  godot min (%.3f %.3f %.3f) max (%.3f %.3f %.3f) origin (%.3f %.3f %.3f)" % (
        obj.name, sum(len(p.vertices) - 2 for p in obj.data.polygons),
        low.x, low.z, -high.y, high.x, high.z, -low.y,
        obj.location.x, obj.location.z, -obj.location.y))
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=False, export_yup=True,
                          export_animations=False, export_skins=False, export_morph=False,
                          export_image_format="AUTO")
print("EXPORTED", out)
