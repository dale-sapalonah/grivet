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

Run headless (no window):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P tools/blender/prepare_mixamo.py -- <in.fbx> <out.glb> [--triangles 11000] [--texture 1024] [--anims <folder>]

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
character = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
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

print("TOTAL %d tris" % total)
if ANIMS:
    _add_clips(ANIMS)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=False, export_yup=True,
                          export_skins=True, export_animations=bool(ANIMS), export_animation_mode="NLA_TRACKS",
                          export_force_sampling=True, export_optimize_animation_size=True, export_morph=False,
                          export_image_format="JPEG", export_jpeg_quality=88)
print("EXPORTED", out)
