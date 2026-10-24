class_name BuaiPickup
extends Area3D
## A bundle of buai (betel nut) and daka (mustard stick) with a little lime
## pot. Walk over it when hurt and the player chews: some health back, a
## shout on the HUD, and a red spit splash on the ground. Used once.

@export var heal := 30.0

var _taken := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYER
	monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	shape.shape = sphere
	add_child(shape)
	body_entered.connect(_on_body_entered)
	_build_look()


func _on_body_entered(body: Node3D) -> void:
	var player := body as Player
	if _taken or player == null or player.dead or player.health.fraction() >= 1.0:
		return
	_taken = true
	player.health.model.heal(heal)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("announce"):
		hud.announce("BUAI! +%d" % roundi(heal), Color(0.45, 0.85, 0.3), 1.1, "Strength back")
	_spit(player.global_position)
	queue_free()


## A red splash where the player stands, left behind (Port Moresby's streets
## are covered in them).
func _spit(at: Vector3) -> void:
	var splash := MeshBaker.new()
	var red := Color(0.5, 0.05, 0.03)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var forward := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	splash.add(MeshBaker.cylinder(0.12, 0.12, 0.004, 12), MeshBaker.at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.7)), red)
	for drop in 6:
		var spot := forward * rng.randf_range(0.12, 0.4) + forward.cross(Vector3.UP) * rng.randf_range(-0.12, 0.12)
		splash.add(MeshBaker.cylinder(0.025, 0.025, 0.004, 8), MeshBaker.at(spot), red)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.25
	var instance := MeshInstance3D.new()
	instance.mesh = splash.commit(material)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(instance)
	instance.global_position = Vector3(at.x, 0.005, at.z) + forward * 0.5
	instance.add_to_group("buai_spit")


func _build_look() -> void:
	var B := MeshBaker
	var bundle := MeshBaker.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(global_position))
	for n in 9:  # a bunch of green nuts
		var spot := Vector3(rng.randf_range(-0.06, 0.06), 0.03 + n * 0.008, rng.randf_range(-0.06, 0.06))
		bundle.add(B.sphere(0.032, 8), B.at(spot), Color(0.3, 0.5, 0.12).lerp(Color(0.62, 0.58, 0.14), rng.randf() * 0.4))
	for d in 6:  # daka sticks
		bundle.add(B.cylinder(0.008, 0.008, 0.18, 5), B.at(Vector3(0.1 + d * 0.016, 0.02, 0.02), Vector3(0, 30, 90)), Color(0.35, 0.52, 0.16))
	bundle.add(B.cylinder(0.035, 0.03, 0.07, 10), B.at(Vector3(-0.1, 0.035, 0.06)), Color(0.9, 0.9, 0.86))  # lime pot
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.6
	# A little glow so it reads as something to pick up at dusk.
	material.emission_enabled = true
	material.emission = Color(0.25, 0.35, 0.05)
	material.emission_energy_multiplier = 0.6
	var instance := MeshInstance3D.new()
	instance.mesh = bundle.commit(material)
	add_child(instance)
