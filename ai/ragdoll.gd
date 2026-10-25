class_name Ragdoll
extends Node3D
## Death physics for a Mannequin. Every body part is handed to its own
## RigidBody3D and joined to its parent with a Generic6DOFJoint3D whose
## per-axis angle limits are anatomical: knees and elbows bend one way only,
## hips and shoulders swing further forward than back, spine and neck twist
## a little. Limits are measured from the straight (neutral) pose, not the
## pose the soldier died in: the joints are built with the body straightened,
## then the parts are put back where they were. The killing round nudges the
## struck part (a velocity change, so light limbs don't fly off); the weapon
## drops as its own body.

## [child part, parent part, joint pivot, [X lower, X upper], [Y lower, Y upper], [Z lower, Z upper]]
## Degrees in the pivot's frame: X = bend (forward/back), Y = twist, Z = sideways.
## Sign follows Mannequin: limbs hanging down swing forward with +X, knees
## fold back with -X, elbows fold forward with +X, the spine leans back with +X.
const JOINTS := [
	["torso", "pelvis", "spine", [-40.0, 15.0], [-25.0, 25.0], [-20.0, 20.0]],
	["head", "torso", "neck", [-45.0, 35.0], [-60.0, 60.0], [-30.0, 30.0]],
	["upper_arm_l", "torso", "shoulder_l", [-50.0, 150.0], [-45.0, 45.0], [-80.0, 20.0]],
	["upper_arm_r", "torso", "shoulder_r", [-50.0, 150.0], [-45.0, 45.0], [-20.0, 80.0]],
	["lower_arm_l", "upper_arm_l", "elbow_l", [0.0, 145.0], [0.0, 0.0], [0.0, 0.0]],
	["lower_arm_r", "upper_arm_r", "elbow_r", [0.0, 145.0], [0.0, 0.0], [0.0, 0.0]],
	["thigh_l", "pelvis", "hip_l", [-15.0, 110.0], [-25.0, 25.0], [-35.0, 15.0]],
	["thigh_r", "pelvis", "hip_r", [-15.0, 110.0], [-25.0, 25.0], [-15.0, 35.0]],
	["shin_l", "thigh_l", "knee_l", [-150.0, 0.0], [0.0, 0.0], [0.0, 0.0]],
	["shin_r", "thigh_r", "knee_r", [-150.0, 0.0], [0.0, 0.0], [0.0, 0.0]],
]
const LINEAR_DAMP := 0.6
const ANGULAR_DAMP := 4.0
const GUN_MASS := 3.5

var bodies: Dictionary = {}  # part name -> RigidBody3D


## Builds a ragdoll in `parent` from the mannequin's current pose. `velocity`
## is the body's motion at death; the struck part (`hit_part`) gets an extra
## `push` (world velocity change, m/s).
static func from_mannequin(mannequin: Mannequin, parent: Node, velocity: Vector3,
		hit_part: String, push: Vector3) -> Ragdoll:
	var ragdoll := Ragdoll.new()
	ragdoll.name = "Ragdoll"
	parent.add_child(ragdoll)
	var death_pose := {}
	for part_name: String in Mannequin.PARTS:
		var part: Node3D = mannequin.parts[part_name]
		death_pose[part_name] = part.global_transform
		var body := _body(ragdoll, part_name, part.global_transform, Mannequin.PARTS[part_name][2])
		var shape_info: Array = mannequin.shapes[part_name]
		var collision := CollisionShape3D.new()
		collision.shape = shape_info[0]
		collision.transform = shape_info[1]
		body.add_child(collision)
		part.reparent(body)
		ragdoll.bodies[part_name] = body

	# Joints are built with the body straight so limits are anatomical...
	mannequin.neutral_pose()
	for part_name: String in Mannequin.PARTS:
		ragdoll.bodies[part_name].global_transform = mannequin.pivots[Mannequin.PARTS[part_name][0]].global_transform
	for spec in JOINTS:
		ragdoll._join(spec, mannequin.pivots[spec[2]])
	# ...then the parts go back to where they were at death.
	for part_name: String in Mannequin.PARTS:
		var body: RigidBody3D = ragdoll.bodies[part_name]
		body.global_transform = death_pose[part_name]
		body.linear_velocity = velocity
	var struck: RigidBody3D = ragdoll.bodies.get(hit_part, ragdoll.bodies.torso)
	struck.linear_velocity += push

	var gun_body := _body(ragdoll, "Gun", mannequin.gun.global_transform, GUN_MASS)
	var gun_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.06, 0.12, 0.65)
	gun_shape.shape = box
	gun_shape.position = Vector3(0, 0, -0.15)
	gun_body.add_child(gun_shape)
	mannequin.gun.reparent(gun_body)
	gun_body.linear_velocity = velocity
	return ragdoll


static func _body(ragdoll: Ragdoll, body_name: String, at: Transform3D, mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = body_name
	body.mass = mass
	body.collision_layer = PhysicsLayers.DEBRIS
	body.collision_mask = PhysicsLayers.WORLD
	body.linear_damp = LINEAR_DAMP
	body.angular_damp = ANGULAR_DAMP
	ragdoll.add_child(body)
	body.global_transform = at
	return body


## The joint measures its angle with the opposite sign to Mannequin's pivot
## rotations (measured: a [-150, 0] knee let the shin swing forward), so each
## [lower, upper] range is mirrored to [-upper, -lower].
func _join(spec: Array, pivot: Node3D) -> void:
	var joint := Generic6DOFJoint3D.new()
	var x: Array = spec[3]
	var y: Array = spec[4]
	var z: Array = spec[5]
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-x[1]))
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(-x[0]))
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-y[1]))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(-y[0]))
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(-z[1]))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(-z[0]))
	add_child(joint)
	joint.global_transform = Transform3D(pivot.global_basis.orthonormalized(), pivot.global_position)
	joint.node_a = joint.get_path_to(bodies[spec[1]])
	joint.node_b = joint.get_path_to(bodies[spec[0]])


## True once every part has come to rest.
func settled() -> bool:
	for body: RigidBody3D in bodies.values():
		if not body.sleeping and body.linear_velocity.length() > 0.15:
			return false
	return true


## Signed bend (degrees) of `child` relative to `parent` about the parent's
## left-right axis, in Mannequin's sign convention (knees fold negative,
## elbows fold positive). For tests.
func bend(parent: String, child: String) -> float:
	var upper: RigidBody3D = bodies[parent]
	var lower: RigidBody3D = bodies[child]
	var lateral := upper.global_basis.x
	var a := -upper.global_basis.y
	var b := -lower.global_basis.y
	return rad_to_deg(atan2(a.cross(b).dot(lateral), a.dot(b)))


## Physics can't recover a body that went non-finite (it floods the log
## every step): report it once and remove the corpse.
func _physics_process(_delta: float) -> void:
	for body: RigidBody3D in bodies.values():
		if is_instance_valid(body) and not (body.global_position.is_finite() and body.linear_velocity.is_finite()):
			push_error("Ragdoll %s part %s went non-finite: position %s velocity %s - removed" % [
					name, body.name, body.global_position, body.linear_velocity])
			queue_free()
			return
