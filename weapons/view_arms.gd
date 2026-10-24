class_name ViewArms
extends Node3D
## First-person arms: two gloved hands closed around the weapon and forearms
## running back to elbows below the screen (bare wrist, rolled camouflage
## sleeve). Procedural like the rest of the view model.
##
## Each hand is built around a grip: a cylinder of `radius` along the hand's
## local Y axis. The palm sits on the hand's +X side (−X when mirrored),
## fingers curl from there around the front (−Z) to the far side, the thumb
## wraps round the back (+Z). The trigger finger, when asked for, lies forward
## instead. The WeaponViewModel places the hands on the weapon each frame and
## the forearms stretch from each wrist to its elbow.

## One hand: where it holds, how it is shaped.
class Grip:
	var radius := 0.02
	var mirrored := false
	var trigger_finger := false
	## How far round the grip the fingertips reach (degrees from the palm).
	var curl_degrees := 192.0
	## Thumb laid forward along the grip on the palm's near side (a support
	## hand under a handguard) instead of wrapped round the back.
	var thumb_along := false
	## Wrist point in the hand's own frame (where the forearm starts).
	var wrist := Vector3.ZERO

	func _init(grip_radius: float, wrist_point: Vector3, is_mirrored := false, has_trigger_finger := false) -> void:
		radius = grip_radius
		wrist = wrist_point
		mirrored = is_mirrored
		trigger_finger = has_trigger_finger


	## A support hand under a barrel-axis part: fingers curl under to the far
	## side and stop there, thumb forward along the near side.
	static func support(grip_radius: float, wrist_point: Vector3) -> Grip:
		var grip := Grip.new(grip_radius, wrist_point)
		grip.curl_degrees = 130.0
		grip.thumb_along = true
		return grip


const BODY_SHADER := preload("res://ai/soldier_body.gdshader")
const FINGER_SEGMENTS := 6

var tuning: ViewModelTuning

var _material: ShaderMaterial
var _hands: Array[MeshInstance3D] = []
var _forearms: Array[MeshInstance3D] = []
var _grips: Array[Grip] = []


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = BODY_SHADER
	_material.set_shader_parameter("camo_a", tuning.sleeve_camo_a)
	_material.set_shader_parameter("camo_b", tuning.sleeve_camo_b)
	_material.set_shader_parameter("camo_c", tuning.sleeve_camo_c)
	_material.set_shader_parameter("camo_scale", 30.0)
	for i in 2:
		var hand := _instance()
		var forearm := _instance()
		forearm.mesh = _forearm_mesh()
		_hands.append(hand)
		_forearms.append(forearm)


## Shapes the hands for a weapon: [right grip, left grip].
func build(right: Grip, left: Grip) -> void:
	_grips = [right, left]
	for i in 2:
		_hands[i].mesh = _hand_mesh(_grips[i])


## Places hand i (0 right, 1 left) at `hold` (in this node's parent's space,
## like the gun) and stretches its forearm to `elbow`.
func place(i: int, hold: Transform3D, elbow: Vector3) -> void:
	if _grips.is_empty():
		return
	_hands[i].transform = hold
	var wrist := hold * _grips[i].wrist
	var along := elbow - wrist
	var length := along.length()
	var y := along / maxf(length, 0.001)
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	_forearms[i].transform = Transform3D(Basis(x, y * length, z), wrist)


func _instance() -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


## A gloved hand closed around its grip.
func _hand_mesh(grip: Grip) -> ArrayMesh:
	var B := MeshBaker
	var side := -1.0 if grip.mirrored else 1.0
	var glove := Color(tuning.glove_color, 0.0)
	var pad := Color(tuning.glove_pad_color, 0.0)
	var r := grip.radius
	var hand := MeshBaker.new()
	# Back of the hand and palm: a flattened lump on the grip's palm side.
	hand.add(B.sphere(1.0, 12), B.at(Vector3(side * (r + 0.017), -0.004, 0.012), Vector3.ZERO, Vector3(0.023, 0.056, 0.046)), glove)
	hand.add(B.box(Vector3(0.012, 0.07, 0.022)), B.at(Vector3(side * (r + 0.03), 0.0, -0.01)), pad)  # knuckle pad
	# Fingers, index on top, curling round the front of the grip.
	var fingers := [[0.029, 0.0122], [0.006, 0.0126], [-0.016, 0.012], [-0.037, 0.0108]]
	for f in fingers.size():
		var y: float = fingers[f][0]
		var thickness: float = fingers[f][1]
		if f == 0 and grip.trigger_finger:
			# On the trigger: out along the frame, the tip curling in.
			var root := _wrap(r, side, 15.0, y + 0.006)
			var knuckle := root + Vector3(-side * 0.008, 0.004, -0.04)
			var tip := knuckle + Vector3(-side * 0.012, -0.012, -0.022)
			_finger(hand, root, knuckle, thickness, glove)
			_finger(hand, knuckle, tip, thickness * 0.92, glove)
			continue
		var reach := grip.curl_degrees
		var bend := [12.0, reach * 0.4, reach * 0.72, reach]
		for k in 3:
			_finger(hand, _wrap(r, side, bend[k], y), _wrap(r, side, bend[k + 1], y - 0.002 * k), thickness * (1.0 - 0.06 * k), glove)
	# Thumb: from the heel round the back to the far side, pointing forward;
	# or laid forward (towards −Y) along the near side.
	var heel := Vector3(side * (r + 0.006), -0.03, r * 0.8 + 0.012)
	var thumb_mid := Vector3(-side * r * 0.4, 0.0, r + 0.012)
	var thumb_tip := Vector3(-side * (r + 0.006), 0.02, r * 0.1)
	if grip.thumb_along:
		heel = Vector3(side * (r + 0.008), 0.03, r * 0.6 + 0.01)
		thumb_mid = Vector3(side * r * 0.35, -0.01, r + 0.011)
		thumb_tip = Vector3(side * r * 0.1, -0.055, r + 0.009)
	_finger(hand, heel, thumb_mid, 0.0135, glove)
	_finger(hand, thumb_mid, thumb_tip, 0.0125, glove)
	# Glove cuff to the wrist, with its strap.
	var wrist := grip.wrist
	var cuff_from := Vector3(side * (r + 0.012), -0.035, 0.014)
	_finger(hand, cuff_from, wrist, 0.031, glove)
	hand.add(B.cylinder(0.034, 0.034, 0.02, 14), Transform3D(_along(wrist - cuff_from), cuff_from.lerp(wrist, 0.7)), pad)
	return hand.commit(_material)


## Forearm along +Y from the wrist (0) to the elbow (1): glove cuff, bare
## wrist and forearm, then the rolled sleeve. Stretched to length by place().
func _forearm_mesh() -> ArrayMesh:
	var B := MeshBaker
	var skin := Color(tuning.skin_color, 0.0)
	var sleeve := Color(1, 1, 1, 1)  # camouflage
	var arm := MeshBaker.new()
	# A working forearm: slim at the wrist, swelling with muscle towards the
	# elbow, slightly flattened; then the rolled sleeve over it.
	arm.add(B.lathe(PackedVector2Array([Vector2(-0.02, 0.031), Vector2(0.08, 0.035), Vector2(0.2, 0.043),
			Vector2(0.34, 0.051), Vector2(0.46, 0.054), Vector2(0.55, 0.053)]), 16), B.at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.84)), skin)
	arm.add(B.lathe(PackedVector2Array([Vector2(0.5, 0.058), Vector2(0.6, 0.064), Vector2(0.8, 0.066), Vector2(1.0, 0.068)]), 16),
			B.at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.9)), sleeve)
	arm.add(B.torus(0.05, 0.072), B.at(Vector3(0, 0.52, 0), Vector3.ZERO, Vector3(1, 1.5, 0.9)), sleeve)  # rolled cuff
	return arm.commit(_material)


## A point on the circle the fingers follow around the grip: `degrees` from
## the palm side towards the front.
func _wrap(r: float, side: float, degrees: float, y: float) -> Vector3:
	var angle := deg_to_rad(degrees)
	var reach := r + 0.008
	return Vector3(side * cos(angle) * reach, y, -sin(angle) * reach)


func _finger(hand: MeshBaker, from: Vector3, to: Vector3, thickness: float, color: Color) -> void:
	var length := from.distance_to(to)
	hand.add(MeshBaker.capsule(thickness, length + thickness * 2.0, FINGER_SEGMENTS),
			Transform3D(_along(to - from), (from + to) * 0.5), color)


## A basis whose +Y runs along `axis`.
static func _along(axis: Vector3) -> Basis:
	var y := axis.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y)).orthonormalized()
