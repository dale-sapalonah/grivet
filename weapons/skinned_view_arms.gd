class_name SkinnedViewArms
extends Node3D
## First-person arms from a rigged character (ViewModelTuning.arms_model: the
## police officer's arms cut from its Mixamo body, tools/blender/prepare_mixamo.py
## --keep-bones LeftShoulder,RightShoulder), posed each frame instead of built
## from shapes. Same contract as ViewArms: build() takes the two grips,
## place() a hand's hold (the grip cylinder along the hold's Y, the palm on
## its +X side, or -X when mirrored, fingers curling round the front, -Z) and
## the elbow point. Each hand is turned so its palm faces the grip and its
## fingers run round the front, its palm put on the grip's surface; the
## forearm reaches back from the wrist toward the elbow point and the upper
## arm on to a shoulder off screen. Fingers curl by the grip's curl, the
## trigger finger stays out along the frame.
##
## With an "idle" clip in the model (the Mixamo rifle aiming idle, baked by
## prepare_mixamo.py --anims), rifles and shotguns use the clip's hands
## instead: their place on the rifle (the gun set in the right palm, facing
## the body's front, as soldiers hold theirs) and every finger joint, the
## left hand slid along the barrel to the handguard or pump. Pistols, with no
## clip, keep the curled hands.
##
## Hands posed from the clip then close on the gun itself (its triangles,
## from the view model): the palm is seated on the grip or handguard a skin's
## width off, then every finger and the thumb start straight and close joint
## by joint, the base joint first, each joint stopping the moment any part of
## the finger beyond it would touch the gun, while the joints further out keep
## closing. The fingers wrap tight without passing into the gun; the trigger
## finger closes onto the trigger the same way. (Not a ViewArms subclass:
## extending it kept view_arms.gd alive at exit through its inner Grip class.)

const SIDES := ["Right", "Left"]
const FINGERS := ["Index", "Middle", "Ring", "Pinky"]

var tuning: ViewModelTuning

var _skeleton: Skeleton3D
var _grips: Array = []  # [right, left] ViewArms.Grip
## The clip's hands, if the model has one: per side the hand bone (skeleton
## space) and the finger joints' rotations.
var _clip_hands: Array[Transform3D] = []
var _clip_fingers: Array[Dictionary] = []
## For the current gun: the clip's hands in the gun's frame, and the inverse of
## the view model's holds (to get from a hold back to the gun).
## Per hand: posed from the clip (the shooting hand always, when there is a
## clip: a pistol grip is held like a rifle's; the support hand for rifles and
## shotguns only, a pistol's cups the other hand).
var _use_clip: Array[bool] = [false, false]
var _relative: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var _hold_inverse: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var _right_hold := Transform3D.IDENTITY  # the shooting hand's hold, gun frame
var _left_hold := Transform3D.IDENTITY  # the support hand's, gun frame
var _trigger := Vector3.ZERO  # the gun's trigger, gun frame
## A pistol: the support hand cups the shooting hand, so it takes the clip's
## wrapped shape without closing on the gun.
var _pistol := false
## The gun's surface (gun frame) and, per hand, the point at the middle of what
## it holds (the grip, the handguard or pump).
var _surface: TriangleMesh
## Per hand, what it closes on: the gun, or for a pistol's support hand the
## shooting hand's fist (a cylinder round the grip, ViewModelTuning.arms_cup_*).
var _closes_on: Array[TriangleMesh] = [null, null]
## Hands closed on a gun, per gun and style: [relative right, relative left,
## {bone: rotation}]. The search costs ~30 ms, so a gun is solved once a session.
static var _closed_cache := {}
var _cache_key := ""
var _make_surface: Callable
var _held_middle: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## Per side (0 right, 1 left): bone indices and rest facts, in skeleton space.
var _bones: Array[Dictionary] = []
## Per finger/thumb bone: how far the skin reaches from the bone's line (m,
## the 90th percentile of its vertices), measured from the mesh at load.
var _flesh := {}
## The finger meshes for the exact no-intersection rule: per chain (keyed by
## its first bone) the skin vertices it moves (index, bones, weights), its
## edges and its triangles; with the skeleton-space bind poses per bone.
var _finger_mesh := {}
var _skin_points := PackedVector3Array()
var _bind := {}  # bone -> bind pose (skin space -> bone space)
## The gun's edges (gun frame), for the reverse test: no gun edge may pass
## through a finger's triangles.
var _gun_edges := PackedVector3Array()


func _ready() -> void:
	var model := tuning.arms_model.instantiate() as Node3D
	add_child(model)
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.extra_cull_margin = 1.0  # posed far from its rest place
	for side: String in SIDES:
		var hand := _skeleton.find_bone(side + "Hand")
		var hand_rest := _skeleton.get_bone_global_rest(hand)
		var middle := _rest_at(side + "HandMiddle1")
		var index := _rest_at(side + "HandIndex1")
		var pinky := _rest_at(side + "HandPinky1")
		var fingers := (middle - hand_rest.origin).normalized()
		var thumb_side := (index - pinky).normalized()
		# The palm normal, the same way for both hands (measured on the model).
		var palm := thumb_side.cross(fingers).normalized()
		thumb_side = fingers.cross(palm).normalized()
		var facts := {
			"shoulder": _skeleton.find_bone(side + "Shoulder"), "arm": _skeleton.find_bone(side + "Arm"),
			"forearm": _skeleton.find_bone(side + "ForeArm"), "hand": hand,
			"sign": 1.0 if side == "Right" else -1.0,  # which side of the view
			"upper_length": _skeleton.get_bone_rest(_skeleton.find_bone(side + "ForeArm")).origin.length(),
			"fore_length": (_skeleton.get_bone_rest(hand) as Transform3D).origin.length(),
			"frame": Basis(fingers, palm, thumb_side),  # rest: fingers, palm normal, thumb side
			# The palm's middle, from the wrist, in the rest hand's frame.
			"palm": hand_rest.basis.inverse() * ((middle - hand_rest.origin) * 0.55 - palm * tuning.arms_palm_depth),
			"curl_axis": palm.cross(fingers).normalized(),
			"fingers": [], "thumb": [],
		}
		for finger: String in FINGERS:
			var joints: Array[int] = []
			for k in 3:
				joints.append(_skeleton.find_bone(side + "Hand%s%d" % [finger, k + 1]))
			(facts.fingers as Array).append(joints)
		for k in 3:
			(facts.thumb as Array).append(_skeleton.find_bone(side + "HandThumb%d" % (k + 1)))
		# Each chain's tip bone (the "4" end bone; -1 if the rig has none).
		var tips: Array[int] = []
		for finger: String in FINGERS + ["Thumb"]:
			tips.append(_skeleton.find_bone(side + "Hand%s4" % finger))
		facts["tips"] = tips
		var thumb_root := _rest_at(side + "HandThumb1")
		var thumb_next := _rest_at(side + "HandThumb2")
		facts["thumb_axis"] = palm.cross((thumb_next - thumb_root).normalized()).normalized()
		_bones.append(facts)
	_measure_flesh(model)
	_sample_clip(model)
	_shorten_thumbs()


## The model's thumbs read too long in first person: every thumb segment is
## shortened to arms_thumb_length of its length (each joint moved toward the
## one before it, so the joints keep their spacing), the tip a little slimmer.
func _shorten_thumbs() -> void:
	for side: String in SIDES:
		for k in range(2, 5):
			var bone := _skeleton.find_bone(side + "HandThumb%d" % k)
			if bone < 0:
				continue
			_skeleton.set_bone_rest(bone, Transform3D(_skeleton.get_bone_rest(bone).basis,
					_skeleton.get_bone_rest(bone).origin * tuning.arms_thumb_length))
			_skeleton.set_bone_pose_position(bone, _skeleton.get_bone_rest(bone).origin)


## Reads the clip's first frame: each hand's place and its finger joints.
func _sample_clip(model: Node3D) -> void:
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty() or not (players[0] as AnimationPlayer).has_animation("idle"):
		return
	var player := players[0] as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play("idle")
	player.advance(0.0)  # applies the first frame now (seek alone did not)
	for i in 2:
		var facts := _bones[i]
		_clip_hands.append(_skeleton.get_bone_global_pose(facts.hand))
		var fingers := {}
		for joints: Array in facts.fingers:
			for bone: int in joints:
				fingers[bone] = _skeleton.get_bone_pose_rotation(bone)
		for bone: int in facts.thumb:
			fingers[bone] = _skeleton.get_bone_pose_rotation(bone)
		_clip_fingers.append(fingers)
	# Gone once read: left in place it kept putting the clip's pose back over
	# the arms each frame.
	player.get_parent().remove_child(player)
	player.free()
	_skeleton.reset_bone_poses()


## The gun now held: its model, the view style, and the view model's holds
## in the gun's frame (the left one where it is on the gun, pump included).
## `make_surface` returns the gun's triangles (gun frame); it is called only
## when this gun's hands aren't cached yet.
func set_holds(gun: GunModel, style: int, right_hold: Transform3D, left_hold: Transform3D, make_surface: Callable) -> void:
	_cache_key = "%s#%d" % [gun.resource_path, style]
	_trigger = gun.trigger
	_make_surface = make_surface
	_surface = null
	_held_middle = [gun.grip, left_hold.origin]
	_closes_on = [null, null]
	if style == WeaponDefinition.ViewStyle.PISTOL:
		_held_middle[1] = gun.grip
	var clip := not _clip_hands.is_empty()
	_pistol = style == WeaponDefinition.ViewStyle.PISTOL
	_use_clip = [clip, clip]
	_left_hold = left_hold
	_hold_inverse = [right_hold.affine_inverse(), left_hold.affine_inverse()]
	_right_hold = right_hold
	if not _use_clip[1] or _pistol:
		return
	# The clip's rifle runs from the right palm (on the grip) to the left
	# (under the handguard): turn this gun so its grip-to-support line lies
	# along that, top up, grip in the right palm.
	var right_palm := _clip_hands[0] * (_bones[0].palm as Vector3)
	var left_palm := _clip_hands[1] * (_bones[1].palm as Vector3)
	var support := left_hold.origin
	var support_palm := Vector3(support.x, support.y - gun.support_radius, support.z)
	var turn := _frame(left_palm - right_palm, Vector3.UP) * _frame(support_palm - gun.grip, Vector3.UP).inverse()
	var clip_gun := Transform3D(turn, right_palm - turn * gun.grip)
	var to_gun := clip_gun.affine_inverse()
	_relative[0] = to_gun * _clip_hands[0]
	var left := to_gun * _clip_hands[1]
	# Then the left palm exactly onto this gun's handguard or pump.
	left.origin += support_palm - left * (_bones[1].palm as Vector3)
	_relative[1] = left


## A cylinder standing in for the shooting hand's fist round the grip (along
## the hold's Y through its origin): what a pistol's support hand wraps.
func _fist_round(right_hold: Transform3D) -> TriangleMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = tuning.arms_cup_radius
	cylinder.bottom_radius = tuning.arms_cup_radius
	cylinder.height = tuning.arms_cup_height
	cylinder.radial_segments = 16
	var fist := TriangleMesh.new()
	fist.create_from_faces(Transform3D(right_hold.basis.orthonormalized(), right_hold.origin) * cylinder.get_faces())
	return fist


## Measures each finger and thumb bone's flesh: the distance from its bone
## line (to its child) of the skin vertices it mostly moves, 90th percentile.
## The contact tests use it, so the whole glove stops at the gun, not just the
## bone inside it.
func _measure_flesh(model: Node3D) -> void:
	var samples := {}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if verts.is_empty() or bones.is_empty():
				continue
			var stride: int = bones.size() / verts.size()
			for v in verts.size():
				var best := 0
				for j in stride:
					if weights[v * stride + j] > weights[v * stride + best]:
						best = j
				var bind: int = bones[v * stride + best]
				var bone_name := String(mesh.skin.get_bind_name(bind))
				var bone := _skeleton.find_bone(bone_name) if bone_name != "" else mesh.skin.get_bind_bone(bind)
				if bone < 0 or not ("Thumb" in _skeleton.get_bone_name(bone) or "Index" in _skeleton.get_bone_name(bone) 						or "Middle" in _skeleton.get_bone_name(bone) or "Ring" in _skeleton.get_bone_name(bone) or "Pinky" in _skeleton.get_bone_name(bone)):
					continue
				var children := _skeleton.get_bone_children(bone)
				if children.is_empty():
					continue
				var a := _skeleton.get_bone_global_rest(bone).origin
				var b := _skeleton.get_bone_global_rest(children[0]).origin
				var t := clampf((verts[v] - a).dot(b - a) / maxf((b - a).length_squared(), 1e-8), 0.0, 1.0)
				if not samples.has(bone):
					samples[bone] = []
				(samples[bone] as Array).append(verts[v].distance_to(a.lerp(b, t)))
	_collect_finger_meshes(model)
	for bone: int in samples:
		var distances: Array = samples[bone]
		distances.sort()
		# Capped: a thumb's first bone also moves the fleshy base of the palm.
		_flesh[bone] = minf(float(distances[int(distances.size() * tuning.arms_flesh_percentile)]), tuning.arms_flesh_max)


## Collects each finger's and thumb's share of the skinned mesh: the vertices
## mostly moved by the chain's bones (with all their weights), and the edges
## and triangles among them.
func _collect_finger_meshes(model: Node3D) -> void:
	var chain_of := {}  # bone -> its chain's first bone
	for facts: Dictionary in _bones:
		var tips: Array = facts.tips
		var chains: Array = (facts.fingers as Array) + [facts.thumb]
		for c in chains.size():
			var chain: Array = chains[c]
			for bone: int in chain:
				chain_of[bone] = chain[0]
			if (tips[c] as int) >= 0:
				chain_of[tips[c]] = chain[0]
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin == null:
			continue
		for b in mesh.skin.get_bind_count():
			var bone_name := String(mesh.skin.get_bind_name(b))
			var bone := _skeleton.find_bone(bone_name) if bone_name != "" else mesh.skin.get_bind_bone(b)
			if bone >= 0:
				_bind[bone] = mesh.skin.get_bind_pose(b)
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var binds: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if verts.is_empty() or binds.is_empty():
				continue
			var stride: int = binds.size() / verts.size()
			var owner := PackedInt32Array()
			owner.resize(verts.size())
			for v in verts.size():
				var best := 0
				for j in stride:
					if weights[v * stride + j] > weights[v * stride + best]:
						best = j
				var bind_index: int = binds[v * stride + best]
				var bone_name := String(mesh.skin.get_bind_name(bind_index))
				var bone := _skeleton.find_bone(bone_name) if bone_name != "" else mesh.skin.get_bind_bone(bind_index)
				owner[v] = chain_of.get(bone, -1)
			var tris: PackedInt32Array = indices
			if tris.is_empty():
				tris.resize(verts.size())
				for v in verts.size():
					tris[v] = v
			for t in range(0, tris.size(), 3):
				var key: int = owner[tris[t]]
				if key < 0 or owner[tris[t + 1]] != key or owner[tris[t + 2]] != key:
					continue
				if not _finger_mesh.has(key):
					_finger_mesh[key] = {"verts": {}, "tris": PackedInt32Array()}
				var entry: Dictionary = _finger_mesh[key]
				for corner in 3:
					var v: int = tris[t + corner]
					if not (entry.verts as Dictionary).has(v):
						var influences := []
						for j in stride:
							var w := weights[v * stride + j]
							if w <= 0.0:
								continue
							var bind_index: int = binds[v * stride + j]
							var bone_name := String(mesh.skin.get_bind_name(bind_index))
							var bone := _skeleton.find_bone(bone_name) if bone_name != "" else mesh.skin.get_bind_bone(bind_index)
							influences.append([bone, w])
						(entry.verts as Dictionary)[v] = [verts[v], influences]
					var corners: PackedInt32Array = entry.tris
					corners.append(v)
					entry.tris = corners  # packed arrays come out of a Dictionary as copies


## Hand i's finger `chain` as drawn in its current pose, in the gun's frame:
## [triangle corner points (3 per triangle)].
func _finger_triangles(i: int, chain: Array) -> PackedVector3Array:
	var entry: Dictionary = _finger_mesh.get(chain[0], {})
	var points := PackedVector3Array()
	if entry.is_empty():
		return points
	var to_gun := _relative[i] * _skeleton.get_bone_global_pose(_bones[i].hand).affine_inverse()
	var placed := {}
	var poses := {}
	for v: int in entry.verts:
		var data: Array = entry.verts[v]
		var at := Vector3.ZERO
		for influence: Array in data[1]:
			var bone: int = influence[0]
			if not poses.has(bone):
				poses[bone] = _skeleton.get_bone_global_pose(bone) * (_bind.get(bone, Transform3D.IDENTITY) as Transform3D)
			at += (poses[bone] as Transform3D) * (data[0] as Vector3) * float(influence[1])
		placed[v] = to_gun * at
	for v in entry.tris as PackedInt32Array:
		points.append(placed[v])
	return points


## The rule: the finger's mesh and the gun's may touch but never cross. True
## when any finger edge passes through a gun triangle or any gun edge near
## the finger passes through a finger triangle.
func _mesh_crosses(i: int, chain: Array, surface: TriangleMesh) -> bool:
	var tris := _finger_triangles(i, chain)
	if tris.is_empty():
		return false
	var low := tris[0]
	var high := tris[0]
	for t in range(0, tris.size(), 3):
		for corner in 3:
			var a := tris[t + corner]
			low = low.min(a)
			high = high.max(a)
			var b := tris[t + (corner + 1) % 3]
			if not surface.intersect_segment(a, b).is_empty():
				return true
	# Gun edges inside the finger's box, against its triangles.
	var box := AABB(low, high - low).grow(0.002)
	for e in range(0, _gun_edges.size(), 2):
		var a := _gun_edges[e]
		var b := _gun_edges[e + 1]
		if not box.intersects_segment(a, b):
			continue
		for t in range(0, tris.size(), 3):
			if Geometry3D.segment_intersects_triangle(a, b, tris[t], tris[t + 1], tris[t + 2]) != null:
				return true
	return false


## Where bone `bone_name` sits at rest (skeleton space).
func _rest_at(bone_name: String) -> Vector3:
	return _skeleton.get_bone_global_rest(_skeleton.find_bone(bone_name)).origin


## Shapes the hands for a weapon: [right grip, left grip].
func build(right: ViewArms.Grip, left: ViewArms.Grip) -> void:
	_grips = [right, left]
	if not _use_clip[1]:
		_curl(1, left)
	if not _use_clip[0]:
		_curl(0, right)
		return
	# The shooting hand placed by this gun's grip: fitted to the clip's own
	# rifle it sat ahead of the grip with the fingers wrapping behind it.
	if _closed_cache.has(_cache_key):
		var cached: Array = _closed_cache[_cache_key]
		_relative[0] = cached[0]
		_relative[1] = cached[1]
		for bone: int in cached[2]:
			_skeleton.set_bone_pose_rotation(bone, cached[2][bone])
		return
	_relative[0] = _hand_on(0, _right_hold, right)
	# The whole hand tilted up toward the gun's body (about the gun's side
	# axis), so the knuckles ride high and the
	# index finger meets the trigger level, not from below.
	# Turned about the palm, not the wrist: about the wrist it pushed the palm
	# off the front of the grip and the fingers closed in front of it.
	var lift := Basis(Vector3.RIGHT, deg_to_rad(tuning.arms_wrist_lift_degrees))
	var palm := _relative[0] * (_bones[0].palm as Vector3)
	_relative[0] = Transform3D(lift, palm) * Transform3D(Basis.IDENTITY, -palm) * _relative[0]
	# Back along the gun so the grip lies under the finger roots, inside the
	# fist, not against the heel of the palm.
	_relative[0].origin += Vector3(0, -tuning.arms_grip_down, tuning.arms_grip_back)
	# Turned outward about the grip so the knuckles sit at its front corner on
	# the palm's side rather than out in front of it.
	var yaw := Basis(Vector3.UP, deg_to_rad(tuning.arms_grip_yaw_degrees))
	var pivot := _relative[0] * (_bones[0].palm as Vector3)
	_relative[0] = Transform3D(yaw, pivot) * Transform3D(Basis.IDENTITY, -pivot) * _relative[0]
	if _pistol and _use_clip[1]:
		# Cupping the shooting hand: placed as the shape arms place it, then
		# closed round the fist.
		_relative[1] = _hand_on(1, _left_hold, left)
	_surface = _make_surface.call() if _make_surface.is_valid() else null
	_gun_edges = PackedVector3Array()
	if _surface != null:
		var faces := _surface.get_faces()
		for t in range(0, faces.size(), 3):
			for corner in 3:
				_gun_edges.append(faces[t + corner])
				_gun_edges.append(faces[t + (corner + 1) % 3])
	if _surface != null:
		_closes_on = [_surface, _fist_round(_right_hold) if _pistol else _surface]
	for i in 2:
		if _use_clip[i] and _closes_on[i] != null:
			_close_on_gun(i)
	var poses := {}
	for i in 2:
		for chain: Array in (_bones[i].fingers as Array) + [_bones[i].thumb]:
			for bone: int in chain:
				poses[bone] = _skeleton.get_bone_pose_rotation(bone)
	_closed_cache[_cache_key] = [_relative[0], _relative[1], poses]
	_surface = null  # only needed while closing
	_closes_on = [null, null]


# --- Closing on the gun ------------------------------------------------------

## Seats hand i's palm on what it holds and closes its fingers and thumb on
## the gun's surface (all in the gun's frame, through _relative[i]).
func _close_on_gun(i: int) -> void:
	var facts := _bones[i]
	var chains: Array = (facts.fingers as Array) + [facts.thumb]
	for bone: int in _clip_fingers[i]:
		_skeleton.set_bone_pose_rotation(bone, _clip_fingers[i][bone])
	_seat_palm(i)
	_clear_hand(i, chains)
	if i == 1 and not _pistol:
		_swing_thumb_out(1, tuning.arms_support_thumb_swing)  # round the handguard's left side
	elif i == 0 and _pistol:
		_swing_thumb_out(0, tuning.arms_pistol_thumb_swing)  # forward along the frame
	elif i == 0:
		_swing_thumb_out(0, tuning.arms_grip_thumb_swing)  # round the grip over the fingers
	var middle := _held_middle[i]
	for c in chains.size():
		var thumb := c == chains.size() - 1
		if c == 0 and i == 0 and _grips[0].trigger_finger:
			_pull_trigger()  # the index goes through the guard, not round the grip
			continue
		var axis: Vector3 = facts.thumb_axis if thumb else facts.curl_axis
		var limits := tuning.arms_thumb_max_degrees if thumb else tuning.arms_finger_max_degrees
		var surface := _closes_on[i]
		if thumb:
			# A thumb bends at its two outer joints only, and never opens back:
			# opened at its base it kinked inside the palm and stood up long.
			limits.x = 0.0
			if (i == 1 and not _pistol) or (i == 0 and _pistol):
				limits *= tuning.arms_support_thumb_close  # laid along the side
			surface = _surface  # a pistol's support thumb lies along the frame
		if thumb:
			_close_chain(i, chains[c], (facts.tips as Array)[c], axis, limits, middle, surface, true, thumb)
		else:
			_wrap_finger(i, chains[c], (facts.tips as Array)[c], middle, surface)


## Hand i's thumb swung at its base joint (degrees: about its curl axis, then
## spread about the palm's normal); its outer joints then close onto the gun.
func _swing_thumb_out(i: int, swing: Vector2) -> void:
	var facts := _bones[i]
	var bone: int = facts.thumb[0]
	var to_local := _skeleton.get_bone_global_rest(bone).basis.orthonormalized().inverse()
	var curl := Quaternion((to_local * (facts.thumb_axis as Vector3)).normalized(), deg_to_rad(swing.x))
	var spread := Quaternion((to_local * (facts.frame as Basis).y).normalized(), deg_to_rad(swing.y))
	_skeleton.set_bone_pose_rotation(bone, _skeleton.get_bone_pose_rotation(bone) * curl * spread)


## The shooting hand's index finger through the guard onto the trigger: from
## the clip's shape, its joints turned (cyclic coordinate descent: the base
## joint freely, the outer two about their hinge, flexing only) until the pad
## of the fingertip sits on the gun's trigger point.
func _pull_trigger() -> void:
	var facts := _bones[0]
	var joints: Array = facts.fingers[0]
	var tip: int = (facts.tips as Array)[0]
	var hand := _skeleton.get_bone_global_pose(facts.hand)
	var target := hand * (_relative[0].affine_inverse() * _trigger)
	for pass_index in 12:
		for k in [2, 1, 0]:
			var bone: int = joints[k]
			var joint := _skeleton.get_bone_global_pose(bone)
			var pad := _pad(joints, tip)
			var from := (pad - joint.origin)
			var to := (target - joint.origin)
			if from.length() < 0.001 or to.length() < 0.001:
				continue
			var turn: Quaternion
			if k == 0:
				turn = Quaternion(from.normalized(), to.normalized())
			else:
				var axis := (joint.basis.orthonormalized() * (_skeleton.get_bone_global_rest(bone).basis.orthonormalized().inverse() * (facts.curl_axis as Vector3))).normalized()
				var a := (from - axis * from.dot(axis)).normalized()
				var b := (to - axis * to.dot(axis)).normalized()
				turn = Quaternion(axis, atan2(axis.dot(a.cross(b)), a.dot(b)))
			var local := joint.basis.orthonormalized().inverse() * Basis(turn) * joint.basis.orthonormalized()
			_skeleton.set_bone_pose_rotation(bone, _skeleton.get_bone_pose_rotation(bone) * local.get_rotation_quaternion())
		if _pad(joints, tip).distance_to(target) < 0.002:
			break


## The index fingertip's pad (skeleton space): part way down its last segment.
func _pad(joints: Array, tip: int) -> Vector3:
	var last := _skeleton.get_bone_global_pose(joints[2]).origin
	var end := _skeleton.get_bone_global_pose(tip).origin if tip >= 0 else last
	return last.lerp(end, tuning.arms_trigger_pad)


## The rule for the hand as a whole: with every finger straight, no finger
## mesh may cross the gun; while one does (the knuckles sunk into a wide
## grip), the hand backs off along its palm's normal a little at a time.
func _clear_hand(i: int, chains: Array) -> void:
	var facts := _bones[i]
	var surface := _closes_on[i]
	var saved := {}
	for chain: Array in chains:
		for bone: int in chain:
			saved[bone] = _skeleton.get_bone_pose_rotation(bone)
			_skeleton.set_bone_pose_rotation(bone, _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())
	var hand_rest := _skeleton.get_bone_global_rest(facts.hand).basis.orthonormalized()
	var out := -(_relative[i].basis * (hand_rest.inverse() * (facts.frame as Basis).y)).normalized()
	if out.dot(_held_middle[i] - _relative[i] * (facts.palm as Vector3)) > 0.0:
		out = -out
	var moved := 0.0
	while moved < tuning.arms_clear_max:
		var crossing := false
		for c in chains.size():
			if c == chains.size() - 1 or (c == 0 and i == 0 and _grips[0].trigger_finger):
				continue  # the thumb and trigger finger have their own places
			if _mesh_crosses(i, chains[c], surface):
				crossing = true
				break
		if not crossing:
			break
		_relative[i].origin += out * 0.0015
		moved += 0.0015
	for bone: int in saved:
		_skeleton.set_bone_pose_rotation(bone, saved[bone])


## Moves hand i along its palm's normal until the palm lies a skin's width
## off the gun's surface.
func _seat_palm(i: int) -> void:
	# Straight in along the palm's normal: toward the held part's middle it
	# slid the hand along the grip, knuckles out in front of it.
	var facts := _bones[i]
	var palm := _relative[i] * (facts.palm as Vector3)
	var hand_rest := _skeleton.get_bone_global_rest(facts.hand).basis.orthonormalized()
	var toward := (_relative[i].basis * (hand_rest.inverse() * (facts.frame as Basis).y)).normalized()
	if toward.dot(_held_middle[i] - palm) < 0.0:
		toward = -toward
	var reach := tuning.arms_palm_search
	var hit := _closes_on[i].intersect_segment(palm - toward * reach, palm + toward * reach)
	if hit.is_empty():
		return
	var seated: Vector3 = (hit.position as Vector3) - toward * tuning.arms_palm_skin
	_relative[i].origin += seated - palm


## Where bone `bone` is, in the gun's frame, with hand i where it holds.
func _in_gun(i: int, bone: int) -> Vector3:
	var hand := _skeleton.get_bone_global_pose(_bones[i].hand)
	return _relative[i] * (hand.affine_inverse() * _skeleton.get_bone_global_pose(bone).origin)


## The chain's joints and tip in the gun's frame.
func _chain_points(i: int, chain: Array, tip: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	for bone: int in chain:
		points.append(_in_gun(i, bone))
	if tip >= 0:
		points.append(_in_gun(i, tip))
	else:
		points.append(points[2] + (points[2] - points[1]))
	return points


## True when the chain beyond joint `from` (its links from that joint out)
## touches the gun: along each link's line, and along its side facing the
## middle of what the hand holds (a finger's width in).
func _touches(surface: TriangleMesh, points: PackedVector3Array, from: int, middle: Vector3, chain: Array = []) -> bool:
	for k in range(from, points.size() - 1):
		var radius: float = _flesh.get(chain[k], tuning.arms_finger_radius) if k < chain.size() else tuning.arms_finger_radius
		radius += tuning.arms_flesh_margin
		var a := points[k]
		var b := points[k + 1]
		if k == 0:
			a = a.lerp(b, tuning.arms_knuckle_skip)  # the knuckle sits in the palm
		var along := (b - a).normalized()
		if not surface.intersect_segment(a, b).is_empty():
			return true
		# The phalanx is a tube a finger thick: a ring of lines round its bone.
		var inward := middle - (a + b) * 0.5
		inward = (inward - along * inward.dot(along)).normalized()
		var side := along.cross(inward).normalized()
		for n in 8:
			var angle := TAU * n / 8.0
			var offset := (inward * cos(angle) + side * sin(angle)) * radius
			if not surface.intersect_segment(a + offset, b + offset).is_empty():
				return true
	return false


## Closes a finger from straight the way a hand does (see Docs/HandBiomechanics.md):
## the knuckle (MCP) and middle joint (PIP) turn about their hinge at the
## bones' own pivots, the tip joint (DIP) always following at
## arms_dip_pip_coupling of the middle joint, every joint within its range
## (arms_mcp/pip/dip_max_degrees). First knuckle and middle joint close
## together until any part of the finger (a tube arms_finger_radius thick)
## would enter the gun; then the knuckle alone closes until the first
## phalanx meets it; then the middle joint (tip coupled) until the outer
## phalanges meet it. The finger ends wrapped on the surface, never inside it.
func _close_finger(i: int, chain: Array, tip: int, middle: Vector3, surface: TriangleMesh) -> void:
	var facts := _bones[i]
	var hinges: Array[Vector3] = []
	var rests: Array[Quaternion] = []
	for bone: int in chain:
		hinges.append((_skeleton.get_bone_global_rest(bone).basis.orthonormalized().inverse() * (facts.curl_axis as Vector3)).normalized())
		rests.append(_skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())
	# Which way is flexion: the one that brings the fingertip toward the grip.
	var sign := 1.0
	_pose_finger(chain, hinges, rests, 1.0, deg_to_rad(30.0), 0.0)
	var plus := _chain_points(i, chain, tip)[3].distance_to(middle)
	_pose_finger(chain, hinges, rests, -1.0, deg_to_rad(30.0), 0.0)
	var minus := _chain_points(i, chain, tip)[3].distance_to(middle)
	sign = 1.0 if plus < minus else -1.0
	var mcp_max := deg_to_rad(tuning.arms_mcp_max_degrees)
	var pip_max := deg_to_rad(tuning.arms_pip_max_degrees)
	var step := deg_to_rad(tuning.arms_close_step_degrees) * 0.5
	var mcp := 0.0
	var pip := 0.0
	# 1. Together, in a grasp's proportion.
	while mcp < mcp_max or pip < pip_max:
		var next_mcp := minf(mcp + step * tuning.arms_mcp_share, mcp_max)
		var next_pip := minf(pip + step, pip_max)
		_pose_finger(chain, hinges, rests, sign, next_mcp, next_pip)
		if _touches(surface, _chain_points(i, chain, tip), 0, middle, chain):
			break
		mcp = next_mcp
		pip = next_pip
	# 2. The knuckle until the first phalanx lies on the gun.
	while mcp < mcp_max:
		var next := minf(mcp + step, mcp_max)
		_pose_finger(chain, hinges, rests, sign, next, pip)
		if _touches(surface, _chain_points(i, chain, tip), 0, middle, chain):
			break
		mcp = next
	# 3. The middle joint (tip coupled) until the outer phalanges lie on it.
	while pip < pip_max:
		var next := minf(pip + step, pip_max)
		_pose_finger(chain, hinges, rests, sign, mcp, next)
		if _touches(surface, _chain_points(i, chain, tip), 1, middle, chain):
			break
		pip = next
	_pose_finger(chain, hinges, rests, sign, mcp, pip)


## Wraps a finger round what the hand holds, the way the reference grips do:
## its pad goes on the far side of the grip (or handguard) level with its own
## knuckle, so the finger encloses it. Every knuckle / middle-joint pair in
## the finger's range (tip coupled, Docs/HandBiomechanics.md) is tried; poses
## where any phalanx (its measured thickness) would enter the gun are
## rejected; the one whose pad lands closest to the target wins.
func _wrap_finger(i: int, chain: Array, tip: int, middle: Vector3, surface: TriangleMesh) -> void:
	var facts := _bones[i]
	var hinges: Array[Vector3] = []
	var rests: Array[Quaternion] = []
	for bone: int in chain:
		hinges.append((_skeleton.get_bone_global_rest(bone).basis.orthonormalized().inverse() * (facts.curl_axis as Vector3)).normalized())
		rests.append(_skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())
	_pose_finger(chain, hinges, rests, 1.0, deg_to_rad(30.0), 0.0)
	var plus := _chain_points(i, chain, tip)[3].distance_to(middle)
	_pose_finger(chain, hinges, rests, -1.0, deg_to_rad(30.0), 0.0)
	var minus := _chain_points(i, chain, tip)[3].distance_to(middle)
	var sign := 1.0 if plus < minus else -1.0
	# The target: through the held part, straight across from the knuckle,
	# out of the palm's side, on the far surface.
	_pose_finger(chain, hinges, rests, sign, 0.0, 0.0)
	var knuckle := _chain_points(i, chain, tip)[0]
	var palm := _relative[i] * (facts.palm as Vector3)
	var across := (middle - palm).normalized()  # palm side -> far side
	var level := knuckle + across * (middle - knuckle).dot(across)
	var hit := surface.intersect_segment(level + across * tuning.arms_wrap_search, level)
	var target: Vector3
	if hit.is_empty():
		target = level + across * 0.02
	else:
		target = (hit.position as Vector3) + across * (_flesh.get(chain[2], tuning.arms_finger_radius) as float)
	# Coarse over the whole range, then fine round the best coarse pose.
	var mcp_max := deg_to_rad(tuning.arms_mcp_max_degrees)
	var pip_max := deg_to_rad(tuning.arms_pip_max_degrees)
	var coarse := deg_to_rad(tuning.arms_wrap_step_degrees) * 2.0
	var found := _search_pose(i, chain, tip, hinges, rests, sign, middle, surface, target,
			Vector2.ZERO, Vector2(mcp_max, pip_max), coarse, Vector2(-1, -1), INF)
	var best: Vector2 = found[0]
	if best.x >= 0.0:
		var fine := deg_to_rad(tuning.arms_wrap_step_degrees) * 0.5
		var low := Vector2(maxf(best.x - coarse, 0.0), maxf(best.y - coarse, 0.0))
		var high := Vector2(minf(best.x + coarse, mcp_max), minf(best.y + coarse, pip_max))
		best = _search_pose(i, chain, tip, hinges, rests, sign, middle, surface, target, low, high, fine, best, found[1])[0]
	if best.x < 0.0:
		best = Vector2.ZERO  # nothing fits: straight
	_pose_finger(chain, hinges, rests, sign, best.x, best.y)


## Tries knuckle / middle-joint angles from `low` to `high` by `step`:
## returns [best angles, its cost], starting from `best` / `best_cost`.
func _search_pose(i: int, chain: Array, tip: int, hinges: Array[Vector3], rests: Array[Quaternion], sign: float,
		middle: Vector3, surface: TriangleMesh, target: Vector3, low: Vector2, high: Vector2, step: float,
		best: Vector2, best_cost: float) -> Array:
	var mcp := low.x
	while mcp <= high.x + 0.0001:
		var pip := low.y
		while pip <= high.y + 0.0001:
			_pose_finger(chain, hinges, rests, sign, mcp, pip)
			var points := _chain_points(i, chain, tip)
			var cost := points[2].lerp(points[3], tuning.arms_trigger_pad).distance_to(target)
			if cost < best_cost and not _touches(surface, points, 0, middle, chain) \
					and not _mesh_crosses(i, chain, surface):
				best_cost = cost
				best = Vector2(mcp, pip)
			pip += step
		mcp += step
	return [best, best_cost]


## Poses a finger: knuckle `mcp`, middle joint `pip`, tip coupled to it (radians).
func _pose_finger(chain: Array, hinges: Array[Vector3], rests: Array[Quaternion], sign: float, mcp: float, pip: float) -> void:
	var dip := minf(pip * tuning.arms_dip_pip_coupling, deg_to_rad(tuning.arms_dip_max_degrees))
	var angles := [mcp, pip, dip]
	for k in 3:
		_skeleton.set_bone_pose_rotation(chain[k], rests[k] * Quaternion(hinges[k], sign * float(angles[k])))


## Closes a finger (or the thumb) about its hinge axis `axis` (skeleton
## space, rest) on `surface` from the clip's shape: first opened (all joints
## together, if `may_open`) just until it touches nothing, then every joint turns a step at a time, base
## first; a joint stops when the chain beyond it would touch the gun, or at its
## limit (degrees per joint, past the clip's shape). The bending direction is
## the one that brings the tip toward `middle`.
func _close_chain(i: int, chain: Array, tip: int, axis: Vector3, limits: Vector3, middle: Vector3, surface: TriangleMesh, may_open: bool, thumb := false) -> void:
	var hinges: Array[Vector3] = []
	var rests: Array[Quaternion] = []
	for bone: int in chain:
		hinges.append((_skeleton.get_bone_global_rest(bone).basis.orthonormalized().inverse() * axis).normalized())
		rests.append(_skeleton.get_bone_pose_rotation(bone))  # the clip's
	# Which way closes: the tip moves toward what is held.
	var probe := deg_to_rad(10.0)
	_skeleton.set_bone_pose_rotation(chain[0], rests[0] * Quaternion(hinges[0], probe))
	var plus := _chain_points(i, chain, tip)[3].distance_to(middle)
	_skeleton.set_bone_pose_rotation(chain[0], rests[0] * Quaternion(hinges[0], -probe))
	var minus := _chain_points(i, chain, tip)[3].distance_to(middle)
	var sign := 1.0 if plus < minus else -1.0
	_skeleton.set_bone_pose_rotation(chain[0], rests[0])
	var step := deg_to_rad(tuning.arms_close_step_degrees)
	# Open out of the gun first, if the clip's shape sinks into it.
	var opened := 0.0
	while may_open and _touches(surface, _chain_points(i, chain, tip), 0, middle, chain) and opened < deg_to_rad(tuning.arms_open_max_degrees):
		opened += step
		for k in 3:
			if thumb and k == 0:
				continue  # a thumb backs out at its outer joints, never its base
			_skeleton.set_bone_pose_rotation(chain[k], rests[k] * Quaternion(hinges[k], -sign * opened))
	# Close all three joints together in a hand's natural ratio until the
	# finger meets the gun (one joint at a time, base first, left the base
	# straight and hooked the tips in like claws)...
	var ratio := tuning.arms_curl_ratio
	var weights := [ratio.x, ratio.y, ratio.z]
	var limit := [deg_to_rad(limits.x), deg_to_rad(limits.y), deg_to_rad(limits.z)]
	var angles := [0.0 if thumb else -opened, -opened, -opened]
	var t := 0.0
	while true:
		t += step
		var trial := [0.0, 0.0, 0.0]
		var moved := false
		for k in 3:
			trial[k] = minf(float(angles[k]) + step * float(weights[k]), limit[k]) if float(weights[k]) > 0.0 else float(angles[k])
			moved = moved or trial[k] > float(angles[k]) + 0.0001
			_skeleton.set_bone_pose_rotation(chain[k], rests[k] * Quaternion(hinges[k], sign * float(trial[k])))
		if not moved:
			break
		if _touches(surface, _chain_points(i, chain, tip), 0, middle, chain):
			for k in 3:
				_skeleton.set_bone_pose_rotation(chain[k], rests[k] * Quaternion(hinges[k], sign * float(angles[k])))
			break
		angles = trial
	# ...then each joint, the outer ones first, settles a few degrees more onto
	# the surface (no gap) without hooking in.
	var extra := deg_to_rad(tuning.arms_settle_degrees)
	for k in [1, 2, 0]:
		var start := float(angles[k])
		var settled := start
		var room := extra * (tuning.arms_tip_settle_share if k == 2 else 1.0)
		while settled < minf(start + room, limit[k]):
			var next := minf(settled + step * 0.5, limit[k])
			_skeleton.set_bone_pose_rotation(chain[k], rests[k] * Quaternion(hinges[k], sign * next))
			if _touches(surface, _chain_points(i, chain, tip), k, middle, chain):
				break
			settled = next
		_skeleton.set_bone_pose_rotation(chain[k], rests[k] * Quaternion(hinges[k], sign * settled))


## Bends the fingers round the grip: three joints sharing the grip's curl,
## the trigger finger nearly straight, the thumb across.
func _curl(i: int, grip: ViewArms.Grip) -> void:
	var facts := _bones[i]
	for f in FINGERS.size():
		var total := grip.curl_degrees * tuning.arms_curl_scale
		if f == 0 and grip.trigger_finger:
			total = tuning.arms_trigger_curl_degrees
		for k in 3:
			var joint: int = facts.fingers[f][k]
			_bend(joint, facts.curl_axis, deg_to_rad(total * [0.4, 0.35, 0.25][k]))
	var thumb := tuning.arms_thumb_curl_degrees * (0.5 if grip.thumb_along else 1.0)
	for k in 3:
		_bend(facts.thumb[k], facts.thumb_axis, deg_to_rad(thumb * [0.2, 0.4, 0.4][k]))


## Turns `bone` from its rest by `angle` about `axis` (skeleton space, rest).
func _bend(bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0:
		return
	var local_axis := (_skeleton.get_bone_global_rest(bone).basis.orthonormalized().inverse() * axis).normalized()
	_skeleton.set_bone_pose_rotation(bone, _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion() * Quaternion(local_axis, angle))


## An orthonormal frame with its first axis along `along` and its second as
## near `up` as it can be.
static func _frame(along: Vector3, up: Vector3) -> Basis:
	var forward := along.normalized()
	var side := forward.cross(up).normalized()
	return Basis(forward, side.cross(forward), side)


## Places hand i (0 right, 1 left) on `hold` (in the parent's space, like the
## gun) with its forearm reaching toward `elbow`.
func place(i: int, hold: Transform3D, elbow: Vector3) -> void:
	if _grips.is_empty():
		return
	var facts := _bones[i]
	var grip: ViewArms.Grip = _grips[i]
	var to_skeleton := _skeleton.global_transform.affine_inverse() * get_parent_node_3d().global_transform
	if _use_clip[i]:
		var target := to_skeleton * hold * _hold_inverse[i] * _relative[i]
		_reach(facts, target.basis.orthonormalized(), target.origin, to_skeleton * elbow, to_skeleton)
		return
	var hand := _hand_on(i, to_skeleton * hold, grip)
	_reach(facts, hand.basis, hand.origin, to_skeleton * elbow, to_skeleton)


## Hand i on `held` (a grip's hold, in any space): turned so the palm faces
## the grip's axis and the fingers run round its front, the palm on the grip's
## surface. Returns the hand bone's transform in that same space.
func _hand_on(i: int, held: Transform3D, grip: ViewArms.Grip) -> Transform3D:
	var facts := _bones[i]
	if grip.thumb_along:
		# A support hand under a handguard: rolled about the barrel so the palm
		# cups it from below rather than from the side.
		held.basis = held.basis * Basis(Vector3.UP, deg_to_rad(tuning.arms_support_roll_degrees))
	var side := -1.0 if grip.mirrored else 1.0
	# The hand: fingers round the front (-Z), palm toward the grip's axis.
	var fingers := (held.basis * Vector3.FORWARD).normalized()
	var palm := (held.basis * Vector3(-side, 0, 0)).normalized()
	if i == 1 and grip.mirrored:
		# The measured palm normal is the back of the left hand: a cupping left
		# hand turned by it faced the grip with its knuckles.
		palm = -palm
	var rest_frame: Basis = facts.frame
	var thumb_side: Vector3 = fingers.cross(palm)
	var turn := Basis(fingers, palm, thumb_side.normalized()) * rest_frame.inverse()
	var hand_rest := _skeleton.get_bone_global_rest(facts.hand)
	var hand_basis := (turn * hand_rest.basis.orthonormalized()).orthonormalized()
	var palm_at := held * Vector3(side * (grip.radius + tuning.arms_palm_gap), 0.0, 0.0)
	return Transform3D(hand_basis, palm_at - hand_basis * (facts.palm as Vector3))


## The arm from its shoulder (ViewModelTuning.arms_shoulder, below and beside
## the eye, mirrored for the left) to the hand at `wrist` turned to
## `hand_basis` (skeleton space): two-bone IK with the elbow bending down and
## out, the forearm taking part of the hand's twist. A hand out of reach
## draws the shoulder after it (off screen).
func _reach(facts: Dictionary, hand_basis: Basis, wrist: Vector3, _elbow_hint: Vector3, to_skeleton: Transform3D) -> void:
	var fore: float = facts.fore_length
	var upper: float = facts.upper_length
	var sign: float = facts.sign
	var base := tuning.arms_shoulder
	var shoulder_at := to_skeleton * Vector3(base.x * sign, base.y, base.z)
	var reach := (upper + fore) * 0.985
	if shoulder_at.distance_to(wrist) > reach:
		shoulder_at = wrist + (shoulder_at - wrist).normalized() * reach
	var span := wrist - shoulder_at
	var length := maxf(span.length(), 0.01)
	var along := span / length
	var pole := (to_skeleton.basis * Vector3(tuning.arms_elbow_pole.x * sign, tuning.arms_elbow_pole.y, tuning.arms_elbow_pole.z)).normalized()
	var bend := (pole - along * pole.dot(along)).normalized()
	var cos_shoulder := clampf((upper * upper + length * length - fore * fore) / (2.0 * upper * length), -1.0, 1.0)
	var elbow_point := shoulder_at + along * upper * cos_shoulder + bend * upper * sqrt(1.0 - cos_shoulder * cos_shoulder)
	var arm_basis := _swing(facts.arm, facts.forearm, elbow_point - shoulder_at)
	var fore_basis := _swing(facts.forearm, facts.hand, wrist - elbow_point)
	# Spread the hand's twist into the forearm so the wrist doesn't wring.
	var twist := _twist(fore_basis, hand_basis, (wrist - elbow_point).normalized())
	fore_basis = Basis((wrist - elbow_point).normalized(), twist * tuning.arms_forearm_twist) * fore_basis
	# Shoulder (clavicle) moved so the arm starts at shoulder_at, keeping its turn.
	var shoulder_rest := _skeleton.get_bone_global_rest(facts.shoulder)
	var arm_offset := _skeleton.get_bone_rest(facts.arm).origin
	var shoulder_global := Transform3D(shoulder_rest.basis, shoulder_at - shoulder_rest.basis * arm_offset)
	var parent := _skeleton.get_bone_parent(facts.shoulder)
	var parent_global := _skeleton.get_bone_global_rest(parent) if parent >= 0 else Transform3D.IDENTITY
	_set_global(facts.shoulder, parent_global, shoulder_global)
	var arm_global := Transform3D(arm_basis, shoulder_at)
	_set_rotation(facts.arm, shoulder_global, arm_global)
	var fore_global := Transform3D(fore_basis, elbow_point)
	_set_rotation(facts.forearm, arm_global, fore_global)
	_set_rotation(facts.hand, fore_global, Transform3D(hand_basis, wrist))


## The bone's rest basis swung so the line to `child` runs along `along`
## (not its +Y: older rigs' bones don't point at their children).
func _swing(bone: int, child: int, along: Vector3) -> Basis:
	var rest := _skeleton.get_bone_global_rest(bone)
	var toward := _skeleton.get_bone_global_rest(child).origin - rest.origin
	return (Basis(Quaternion(toward.normalized(), along.normalized())) * rest.basis.orthonormalized()).orthonormalized()


## Angle about `axis` from `from`'s X to `to`'s X, both flattened across it.
static func _twist(from: Basis, to: Basis, axis: Vector3) -> float:
	var a := (from.x - axis * from.x.dot(axis)).normalized()
	var b := (to.x - axis * to.x.dot(axis)).normalized()
	return atan2(axis.dot(a.cross(b)), a.dot(b))


func _set_global(bone: int, parent_global: Transform3D, global: Transform3D) -> void:
	var local := parent_global.affine_inverse() * global
	_skeleton.set_bone_pose_position(bone, local.origin)
	_skeleton.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())


func _set_rotation(bone: int, parent_global: Transform3D, global: Transform3D) -> void:
	var local := parent_global.basis.inverse() * global.basis
	_skeleton.set_bone_pose_rotation(bone, local.get_rotation_quaternion())
