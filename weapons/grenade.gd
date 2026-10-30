class_name Grenade
extends RigidBody3D
## A thrown frag: bounces (with a clink), then after its fuse explodes.
## Blast damage falls off with distance and needs a clear line from the blast
## to the victim's torso (walls protect); fragments fly through the normal
## Ballistics simulation (so they penetrate and ricochet like bullets);
## ragdolls and loose bodies get shoved; the AI hears it; nearby cameras shake.

## Emitted on detonation, for the HUD and probes.
signal exploded(position: Vector3)

## Live grenades, for the HUD's danger indicator.
static var live: Array[Grenade] = []

var definition: GrenadeDefinition
var thrower: Node
var fuse_left := 0.0

var _bounce_audio := AudioStreamPlayer3D.new()
var _rng := RandomNumberGenerator.new()


## Spawns and throws a grenade into `parent`'s world.
static func throw(definition: GrenadeDefinition, parent: Node, from: Vector3, velocity: Vector3,
		thrower_node: Node) -> Grenade:
	var grenade := Grenade.new()
	grenade.definition = definition
	grenade.thrower = thrower_node
	parent.add_child(grenade)
	grenade.global_position = from
	grenade.linear_velocity = velocity
	grenade.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	return grenade


func _ready() -> void:
	_rng.randomize()
	fuse_left = definition.fuse_time
	mass = definition.mass
	collision_layer = PhysicsLayers.DEBRIS
	collision_mask = PhysicsLayers.WORLD
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 1
	var material := PhysicsMaterial.new()
	material.bounce = definition.bounce
	material.friction = definition.friction
	physics_material_override = material
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = definition.radius
	shape.shape = sphere
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = definition.radius
	body.height = definition.radius * 2.6
	mesh.mesh = body
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.25, 0.28, 0.18)
	mesh.material_override = olive
	add_child(mesh)
	_bounce_audio.unit_size = 4.0
	add_child(_bounce_audio)
	body_entered.connect(_on_bounce)
	live.append(self)


func _exit_tree() -> void:
	live.erase(self)


func _physics_process(delta: float) -> void:
	if not global_position.is_finite() or not linear_velocity.is_finite():
		push_error("Grenade went non-finite: position %s velocity %s - removed" % [global_position, linear_velocity])
		queue_free()
		return
	fuse_left -= delta
	if fuse_left <= 0.0:
		_explode()


func _on_bounce(_body: Node) -> void:
	if linear_velocity.length() < 1.0:
		return
	_bounce_audio.stream = ProceduralAudio.cached("grenade_bounce",
			func() -> AudioStreamWAV: return ProceduralAudio.grenade_bounce())
	_bounce_audio.pitch_scale = _rng.randf_range(0.9, 1.1)
	_bounce_audio.play()


func _explode() -> void:
	if not is_instance_valid(thrower):
		thrower = null  # killed while the fuse burned
	var center := global_position + Vector3.UP * 0.1
	var space := get_world_3d().direct_space_state
	if definition.flash:
		_flash(space, center)
		return
	_damage_bodies(space, center)
	_shove_loose_bodies(space, center)
	if definition.fragment != null:
		for i in definition.fragment_count:
			var direction := Vector3(_rng.randfn(), absf(_rng.randfn()) * 0.6, _rng.randfn()).normalized()
			Ballistics.fire(center, direction, definition.fragment, thrower, [])
	Ballistics.effects().explosion(center, definition)
	AI.make_noise(center, definition.loudness, thrower)
	Soundscape.blast(center)  # dull, ringing ears close by
	get_tree().call_group("produce", "blast", center, definition.blast_radius)  # market stalls burst
	for player: Node in get_tree().get_nodes_in_group("player"):
		var distance := (player as Node3D).global_position.distance_to(center)
		if distance < definition.shake_radius:
			(player as Player).camera_rig().add_shake(definition.shake_degrees * (1.0 - distance / definition.shake_radius))
	exploded.emit(center)
	queue_free()


## A flashbang: a white burst and a crack; everyone with a clear line from the
## bang to their eyes is blinded for ThrowMath.blind_seconds (by distance and
## by how squarely they face it); the player close by is deafened too.
func _flash(space: PhysicsDirectSpaceState3D, center: Vector3) -> void:
	for player: Node in get_tree().get_nodes_in_group("player"):
		var eye := (player as Player).head_point()
		var seconds := _blind_seconds_for(space, center, eye, -(player as Player).aim_transform().basis.z)
		if seconds > 0.0:
			(player as Player).flash(seconds)
		var distance := eye.distance_to(center)
		if distance < definition.shake_radius:
			(player as Player).camera_rig().add_shake(definition.shake_degrees * (1.0 - distance / definition.shake_radius))
	for soldier: Soldier in AI.soldiers:
		var seconds := _blind_seconds_for(space, center, soldier.eye_point(), -soldier.global_basis.z)
		if seconds > 0.0:
			soldier.flash(seconds)
	Ballistics.effects().flashbang(center, definition)
	AI.make_noise(center, definition.loudness, thrower)
	Soundscape.blast(center)
	exploded.emit(center)
	queue_free()


func _blind_seconds_for(space: PhysicsDirectSpaceState3D, center: Vector3, eye: Vector3, forward: Vector3) -> float:
	var to_bang := center - eye
	if to_bang.length() >= definition.flash_radius:
		return 0.0
	var query := PhysicsRayQueryParameters3D.create(center, eye, PhysicsLayers.WORLD)
	if not space.intersect_ray(query).is_empty():
		return 0.0  # round a corner: the flash never reaches the eyes
	return ThrowMath.blind_seconds(definition, to_bang.length(), forward.normalized().dot(to_bang.normalized()))


## Everyone with a Health inside the radius and a clear line to the blast.
func _damage_bodies(space: PhysicsDirectSpaceState3D, center: Vector3) -> void:
	var victims: Array[Node3D] = []
	victims.append_array(get_tree().get_nodes_in_group("player"))
	for soldier in AI.soldiers:
		victims.append(soldier)
	for victim in victims:
		var torso: Vector3 = victim.aim_point() if victim.has_method("aim_point") else victim.global_position
		var distance := center.distance_to(torso)
		if distance >= definition.blast_radius:
			continue
		var query := PhysicsRayQueryParameters3D.create(center, torso, PhysicsLayers.WORLD)
		if not space.intersect_ray(query).is_empty():
			continue  # behind cover
		var health: Health = victim.get("health")
		if health != null:
			health.take_hit(ThrowMath.blast_damage(definition, distance), DamageModel.Zone.TORSO, {
				"shooter": thrower, "direction": (torso - center).normalized(), "position": torso,
				"energy": 1.0, "explosion": true, "shape": -1})


func _shove_loose_bodies(space: PhysicsDirectSpaceState3D, center: Vector3) -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = definition.blast_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = PhysicsLayers.DEBRIS
	query.exclude = [get_rid()]
	for result in space.intersect_shape(query, 64):
		var body := result.collider as RigidBody3D
		if body == null:
			continue
		var ragdoll := body.get_parent() as Ragdoll
		if ragdoll != null and ragdoll.frozen:
			ragdoll.wake()
		var offset := body.global_position - center
		var strength := 1.0 - clampf(offset.length() / definition.blast_radius, 0.0, 1.0)
		body.apply_central_impulse((offset.normalized() + Vector3.UP * 0.5).normalized()
				* body.mass * definition.blast_push_speed * strength)
