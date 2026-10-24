class_name Mannequin
extends Node3D
## Procedural soldier on a pivot skeleton: hips, spine, neck, shoulders,
## elbows, hips, knees. Tapered limbs, shaped chest and head, helmet, plate
## carrier with pouches, belt, knee pads, gloves, boots and a carried weapon,
## with camouflage cloth from soldier_body.gdshader. Each body part (the
## pieces between two joints) is baked into one mesh (MeshBaker) on its own
## Node3D under its pivot, so the Soldier can copy part transforms into hit
## zones and, on death, hand the parts to ragdoll bodies; about a dozen draw
## calls per soldier. Procedural poses: stand / crouch blend, walk cycle, aim
## pitch, low ready, and a flinch spring.
##
## Rotation conventions (soldier faces -Z): a limb hanging along -Y swings
## forward with +X rotation; knees and elbows fold with -X / +X respectively.

const HIP_HEIGHT := 0.95
const CROUCH_HIP_HEIGHT := 0.58
const HUNKER_HIP_HEIGHT := 0.42
const STRIDE := 1.4
const BODY_SHADER := preload("res://ai/soldier_body.gdshader")
const UPPER_ARM := 0.29  # shoulder to elbow
const FOREARM := 0.29  # elbow to the middle of the hand

## Part name -> [pivot name, hit zone, mass kg] for hitboxes and the ragdoll.
const PARTS := {
	"pelvis": ["hips", "abdomen", 12.0],  # below the plate carrier
	"torso": ["spine", "torso", 18.0],
	"head": ["neck", "head", 5.0],
	"upper_arm_l": ["shoulder_l", "arms", 2.5],
	"lower_arm_l": ["elbow_l", "arms", 1.8],
	"upper_arm_r": ["shoulder_r", "arms", 2.5],
	"lower_arm_r": ["elbow_r", "arms", 1.8],
	"thigh_l": ["hip_l", "legs", 8.0],
	"shin_l": ["knee_l", "legs", 4.5],
	"thigh_r": ["hip_r", "legs", 8.0],
	"shin_r": ["knee_r", "legs", 4.5],
}

## Armour plate outline per part, in its hit shape's local X/Y (front and
## back plates, 30 x 30 cm, centred 4 cm above the torso capsule's middle).
const PLATES := {"torso": Rect2(-0.15, -0.11, 0.3, 0.3)}

var pivots: Dictionary = {}  # name -> Node3D
var parts: Dictionary = {}  # part name -> Node3D holding its meshes
## Collision shape per part, centred in the part's frame (hitbox and ragdoll).
var shapes: Dictionary = {}  # part name -> [Shape3D, Transform3D]
var gun: Node3D
var muzzle: Node3D

var _material: ShaderMaterial
var _grip := Vector3.ZERO  # hand holds, in the gun's frame
var _support := Vector3.ZERO
var _walk_phase := 0.0
var _flinch := Vector2.ZERO
var _flinch_velocity := Vector2.ZERO


func build(profile: EnemyProfile) -> void:
	_material = ShaderMaterial.new()
	_material.shader = BODY_SHADER
	_material.set_shader_parameter("camo_a", profile.uniform_color)
	_material.set_shader_parameter("camo_b", profile.camo_b)
	_material.set_shader_parameter("camo_c", profile.camo_c)
	var cloth := Color(1, 1, 1, 1)  # alpha 1: camo pattern
	var gear := Color(profile.gear_color, 0.0)
	var gear_dark := Color(profile.gear_color.darkened(0.35), 0.0)
	var skin := Color(0.62, 0.47, 0.38, 0.0)
	var face := Color(profile.gear_color.darkened(0.3), 0.0) if profile.balaclava else skin
	var boots := Color(0.13, 0.1, 0.08, 0.0)
	var gloves := Color(0.07, 0.07, 0.07, 0.0)
	var B := MeshBaker

	var hips := _pivot("hips", self, Vector3(0, HIP_HEIGHT, 0))
	var spine := _pivot("spine", hips, Vector3.ZERO)
	var neck := _pivot("neck", spine, Vector3(0, 0.55, 0))

	_part("pelvis", hips, BoxShape3D.new(), Vector3(0.32, 0.18, 0.2), Vector3.ZERO)
	var pelvis := MeshBaker.new()
	pelvis.add(B.sphere(1.0, 14), B.at(Vector3(0, -0.01, 0), Vector3.ZERO, Vector3(0.17, 0.12, 0.12)), cloth)
	pelvis.add(B.cylinder(0.165, 0.165, 0.05, 14), B.at(Vector3(0, 0.08, 0), Vector3.ZERO, Vector3(1, 1, 0.78)), gear_dark)  # belt
	pelvis.add(B.box(Vector3(0.05, 0.04, 0.02)), B.at(Vector3(0, 0.08, -0.135)), Color(0.35, 0.33, 0.28, 0))  # buckle
	for side in [-1.0, 1.0]:
		pelvis.add(B.box(Vector3(0.05, 0.09, 0.07)), B.at(Vector3(side * 0.16, 0.02, 0.03)), gear)  # belt pouches
	_bake(parts.pelvis, pelvis)

	_part("torso", spine, CapsuleShape3D.new(), Vector3(0.17, 0.55, 0), Vector3(0, 0.32, 0))
	var torso := MeshBaker.new()
	torso.add(B.cylinder(0.15, 0.14, 0.24, 14), B.at(Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(1, 1, 0.78)), cloth)  # abdomen
	torso.add(B.sphere(1.0, 16), B.at(Vector3(0, 0.37, 0), Vector3.ZERO, Vector3(0.19, 0.21, 0.13)), cloth)  # chest
	torso.add(B.capsule(0.07, 0.42, 10), B.at(Vector3(0, 0.47, 0), Vector3(0, 0, 90), Vector3(1, 1, 0.8)), cloth)  # shoulders
	torso.add(B.box(Vector3(0.3, 0.3, 0.05)), B.at(Vector3(0, 0.36, -0.115)), gear)  # front plate
	torso.add(B.box(Vector3(0.3, 0.32, 0.05)), B.at(Vector3(0, 0.37, 0.115)), gear)  # back plate
	torso.add(B.cylinder(0.165, 0.16, 0.11, 14), B.at(Vector3(0, 0.25, 0), Vector3.ZERO, Vector3(1, 1, 0.82)), gear)  # cummerbund
	for x in [-0.085, 0.0, 0.085]:
		torso.add(B.box(Vector3(0.065, 0.11, 0.045)), B.at(Vector3(x, 0.29, -0.155)), gear_dark)  # magazine pouches
	for side in [-1.0, 1.0]:
		torso.add(B.box(Vector3(0.06, 0.03, 0.27)), B.at(Vector3(side * 0.11, 0.52, 0)), gear)  # shoulder straps
	torso.add(B.box(Vector3(0.08, 0.16, 0.05)), B.at(Vector3(-0.09, 0.4, 0.165)), gear_dark)  # radio
	torso.add(B.cylinder(0.006, 0.006, 0.22, 4), B.at(Vector3(-0.11, 0.56, 0.17)), gloves)  # antenna
	_bake(parts.torso, torso)

	_part("head", neck, SphereShape3D.new(), Vector3(0.11, 0, 0), Vector3(0, 0.12, 0))
	var head := MeshBaker.new()
	head.add(B.cylinder(0.05, 0.055, 0.1, 10), B.at(Vector3(0, 0.03, 0)), face)  # neck
	head.add(B.sphere(1.0, 16), B.at(Vector3(0, 0.13, 0), Vector3.ZERO, Vector3(0.095, 0.115, 0.105)), face)
	head.add(B.box(Vector3(0.022, 0.035, 0.03)), B.at(Vector3(0, 0.12, -0.103), Vector3(-15, 0, 0)), face)  # nose
	for side in [-1.0, 1.0]:
		head.add(B.sphere(0.022, 6), B.at(Vector3(side * 0.095, 0.125, 0.005), Vector3.ZERO, Vector3(0.6, 1, 1)), face)  # ears
		head.add(B.sphere(0.011, 6), B.at(Vector3(side * 0.034, 0.15, -0.092)), Color(0.05, 0.04, 0.04, 0))  # eyes
	head.add(B.sphere(0.125, 16, true), B.at(Vector3(0, 0.165, 0.008), Vector3.ZERO, Vector3(1, 0.9, 1.06)), gear)  # helmet
	head.add(B.torus(0.118, 0.134), B.at(Vector3(0, 0.168, 0.008), Vector3.ZERO, Vector3(1, 0.35, 1.06)), gear_dark)  # brim
	head.add(B.box(Vector3(0.05, 0.035, 0.03)), B.at(Vector3(0, 0.22, -0.115), Vector3(20, 0, 0)), gear_dark)  # NVG mount
	head.add(B.box(Vector3(0.02, 0.07, 0.015)), B.at(Vector3(0.09, 0.12, 0.02)), gear_dark)  # chin strap
	head.add(B.box(Vector3(0.02, 0.07, 0.015)), B.at(Vector3(-0.09, 0.12, 0.02)), gear_dark)
	_bake(parts.head, head)

	for side in [-1.0, 1.0]:
		var suffix := "_l" if side < 0.0 else "_r"
		var shoulder := _pivot("shoulder" + suffix, spine, Vector3(side * 0.22, 0.48, 0))
		var elbow := _pivot("elbow" + suffix, shoulder, Vector3(0, -0.29, 0))
		var hip := _pivot("hip" + suffix, hips, Vector3(side * 0.1, 0, 0))
		var knee := _pivot("knee" + suffix, hip, Vector3(0, -0.45, 0))

		_part("upper_arm" + suffix, shoulder, CapsuleShape3D.new(), Vector3(0.05, 0.3, 0), Vector3(0, -0.15, 0))
		var upper_arm := MeshBaker.new()
		upper_arm.add(B.sphere(0.063, 12), B.at(Vector3(0, -0.025, 0)), cloth)  # deltoid
		upper_arm.add(B.cylinder(0.053, 0.043, 0.27, 12), B.at(Vector3(0, -0.15, 0)), cloth)
		upper_arm.add(B.box(Vector3(0.012, 0.07, 0.06)), B.at(Vector3(side * 0.053, -0.08, 0)), gear_dark)  # patch
		_bake(parts["upper_arm" + suffix], upper_arm)

		_part("lower_arm" + suffix, elbow, CapsuleShape3D.new(), Vector3(0.045, 0.28, 0), Vector3(0, -0.14, 0))
		var forearm := MeshBaker.new()
		forearm.add(B.sphere(0.046, 10), B.at(Vector3.ZERO), cloth)  # elbow
		forearm.add(B.cylinder(0.045, 0.035, 0.25, 12), B.at(Vector3(0, -0.13, 0)), cloth)
		forearm.add(B.sphere(1.0, 10), B.at(Vector3(0, -0.29, -0.005), Vector3.ZERO, Vector3(0.038, 0.055, 0.03)), gloves)  # glove
		_bake(parts["lower_arm" + suffix], forearm)

		_part("thigh" + suffix, hip, CapsuleShape3D.new(), Vector3(0.075, 0.45, 0), Vector3(0, -0.22, 0))
		var thigh := MeshBaker.new()
		thigh.add(B.sphere(0.08, 12), B.at(Vector3(0, -0.02, 0)), cloth)
		thigh.add(B.cylinder(0.085, 0.06, 0.42, 12), B.at(Vector3(0, -0.22, 0)), cloth)
		thigh.add(B.box(Vector3(0.03, 0.12, 0.09)), B.at(Vector3(side * 0.075, -0.24, 0)), cloth)  # cargo pocket
		_bake(parts["thigh" + suffix], thigh)

		_part("shin" + suffix, knee, CapsuleShape3D.new(), Vector3(0.06, 0.45, 0), Vector3(0, -0.22, 0))
		var shin := MeshBaker.new()
		shin.add(B.sphere(1.0, 10), B.at(Vector3(0, 0.0, -0.035), Vector3.ZERO, Vector3(0.068, 0.075, 0.045)), gear)  # knee pad
		shin.add(B.cylinder(0.06, 0.045, 0.36, 12), B.at(Vector3(0, -0.19, 0)), cloth)
		shin.add(B.cylinder(0.05, 0.055, 0.12, 12), B.at(Vector3(0, -0.4, 0)), boots)  # boot shaft
		shin.add(B.sphere(1.0, 10), B.at(Vector3(0, -0.445, -0.06), Vector3.ZERO, Vector3(0.05, 0.035, 0.1)), boots)  # foot
		shin.add(B.box(Vector3(0.1, 0.02, 0.24)), B.at(Vector3(0, -0.47, -0.04)), Color(0.06, 0.05, 0.04, 0))  # sole
		_bake(parts["shin" + suffix], shin)

	# The weapon rides on the torso, pointing where the spine points.
	gun = Node3D.new()
	gun.position = Vector3(0.1, 0.42, -0.3)
	spine.add_child(gun)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0.015, _bake_gun(profile))
	gun.add_child(muzzle)


## Builds the carried weapon (rifle or pump shotgun) as one mesh; returns the
## muzzle's z.
func _bake_gun(profile: EnemyProfile) -> float:
	var B := MeshBaker
	var metal := Color(0.1, 0.1, 0.11, 0)
	var polymer := Color(0.16, 0.16, 0.15, 0)
	var wood := Color(0.42, 0.27, 0.15, 0)
	var weapon := MeshBaker.new()
	var muzzle_z: float
	if profile.weapon != null and profile.weapon.view_style == WeaponDefinition.ViewStyle.SHOTGUN:
		weapon.add(B.box(Vector3(0.05, 0.065, 0.22)), B.at(Vector3.ZERO), metal)  # receiver
		weapon.add(B.cylinder(0.013, 0.013, 0.5, 8), B.at(Vector3(0, 0.02, -0.36), Vector3(90, 0, 0)), metal)  # barrel
		weapon.add(B.cylinder(0.012, 0.012, 0.42, 8), B.at(Vector3(0, -0.012, -0.32), Vector3(90, 0, 0)), metal)  # magazine tube
		weapon.add(B.cylinder(0.022, 0.022, 0.14, 10), B.at(Vector3(0, -0.012, -0.24), Vector3(90, 0, 0)), wood)  # pump
		weapon.add(B.box(Vector3(0.04, 0.07, 0.26)), B.at(Vector3(0, -0.03, 0.24), Vector3(-8, 0, 0)), wood)  # stock
		_grip = Vector3(0, -0.06, 0.1)
		_support = Vector3(0, -0.02, -0.22)
		muzzle_z = -0.61
	else:
		weapon.add(B.box(Vector3(0.045, 0.07, 0.3)), B.at(Vector3.ZERO), metal)  # receiver
		weapon.add(B.box(Vector3(0.025, 0.012, 0.28)), B.at(Vector3(0, 0.041, 0)), metal)  # rail
		weapon.add(B.cylinder(0.027, 0.027, 0.22, 8), B.at(Vector3(0, 0.01, -0.26), Vector3(90, 0, 0)), polymer)  # handguard
		weapon.add(B.cylinder(0.009, 0.009, 0.2, 8), B.at(Vector3(0, 0.01, -0.45), Vector3(90, 0, 0)), metal)  # barrel
		weapon.add(B.box(Vector3(0.028, 0.15, 0.06)), B.at(Vector3(0, -0.1, -0.06), Vector3(12, 0, 0)), metal)  # magazine
		weapon.add(B.box(Vector3(0.03, 0.08, 0.035)), B.at(Vector3(0, -0.07, 0.09), Vector3(-18, 0, 0)), polymer)  # grip
		weapon.add(B.box(Vector3(0.04, 0.08, 0.2)), B.at(Vector3(0, -0.01, 0.24)), polymer)  # stock
		weapon.add(B.box(Vector3(0.03, 0.04, 0.09)), B.at(Vector3(0, 0.066, -0.02)), metal)  # optic
		_grip = Vector3(0, -0.09, 0.1)
		_support = Vector3(0, -0.01, -0.19)
		muzzle_z = -0.55
	_bake(gun, weapon)
	return muzzle_z


## Poses the body. crouch 0..1, aim_pitch radians (+ up), speed m/s,
## aiming = weapon up (else low ready). hunker 0..1 folds a crouch into a
## hunched kneel (head ~1 m up) for hiding behind waist-high cover.
func pose(delta: float, crouch: float, aim_pitch: float, speed: float, aiming: bool, hunker: float = 0.0) -> void:
	pivots.hips.position.y = lerpf(lerpf(HIP_HEIGHT, CROUCH_HIP_HEIGHT, crouch), HUNKER_HIP_HEIGHT, hunker)
	aim_pitch *= 1.0 - hunker
	_walk_phase = fmod(_walk_phase + speed * delta / STRIDE * PI, TAU)
	var swing := deg_to_rad(28.0) * clampf(speed / 3.0, 0.0, 1.0)
	for side in [["_l", 0.0], ["_r", PI]]:
		var phase: float = _walk_phase + side[1]
		var thigh := lerpf(lerpf(0.0, deg_to_rad(75.0), crouch), deg_to_rad(90.0), hunker) + sin(phase) * swing
		var knee := lerpf(lerpf(0.0, deg_to_rad(-115.0), crouch), deg_to_rad(-145.0), hunker) \
				- maxf(0.0, -sin(phase)) * swing * 1.5
		pivots["hip" + side[0]].rotation.x = thigh
		pivots["knee" + side[0]].rotation.x = knee

	# Flinch spring: hits push the torso around, it recovers.
	_flinch_velocity += (-120.0 * _flinch - 14.0 * _flinch_velocity) * delta
	_flinch += _flinch_velocity * delta
	var lean := deg_to_rad(8.0) * clampf(speed / 5.0, 0.0, 1.0) * (1.0 - crouch)
	pivots.spine.rotation = Vector3(aim_pitch * 0.5 - lean - deg_to_rad(40.0) * hunker + _flinch.x, 0.0, _flinch.y)
	pivots.neck.rotation.x = aim_pitch * 0.5 - deg_to_rad(15.0) * hunker

	gun.rotation.x = 0.0 if aiming else deg_to_rad(-35.0)
	# Both hands on the weapon: right on the grip, left on the handguard / pump.
	_reach("_r", gun.transform * _grip, Vector3(0.6, -1.0, 0.4))
	_reach("_l", gun.transform * _support, Vector3(-0.5, -1.0, 0.1))


## Two-bone IK in the spine's space: turns the shoulder and folds the elbow so
## the hand lands on `target`, the elbow bending towards `pole`. The elbow is a
## hinge about the upper arm's X axis (+X folds the forearm forward), the same
## axis the ragdoll's elbow joint uses.
func _reach(suffix: String, target: Vector3, pole: Vector3) -> void:
	var shoulder: Node3D = pivots["shoulder" + suffix]
	var to_target := target - shoulder.position
	var distance := clampf(to_target.length(), 0.05, (UPPER_ARM + FOREARM) * 0.999)
	var direction := to_target.normalized()
	var cos_upper := (UPPER_ARM * UPPER_ARM + distance * distance - FOREARM * FOREARM) / (2.0 * UPPER_ARM * distance)
	var bend_side := (pole - direction * pole.dot(direction)).normalized()
	var upper := direction * clampf(cos_upper, -1.0, 1.0) + bend_side * sqrt(maxf(0.0, 1.0 - cos_upper * cos_upper))
	var forearm := (shoulder.position + direction * distance - (shoulder.position + upper * UPPER_ARM)).normalized()
	var forward := forearm - upper * forearm.dot(upper)
	if forward.length_squared() < 1e-6:
		forward = -bend_side
	var y := -upper
	var z := -forward.normalized()
	shoulder.basis = Basis(y.cross(z), y, z)
	pivots["elbow" + suffix].rotation = Vector3(acos(clampf(upper.dot(forearm), -1.0, 1.0)), 0.0, 0.0)


## Straight standing pose (all joints at zero), used to build ragdoll joints
## whose limits are anatomical. Updates transforms immediately.
func neutral_pose() -> void:
	for pivot: Node3D in pivots.values():
		pivot.rotation = Vector3.ZERO
	pivots.hips.position.y = HIP_HEIGHT
	force_update_transform()
	for pivot: Node3D in pivots.values():
		pivot.force_update_transform()


## Knocks the torso away from a hit (direction in world space).
func flinch(direction: Vector3, strength: float) -> void:
	var local := global_basis.inverse() * direction
	_flinch_velocity += Vector2(-local.z, local.x) * strength


func _pivot(pivot_name: String, parent: Node3D, at: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = pivot_name
	pivot.position = at
	parent.add_child(pivot)
	pivots[pivot_name] = pivot
	return pivot


## A body part under a pivot, with its collision shape. size: box extents,
## or (radius, height) for capsules, or (radius) for spheres.
func _part(part_name: String, pivot: Node3D, shape: Shape3D, size: Vector3, center: Vector3) -> void:
	var part := Node3D.new()
	part.name = part_name
	pivot.add_child(part)
	parts[part_name] = part
	if shape is BoxShape3D:
		shape.size = size
	elif shape is CapsuleShape3D:
		shape.radius = size.x
		shape.height = size.y
	elif shape is SphereShape3D:
		shape.radius = size.x
	shapes[part_name] = [shape, Transform3D(Basis.IDENTITY, center)]


func _bake(part: Node3D, baker: MeshBaker) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = baker.commit(_material)
	part.add_child(instance)
