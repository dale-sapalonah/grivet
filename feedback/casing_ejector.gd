class_name CasingEjector
extends Node3D
## Spent casings: thrown from the ejection port, tumbling under gravity,
## bouncing off whatever they hit with a clink that depends on the surface
## (bright on steel, softer on concrete, dull on wood, silent on dirt or
## bodies; hollow tocks for plastic shotgun hulls), then lying there for a while. Simulated with rays, not rigid
## bodies, so dozens cost almost nothing. Pooled, oldest reused first.

## Emitted on every bounce, for probes. `bounce` counts from 0.
signal casing_landed(surface: String, bounce: int)

@export var max_casings := 40
## Seconds a casing lies on the ground before it is recycled.
@export var lifetime := 8.0
@export var restitution := 0.3
@export var max_bounces := 2
## Below this speed (m/s) after a bounce the casing comes to rest.
@export var rest_speed := 0.5
@export var spin_degrees_per_second := 1400.0
@export var bounce_volume_drop_db := 7.0
@export var sound_unit_size := 5.0
@export var sound_players := 8
## Takes per weapon and surface, picked at random.
@export var clink_variants := 4
## Lift off a surface after a bounce so the next ray does not re-hit it (m).
@export var surface_offset := 0.004


class Casing:
	var node: MeshInstance3D
	var velocity := Vector3.ZERO
	var spin_axis := Vector3.RIGHT
	var weapon: WeaponDefinition
	var bounces := 0
	var resting := false
	var age := 0.0
	var active := false


var exclude: Array[RID] = []

var _casings: Array[Casing] = []
var _next := 0
var _meshes: Dictionary = {}  # weapon id -> CylinderMesh
var _players: Array[AudioStreamPlayer3D] = []
var _prewarm_task := -1  # WorkerThreadPool task id, waited on before we go
var _next_player := 0
var _reported_bad := false


func _ready() -> void:
	top_level = true  # world space, not glued to the camera it lives under
	global_transform = Transform3D.IDENTITY
	for i in max_casings:
		var casing := Casing.new()
		casing.node = MeshInstance3D.new()
		casing.node.visible = false
		casing.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(casing.node)
		_casings.append(casing)
	for i in sound_players:
		var player := AudioStreamPlayer3D.new()
		player.unit_size = sound_unit_size
		add_child(player)
		_players.append(player)


## Throws one casing from `port` (the ejection port's world transform).
func eject(weapon: WeaponDefinition, port: Transform3D, velocity: Vector3) -> void:
	# A NaN casing never lands, so it would warn every tick for ever.
	if not (port.is_finite() and velocity.is_finite()):
		if not _reported_bad:
			_reported_bad = true
			push_error("CasingEjector: refused a non-finite %s casing: port %s velocity %s" % [weapon.id, port, velocity])
		return
	var casing := _casings[_next]
	_next = (_next + 1) % _casings.size()
	casing.weapon = weapon
	casing.velocity = velocity
	casing.spin_axis = port.basis.y.normalized()
	casing.bounces = 0
	casing.resting = false
	casing.age = 0.0
	casing.active = true
	casing.node.mesh = _mesh(weapon)
	# Cylinders stand along +Y; lay the case along the barrel axis.
	casing.node.global_transform = Transform3D(port.basis * Basis(Vector3.RIGHT, PI * 0.5), port.origin)
	casing.node.visible = true


func _physics_process(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var gravity := Ballistics.settings.gravity
	for casing in _casings:
		if not casing.active:
			continue
		if casing.resting:
			casing.age += delta
			if casing.age > lifetime:
				casing.active = false
				casing.node.visible = false
			continue
		casing.velocity += Vector3.DOWN * gravity * delta
		var from := casing.node.global_position
		if not (from.is_finite() and casing.velocity.is_finite()) or casing.age > lifetime:
			casing.active = false  # bad, or fell out of the world: recycle it
			casing.node.visible = false
			continue
		casing.age += delta
		var to := from + casing.velocity * delta
		var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD, exclude)
		query.hit_back_faces = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			casing.node.global_position = to
			casing.node.rotate(casing.spin_axis, deg_to_rad(spin_degrees_per_second) * delta)
			continue
		_bounce(casing, hit)


func _bounce(casing: Casing, hit: Dictionary) -> void:
	var normal: Vector3 = hit.normal
	var surface: SurfaceMaterial = Ballistics.surface_of(hit.collider)
	_play_clink(casing, surface, hit.position)
	casing_landed.emit(surface.id, casing.bounces)
	casing.bounces += 1
	casing.velocity = BallisticsMath.reflect(casing.velocity, normal) * restitution
	casing.node.global_position = (hit.position as Vector3) + normal * surface_offset
	if casing.bounces > max_bounces or casing.velocity.length() < rest_speed:
		casing.resting = true
		casing.age = 0.0
		casing.velocity = Vector3.ZERO
		# Lie on its side: case axis (+Y of the cylinder) across the surface.
		var along := normal.cross(Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT)
		along = along.rotated(normal, randf() * TAU).normalized()
		var basis := Basis(along.cross(normal), along, normal).orthonormalized()
		casing.node.global_transform = Transform3D(basis,
				casing.node.global_position + normal * casing.weapon.casing_radius)


## Builds every clink for these weapons on every surface on a worker thread,
## so no casing ever builds a sound mid-fight. Clinks not built yet are skipped.
func prewarm(weapons: Array) -> void:
	var jobs: Array = []
	for weapon: WeaponDefinition in weapons:
		if weapon == null or not weapon.casing_ejects:
			continue
		for surface: SurfaceMaterial in Ballistics.settings.surfaces.values():
			for variant in clink_variants:
				if not ProceduralAudio.has(_clink_key(weapon, surface, variant)):
					jobs.append([weapon, surface, variant])
	if not jobs.is_empty():
		_finish_prewarm()
		_prewarm_task = WorkerThreadPool.add_task(CasingEjector._build_clinks.bind(jobs), false, "casing clinks")


func _exit_tree() -> void:
	_finish_prewarm()


## Every pool task must be waited on (an unwaited one crashes the engine at
## exit), and the build must not outlive this node.
func _finish_prewarm() -> void:
	if _prewarm_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_prewarm_task)
		_prewarm_task = -1


## Worker thread: static, so it never touches a node that may be gone; hands
## each sound to the main thread's cache.
static func _build_clinks(jobs: Array) -> void:
	for job in jobs:
		var stream := ProceduralAudio.casing_clink(job[0], job[1], job[2])
		ProceduralAudio.store.call_deferred(_clink_key(job[0], job[1], job[2]), stream)


static func _clink_key(weapon: WeaponDefinition, surface: SurfaceMaterial, variant: int) -> String:
	return "casing:%s:%s:%d" % [weapon.id, surface.id, variant]


func _play_clink(casing: Casing, surface: SurfaceMaterial, position: Vector3) -> void:
	var weapon := casing.weapon
	var key := _clink_key(weapon, surface, randi() % clink_variants)
	var stream := ProceduralAudio.fetch(key)
	if stream == null:
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.global_position = position
	player.stream = stream
	player.volume_db = weapon.casing_volume_db - bounce_volume_drop_db * casing.bounces
	player.pitch_scale = randf_range(0.95, 1.06)
	player.play()


func _mesh(weapon: WeaponDefinition) -> CylinderMesh:
	if not _meshes.has(weapon.id):
		var mesh := CylinderMesh.new()
		mesh.top_radius = weapon.casing_radius
		mesh.bottom_radius = weapon.casing_radius
		mesh.height = weapon.casing_length
		mesh.radial_segments = 8
		mesh.rings = 1
		var material := StandardMaterial3D.new()
		material.albedo_color = weapon.casing_color
		material.metallic = weapon.casing_metallic
		material.roughness = 0.35
		mesh.material = material
		_meshes[weapon.id] = mesh
	return _meshes[weapon.id]
