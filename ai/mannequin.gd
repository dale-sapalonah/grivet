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
const FLINCH_SPRING := 120.0
const FLINCH_DAMPING := 14.0

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
## Holding a blade, not a gun: no two-handed grip; `swing` (s since the
## strike began, below zero when not striking) drives the slash.
var melee := false
var swing := -1.0
var swing_windup := 0.3
var muzzle: Node3D

var _material: ShaderMaterial
## Part name -> mesh from the profile's body_model, painted for this profile.
var _imported := {}
## Painted model meshes shared by every soldier with the same model and palette.
static var _painted := {}
var _instances: Array[MeshInstance3D] = []
var _shadows_on := true
var _grip := Vector3.ZERO  # hand holds, in the gun's frame
var _support := Vector3.ZERO
var _walk_phase := 0.0
var _flinch := Vector2.ZERO
var _flinch_velocity := Vector2.ZERO


func build(profile: EnemyProfile, variant: int = 0) -> void:
	_material = ShaderMaterial.new()
	_material.shader = BODY_SHADER
	_material.set_shader_parameter("camo_a", profile.uniform_color)
	_material.set_shader_parameter("camo_b", profile.camo_b)
	_material.set_shader_parameter("camo_c", profile.camo_c)
	var civilian := profile.outfit == EnemyProfile.Outfit.CIVILIAN
	melee = profile.weapon != null and profile.weapon.melee_damage > 0.0
	# Vertex alpha: 1 = camouflage cloth, 0.5 = plain cloth, 0 = everything else.
	var cloth := Color(1, 1, 1, 1)
	if civilian:
		var shirts := profile.shirt_colors
		cloth = Color(shirts[variant % shirts.size()] if not shirts.is_empty() else profile.uniform_color, 0.5)
	var legs := Color(profile.shorts_color, 0.5) if civilian else cloth
	var gear := Color(profile.gear_color, 0.0)
	var gear_dark := Color(profile.gear_color.darkened(0.35), 0.0)
	var skin := Color(profile.skin_color, 0.0)
	var face := Color(profile.gear_color.darkened(0.3), 0.0) if profile.balaclava else skin
	var boots := Color(0.13, 0.1, 0.08, 0.0)
	var gloves := Color(0.07, 0.07, 0.07, 0.0)
	var hands := skin if civilian else gloves
	var B := MeshBaker
	var eye := Color(0.04, 0.03, 0.03, 0.0)
	if profile.body_model != null and civilian:
		# The civilian model's classes: cloth = T-shirt, gear = shorts, gear_dark = hair, boots/sole = sandals.
		var sandal := Color(0.08, 0.08, 0.09, 0.0)
		_imported = _model_parts(profile.body_model, {
			"cloth": cloth, "gear": legs, "gear_dark": Color(0.04, 0.035, 0.03, 0.0), "skin": skin, "gloves": skin,
			"boots": sandal, "sole": sandal, "eye": eye})
	elif profile.body_model != null and profile.outfit == EnemyProfile.Outfit.POLICE:
		# The police model's classes: cloth = shirt (uniform_color), gear = trousers
		# (shorts_color), gear_dark = beret, belt, epaulettes, patch (gear_color),
		# gloves = badge and buckle; hands are skin.
		_imported = _model_parts(profile.body_model, {
			"cloth": Color(profile.uniform_color, 0.5), "gear": Color(profile.shorts_color, 0.5), "gear_dark": gear,
			"skin": skin, "gloves": Color(profile.badge_color, 0.0), "boots": Color(0.03, 0.03, 0.035, 0.0),
			"sole": Color(0.02, 0.02, 0.02, 0.0), "eye": eye})
	elif profile.body_model != null:
		_imported = _model_parts(profile.body_model, {
			"cloth": cloth, "gear": gear, "gear_dark": gear_dark, "skin": face, "gloves": hands, "boots": boots,
			"sole": Color(0.06, 0.05, 0.04, 0.0), "eye": eye})

	var hips := _pivot("hips", self, Vector3(0, HIP_HEIGHT, 0))
	var spine := _pivot("spine", hips, Vector3.ZERO)
	var neck := _pivot("neck", spine, Vector3(0, 0.55, 0))

	_part("pelvis", hips, BoxShape3D.new(), Vector3(0.32, 0.18, 0.2), Vector3.ZERO)
	var pelvis := MeshBaker.new()
	# Things carried or worn over a part (bilum, strap, headband) bake on their
	# own, so a Blender-made body part can replace the body but keep them.
	var extras := MeshBaker.new()
	pelvis.add(B.lathe(_profile([-0.13, 0.12, -0.07, 0.16, 0.02, 0.172, 0.1, 0.158]), 16), B.at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.74)), legs)
	if civilian:
		_bilum_bag(extras, Vector3(0.2, -0.06, 0.03), variant)
	else:
		pelvis.add(B.cylinder(0.165, 0.165, 0.05, 14), B.at(Vector3(0, 0.08, 0), Vector3.ZERO, Vector3(1, 1, 0.78)), gear_dark)  # belt
		pelvis.add(B.box(Vector3(0.05, 0.04, 0.02)), B.at(Vector3(0, 0.08, -0.135)), Color(0.35, 0.33, 0.28, 0))  # buckle
		for side in [-1.0, 1.0]:
			pelvis.add(B.box(Vector3(0.05, 0.09, 0.07)), B.at(Vector3(side * 0.16, 0.02, 0.03)), gear)  # belt pouches
	_bake(parts.pelvis, pelvis)
	extras = _bake_extras(parts.pelvis, extras)

	_part("torso", spine, CapsuleShape3D.new(), Vector3(0.17, 0.55, 0), Vector3(0, 0.32, 0))
	var torso := MeshBaker.new()
	# Waist, ribcage and chest in one smooth shell, flattened front to back.
	torso.add(B.lathe(_profile([-0.02, 0.15, 0.1, 0.145, 0.22, 0.162, 0.34, 0.19, 0.44, 0.2, 0.5, 0.18, 0.55, 0.11, 0.58, 0.06]), 18),
			B.at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.68)), cloth)
	torso.add(B.capsule(0.07, 0.42, 10), B.at(Vector3(0, 0.47, 0), Vector3(0, 0, 90), Vector3(1, 1, 0.8)), cloth)  # shoulders
	if civilian:
		# Bilum strap from the left shoulder across the chest and back to the right hip.
		var strap := Color(0.75, 0.6, 0.12, 0.0)
		for depth in [-1.0, 1.0]:
			var from := Vector3(-0.13, 0.53, depth * 0.06)
			var to := Vector3(0.17, -0.06, depth * 0.12)
			extras.add(B.box(Vector3(0.035, from.distance_to(to), 0.012)), Transform3D(_along(to - from), (from + to) * 0.5), strap)
	else:
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
	extras = _bake_extras(parts.torso, extras)

	_part("head", neck, SphereShape3D.new(), Vector3(0.11, 0, 0), Vector3(0, 0.12, 0))
	var head := MeshBaker.new()
	head.add(B.lathe(_profile([-0.03, 0.058, 0.03, 0.05, 0.09, 0.052]), 12), B.at(Vector3.ZERO), face)  # neck
	# Skull to jaw in one shape: narrow chin, full cheeks, rounded crown,
	# deeper front to back than side to side.
	head.add(B.lathe(_profile([0.04, 0.035, 0.06, 0.062, 0.095, 0.08, 0.14, 0.093, 0.19, 0.088, 0.225, 0.062, 0.245, 0.02]), 16),
			B.at(Vector3(0, 0, -0.004), Vector3.ZERO, Vector3(0.94, 1, 1.1)), face)
	var shade := Color(face.darkened(0.25), 0.0)
	head.add(B.capsule(0.013, 0.1, 8), B.at(Vector3(0, 0.162, -0.088), Vector3(0, 0, 90), Vector3(1, 1, 0.8)), face)  # brow ridge
	head.add(B.sphere(1.0, 8), B.at(Vector3(0, 0.128, -0.103), Vector3(-12, 0, 0), Vector3(0.017, 0.028, 0.02)), face)  # nose
	head.add(B.sphere(1.0, 8), B.at(Vector3(0, 0.112, -0.1), Vector3.ZERO, Vector3(0.024, 0.011, 0.012)), face)  # nostrils
	head.add(B.capsule(0.006, 0.042, 6), B.at(Vector3(0, 0.088, -0.094), Vector3(0, 0, 90)), shade)  # lips
	for side in [-1.0, 1.0]:
		head.add(B.sphere(0.022, 6), B.at(Vector3(side * 0.09, 0.13, 0.008), Vector3.ZERO, Vector3(0.55, 1.1, 0.9)), face)  # ears
		head.add(B.sphere(1.0, 8), B.at(Vector3(side * 0.033, 0.147, -0.09), Vector3.ZERO, Vector3(0.018, 0.011, 0.008)), shade)  # eye socket
		head.add(B.sphere(0.008, 6), B.at(Vector3(side * 0.033, 0.147, -0.093)), Color(0.04, 0.03, 0.03, 0))  # eye
	if civilian:
		# Short tight hair over the crown, and a headband on some.
		head.add(B.sphere(0.1, 14, true), B.at(Vector3(0, 0.166, 0.006), Vector3.ZERO, Vector3(0.98, 0.98, 1.11)), Color(0.04, 0.035, 0.03, 0.0))
		if variant % 3 == 0:
			extras.add(B.torus(0.091, 0.1), B.at(Vector3(0, 0.178, 0.0), Vector3.ZERO, Vector3(0.97, 0.6, 1.1)), Color(0.7, 0.08, 0.06, 0.0))
	else:
		head.add(B.sphere(0.125, 16, true), B.at(Vector3(0, 0.165, 0.008), Vector3.ZERO, Vector3(1, 0.9, 1.06)), gear)  # helmet
		head.add(B.torus(0.118, 0.134), B.at(Vector3(0, 0.168, 0.008), Vector3.ZERO, Vector3(1, 0.35, 1.06)), gear_dark)  # brim
		head.add(B.box(Vector3(0.05, 0.035, 0.03)), B.at(Vector3(0, 0.22, -0.115), Vector3(20, 0, 0)), gear_dark)  # NVG mount
		head.add(B.box(Vector3(0.02, 0.07, 0.015)), B.at(Vector3(0.09, 0.12, 0.02)), gear_dark)  # chin strap
		head.add(B.box(Vector3(0.02, 0.07, 0.015)), B.at(Vector3(-0.09, 0.12, 0.02)), gear_dark)
	_bake(parts.head, head)
	extras = _bake_extras(parts.head, extras)

	for side in [-1.0, 1.0]:
		var suffix := "_l" if side < 0.0 else "_r"
		var shoulder := _pivot("shoulder" + suffix, spine, Vector3(side * 0.22, 0.48, 0))
		var elbow := _pivot("elbow" + suffix, shoulder, Vector3(0, -0.29, 0))
		var hip := _pivot("hip" + suffix, hips, Vector3(side * 0.1, 0, 0))
		var knee := _pivot("knee" + suffix, hip, Vector3(0, -0.45, 0))

		_part("upper_arm" + suffix, shoulder, CapsuleShape3D.new(), Vector3(0.05, 0.3, 0), Vector3(0, -0.15, 0))
		var upper_arm := MeshBaker.new()
		upper_arm.add(B.sphere(0.066, 12), B.at(Vector3(0, -0.02, 0)), cloth)  # deltoid
		# Shoulder into biceps, tapering to the elbow.
		var arm_profile := _profile([-0.31, 0.043, -0.26, 0.045, -0.18, 0.054, -0.12, 0.058, -0.05, 0.061, 0.02, 0.052])
		if civilian:
			upper_arm.add(B.lathe(arm_profile, 14), B.at(Vector3.ZERO, Vector3.ZERO, Vector3(0.95, 1, 0.88)), skin)
			upper_arm.add(B.lathe(_profile([-0.14, 0.064, -0.08, 0.066, 0.0, 0.068, 0.03, 0.06]), 14), B.at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.92)), cloth)  # short sleeve
		else:
			upper_arm.add(B.lathe(arm_profile, 14), B.at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.92)), cloth)
			upper_arm.add(B.box(Vector3(0.012, 0.07, 0.06)), B.at(Vector3(side * 0.053, -0.08, 0)), gear_dark)  # patch
		_bake(parts["upper_arm" + suffix], upper_arm)

		_part("lower_arm" + suffix, elbow, CapsuleShape3D.new(), Vector3(0.045, 0.28, 0), Vector3(0, -0.14, 0))
		var forearm := MeshBaker.new()
		var sleeve := skin if civilian else cloth
		forearm.add(B.sphere(0.046, 10), B.at(Vector3.ZERO), sleeve)  # elbow
		# Forearm swelling below the elbow, slimming to the wrist.
		forearm.add(B.lathe(_profile([-0.27, 0.034, -0.21, 0.038, -0.13, 0.046, -0.06, 0.05, 0.02, 0.044]), 14),
				B.at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.86)), sleeve)
		forearm.add(B.sphere(1.0, 10), B.at(Vector3(0, -0.29, -0.005), Vector3.ZERO, Vector3(0.038, 0.055, 0.03)), hands)  # hand
		_bake(parts["lower_arm" + suffix], forearm)

		_part("thigh" + suffix, hip, CapsuleShape3D.new(), Vector3(0.075, 0.45, 0), Vector3(0, -0.22, 0))
		var thigh := MeshBaker.new()
		var thigh_profile := _profile([-0.46, 0.058, -0.36, 0.066, -0.22, 0.08, -0.1, 0.09, 0.0, 0.092, 0.05, 0.075])
		if civilian:
			thigh.add(B.lathe(thigh_profile, 14), B.at(Vector3.ZERO, Vector3.ZERO, Vector3(0.96, 1, 0.92)), skin)
			thigh.add(B.lathe(_profile([-0.27, 0.086, -0.2, 0.09, -0.1, 0.097, 0.0, 0.098, 0.05, 0.08]), 14), B.at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.97)), legs)  # shorts
		else:
			thigh.add(B.lathe(thigh_profile, 14), B.at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.95)), cloth)
			thigh.add(B.box(Vector3(0.03, 0.12, 0.09)), B.at(Vector3(side * 0.075, -0.24, 0)), cloth)  # cargo pocket
		_bake(parts["thigh" + suffix], thigh)

		_part("shin" + suffix, knee, CapsuleShape3D.new(), Vector3(0.06, 0.45, 0), Vector3(0, -0.22, 0))
		var shin := MeshBaker.new()
		# Knee into the calf, slimming to the ankle.
		var shin_profile := _profile([-0.38, 0.045, -0.31, 0.047, -0.22, 0.057, -0.1, 0.066, 0.0, 0.06, 0.04, 0.055])
		if civilian:
			shin.add(B.lathe(shin_profile, 14), B.at(Vector3.ZERO, Vector3.ZERO, Vector3(0.95, 1, 0.9)), skin)
			shin.add(B.sphere(1.0, 10), B.at(Vector3(0, -0.425, -0.05), Vector3.ZERO, Vector3(0.045, 0.03, 0.1)), skin)  # bare foot
			shin.add(B.box(Vector3(0.095, 0.014, 0.25)), B.at(Vector3(0, -0.455, -0.045)), Color(0.08, 0.08, 0.09, 0))  # rubber sandal
			shin.add(B.box(Vector3(0.008, 0.03, 0.05)), B.at(Vector3(0, -0.44, -0.12), Vector3(30, 0, 0)), Color(0.08, 0.08, 0.09, 0))  # thong strap
		else:
			shin.add(B.sphere(1.0, 10), B.at(Vector3(0, 0.0, -0.035), Vector3.ZERO, Vector3(0.068, 0.075, 0.045)), gear)  # knee pad
			shin.add(B.lathe(shin_profile, 14), B.at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.92)), cloth)
			shin.add(B.cylinder(0.05, 0.055, 0.12, 12), B.at(Vector3(0, -0.4, 0)), boots)  # boot shaft
			shin.add(B.sphere(1.0, 10), B.at(Vector3(0, -0.445, -0.06), Vector3.ZERO, Vector3(0.05, 0.035, 0.1)), boots)  # foot
			shin.add(B.box(Vector3(0.1, 0.02, 0.24)), B.at(Vector3(0, -0.47, -0.04)), Color(0.06, 0.05, 0.04, 0))  # sole
		_bake(parts["shin" + suffix], shin)

	# The weapon rides on the torso, pointing where the spine points; a
	# machete is in the right hand instead.
	gun = Node3D.new()
	gun.position = Vector3(0.1, 0.42, -0.3)
	spine.add_child(gun)
	muzzle = Node3D.new()
	gun.add_child(muzzle)
	if melee:
		_bake_machete(parts.lower_arm_r)
	else:
		muzzle.position = Vector3(0, 0.015, _bake_gun(profile))


## A bush knife held in a hand at the end of `forearm` (its part frame: the
## hand at y −0.29), blade forward.
func _bake_machete(forearm: Node3D) -> void:
	var B := MeshBaker
	var blade := Color(0.5, 0.51, 0.5, 0.0)
	var edge := Color(0.78, 0.79, 0.77, 0.0)
	var machete := MeshBaker.new()
	machete.add(B.box(Vector3(0.026, 0.032, 0.13)), B.at(Vector3(0, -0.3, 0.02)), Color(0.08, 0.06, 0.05, 0.0))  # handle
	# Blade widening towards the tip, with a bright worn edge underneath. The
	# outline's width runs up the part, its length forward (−Z).
	machete.add(B.prism(PackedVector2Array([Vector2(-0.018, 0.0), Vector2(0.018, 0.0), Vector2(0.03, -0.42),
			Vector2(0.005, -0.47), Vector2(-0.035, -0.42)]), 0.004), Transform3D(Basis(Vector3.UP, Vector3.BACK, Vector3.RIGHT), Vector3(0, -0.3, -0.04)), blade)
	machete.add(B.box(Vector3(0.0045, 0.006, 0.4)), B.at(Vector3(0, -0.322, -0.26)), edge)
	_bake(forearm, machete)


## A bilum (string bag) at the hip, in bright stripes.
func _bilum_bag(baker: MeshBaker, at: Vector3, variant: int) -> void:
	var stripes := [Color(0.8, 0.15, 0.1, 0), Color(0.95, 0.75, 0.1, 0), Color(0.1, 0.1, 0.1, 0),
			Color(0.15, 0.5, 0.25, 0), Color(0.95, 0.95, 0.9, 0), Color(0.2, 0.3, 0.7, 0)]
	for b in 5:
		var width := 0.11 * (1.0 - 0.3 * absf(float(b) / 5.0 - 0.5))
		baker.add(MeshBaker.cylinder(width, width, 0.045, 12), MeshBaker.at(at + Vector3(0, -b * 0.044, 0), Vector3.ZERO, Vector3(0.5, 1, 1)),
				stripes[(variant + b * 2) % stripes.size()])


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

	# Flinch spring: hits push the torso around, it recovers. Sub-stepped: far
	# soldiers pose every other frame, and one step per pose blew up (NaN body).
	var bend := Spring.step(Vector2(_flinch.x, _flinch_velocity.x), FLINCH_SPRING, FLINCH_DAMPING, delta)
	var sway := Spring.step(Vector2(_flinch.y, _flinch_velocity.y), FLINCH_SPRING, FLINCH_DAMPING, delta)
	_flinch = Vector2(bend.x, sway.x)
	_flinch_velocity = Vector2(bend.y, sway.y)
	var lean := deg_to_rad(8.0) * clampf(speed / 5.0, 0.0, 1.0) * (1.0 - crouch)
	pivots.spine.rotation = Vector3(aim_pitch * 0.5 - lean - deg_to_rad(40.0) * hunker + _flinch.x, 0.0, _flinch.y)
	pivots.neck.rotation.x = aim_pitch * 0.5 - deg_to_rad(15.0) * hunker

	if melee:
		_pose_blade(speed)
		return
	gun.rotation.x = 0.0 if aiming else deg_to_rad(-35.0)
	# Both hands on the weapon: right on the grip, left on the handguard / pump.
	_reach("_r", gun.transform * _grip, Vector3(0.6, -1.0, 0.4))
	_reach("_l", gun.transform * _support, Vector3(-0.5, -1.0, 0.1))


## Machete arms: the free arm pumps with the stride; the blade arm carries the
## knife forward and low, then a strike raises it overhead through the windup
## and chops down hard.
func _pose_blade(speed: float) -> void:
	var run := clampf(speed / 4.0, 0.0, 1.0)
	var pump := sin(_walk_phase) * 0.8 * run
	pivots.shoulder_l.rotation = Vector3(0.15 - pump, 0.0, -0.12)
	pivots.elbow_l.rotation = Vector3(0.4 + 0.9 * run, 0.0, 0.0)
	var raise := 0.5 + pump * 0.4
	var bend := 1.1
	if swing >= 0.0:
		if swing < swing_windup:
			var t := smoothstep(0.0, 1.0, swing / swing_windup)
			raise = lerpf(0.5, 2.9, t)
			bend = lerpf(1.1, 1.7, t)
		else:
			var t := clampf((swing - swing_windup) / 0.16, 0.0, 1.0)
			raise = lerpf(2.9, 0.15, t)
			bend = lerpf(1.7, 0.25, t)
	pivots.shoulder_r.rotation = Vector3(raise, 0.0, 0.1)
	pivots.elbow_r.rotation = Vector3(bend, 0.0, 0.0)


## A basis whose +Y runs along `axis`.
static func _along(axis: Vector3) -> Basis:
	var y := axis.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y)).orthonormalized()


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


## Back to the neutral pose with no flinch left: recovery from a NaN pose.
func reset_pose() -> void:
	_flinch = Vector2.ZERO
	_flinch_velocity = Vector2.ZERO
	_walk_phase = 0.0
	neutral_pose()


## Knocks the torso away from a hit (direction in world space).
func flinch(direction: Vector3, strength: float) -> void:
	var local := global_basis.inverse() * direction
	if local.is_finite():
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


## Flat [y, radius, y, radius, ...] into lathe profile points.
static func _profile(values: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(0, values.size(), 2):
		points.append(Vector2(values[i], values[i + 1]))
	return points


## Switches every part's shadow on or off (distance LOD; cheap to call often).
## Vertex-colour class codes in a body model (each channel 0 or 1):
## index = r*4 + g*2 + b. See tools/blender/build_soldier.py CLASSES.
const BODY_CLASSES := ["eye", "skin", "gear", "gear_dark", "cloth", "boots", "gloves", "sole"]


## The model's part meshes with each vertex's class painted from `palette`
## (class -> colour, alpha as the body shader reads it). Shared per palette.
static func _model_parts(model: PackedScene, palette: Dictionary) -> Dictionary:
	var key := "%s|%s" % [model.resource_path, var_to_str(palette)]
	if _painted.has(key):
		return (_painted[key] as Dictionary).duplicate()
	var meshes := {}
	var scene := model.instantiate()
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var source := (node as MeshInstance3D).mesh
		if source == null or source.get_surface_count() == 0:
			continue
		var arrays := source.surface_get_arrays(0)
		var codes: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		if codes.is_empty():
			push_warning("body model part %s has no vertex colours: built in code instead" % node.name)
			continue
		var painted := PackedColorArray()
		painted.resize(codes.size())
		for i in codes.size():
			var c := codes[i]
			var index := (roundi(c.r) << 2) | (roundi(c.g) << 1) | roundi(c.b)
			painted[i] = palette.get(BODY_CLASSES[index], Color.MAGENTA)
		arrays[Mesh.ARRAY_COLOR] = painted
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		meshes[str(node.name)] = mesh
	scene.free()
	_painted[key] = meshes
	return meshes.duplicate()


func cast_shadows(on: bool) -> void:
	if on == _shadows_on:
		return
	_shadows_on = on
	for instance: MeshInstance3D in _instances:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Bakes `extras` onto `part` if it holds anything; returns a fresh baker.
func _bake_extras(part: Node3D, extras: MeshBaker) -> MeshBaker:
	if not extras.is_empty():
		_imported.erase(part.name)  # already used by the body: this bake is the extras' own
		_bake(part, extras)
	return MeshBaker.new()


func _bake(part: Node3D, baker: MeshBaker) -> void:
	var instance := MeshInstance3D.new()
	if _imported.has(part.name):
		instance.mesh = _imported[part.name]  # the Blender-made part replaces the code-built one
		instance.material_override = _material
		_imported.erase(part.name)  # once: a second bake on the part (a blade) is its own
	else:
		instance.mesh = baker.commit(_material)
	part.add_child(instance)
	_instances.append(instance)
