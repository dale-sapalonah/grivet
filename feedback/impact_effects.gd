class_name ImpactEffects
extends Node3D
## What a bullet strike looks and sounds like, decided by physics: the
## surface's AcousticType, the outcome (penetrated / stopped / ricochet / exit
## face), the struck object's mass factor (density x thickness met) and the
## energy the round still carries.
##   Steel    - sparks; a hole when punched through, a grey lead splash when
##              stopped; sparks skating off along a ricochet.
##   Wood     - thin boards throw splinters (more from the exit face); dense
##              wood throws a few chips and a puff of fibre dust.
##   Concrete - a crater growing with energy, chips (powder for light rounds,
##              rubble for heavy) and a dust cloud; spall on the exit face.
##   Bodies   - a small dark puff.
## Sounds are positional and arrive late with distance (speed of sound). The
## impact-sound library is built on a worker thread, carried weapons' energies
## first; a hit never builds a sound on the main thread (it plays the nearest
## ready variation and moves the exact one to the front of the queue). Effect
## shaders are compiled up front by drawing each effect once, invisibly small,
## when a camera first exists. Owned by the Ballistics autoload; placeholder
## until Milestone 5's FX and recorded audio.

## Emitted when an impact sound is scheduled; `delay` is its travel time.
signal sound_scheduled(outcome: String, surface: String, delay: float)

const OUTCOMES_BY_TYPE := {
	SurfaceMaterial.AcousticType.METAL: ["penetrated", "stopped", "ricochet"],
	SurfaceMaterial.AcousticType.WOOD: ["penetrated", "stopped"],
	SurfaceMaterial.AcousticType.MASONRY: ["stopped", "ricochet"],
	SurfaceMaterial.AcousticType.SOFT: ["stopped"],
}

var _settings: BallisticsSettings
var _holes: Array[MeshInstance3D] = []
var _next_hole := 0
var _debris: Array[CPUParticles3D] = []
var _next_debris := 0
var _dust: Array[CPUParticles3D] = []
var _next_dust := 0
var _players: Array[AudioStreamPlayer3D] = []
var _next_player := 0
var _pending: Array[Dictionary] = []  # {"at", "stream", "position", "volume_db", "pitch"}
var _recent: Dictionary = {}  # surface id -> Array[float] of recent play times

var _hole_dark := _decal_material(Color(0.07, 0.07, 0.07), 0.0, 1.0)
var _hole_wood := _decal_material(Color(0.13, 0.08, 0.04), 0.0, 1.0)
var _hole_lead := _decal_material(Color(0.5, 0.5, 0.52), 0.6, 0.5)
var _hole_flesh := _decal_material(Color(0.25, 0.02, 0.02), 0.0, 0.8)
var _spark_mesh := BoxMesh.new()
var _splinter_mesh := BoxMesh.new()
var _chip_mesh := BoxMesh.new()

var _warm_thread := Thread.new()
var _warm_mutex := Mutex.new()
var _warm_jobs_left: Array = []  # [key, surface, params, variant]; guarded by _warm_mutex
var _warm_results: Dictionary = {}  # key -> AudioStreamWAV; guarded by _warm_mutex
var _priority_energies: Dictionary = {}  # quantized energy -> true; guarded
var _urgent_keys := PackedStringArray()  # guarded
var _warm_stop := false
var _visuals_prewarmed := false
var _prewarm_frames_left := 0
var _prewarm_holes: Array[MeshInstance3D] = []


func setup(settings: BallisticsSettings) -> void:
	_settings = settings
	for i in settings.impact_sound_pool_size:
		var player := AudioStreamPlayer3D.new()
		player.unit_size = settings.impact_sound_unit_size
		player.max_distance = settings.impact_sound_max_distance
		add_child(player)
		_players.append(player)

	var hole_mesh := QuadMesh.new()
	hole_mesh.size = Vector2.ONE * settings.hole_size
	for i in settings.hole_pool_size:
		var hole := MeshInstance3D.new()
		hole.mesh = hole_mesh
		hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hole.visible = false
		add_child(hole)
		_holes.append(hole)

	_spark_mesh.size = Vector3.ONE * 0.012
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.vertex_color_use_as_albedo = true
	_spark_mesh.material = glow
	var lit := StandardMaterial3D.new()
	lit.vertex_color_use_as_albedo = true
	lit.roughness = 0.9
	_splinter_mesh.size = Vector3(0.004, 0.04, 0.004)  # long along Y, aligned to velocity
	_splinter_mesh.material = lit
	_chip_mesh.size = Vector3.ONE * 0.012
	_chip_mesh.material = lit
	for i in settings.debris_pool_size:
		var debris := CPUParticles3D.new()
		debris.emitting = false
		debris.one_shot = true
		debris.explosiveness = 1.0
		debris.direction = Vector3.BACK  # local +Z = out of the surface
		add_child(debris)
		_debris.append(debris)

	var puff := QuadMesh.new()
	puff.size = Vector2.ONE * 0.25
	var puff_material := StandardMaterial3D.new()
	puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff_material.vertex_color_use_as_albedo = true
	puff_material.albedo_texture = _soft_disc(PackedFloat32Array([0.0, 0.5, 1.0]),
			PackedFloat32Array([1.0, 0.45, 0.0]))
	puff.material = puff_material
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.0))
	for i in settings.dust_pool_size:
		var dust := CPUParticles3D.new()
		dust.emitting = false
		dust.one_shot = true
		dust.explosiveness = 0.85
		dust.amount = 6
		dust.lifetime = settings.dust_lifetime
		dust.mesh = puff
		dust.direction = Vector3.BACK
		dust.spread = 50.0
		dust.initial_velocity_min = 0.3
		dust.initial_velocity_max = 1.1
		dust.damping_min = 1.5
		dust.damping_max = 2.5
		dust.gravity = Vector3(0, -0.15, 0)
		dust.color_ramp = fade
		dust.scale_amount_curve = grow
		add_child(dust)
		_dust.append(dust)

	_warm_jobs_left = _warm_jobs()
	_warm_thread.start(_warm_up)


func _exit_tree() -> void:
	_warm_stop = true
	if _warm_thread.is_started():
		_warm_thread.wait_to_finish()


## Visuals and sound for one impact event from the Ballistics simulator.
func handle_impact(surface: SurfaceMaterial, info: Dictionary) -> void:
	var kind: String = info.kind
	var position: Vector3 = info.position
	var normal: Vector3 = info.normal
	var energy: float = info.energy
	var mass := surface.mass_factor(info.thickness, info.solid)
	var facing := _facing(normal)
	var exit := kind == "exit"
	match surface.acoustic_type:
		SurfaceMaterial.AcousticType.METAL:
			if kind == "ricochet":
				var bounce := BallisticsMath.reflect(info.direction, normal).normalized()
				_burst(position, _facing(bounce), _spark_mesh, surface.impact_color,
						_settings.spark_count * 2, _settings.spark_lifetime, 1.5, 15.0, 0.3, false)
			else:
				_burst(position, facing, _spark_mesh, surface.impact_color,
						roundi(_settings.spark_count * lerpf(0.6, 1.4, energy)), _settings.spark_lifetime, 1.0, 35.0, 0.3, false)
				if kind == "stopped":
					_hole(position, normal, _hole_lead, lerpf(1.2, 1.8, energy))  # lead splash
				else:
					_hole(position, normal, _hole_dark, 0.8)
		SurfaceMaterial.AcousticType.WOOD:
			var thin := 1.0 - mass
			_hole(position, normal, _hole_wood, 1.0)
			var splinters := roundi(_settings.splinter_count * thin * lerpf(0.5, 1.0, energy) * (1.5 if exit else 1.0))
			if splinters > 0:
				_burst(position, facing, _splinter_mesh, surface.impact_color, splinters,
						_settings.splinter_lifetime, 1.2, 40.0, 1.0, true)
			if mass > 0.5:
				_burst(position, facing, _chip_mesh, surface.impact_color, roundi(6.0 * mass),
						_settings.splinter_lifetime, 0.6, 30.0, 1.0, false)
				_puff(position, facing, surface.dust_color, 0.5 * mass)
		SurfaceMaterial.AcousticType.MASONRY:
			if kind == "ricochet":
				_hole(position, normal, _hole_dark, 0.6)  # scuff
				_burst(position, facing, _chip_mesh, surface.impact_color, 3, 0.6, 0.6, 30.0, 1.0, false)
				_puff(position, facing, surface.dust_color, 0.4)
			else:
				var spall := 1.3 if exit else 1.0
				_hole(position, normal, _hole_dark, lerpf(1.0, _settings.crater_max_scale, energy) * spall)
				var chips := roundi(lerpf(3.0, _settings.chip_count_heavy, energy) * spall)
				_burst(position, facing, _chip_mesh, surface.impact_color, chips, 0.8,
						lerpf(0.7, 1.4, energy), 45.0, 1.0, false, lerpf(0.5, 1.6, energy))
				_puff(position, facing, surface.dust_color, lerpf(0.6, 1.6, energy) * spall)
		SurfaceMaterial.AcousticType.SOFT:
			if not exit:
				_hole(position, normal, _hole_flesh, 1.0)
				_puff(position, facing, surface.dust_color, 0.35)
	if not exit:
		_play_sound(surface, kind, mass, energy, position)


func _play_sound(surface: SurfaceMaterial, outcome: String, mass: float, energy: float, position: Vector3) -> void:
	var now := _now()
	var recent: Array = _recent.get(surface.id, [])
	recent = recent.filter(func(time: float) -> bool: return now - time < _settings.impact_sound_window)
	if recent.size() >= _settings.impact_sounds_per_window:
		return
	recent.append(now)
	_recent[surface.id] = recent

	var params := _sound_params(surface, outcome, mass, energy)
	var variant := randi() % maxi(1, _settings.impact_sound_variants)
	var key := ProceduralAudio.impact_key(surface, params[0], params[1], params[2], variant)
	var stream := _ready_stream(key)
	if stream == null:
		_request(key)
		stream = _nearest_ready(surface, params)
	if stream == null:
		return  # nothing built for this surface yet (first moments after start)
	var volume_db := surface.impact_volume_db + lerpf(_settings.light_round_volume_db, 0.0, energy)
	var pitch := lerpf(_settings.light_round_pitch, _settings.heavy_round_pitch, energy) * randf_range(0.97, 1.03)
	var delay := _schedule(stream, position, volume_db, pitch)
	if outcome == "ricochet" and surface.acoustic_type != SurfaceMaterial.AcousticType.WOOD:
		var whine := ProceduralAudio.cached("ricochet:%d" % variant,
				func() -> AudioStreamWAV: return ProceduralAudio.ricochet(variant))
		_schedule(whine, position, volume_db + _settings.ricochet_volume_db, 1.0)
	sound_scheduled.emit(outcome, surface.id, delay)


## Rounds mass and energy to shared steps, and drops what a material's sound
## ignores (concrete and bodies don't depend on thickness; concrete's entry
## sound is the same whether the round later exits). Returns [outcome, mass, energy].
func _sound_params(surface: SurfaceMaterial, outcome: String, mass: float, energy: float) -> Array:
	var step := _settings.impact_sound_step
	var quantized_mass := snappedf(clampf(mass, 0.0, 1.0), step)
	var quantized_energy := snappedf(clampf(energy, 0.0, 1.0), step)
	match surface.acoustic_type:
		SurfaceMaterial.AcousticType.MASONRY:
			return ["ricochet" if outcome == "ricochet" else "stopped", 1.0, quantized_energy]
		SurfaceMaterial.AcousticType.SOFT:
			return ["stopped", 1.0, quantized_energy]
	return [outcome, quantized_mass, quantized_energy]


func _schedule(stream: AudioStreamWAV, position: Vector3, volume_db: float, pitch: float) -> float:
	var delay := _listener_distance(position) / _settings.speed_of_sound
	_pending.append({"at": _now() + delay, "stream": stream, "position": position,
			"volume_db": volume_db, "pitch": pitch})
	return delay


func _process(_delta: float) -> void:
	if not _visuals_prewarmed:
		var camera := get_viewport().get_camera_3d()
		if camera != null and camera.is_inside_tree():
			_prewarm_visuals(camera)
	elif _prewarm_frames_left > 0:
		_prewarm_frames_left -= 1
		if _prewarm_frames_left == 0:
			for hole in _prewarm_holes:
				hole.visible = false
			_prewarm_holes.clear()
	if _pending.is_empty():
		return
	var now := _now()
	var waiting: Array[Dictionary] = []
	for sound in _pending:
		if sound.at > now:
			waiting.append(sound)
			continue
		var player := _players[_next_player]
		_next_player = (_next_player + 1) % _players.size()
		player.global_position = sound.position
		player.stream = sound.stream
		player.volume_db = sound.volume_db
		player.pitch_scale = sound.pitch
		player.play()
	_pending = waiting


func _hole(position: Vector3, normal: Vector3, material: Material, size_scale: float) -> void:
	if _holes.is_empty():
		return
	var hole := _holes[_next_hole]
	_next_hole = (_next_hole + 1) % _holes.size()
	var spin := Basis(normal, randf() * TAU)  # varied orientation per hole
	hole.global_transform = Transform3D(spin * _facing(normal) * Basis.from_scale(Vector3.ONE * size_scale),
			position + normal * 0.002)
	hole.material_override = material
	hole.visible = true


## One particle burst out of the surface (+Z of `facing`). speed_scale scales
## the spark speed range; align makes long meshes (splinters) fly lengthwise.
func _burst(position: Vector3, facing: Basis, mesh: Mesh, color: Color, count: int, lifetime: float,
		speed_scale: float, spread: float, gravity_scale: float, align: bool, size_scale: float = 1.0) -> void:
	if count <= 0 or _debris.is_empty():
		return
	var debris := _debris[_next_debris]
	_next_debris = (_next_debris + 1) % _debris.size()
	debris.global_transform = Transform3D(facing, position)
	debris.mesh = mesh
	debris.color = color
	debris.amount = count
	debris.lifetime = lifetime
	debris.spread = spread
	debris.initial_velocity_min = _settings.spark_speed_min * speed_scale
	debris.initial_velocity_max = _settings.spark_speed_max * speed_scale
	debris.gravity = Vector3.DOWN * Ballistics.settings.gravity * gravity_scale
	debris.particle_flag_align_y = align
	debris.scale_amount_min = 0.6 * size_scale
	debris.scale_amount_max = 1.4 * size_scale
	debris.restart()


func _puff(position: Vector3, facing: Basis, color: Color, size_scale: float) -> void:
	if _dust.is_empty():
		return
	var dust := _dust[_next_dust]
	_next_dust = (_next_dust + 1) % _dust.size()
	dust.global_transform = Transform3D(facing, position)
	dust.color = color
	dust.scale_amount_min = 0.7 * size_scale
	dust.scale_amount_max = 1.3 * size_scale
	dust.restart()


# --- Background pre-build of the impact-sound library ---------------------------

func _warm_jobs() -> Array:
	var jobs := []
	var surfaces: Array = _settings.surfaces.values()
	if _settings.default_surface != null and not surfaces.has(_settings.default_surface):
		surfaces.append(_settings.default_surface)
	var steps := roundi(1.0 / _settings.impact_sound_step)
	for surface: SurfaceMaterial in surfaces:
		var seen := {}
		for outcome: String in OUTCOMES_BY_TYPE[surface.acoustic_type]:
			for mass_step in steps + 1:
				for energy_step in steps + 1:
					var params := _sound_params(surface, outcome,
							mass_step * _settings.impact_sound_step, energy_step * _settings.impact_sound_step)
					for variant in _settings.impact_sound_variants:
						var key := ProceduralAudio.impact_key(surface, params[0], params[1], params[2], variant)
						if not seen.has(key):
							seen[key] = true
							jobs.append([key, surface, params, variant])
	return jobs


## Builds sounds for the weapons that will be fired first: call with each
## carried weapon's impact_energy (the WeaponHolder does).
func prioritize_energy(energy: float) -> void:
	_warm_mutex.lock()
	_priority_energies[snappedf(clampf(energy, 0.0, 1.0), _settings.impact_sound_step)] = true
	_warm_mutex.unlock()


## True once every impact sound has been built.
func sounds_ready() -> bool:
	_warm_mutex.lock()
	var done := _warm_jobs_left.is_empty()
	_warm_mutex.unlock()
	return done


func _warm_up() -> void:
	while not _warm_stop:
		_warm_mutex.lock()
		if _warm_jobs_left.is_empty():
			_warm_mutex.unlock()
			return
		var job: Array = _warm_jobs_left.pop_at(_next_job_index())
		_warm_mutex.unlock()
		var params: Array = job[2]
		var stream := ProceduralAudio.impact(job[1], params[0], params[1], params[2], job[3])
		_warm_mutex.lock()
		_warm_results[job[0]] = stream
		_warm_mutex.unlock()


## Urgent keys (a hit is waiting) first, then carried weapons' energies, then
## the rest. Caller holds _warm_mutex.
func _next_job_index() -> int:
	while not _urgent_keys.is_empty():
		var key := _urgent_keys[0]
		_urgent_keys.remove_at(0)
		for i in _warm_jobs_left.size():
			if _warm_jobs_left[i][0] == key:
				return i
	for i in _warm_jobs_left.size():
		if _priority_energies.has(_warm_jobs_left[i][2][2]):
			return i
	return 0


## The stream if built (moving it into the shared cache), else null. Never builds.
func _ready_stream(key: String) -> AudioStreamWAV:
	if ProceduralAudio.has(key):
		return ProceduralAudio.cached(key, Callable())
	_warm_mutex.lock()
	var stream: AudioStreamWAV = _warm_results.get(key)
	_warm_results.erase(key)
	_warm_mutex.unlock()
	if stream != null:
		ProceduralAudio.store(key, stream)
	return stream


func _request(key: String) -> void:
	_warm_mutex.lock()
	if not _urgent_keys.has(key):
		_urgent_keys.append(key)
	_warm_mutex.unlock()


## A built sound as close as possible to the one wanted: other take first,
## then neighbouring energy, then neighbouring mass.
func _nearest_ready(surface: SurfaceMaterial, params: Array) -> AudioStreamWAV:
	var step := _settings.impact_sound_step
	for energy_offset in [0.0, -step, step, -2.0 * step, 2.0 * step]:
		for mass_offset in [0.0, -step, step]:
			var energy := clampf(params[2] + energy_offset, 0.0, 1.0)
			var mass := clampf(params[1] + mass_offset, 0.0, 1.0)
			for variant in _settings.impact_sound_variants:
				var stream := _ready_stream(ProceduralAudio.impact_key(surface, params[0], mass, energy, variant))
				if stream != null:
					return stream
	return null


## Draws every effect material once, too small to see, so their shaders are
## compiled now rather than on the first hit of each kind mid-fight.
func _prewarm_visuals(camera: Camera3D) -> void:
	_visuals_prewarmed = true
	var toward_camera := camera.global_basis.z
	var spot := camera.global_position - toward_camera * 2.0
	var facing := _facing(toward_camera)
	for material in [_hole_dark, _hole_wood, _hole_lead, _hole_flesh]:
		_hole(spot, toward_camera, material, 0.01)
		_prewarm_holes.append(_holes[posmod(_next_hole - 1, _holes.size())])
	for mesh in [_spark_mesh, _splinter_mesh, _chip_mesh]:
		_burst(spot, facing, mesh, Color.WHITE, 1, 0.1, 0.0, 0.0, 0.0, mesh == _splinter_mesh, 0.01)
	_puff(spot, facing, Color(1, 1, 1, 0.01), 0.01)
	_prewarm_frames_left = 3


# --- Helpers -------------------------------------------------------------------

func _listener_distance(position: Vector3) -> float:
	var camera := get_viewport().get_camera_3d()
	return camera.global_position.distance_to(position) if camera != null else 0.0


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Basis whose +Z points along the normal: quads face +Z, particles fly along +Z.
func _facing(normal: Vector3) -> Basis:
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	return Basis.looking_at(-normal, up)


## Bullet-hole and crater material: a tinted soft disc, dark and solid in the
## middle, fading out at the rim, so holes and craters aren't square.
static func _decal_material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = _soft_disc(PackedFloat32Array([0.0, 0.55, 0.8, 1.0]),
			PackedFloat32Array([1.0, 0.95, 0.35, 0.0]))
	return material


## White radial texture whose alpha follows `alphas` at `offsets` (0 = centre, 1 = rim).
static func _soft_disc(offsets: PackedFloat32Array, alphas: PackedFloat32Array) -> GradientTexture2D:
	var gradient := Gradient.new()
	var colors := PackedColorArray()
	for alpha in alphas:
		colors.append(Color(1, 1, 1, alpha))
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture
