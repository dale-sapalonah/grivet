class_name Mannequin
extends Node3D
## Placeholder soldier built from capsules on a pivot skeleton: hips, spine,
## neck, shoulders, elbows, hips, knees. Each body part (the meshes between
## two joints) is its own Node3D under its pivot so the Soldier can copy part
## transforms into hit zones and, on death, hand the parts to ragdoll bodies.
## Procedural poses: stand / crouch blend, walk cycle, aim pitch, low ready,
## and a flinch spring. Real characters replace this in Milestone 4.
##
## Rotation conventions (soldier faces -Z): a limb hanging along -Y swings
## forward with +X rotation; knees and elbows fold with -X / +X respectively.

const HIP_HEIGHT := 0.95
const CROUCH_HIP_HEIGHT := 0.58
const HUNKER_HIP_HEIGHT := 0.42
const STRIDE := 1.4

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

var pivots: Dictionary = {}  # name -> Node3D
var parts: Dictionary = {}  # part name -> Node3D holding its meshes
## Collision shape per part, centred in the part's frame (hitbox and ragdoll).
var shapes: Dictionary = {}  # part name -> [Shape3D, Transform3D]
var gun: Node3D
var muzzle: Node3D

var _walk_phase := 0.0
var _flinch := Vector2.ZERO
var _flinch_velocity := Vector2.ZERO


func build(profile: EnemyProfile) -> void:
	var uniform := _material(profile.uniform_color, 0.85)
	var gear := _material(profile.gear_color, 0.7)
	var skin := _material(Color(0.55, 0.42, 0.33), 0.8)
	var metal := _material(Color(0.1, 0.1, 0.1), 0.5)

	var hips := _pivot("hips", self, Vector3(0, HIP_HEIGHT, 0))
	var spine := _pivot("spine", hips, Vector3.ZERO)
	var neck := _pivot("neck", spine, Vector3(0, 0.55, 0))
	_part("pelvis", hips, BoxShape3D.new(), Vector3(0.32, 0.18, 0.2), Vector3.ZERO)
	_box_mesh(parts.pelvis, Vector3(0.32, 0.18, 0.2), Vector3.ZERO, uniform)
	_part("torso", spine, CapsuleShape3D.new(), Vector3(0.17, 0.55, 0), Vector3(0, 0.32, 0))
	_capsule_mesh(parts.torso, 0.17, 0.55, Vector3(0, 0.32, 0), uniform)
	_box_mesh(parts.torso, Vector3(0.36, 0.34, 0.26), Vector3(0, 0.36, 0), gear)  # plate carrier
	_part("head", neck, SphereShape3D.new(), Vector3(0.11, 0, 0), Vector3(0, 0.12, 0))
	_sphere_mesh(parts.head, 0.11, Vector3(0, 0.12, 0), skin)
	var helmet := _sphere_mesh(parts.head, 0.125, Vector3(0, 0.19, 0.015), gear)
	helmet.scale = Vector3(1.0, 0.65, 1.05)  # sits on top, face shows below the brim

	for side in [-1.0, 1.0]:
		var suffix := "_l" if side < 0.0 else "_r"
		var shoulder := _pivot("shoulder" + suffix, spine, Vector3(side * 0.22, 0.48, 0))
		var elbow := _pivot("elbow" + suffix, shoulder, Vector3(0, -0.29, 0))
		_part("upper_arm" + suffix, shoulder, CapsuleShape3D.new(), Vector3(0.05, 0.3, 0), Vector3(0, -0.15, 0))
		_capsule_mesh(parts["upper_arm" + suffix], 0.05, 0.3, Vector3(0, -0.15, 0), uniform)
		_part("lower_arm" + suffix, elbow, CapsuleShape3D.new(), Vector3(0.045, 0.28, 0), Vector3(0, -0.14, 0))
		_capsule_mesh(parts["lower_arm" + suffix], 0.045, 0.28, Vector3(0, -0.14, 0), uniform)
		_sphere_mesh(parts["lower_arm" + suffix], 0.045, Vector3(0, -0.29, 0), skin)  # hand

		var hip := _pivot("hip" + suffix, hips, Vector3(side * 0.1, 0, 0))
		var knee := _pivot("knee" + suffix, hip, Vector3(0, -0.45, 0))
		_part("thigh" + suffix, hip, CapsuleShape3D.new(), Vector3(0.075, 0.45, 0), Vector3(0, -0.22, 0))
		_capsule_mesh(parts["thigh" + suffix], 0.075, 0.45, Vector3(0, -0.22, 0), uniform)
		_part("shin" + suffix, knee, CapsuleShape3D.new(), Vector3(0.06, 0.45, 0), Vector3(0, -0.22, 0))
		_capsule_mesh(parts["shin" + suffix], 0.06, 0.45, Vector3(0, -0.22, 0), uniform)
		_box_mesh(parts["shin" + suffix], Vector3(0.1, 0.07, 0.24), Vector3(0, -0.46, -0.05), gear)  # boot

	# The rifle rides on the torso, pointing where the spine points.
	gun = Node3D.new()
	gun.position = Vector3(0.1, 0.42, -0.3)
	spine.add_child(gun)
	_box_mesh(gun, Vector3(0.05, 0.08, 0.42), Vector3.ZERO, metal)
	_box_mesh(gun, Vector3(0.03, 0.12, 0.05), Vector3(0, -0.08, -0.04), metal)  # magazine
	var barrel_length := 0.25
	var barrel := _box_mesh(gun, Vector3(0.025, 0.025, barrel_length), Vector3(0, 0.015, -0.21 - barrel_length * 0.5), metal)
	barrel.name = "Barrel"
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0.015, -0.21 - barrel_length)
	gun.add_child(muzzle)


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

	var shoulder := deg_to_rad(82.0) if aiming else deg_to_rad(25.0)
	var elbow := deg_to_rad(15.0) if aiming else deg_to_rad(60.0)
	pivots.shoulder_r.rotation = Vector3(shoulder, deg_to_rad(-8.0), 0.0)
	pivots.elbow_r.rotation.x = elbow
	pivots.shoulder_l.rotation = Vector3(shoulder - deg_to_rad(10.0), deg_to_rad(30.0), 0.0)
	pivots.elbow_l.rotation.x = elbow + deg_to_rad(25.0)
	gun.rotation.x = 0.0 if aiming else deg_to_rad(-35.0)


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


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _box_mesh(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _instance(parent, mesh, at, material)


func _capsule_mesh(parent: Node3D, radius: float, height: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 4
	return _instance(parent, mesh, at, material)


func _sphere_mesh(parent: Node3D, radius: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return _instance(parent, mesh, at, material)


func _instance(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	parent.add_child(instance)
	return instance
