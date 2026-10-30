extends Node
## The soundscape (autoload `Soundscape`): every procedural sound is built on
## a worker thread at start; gunshots play as a close and a distant layer that
## cross-fade with distance and arrive late (speed of sound); enemy rounds
## passing near the listener snap; the reverb on the SFX bus follows the space
## around the listener (measured with rays: tight slap between containers, a
## wide echo in the open); footsteps follow the surface underfoot; and the
## player hears hit and kill cues, laboured breathing when badly hurt, and
## ringing, muffled ears after a blast close by.

const SETTINGS := preload("res://data/audio/audio_settings.tres")
const WEAPON_DIR := "res://data/weapons/"

var settings: AudioSettings = SETTINGS
## The reverb as currently applied (blended towards `acoustics_target`).
var acoustics := {}
var acoustics_target := {}
## Counters for probes.
var counts := {"shots": 0, "snaps": 0, "steps": 0, "hits": 0, "kills": 0, "breaths": 0, "blasts": 0}
## Seconds of deafness left (0 = hearing fine).
var deaf_left := 0.0

var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _pending: Array[Dictionary] = []
var _prewarm_task := -1
var _probe_left := 0.0
var _reverb: AudioEffectReverb
var _lowpass: AudioEffectLowPassFilter
var _sfx_bus := -1
var _lowpass_index := -1
var _deaf_total := 0.0
var _deaf_strength := 0.0
var _cues: AudioStreamPlayer
var _ring: AudioStreamPlayer
var _breath: AudioStreamPlayer
var _breath_left := 0.0
var _last_snap := -INF
var _weapons: Array[WeaponDefinition] = []


func _ready() -> void:
	for i in settings.pool_size:
		var player := AudioStreamPlayer3D.new()
		player.max_distance = settings.max_hear_distance
		add_child(player)  # Settings routes it to SFX
		_pool.append(player)
	_cues = _cue_player()
	_ring = _cue_player()
	_breath = _cue_player()
	_setup_bus_effects()
	_weapons = _load_weapons()
	Ballistics.bullet_moved.connect(_on_bullet_moved)
	Ballistics.target_hit.connect(_on_target_hit)
	get_tree().scene_changed.connect(_on_scene_changed)
	_prewarm()
	Debug.register("sound.demo", _cmd_demo, "Play every sound in turn at several distances (judge them by ear).")
	Debug.register("sound.acoustics", _cmd_acoustics, "Show the measured space and the reverb it gets.")
	Debug.register("sound.deafen", _cmd_deafen, "sound.deafen [0..1]: ring the ears as if a grenade went off close by.")


func _exit_tree() -> void:
	# Every pool task must be waited on, or the engine crashes at exit.
	if _prewarm_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_prewarm_task)
		_prewarm_task = -1


# --- Gunshots, snaps, footsteps ---------------------------------------------------

## A shot fired at `position` by anyone but the listener: both layers, mixed
## by distance, heard late by distance.
func gunshot(weapon: WeaponDefinition, position: Vector3) -> void:
	var distance := _listener_distance(position)
	if distance > settings.max_hear_distance:
		return
	var mix := SoundModels.shot_mix(distance, settings)
	var delay := distance / Ballistics.settings.speed_of_sound
	var pitch := randf_range(0.96, 1.04)
	var close := ProceduralAudio.fetch("shot:" + weapon.id)
	if close != null and mix.x > -40.0:
		_schedule(close, position, weapon.shot_volume_db + mix.x, settings.shot_close_unit_size, delay, pitch)
	var far := ProceduralAudio.fetch("shot_far:" + weapon.id)
	if far != null and mix.y > -40.0:
		_schedule(far, position, weapon.shot_volume_db + mix.y, settings.shot_distant_unit_size, delay, pitch)
	counts.shots += 1


## The listener's own shot: the close layer plays on the weapon itself; this
## adds the quiet rolling tail that open ground throws back.
func own_shot_tail(weapon: WeaponDefinition) -> void:
	var far := ProceduralAudio.fetch("shot_far:" + weapon.id)
	var camera := get_viewport().get_camera_3d()
	if far != null and camera != null:
		_schedule(far, camera.global_position, weapon.shot_volume_db + settings.own_shot_tail_db,
				settings.shot_distant_unit_size, 0.0, randf_range(0.97, 1.03))


## A prewarmed sound (`key` as built at start) at `position`, now.
func play_at(key: String, position: Vector3, volume_db: float, unit_size: float) -> void:
	var stream := ProceduralAudio.fetch(key)
	if stream != null and _listener_distance(position) <= settings.max_hear_distance:
		_schedule(stream, position, volume_db, unit_size, 0.0, randf_range(0.92, 1.08))


## A footfall at `feet` (a body's floor position): the surface underfoot
## picks the sound. Far-away steps are skipped.
func footstep(feet: Vector3, volume_db: float, unit_size: float, max_distance: float = INF) -> void:
	if _listener_distance(feet) > max_distance:
		return
	var surface := _surface_under(feet)
	var stream := ProceduralAudio.fetch("step:%s:%d" % [surface.id, randi() % settings.footstep_variants])
	if stream == null:
		return
	_schedule(stream, feet, volume_db + surface.footstep_volume_db, unit_size, 0.0, randf_range(0.94, 1.06))
	counts.steps += 1


func _on_bullet_moved(from: Vector3, to: Vector3, shooter: Node) -> void:
	if shooter is Player:
		return  # your own rounds don't crack past your ears
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var ear := camera.global_position
	var closest := Geometry3D.get_closest_point_to_segment(ear, from, to)
	var distance := ear.distance_to(closest)
	if distance > settings.snap_radius or closest.is_equal_approx(from):
		return  # too far, or the round has not reached us yet this tick
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_snap < settings.snap_min_interval:
		return
	_last_snap = now
	var stream := ProceduralAudio.fetch("snap:%d" % (randi() % settings.snap_variants))
	if stream == null:
		return
	var level := settings.snap_volume_db + linear_to_db(lerpf(1.0, 0.3, distance / settings.snap_radius))
	_schedule(stream, closest, level, settings.snap_unit_size, 0.0, randf_range(0.92, 1.08))
	counts.snaps += 1


# --- Feedback cues -----------------------------------------------------------------

func _on_target_hit(info: Dictionary) -> void:
	if not info.shooter is Player:
		return
	var killed := _is_dead(info.target)
	var stream := ProceduralAudio.fetch("cue:kill" if killed else "cue:hit")
	if stream == null:
		return
	_cues.stream = stream
	_cues.volume_db = settings.kill_cue_db if killed else settings.hit_confirm_db
	_cues.play()
	counts["kills" if killed else "hits"] += 1


## Whether what was hit (a Hitbox, or the body itself) is now dead: the
## nearest of it and its parents that knows.
func _is_dead(target: Object) -> bool:
	var node := target as Node
	for depth in 3:
		if not is_instance_valid(node):
			return false
		var dead: Variant = node.get("dead")
		if dead != null:
			return bool(dead)
		node = node.get_parent()
	return false


## A blast at `center`: within deafen_radius the world goes dull and the
## ears ring, more and for longer the closer it was.
func blast(center: Vector3) -> void:
	var distance := _listener_distance(center)
	if distance >= settings.deafen_radius:
		return
	deafen(1.0 - distance / settings.deafen_radius)


func deafen(strength: float) -> void:
	strength = clampf(strength, 0.0, 1.0)
	if strength <= 0.0:
		return
	_deaf_strength = maxf(strength, _deaf_strength if deaf_left > 0.0 else 0.0)
	_deaf_total = settings.deafen_seconds * _deaf_strength
	deaf_left = _deaf_total
	if _lowpass != null:
		AudioServer.set_bus_effect_enabled(_sfx_bus, _lowpass_index, true)
	var ring := ProceduralAudio.fetch("ear_ring")
	if ring != null:
		_ring.stream = ring
		_ring.volume_db = settings.ear_ring_db + linear_to_db(_deaf_strength)
		_ring.play()
	counts.blasts += 1


func _update_deafness(delta: float) -> void:
	if deaf_left <= 0.0:
		return
	deaf_left = maxf(deaf_left - delta, 0.0)
	if _lowpass == null:
		return
	# Cutoff rises (log scale) from muffled back to open as the ears recover.
	var muffle := pow(deaf_left / maxf(_deaf_total, 0.001), 0.7)
	var low := exp(lerpf(log(20000.0), log(settings.deafen_lowpass_hz), _deaf_strength))  # pitch is logarithmic
	_lowpass.cutoff_hz = exp(lerpf(log(20000.0), log(low), muffle))
	if deaf_left <= 0.0:
		AudioServer.set_bus_effect_enabled(_sfx_bus, _lowpass_index, false)


func _update_breathing(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or player.dead or player.health.fraction() >= settings.low_health_fraction:
		_breath_left = 0.0
		return
	_breath_left -= delta
	if _breath_left > 0.0:
		return
	_breath_left = settings.breath_period * randf_range(0.9, 1.1)
	var stream := ProceduralAudio.fetch("breath:%d" % (randi() % settings.breath_variants))
	if stream != null:
		_breath.stream = stream
		_breath.volume_db = settings.breath_db
		_breath.play()
		counts.breaths += 1


# --- Acoustics -----------------------------------------------------------------------

func _update_acoustics(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or not camera.is_inside_tree():
		return
	_probe_left -= delta
	if _probe_left <= 0.0 or acoustics_target.is_empty():
		_probe_left = settings.probe_interval
		acoustics_target = measure(camera.global_position)
	if acoustics.is_empty():
		acoustics = acoustics_target.duplicate()
	var blend := 1.0 - exp(-settings.blend_speed * delta)
	for key: String in acoustics_target:
		acoustics[key] = lerpf(acoustics[key], acoustics_target[key], blend)
	if _reverb != null:
		_reverb.room_size = acoustics.room_size
		_reverb.damping = acoustics.damping
		_reverb.wet = acoustics.wet
		_reverb.predelay_msec = acoustics.predelay_ms
		_reverb.predelay_feedback = acoustics.echo_feedback


## Rays round `ear` (and one up) measure the space; returns the reverb for it.
func measure(ear: Vector3) -> Dictionary:
	var space := get_viewport().world_3d.direct_space_state if get_viewport().world_3d != null else null
	var distances := PackedFloat32Array()
	var roofed := false
	if space != null:
		for i in settings.probe_rays:
			var angle := TAU * i / settings.probe_rays
			var to := ear + Vector3(cos(angle), 0.0, sin(angle)) * settings.probe_range
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(ear, to, PhysicsLayers.WORLD))
			distances.append(ear.distance_to(hit.position) if not hit.is_empty() else INF)
		var up := PhysicsRayQueryParameters3D.create(ear, ear + Vector3.UP * settings.roof_height, PhysicsLayers.WORLD)
		roofed = not space.intersect_ray(up).is_empty()
	return SoundModels.acoustics(distances, roofed, settings, Ballistics.settings.speed_of_sound)


# --- Plumbing ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_acoustics(delta)
	_update_deafness(delta)
	_update_breathing(delta)
	if _pending.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var waiting: Array[Dictionary] = []
	for sound in _pending:
		if sound.at > now:
			waiting.append(sound)
		else:
			_play(sound)
	_pending = waiting


func _schedule(stream: AudioStreamWAV, position: Vector3, volume_db: float, unit_size: float,
		delay: float, pitch: float) -> void:
	var sound := {"at": Time.get_ticks_msec() / 1000.0 + delay, "stream": stream, "position": position,
			"volume_db": volume_db, "unit_size": unit_size, "pitch": pitch}
	if delay <= 0.0:
		_play(sound)
	else:
		_pending.append(sound)


func _play(sound: Dictionary) -> void:
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.global_position = sound.position
	player.stream = sound.stream
	player.volume_db = sound.volume_db
	player.unit_size = sound.unit_size
	player.pitch_scale = sound.pitch
	player.play()


## Shots still in flight belong to the level that is going away.
func _on_scene_changed() -> void:
	_pending.clear()
	acoustics.clear()
	acoustics_target.clear()
	deaf_left = 0.0
	if _lowpass != null:
		AudioServer.set_bus_effect_enabled(_sfx_bus, _lowpass_index, false)


func _cue_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.bus = &"Cues"  # beside SFX: not muffled by deafness, same volume setting
	return player


## Reverb (always on) and the deafness low-pass (on while deafened) on SFX.
func _setup_bus_effects() -> void:
	_sfx_bus = AudioServer.get_bus_index("SFX")
	if _sfx_bus < 0:
		return
	for i in AudioServer.get_bus_effect_count(_sfx_bus):
		var effect := AudioServer.get_bus_effect(_sfx_bus, i)
		if effect is AudioEffectReverb:
			_reverb = effect
		elif effect is AudioEffectLowPassFilter:
			_lowpass = effect
			_lowpass_index = i
	if _reverb == null:
		_reverb = AudioEffectReverb.new()
		_reverb.dry = 1.0
		_reverb.spread = 1.0
		_reverb.hipass = settings.reverb_hipass
		_reverb.wet = settings.open_wet
		AudioServer.add_bus_effect(_sfx_bus, _reverb)
	if _lowpass == null:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(_sfx_bus, _lowpass)
		_lowpass_index = AudioServer.get_bus_effect_count(_sfx_bus) - 1
	AudioServer.set_bus_effect_enabled(_sfx_bus, _lowpass_index, false)


func _surface_under(feet: Vector3) -> SurfaceMaterial:
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.3,
			feet + Vector3.DOWN * settings.ground_probe, PhysicsLayers.WORLD)
	var hit := space.intersect_ray(query)
	return Ballistics.surface_of(hit.collider) if not hit.is_empty() else Ballistics.settings.default_surface


func _listener_distance(position: Vector3) -> float:
	var camera := get_viewport().get_camera_3d()
	return camera.global_position.distance_to(position) if camera != null else 0.0


func _load_weapons() -> Array[WeaponDefinition]:
	var weapons: Array[WeaponDefinition] = []
	for file in ResourceLoader.list_directory(WEAPON_DIR):
		if not file.ends_with(".tres"):
			continue
		var weapon := load(WEAPON_DIR + file) as WeaponDefinition
		if weapon != null and weapon.melee_damage <= 0.0:
			weapons.append(weapon)
	return weapons


# --- Prewarm -------------------------------------------------------------------------

## Builds every sound on a worker thread (never on the main thread in play);
## a sound not built yet is simply skipped.
func _prewarm() -> void:
	var jobs: Array = []
	for weapon in _weapons:
		jobs.append(["shot:" + weapon.id, "shot", weapon])
		jobs.append(["shot_far:" + weapon.id, "shot_far", weapon, settings.distant_shot_length])
	var surfaces: Array = Ballistics.settings.surfaces.values()
	if not surfaces.has(Ballistics.settings.default_surface):
		surfaces.append(Ballistics.settings.default_surface)
	for surface: SurfaceMaterial in surfaces:
		for variant in settings.footstep_variants:
			jobs.append(["step:%s:%d" % [surface.id, variant], "step", surface, variant])
	for variant in settings.snap_variants:
		jobs.append(["snap:%d" % variant, "snap", variant])
	for variant in settings.breath_variants:
		jobs.append(["breath:%d" % variant, "breath", variant])
	for variant in 3:
		jobs.append(["splat:%d" % variant, "splat", variant])
	jobs.append(["cue:hit", "hit"])
	jobs.append(["cue:kill", "kill"])
	jobs.append(["ear_ring", "ring"])
	var shouts := AI.settings.shouts
	if shouts != null:
		for line in shouts.lines:
			if line.voice is AudioStreamWAV:
				jobs.append([shout_key(line), "shout", line.voice, shouts.drive, shouts.edge])
		for kind in PAIN_KINDS:
			for variant in shouts.pain_variants:
				jobs.append(["pain:%s:%d" % [kind, variant], "pain", kind, variant])
	jobs = jobs.filter(func(job: Array) -> bool: return not ProceduralAudio.has(job[0]))
	if not jobs.is_empty():
		_prewarm_task = WorkerThreadPool.add_task(_build.bind(jobs), false, "soundscape sounds")


## Worker thread: static, so it never touches a node that may be gone.
static func _build(jobs: Array) -> void:
	for job: Array in jobs:
		var stream: AudioStreamWAV
		match job[1]:
			"shot":
				stream = ProceduralAudio.gunshot(job[2])
			"shot_far":
				stream = ProceduralAudio.gunshot_distant(job[2], job[3])
			"step":
				stream = ProceduralAudio.footstep(job[2], job[3])
			"snap":
				stream = ProceduralAudio.bullet_snap(job[2])
			"breath":
				stream = ProceduralAudio.breath(job[2])
			"splat":
				stream = ProceduralAudio.produce_splat(job[2])
			"hit":
				stream = ProceduralAudio.hit_confirm()
			"kill":
				stream = ProceduralAudio.kill_cue()
			"ring":
				stream = ProceduralAudio.ear_ring()
			"shout":
				stream = ProceduralAudio.shouted(job[2], job[3], job[4])
			"pain":
				stream = ProceduralAudio.pain(job[2], job[3])
		ProceduralAudio.store.call_deferred(job[0], stream)


const PAIN_KINDS := ["grunt", "wince", "groan", "death"]


## Cache key of a shout line's yelled version (built at start).
static func shout_key(line: ShoutLine) -> String:
	return "shout:" + line.voice.resource_path


## True once every prewarmed sound has been handed over (for probes).
func ready_to_play() -> bool:
	return _prewarm_task < 0 or WorkerThreadPool.is_task_completed(_prewarm_task)


# --- Debug -----------------------------------------------------------------------------

func _cmd_acoustics(_args: PackedStringArray) -> String:
	if acoustics.is_empty():
		return "no listener yet"
	return "enclosure %.2f  room %.2f  damping %.2f  wet %.2f  slap %.0f ms  echo %.2f" % [
		acoustics.enclosure, acoustics.room_size, acoustics.damping, acoustics.wet,
		acoustics.predelay_ms, acoustics.echo_feedback]


func _cmd_deafen(args: PackedStringArray) -> String:
	var strength := args[0].to_float() if not args.is_empty() and args[0].is_valid_float() else 1.0
	deafen(strength)
	return "ears ringing (%.1f) for %.1f s" % [strength, deaf_left]


func _cmd_demo(_args: PackedStringArray) -> String:
	_demo.call_deferred()
	return "sound demo: own shots, enemy shots at 10/40/120/300 m, snaps, footsteps, cues, blast"


## Each sound in turn in front of the camera, with a pause between, so they can
## be judged by ear (the Milestone 5 listening check).
func _demo() -> void:
	var tree := get_tree()
	var holder := tree.get_first_node_in_group("player_weapons")
	for weapon in _weapons:
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			return
		print("demo: %s" % weapon.display_name)
		for distance in [10.0, 40.0, 120.0, 300.0]:
			var forward := -camera.global_basis.z
			gunshot(weapon, camera.global_position + forward * distance)
			await tree.create_timer(1.6).timeout
		if holder != null:
			own_shot_tail(weapon)
		await tree.create_timer(1.0).timeout
	for i in 4:
		var camera := get_viewport().get_camera_3d()
		var side := camera.global_basis.x * (1.0 if i % 2 == 0 else -1.0)
		var from := camera.global_position - camera.global_basis.z * 30.0 + side
		_on_bullet_moved(from, from + camera.global_basis.z * 60.0, null)
		await tree.create_timer(0.5).timeout
	for surface: SurfaceMaterial in Ballistics.settings.surfaces.values():
		print("demo: footsteps on %s" % surface.id)
		for i in 4:
			var stream := ProceduralAudio.fetch("step:%s:%d" % [surface.id, i])
			var camera := get_viewport().get_camera_3d()
			if stream != null:
				_schedule(stream, camera.global_position + Vector3.DOWN * 1.6, settings.step_walk_db + surface.footstep_volume_db,
						settings.step_unit_size, 0.0, 1.0)
			await tree.create_timer(0.45).timeout
	for key in ["cue:hit", "cue:kill"]:
		_cues.stream = ProceduralAudio.fetch(key)
		_cues.volume_db = settings.hit_confirm_db
		_cues.play()
		await tree.create_timer(0.8).timeout
	deafen(1.0)
