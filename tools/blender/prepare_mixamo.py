"""Prepares a rigged Mixamo character (FBX) for Grivet: keeps the mesh and its
65-bone mixamorig skeleton, decimates the mesh to a game budget (the
decimation runs before the armature deform, so the skin weights carry over),
shrinks every texture, drops the embedded animation, bakes the centimetre
scale and Z-up rotation in, strips the "mixamorig:" bone prefix (Hips,
LeftArm, ...) and exports a GLB with the skin.

With --anims <folder>, the Mixamo clips in that folder (FBX, same 65-bone
skeleton, with or without skin) are added as animations named by CLIPS
(idle, walk, run, ...), the bone prefix stripped, centimetres turned into
metres and the hips' travel across the ground taken out (the game moves the
body; the clips play in place). Files not in CLIPS are skipped.

--skip <objects> drops meshes (a prop in the hand); --height <m> scales the
character to that standing height (clips scale with it); --recolour
<zmin>,<zmax>,<#rrggbb> (repeatable) repaints the clothes on the faces
between those heights (m, standing) in that colour, keeping the texture's
shading and leaving skin-coloured texels alone (a shirt into a police shirt).
--keep-bones <bones>: only the faces skinned to those bones and below stay
(the first-person arms).
--tint <image>=<#hex> repaints the texture named <image> (else every one whose name contains it)
(keeping its shading); with :skin only its skin-coloured texels.

Run headless (no window):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P tools/blender/prepare_mixamo.py -- <in.fbx> <out.glb> [--triangles 11000] [--texture 1024] [--anims <folder>] [--skip <objects>] [--height <m>] [--recolour <zmin>,<zmax>,<#hex>] [--tint <image name part>=<#hex>[:skin]] [--keep-bones LeftShoulder,RightShoulder]

The source FBX stays outside the repository (Mixamo; see Docs/AssetLicences.md).
"""
import os
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
source, out = args[0], args[1]
TRIANGLES = int(args[args.index("--triangles") + 1]) if "--triangles" in args else 11000
TEXTURE = int(args[args.index("--texture") + 1]) if "--texture" in args else 1024
ANIMS = args[args.index("--anims") + 1] if "--anims" in args else ""
KEEP_BONES = args[args.index("--keep-bones") + 1].split(",") if "--keep-bones" in args else []
SKIP = set(args[args.index("--skip") + 1].split(",")) if "--skip" in args else set()
HEIGHT = float(args[args.index("--height") + 1]) if "--height" in args else 0.0
RECOLOUR = []
TINT = []  # (image name part, colour, skin texels only)
for i, arg in enumerate(args):
    if arg == "--tint":
        name, colour = args[i + 1].split("=")
        only_skin = colour.endswith(":skin")
        colour = colour.split(":")[0].lstrip("#")
        TINT.append((name, tuple(int(colour[j:j + 2], 16) / 255.0 for j in (0, 2, 4)), only_skin))
for i, arg in enumerate(args):
    if arg == "--recolour":
        low, high, colour = args[i + 1].split(",")
        colour = colour.lstrip("#")
        RECOLOUR.append((float(low), float(high), tuple(int(colour[j:j + 2], 16) / 255.0 for j in (0, 2, 4))))

# Mixamo file name (lower case, no extension) -> clip name in the game.
CLIPS = {
    "rifle aiming idle": "idle", "walking": "walk", "walking backwards": "walk_back",
    "rifle run": "run", "run backwards": "run_back",
    "strafe left": "strafe_left", "strafe right": "strafe_right",
    "strafe (2)": "sprint_left", "strafe": "sprint_right",
    "firing rifle": "fire", "reloading": "reload", "toss grenade": "toss",
    "hit reaction": "hit", "turn left": "turn_left", "turning right 45 degrees": "turn_right",
    "rifle jump": "jump",
}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=source)

# The character's own (T-pose) take goes: clips come from --anims.
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)
for obj in bpy.data.objects:
    if obj.animation_data:
        obj.animation_data_clear()

# Metres, Y up, no stray scale: bake the FBX's centimetre scale and Z-up
# rotation into the armature and mesh, so the skeleton's rest poses are clean.
for obj in list(bpy.data.objects):
    if obj.name in SKIP:
        bpy.data.objects.remove(obj, do_unlink=True)
character = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
if HEIGHT > 0.0:
    bpy.context.view_layer.update()
    heights = [(o.matrix_world @ v.co).z for o in bpy.data.objects if o.type == "MESH" for v in o.data.vertices]
    character.scale *= HEIGHT / (max(heights) - min(heights))
    bpy.context.view_layer.update()
UNIT = character.scale.x  # the clips' hips travel is in the FBX's units (cm)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.ops.object.select_all(action="DESELECT")
# Plain bone names ("Hips", "LeftArm"): the "mixamorig:" prefix doesn't survive
# the trip to Godot intact. Vertex groups are renamed with their bones.
for armature in [o for o in bpy.data.objects if o.type == "ARMATURE"]:
    for bone in armature.data.bones:
        bone.name = bone.name.split(":")[-1]


def _curves(action):
    """Every F-curve of an action (Blender 5 keeps them in layered channelbags)."""
    found = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                found.extend(bag.fcurves)
    return found or list(getattr(action, "fcurves", []))


def _add_clips(folder):
    bpy.context.scene.render.fps = 30
    for file_name in sorted(os.listdir(folder)):
        stem, extension = os.path.splitext(file_name)
        clip = CLIPS.get(stem.lower())
        if extension.lower() != ".fbx" or clip is None:
            continue
        before = set(bpy.data.objects)
        known = set(bpy.data.actions)
        bpy.ops.import_scene.fbx(filepath=os.path.join(folder, file_name))
        added = [a for a in bpy.data.actions if a not in known]
        for obj in set(bpy.data.objects) - before:
            bpy.data.objects.remove(obj, do_unlink=True)
        if not added:
            print("CLIP %s: no animation in %s" % (clip, file_name))
            continue
        action = added[0]
        for extra in added[1:]:
            bpy.data.actions.remove(extra)
        action.name = clip
        action.use_fake_user = True
        start, end = action.frame_range
        for curve in _curves(action):
            path = curve.data_path
            if 'pose.bones["' in path:
                bone = path.split('"')[1]
                curve.data_path = path.replace('"%s"' % bone, '"%s"' % bone.split(":")[-1])
            if curve.data_path == 'pose.bones["Hips"].location':
                points = curve.keyframe_points
                first = curve.evaluate(start)
                last = curve.evaluate(end)
                for point in points:
                    value = point.co[1]
                    # Across the ground (bone x / z): take out the steady travel,
                    # keep the sway around the start.
                    if curve.array_index != 1:
                        t = (point.co[0] - start) / max(end - start, 1.0)
                        value -= (last - first) * t
                    point.co[1] = value * UNIT
                    point.handle_left[1] = point.co[1]
                    point.handle_right[1] = point.co[1]
                curve.update()
        # Store each clip on its own NLA track: the exporter writes one glTF
        # animation per track, named after it.
        data = character.animation_data or character.animation_data_create()
        data.action = action
        if hasattr(data, "action_slot") and data.action_slot is None and len(action.slots):
            data.action_slot = action.slots[0]
        track = data.nla_tracks.new()
        track.name = clip
        strip = track.strips.new(clip, int(start), action)
        data.action = None
        print("CLIP %-13s %-28s %3d frames" % (clip, file_name, end - start + 1))



def _keep_only(roots):
    """Deletes the faces whose strongest bone isn't one of `roots` or below
    them (first-person arms: keep LeftShoulder and RightShoulder)."""
    import bmesh
    armature = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    kept = set()
    for bone in armature.data.bones:
        walk = bone
        while walk is not None:
            if walk.name in roots:
                kept.add(bone.name)
                break
            walk = walk.parent
    for obj in [o for o in bpy.data.objects if o.type == "MESH"]:
        names = {g.index: g.name for g in obj.vertex_groups}
        owner = {}
        for v in obj.data.vertices:
            owner[v.index] = names[max(v.groups, key=lambda g: g.weight).group] if v.groups else ""
        mesh = bmesh.new()
        mesh.from_mesh(obj.data)
        doomed = [f for f in mesh.faces if not all(owner[v.index] in kept for v in f.verts)]
        bmesh.ops.delete(mesh, geom=doomed, context="FACES")
        mesh.to_mesh(obj.data)
        mesh.free()
        # Weights on bones that don't stay go to the ones that do (the arms are
        # posed far from the torso's rest; a share of chest weight stretched them).
        doomed_groups = [g for g in obj.vertex_groups if g.name not in kept]
        for v in obj.data.vertices:
            keep = [(g.group, g.weight) for g in v.groups if names[g.group] in kept]
            total = sum(w for _, w in keep)
            if total <= 0.0:
                continue
            for group, weight in keep:
                obj.vertex_groups[group].add([v.index], weight / total, "REPLACE")
        for group in doomed_groups:
            obj.vertex_groups.remove(group)
        print("KEEP %s: %d faces left" % (obj.name, len(obj.data.polygons)))


if KEEP_BONES:
    _keep_only(set(KEEP_BONES))
total = 0
for obj in [o for o in bpy.data.objects if o.type == "MESH"]:
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    if tris > TRIANGLES:
        decimate = obj.modifiers.new("decimate", "DECIMATE")
        decimate.ratio = TRIANGLES / tris
        decimate.use_collapse_triangulate = True
        # Above the armature deform, so it works on the rest pose and keeps weights.
        while obj.modifiers.find(decimate.name) > 0:
            bpy.ops.object.modifier_move_up(modifier=decimate.name)
        bpy.ops.object.modifier_apply(modifier=decimate.name)
    after = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    total += after
    print("MESH %s: %d -> %d tris" % (obj.name, tris, after))
    obj.select_set(False)

for image in bpy.data.images:
    if image.size[0] > TEXTURE or image.size[1] > TEXTURE:
        before = tuple(image.size)
        image.scale(TEXTURE, TEXTURE)
        image.pack()
        print("TEXTURE %s %dx%d -> %dx%d" % (image.name, before[0], before[1], TEXTURE, TEXTURE))



def _diffuse(material):
    """The image feeding a material's base colour, if any."""
    if material is None or not material.use_nodes:
        return None
    for link in material.node_tree.links:
        if link.to_socket.name == "Base Color" and link.from_node.type == "TEX_IMAGE":
            return link.from_node.image
    return None


def _recolour():
    import numpy
    for low, high, colour in RECOLOUR:
        masks = {}
        for obj in [o for o in bpy.data.objects if o.type == "MESH"]:
            uv = obj.data.uv_layers.active
            if uv is None:
                continue
            for poly in obj.data.polygons:
                centre = obj.matrix_world @ poly.center
                if not low <= centre.z <= high:
                    continue
                image = _diffuse(obj.material_slots[poly.material_index].material if obj.material_slots else None)
                if image is None:
                    continue
                width, height = image.size
                mask = masks.setdefault(image.name, numpy.zeros((height, width), dtype=bool))
                corners = [uv.data[i].uv for i in poly.loop_indices]
                for k in range(1, len(corners) - 1):
                    tri = numpy.array([[c.x * width, c.y * height] for c in (corners[0], corners[k], corners[k + 1])])
                    x0, y0 = numpy.floor(tri.min(axis=0)).astype(int)
                    x1, y1 = numpy.ceil(tri.max(axis=0)).astype(int)
                    x0, y0 = max(x0, 0), max(y0, 0)
                    x1, y1 = min(x1, width - 1), min(y1, height - 1)
                    if x1 < x0 or y1 < y0:
                        continue
                    xs, ys = numpy.meshgrid(numpy.arange(x0, x1 + 1) + 0.5, numpy.arange(y0, y1 + 1) + 0.5)
                    (ax, ay), (bx, by), (cx, cy) = tri
                    area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
                    if abs(area) < 1e-9:
                        continue
                    w0 = ((bx - xs) * (cy - ys) - (by - ys) * (cx - xs)) / area
                    w1 = ((cx - xs) * (ay - ys) - (cy - ys) * (ax - xs)) / area
                    inside = (w0 >= -0.02) & (w1 >= -0.02) & (w0 + w1 <= 1.02)
                    mask[y0:y1 + 1, x0:x1 + 1] |= inside
        for name, mask in masks.items():
            image = bpy.data.images[name]
            width, height = image.size
            pixels = numpy.empty(width * height * 4, dtype=numpy.float32)
            image.pixels.foreach_get(pixels)
            pixels = pixels.reshape(height, width, 4)
            rgb = pixels[..., :3]
            top = rgb.max(axis=2)
            bottom = rgb.min(axis=2)
            saturation = numpy.where(top > 0, (top - bottom) / numpy.maximum(top, 1e-6), 0)
            # Skin: warm (red the strongest, blue the weakest) and saturated.
            skin = (rgb[..., 0] >= rgb[..., 1]) & (rgb[..., 1] >= rgb[..., 2]) & (saturation > 0.28)
            cloth = mask & ~skin
            luminance = rgb @ numpy.array([0.3, 0.59, 0.11], dtype=numpy.float32)
            mean = float(luminance[cloth].mean()) if cloth.any() else 1.0
            shade = numpy.clip(luminance / max(mean, 1e-4), 0.35, 1.6)[..., None]
            rgb[cloth] = numpy.clip(numpy.array(colour, dtype=numpy.float32) * shade[cloth], 0.0, 1.0)
            pixels[..., :3] = rgb
            image.pixels.foreach_set(pixels.ravel())
            image.pack()
            print("RECOLOUR %s %.2f-%.2f m: %d texels" % (name, low, high, int(cloth.sum())))


if RECOLOUR:
    _recolour()


def _tint():
    import numpy
    for part, colour, only_skin in TINT:
        exact = [i for i in bpy.data.images if i.name.lower() == part.lower() and i.size[0] > 0]
        for image in exact or [i for i in bpy.data.images if part.lower() in i.name.lower() and i.size[0] > 0]:
            width, height = image.size
            pixels = numpy.empty(width * height * 4, dtype=numpy.float32)
            image.pixels.foreach_get(pixels)
            pixels = pixels.reshape(height, width, 4)
            rgb = pixels[..., :3]
            top = rgb.max(axis=2)
            saturation = numpy.where(top > 0, (top - rgb.min(axis=2)) / numpy.maximum(top, 1e-6), 0)
            chosen = numpy.ones((height, width), dtype=bool)
            if only_skin:
                chosen = (rgb[..., 0] >= rgb[..., 1]) & (rgb[..., 1] >= rgb[..., 2]) & (saturation > 0.12) & (top > 0.12)
            luminance = rgb @ numpy.array([0.3, 0.59, 0.11], dtype=numpy.float32)
            mean = float(luminance[chosen].mean()) if chosen.any() else 1.0
            shade = numpy.clip(luminance / max(mean, 1e-4), 0.3, 1.7)[..., None]
            rgb[chosen] = numpy.clip(numpy.array(colour, dtype=numpy.float32) * shade[chosen], 0.0, 1.0)
            pixels[..., :3] = rgb
            image.pixels.foreach_set(pixels.ravel())
            image.pack()
            print("TINT %s: %d texels" % (image.name, int(chosen.sum())))


if TINT:
    _tint()
print("TOTAL %d tris" % total)
if ANIMS:
    _add_clips(ANIMS)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=False, export_yup=True,
                          export_skins=True, export_animations=bool(ANIMS), export_animation_mode="NLA_TRACKS",
                          export_force_sampling=True, export_optimize_animation_size=True, export_morph=False,
                          export_image_format="JPEG", export_jpeg_quality=88)
print("EXPORTED", out)
