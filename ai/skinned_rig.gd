class_name SkinnedRig
extends Node3D
## A rigged character (a Mixamo humanoid: Hips, Spine, Neck, LeftArm,
## LeftForeArm, LeftUpLeg, LeftLeg, ...) worn over a Mannequin. The Mannequin
## still does everything (poses, IK to the gun, flinch, hit shapes, ragdoll)
## with its own meshes hidden; each pose, update() turns the skeleton's bones
## to follow its pivots. After death the rig follows the ragdoll's bodies.
##
## The correction per bone is found once, at build, with the Mannequin in its
## neutral pose (limbs hanging) and the skeleton in its rest T-pose: each limb
## bone is swung from its T-pose direction onto the pivot's hanging limb, and
## the bone keeps that relation to its pivot from then on. Mixamo models face
## +Z; the rig turns them round to the Mannequin's -Z.
##
## Animated (the model carries the Mixamo shooter clips: idle, walk, run,
## strafes, fire, reload, toss, hit; tools/blender/prepare_mixamo.py --anims):
## the drive turns round. An AnimationTree (advanced by hand, so pose LOD
## holds) plays a locomotion blend by the body's velocity plus upper-body
## one-shots; crouching blends the legs and hips to the Mannequin's
## procedural pose; aim pitch, flinch and hunker bend the spine; then each
## pivot is put where its bone is (pivot = bone * correction inverse), so hit
## shapes and the ragdoll follow what is drawn, and the gun rides the right
## hand.

## Mannequin pivot -> skeleton bone.
const BONES := {"hips": "Hips", "spine": "Spine", "neck": "Neck",
		"shoulder_l": "LeftArm", "elbow_l": "LeftForeArm", "shoulder_r": "RightArm", "elbow_r": "RightForeArm",
		"hip_l": "LeftUpLeg", "knee_l": "LeftLeg", "hip_r": "RightUpLeg", "knee_r": "RightLeg"}
## Pivots whose part hangs down their -Y (the limbs); the rest point up.
const LIMBS := ["shoulder_l", "elbow_l", "shoulder_r", "elbow_r", "hip_l", "knee_l", "hip_r", "knee_r"]

var skeleton: Skeleton3D

var _sources: Dictionary = {}  # pivot name -> Node3D whose global transform drives it
var _bone_of: Dictionary = {}  # pivot name -> bone index
var _pivot_of: Dictionary = {}  # bone index -> pivot name
var _correction: Dictionary = {}  # pivot name -> Basis (bone = pivot * correction)
var _chain := PackedInt32Array()  # driven bones and their ancestors, parents first
var _hips := -1
var _hips_offset := Vector3.ZERO  # the hips bone's origin in the hips pivot's frame
var _following: Ragdoll
var _offset: Dictionary = {}  # pivot name -> the bone's origin in the pivot's frame

## The animation tree (null: the model has no clips and follows the pivots).
var tree: AnimationTree
var _pivot_slots := PackedInt32Array()  # chain slot per driven pivot, parents first
var _pivot_nodes: Array[Node3D] = []
var _inverse: Array[Basis] = []
var _offsets: Array[Vector3] = []
var _leg_slot := PackedByteArray()  # 1: crouching blends this slot to the procedural pose
var _spine_bones := PackedInt32Array()
var _hand := -1
var _gun_offset := Transform3D.IDENTITY  # the gun in the right hand's frame

## Locomotion clips: name -> velocity they were made at (x right, y forward, m/s).
const MOVES := {"idle": Vector2.ZERO, "walk": Vector2(0, 1.36), "run": Vector2(0, 3.0),
		"walk_back": Vector2(0, -1.08), "run_back": Vector2(0, -2.4),
		"strafe_left": Vector2(-1.35, 0), "strafe_right": Vector2(0.73, 0),
		"sprint_left": Vector2(-2.63, 0), "sprint_right": Vector2(3.13, 0)}
## Upper-body one-shots; a later one plays over the ones before it.
const ACTIONS := ["reload", "toss", "fire", "hit"]
const RUN_CLIP_SPEED := 3.0
## Pivots that crouching takes over from the clips.
const LEGS := ["hips", "hip_l", "knee_l", "hip_r", "knee_r"]
# The chain flattened for update(), which runs for every soldier every pose:
# per entry the bone, its parent's slot in the chain (-1: none), its rest,
# its driver (null: keeps its rest) and correction.
var _slot_parent := PackedInt32Array()
var _slot_rest: Array[Transform3D] = []
var _slot_source: Array[Node3D] = []
var _slot_correction: Array[Basis] = []
var _globals: Array[Transform3D] = []


## Instances `model` and fits its skeleton to `pivots` (a Mannequin's, in
## its neutral pose).
func setup(model: PackedScene, pivots: Dictionary) -> void:
	rotation_degrees.y = 180.0
	add_child(model.instantiate())
	skeleton = find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for pivot_name: String in BONES:
		var bone := skeleton.find_bone(BONES[pivot_name])
		if bone < 0:
			push_error("SkinnedRig: %s has no bone %s" % [model.resource_path, BONES[pivot_name]])
			continue
		var source: Node3D = pivots[pivot_name]
		_sources[pivot_name] = source
		_bone_of[pivot_name] = bone
		_pivot_of[bone] = pivot_name
		var rest := skeleton.global_transform * skeleton.get_bone_global_rest(bone)
		var pivot := source.global_transform.orthonormalized()
		var along := rest.basis.y.normalized()
		var target := -pivot.basis.y if pivot_name in LIMBS else along
		var swung := Basis(Quaternion(along, target.normalized())) * rest.basis.orthonormalized()
		_correction[pivot_name] = pivot.basis.inverse() * swung
		_offset[pivot_name] = pivot.affine_inverse() * rest.origin
		if pivot_name == "hips":
			_hips = bone
			_hips_offset = _offset[pivot_name]
	# Every driven bone and its ancestors, parents before children.
	var wanted := {}
	for bone: int in _pivot_of:
		var walk := bone
		while walk >= 0:
			wanted[walk] = true
			walk = skeleton.get_bone_parent(walk)
	var ordered: Array = wanted.keys()
	ordered.sort_custom(func(a: int, b: int) -> bool: return _depth(a) < _depth(b))
	_chain = PackedInt32Array(ordered)
	_flatten()
	var players := find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty() and (players[0] as AnimationPlayer).has_animation("idle"):
		_animate(players[0] as AnimationPlayer, pivots)


func _flatten() -> void:
	_slot_parent.resize(_chain.size())
	_slot_rest.resize(_chain.size())
	_slot_source.resize(_chain.size())
	_slot_correction.resize(_chain.size())
	_globals.resize(_chain.size())
	for slot in _chain.size():
		var bone := _chain[slot]
		_slot_parent[slot] = _chain.find(skeleton.get_bone_parent(bone))
		_slot_rest[slot] = skeleton.get_bone_rest(bone)
		var pivot_name: String = _pivot_of.get(bone, "")
		_slot_source[slot] = _sources[pivot_name] if pivot_name != "" else null
		_slot_correction[slot] = _correction[pivot_name] if pivot_name != "" else Basis.IDENTITY


## Follows the pivots (or, after death, the ragdoll's bodies).
func update() -> void:
	if skeleton == null:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	for slot in _chain.size():
		var parent := _slot_parent[slot]
		var parent_global := _globals[parent] if parent >= 0 else Transform3D.IDENTITY
		var local := _slot_rest[slot]
		var source := _slot_source[slot]
		if source == null:
			local = skeleton.get_bone_pose(_chain[slot])  # as animated (or rest)
		else:
			if not is_instance_valid(source):
				_globals[slot] = parent_global * local
				continue
			var placed := source.global_transform
			local.basis = parent_global.basis.inverse() * (to_skeleton.basis * (placed.basis * _slot_correction[slot]))
			var bone := _chain[slot]
			skeleton.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())
			if bone == _hips:
				local.origin = parent_global.affine_inverse() * (to_skeleton * (placed * _hips_offset))
				skeleton.set_bone_pose_position(bone, local.origin)
		_globals[slot] = parent_global * local


## From now on the bones follow `ragdoll`'s bodies (each sits where its
## part's pivot was); the rig moves under the ragdoll so it outlives the body.
func follow(ragdoll: Ragdoll) -> void:
	for part_name: String in Mannequin.PARTS:
		var pivot_name: String = Mannequin.PARTS[part_name][0]
		if _sources.has(pivot_name) and ragdoll.bodies.has(part_name):
			_sources[pivot_name] = ragdoll.bodies[part_name]
	_flatten()
	reparent(ragdoll)
	_following = ragdoll


func _process(_delta: float) -> void:
	if _following == null:
		return
	if not is_instance_valid(_following):
		_following = null
		return
	update()
	if _following.frozen:
		_following = null  # settled: the pose holds


# --- Animated ---------------------------------------------------------------

func _animate(player: AnimationPlayer, pivots: Dictionary) -> void:
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip: String in MOVES:
		if player.has_animation(clip):
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var root := player.get_node(player.root_node)
	var skeleton_path := String(root.get_path_to(skeleton))
	var blend := AnimationNodeBlendTree.new()
	var moves := AnimationNodeBlendSpace2D.new()
	moves.min_space = Vector2(-3.5, -3.0)
	moves.max_space = Vector2(3.5, 3.5)
	for clip: String in MOVES:
		if player.has_animation(clip):
			var node := AnimationNodeAnimation.new()
			node.animation = clip
			moves.add_blend_point(node, MOVES[clip], -1, StringName(clip))
	blend.add_node("move", moves)
	blend.add_node("pace", AnimationNodeTimeScale.new())
	blend.connect_node("pace", 0, "move")
	var last := "pace"
	# Upper body: the spine and everything above it.
	var upper: Array[NodePath] = []
	var spine := skeleton.find_bone("Spine")
	for bone in skeleton.get_bone_count():
		var walk := bone
		while walk >= 0 and walk != spine:
			walk = skeleton.get_bone_parent(walk)
		if walk == spine:
			upper.append(NodePath("%s:%s" % [skeleton_path, skeleton.get_bone_name(bone)]))
	for action: String in ACTIONS:
		if not player.has_animation(action):
			continue
		var shot := AnimationNodeOneShot.new()
		shot.fadein_time = 0.02 if action == "fire" else 0.1
		shot.fadeout_time = 0.1 if action == "fire" else 0.25
		shot.filter_enabled = true
		for path in upper:
			shot.set_filter_path(path, true)
		var clip := AnimationNodeAnimation.new()
		clip.animation = action
		blend.add_node(action + "_clip", clip)
		blend.add_node(action, shot)
		blend.connect_node(action, 0, last)
		blend.connect_node(action, 1, action + "_clip")
		last = action
	blend.connect_node("output", 0, last)
	tree = AnimationTree.new()
	tree.tree_root = blend
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	root.add_child(tree)
	tree.root_node = tree.get_path_to(root)
	tree.anim_player = tree.get_path_to(player)
	tree.active = true
	for slot in _chain.size():
		var bone := _chain[slot]
		if not _pivot_of.has(bone):
			continue
		var pivot_name: String = _pivot_of[bone]
		_pivot_slots.append(slot)
		_pivot_nodes.append(pivots[pivot_name])
		_inverse.append((_correction[pivot_name] as Basis).inverse())
		_offsets.append(_offset[pivot_name])
	_leg_slot.resize(_chain.size())
	for slot in _chain.size():
		_leg_slot[slot] = 1 if _pivot_of.get(_chain[slot], "") in LEGS else 0
	for bone_name in ["Spine", "Spine1", "Spine2"]:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			_spine_bones.append(bone)
	_hand = skeleton.find_bone("RightHand")


## Fixes the gun in the right hand: with the body in the aiming clip's first
## frame, the gun's `grip` (in its own frame) in the palm and its basis
## `facing` (world). Call once after setup.
func hold_gun(grip: Vector3, facing: Basis) -> void:
	if tree == null or _hand < 0:
		return
	tree.advance(0.0)
	var to_world := skeleton.global_transform
	var hand := to_world * skeleton.get_bone_global_pose(_hand)
	var palm := hand.origin
	var middle := skeleton.find_bone("RightHandMiddle1")
	if middle >= 0:
		palm = palm.lerp(to_world * skeleton.get_bone_global_pose(middle).origin, 0.5)
	var basis := facing.orthonormalized()
	_gun_offset = hand.affine_inverse() * Transform3D(basis, palm - basis * grip)


## Starts an upper-body one-shot (fire, reload, toss, hit).
func act(action: String) -> void:
	if tree != null and action in ACTIONS:
		tree.set("parameters/%s/request" % action, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## One animated pose: clips by `velocity` (the body's, x right, y forward,
## m/s), hips and legs blended to the procedural pivots by `legs` (0..1), the
## spine bent by `bend` (x: pitch up about the body's right, y: sway, radians),
## then the pivots and `gun` put on the result.
func animate(delta: float, velocity: Vector2, legs: float, bend: Vector2, gun: Node3D) -> void:
	tree.set("parameters/move/blend_position", velocity)
	tree.set("parameters/pace/scale", maxf(1.0, velocity.length() / RUN_CLIP_SPEED))
	tree.advance(delta)
	var to_world := skeleton.global_transform
	var to_skeleton := to_world.affine_inverse()
	if legs > 0.001:
		for slot in _chain.size():
			var parent := _slot_parent[slot]
			var parent_global := _globals[parent] if parent >= 0 else Transform3D.IDENTITY
			var bone := _chain[slot]
			var local := skeleton.get_bone_pose(bone)
			if _leg_slot[slot] == 1:
				var placed := _slot_source[slot].global_transform
				var wanted := parent_global.basis.inverse() * (to_skeleton.basis * (placed.basis * _slot_correction[slot]))
				var mixed := local.basis.get_rotation_quaternion().slerp(wanted.get_rotation_quaternion(), legs)
				local.basis = Basis(mixed)
				skeleton.set_bone_pose_rotation(bone, mixed)
				if bone == _hips:
					var origin := parent_global.affine_inverse() * (to_skeleton * (placed * _hips_offset))
					local.origin = local.origin.lerp(origin, legs)
					skeleton.set_bone_pose_position(bone, local.origin)
			_globals[slot] = parent_global * local
	if not bend.is_zero_approx() and not _spine_bones.is_empty():
		var right := (to_skeleton.basis * get_parent_node_3d().global_basis.x).normalized()
		var back := (to_skeleton.basis * get_parent_node_3d().global_basis.z).normalized()
		var share := 1.0 / _spine_bones.size()
		# Each spine bone turns its share about the body's axes, taken in its
		# frame before any turning (each turn keeps its own axis fixed).
		var frames: Array[Basis] = []
		for bone in _spine_bones:
			frames.append(skeleton.get_bone_global_pose(bone).basis.orthonormalized().inverse())
		for i in _spine_bones.size():
			var turn := Quaternion(frames[i] * right, bend.x * share) * Quaternion(frames[i] * back, bend.y * share)
			var bone := _spine_bones[i]
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * turn)
	for i in _pivot_slots.size():
		var global := to_world * skeleton.get_bone_global_pose(_chain[_pivot_slots[i]])
		var basis := global.basis.orthonormalized() * _inverse[i]
		_pivot_nodes[i].global_transform = Transform3D(basis, global.origin - basis * _offsets[i])
	if gun != null and _hand >= 0:
		gun.global_transform = to_world * skeleton.get_bone_global_pose(_hand) * _gun_offset


func cast_shadows(on: bool) -> void:
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _depth(bone: int) -> int:
	var depth := 0
	var walk := skeleton.get_bone_parent(bone)
	while walk >= 0:
		depth += 1
		walk = skeleton.get_bone_parent(walk)
	return depth
