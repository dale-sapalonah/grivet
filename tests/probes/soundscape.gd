extends Node
## Soundscape probe (port level; windowed to exercise real 3D audio): every
## sound gets built off the main thread; the reverb follows the space (the
## most and least enclosed spots the navmesh offers); enemy shots arrive late
## with only the right layers; a real enemy round passing close snaps;
## walking makes footsteps; shooting an enemy gives hit and kill cues; a blast
## muffles the world then lets it go; low health breathes. Exit 0 = pass.
##
##   $GODOT --path . res://tests/probes/soundscape.tscn

const LEVEL := "res://levels/port/port_yard.tscn"
const KESTREL := preload("res://data/weapons/kestrel.tres")

var level: Node3D
var player: Player
var failures := 0


func _ready() -> void:
	level = load(LEVEL).instantiate()
	add_child(level)
	player = level.get_node("Player")
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		printerr("FAIL watchdog")
		get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	await level.combat_ready
	Debug.execute("notarget")
	Debug.execute("ai.freeze")
	await _check("every sound is built off the main thread", func() -> String:
		var waited := 0.0
		while not Soundscape.ready_to_play() and waited < 20.0:
			await get_tree().create_timer(0.25).timeout
			waited += 0.25
		await get_tree().process_frame  # results arrive by call_deferred
		for key in ["shot:kestrel", "shot_far:kestrel", "shot_far:hammerhead", "snap:0", "step:steel:0",
				"step:dirt:3", "cue:hit", "cue:kill", "breath:0", "ear_ring"]:
			if not ProceduralAudio.has(key):
				return "%s missing after %.1f s" % [key, waited]
		return "")
	await _check("the reverb follows the space: an alley is tight and wet, open ground wide and dry", _acoustics)
	await _check("an enemy shot 150 m away arrives late, distant layer only", func() -> String:
		var camera := get_viewport().get_camera_3d()
		var before := Soundscape._pending.size()
		Soundscape.gunshot(KESTREL, camera.global_position - camera.global_basis.z * 150.0)
		var added: Array = Soundscape._pending.slice(before)
		var expected := 150.0 / Ballistics.settings.speed_of_sound
		if added.size() != 1:
			return "%d layers scheduled, wanted only the distant one" % added.size()
		var delay: float = added[0].at - Time.get_ticks_msec() / 1000.0
		if absf(delay - expected) > 0.05:
			return "arrives in %.2f s, wanted %.2f" % [delay, expected]
		if added[0].unit_size != Soundscape.settings.shot_distant_unit_size:
			return "not the distant layer"
		Soundscape._pending.clear()
		return "")
	await _check("an enemy shot 6 m away is the close layer, almost at once", func() -> String:
		var camera := get_viewport().get_camera_3d()
		var shots: int = Soundscape.counts.shots
		var before := Soundscape._pending.size()
		Soundscape.gunshot(KESTREL, camera.global_position - camera.global_basis.z * 6.0)
		var added: Array = Soundscape._pending.slice(before)
		Soundscape._pending.clear()
		if Soundscape.counts.shots != shots + 1 or added.size() != 1 or added[0].unit_size != Soundscape.settings.shot_close_unit_size:
			return "scheduled %s" % [added]
		return "")
	await _check("an enemy round passing a metre away snaps", func() -> String:
		var camera := get_viewport().get_camera_3d()
		var snaps: int = Soundscape.counts.snaps
		var shooter := Node3D.new()
		add_child(shooter)
		var ear := camera.global_position
		var from := ear - camera.global_basis.z * 40.0 + camera.global_basis.x * 1.0
		Ballistics.fire(from, (ear + camera.global_basis.x * 1.0 - from), KESTREL, shooter)
		await get_tree().create_timer(0.5).timeout
		shooter.queue_free()
		return "" if Soundscape.counts.snaps > snaps else "no snap")
	await _check("the player's own rounds don't snap", func() -> String:
		var camera := get_viewport().get_camera_3d()
		var snaps: int = Soundscape.counts.snaps
		var ear := camera.global_position
		Ballistics.fire(ear + camera.global_basis.x * 0.5, -camera.global_basis.z, KESTREL, player)
		await get_tree().create_timer(0.4).timeout
		return "" if Soundscape.counts.snaps == snaps else "own round snapped")
	await _check("walking makes footsteps in time with the stride", func() -> String:
		var steps: int = Soundscape.counts.steps
		Input.action_press("move_forward")
		await get_tree().create_timer(2.0).timeout
		Input.action_release("move_forward")
		var taken: int = Soundscape.counts.steps - steps
		return "" if taken >= 2 else "%d steps in 2 s of walking" % taken)
	await _check("shooting an enemy gives hit cues and a kill cue", _hit_and_kill)
	await _check("a blast close by muffles the world, then hearing comes back", func() -> String:
		var camera := get_viewport().get_camera_3d()
		Soundscape.blast(camera.global_position + Vector3(1.5, 0.0, 0.0))
		var bus := AudioServer.get_bus_index("SFX")
		if Soundscape.deaf_left <= 0.0 or not AudioServer.is_bus_effect_enabled(bus, Soundscape._lowpass_index):
			return "not deafened"
		await get_tree().process_frame
		await get_tree().process_frame
		var muffled := Soundscape._lowpass.cutoff_hz
		if muffled > 2000.0:
			return "cutoff %.0f Hz is not muffled" % muffled
		await get_tree().create_timer(Soundscape.settings.deafen_seconds + 0.3).timeout
		if AudioServer.is_bus_effect_enabled(bus, Soundscape._lowpass_index):
			return "still muffled after %.1f s" % Soundscape.settings.deafen_seconds
		var before: int = Soundscape.counts.blasts
		Soundscape.blast(camera.global_position + Vector3(40.0, 0.0, 0.0))
		return "" if Soundscape.counts.blasts == before else "a blast 40 m away deafened")
	await _check("badly hurt, the player breathes hard", func() -> String:
		if player.health.invulnerable:
			Debug.execute("god")
		var tries := 0
		while player.health.fraction() >= Soundscape.settings.low_health_fraction and tries < 60:
			Debug.execute("damage 5")
			tries += 1
		if player.dead or player.health.fraction() >= Soundscape.settings.low_health_fraction:
			return "could not wound the player (fraction %.2f, dead %s)" % [player.health.fraction(), player.dead]
		var breaths: int = Soundscape.counts.breaths
		await get_tree().create_timer(Soundscape.settings.breath_period * 1.5).timeout
		player.health.revive()
		return "" if Soundscape.counts.breaths > breaths else "no breathing")
	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)


## The most and least enclosed of many navmesh spots: stand in each and let
## the reverb settle.
func _acoustics() -> String:
	var best := Vector3.ZERO
	var worst := Vector3.ZERO
	var most := -1.0
	var least := 2.0
	for i in 150:
		var spot := NavigationServer3D.map_get_random_point(AI.nav_map, 1, true)
		var reading := Soundscape.measure(spot + Vector3.UP * 1.2)
		if reading.enclosure > most:
			most = reading.enclosure
			best = spot
		if reading.enclosure < least:
			least = reading.enclosure
			worst = spot
	var results := []
	for spot in [best, worst]:
		Debug.execute("tp %.2f %.2f %.2f" % [spot.x, spot.y, spot.z])
		await get_tree().create_timer(2.0).timeout
		results.append(Soundscape.acoustics.duplicate())
	var alley: Dictionary = results[0]
	var open: Dictionary = results[1]
	print("  alley %s\n  open  %s" % [_brief(alley), _brief(open)])
	if alley.enclosure < 0.6 or open.enclosure > 0.3:
		return "found no real alley (%.2f) or open ground (%.2f)" % [alley.enclosure, open.enclosure]
	if not (alley.wet > open.wet and alley.predelay_ms < open.predelay_ms and alley.damping < open.damping):
		return "reverb does not follow the space"
	var reverb := Soundscape._reverb
	if absf(reverb.wet - open.wet) > 0.05:
		return "the bus reverb (wet %.2f) is not the measured one (%.2f)" % [reverb.wet, open.wet]
	return ""


func _brief(reading: Dictionary) -> String:
	return "enclosure %.2f wet %.2f room %.2f damping %.2f slap %.0f ms" % [
		reading.enclosure, reading.wet, reading.room_size, reading.damping, reading.predelay_ms]


func _hit_and_kill() -> String:
	Debug.execute("ai.freeze")  # thaw: frozen soldiers don't move their hit zones onto their bodies
	Debug.execute("tp 0 0 0")
	await get_tree().create_timer(0.3).timeout
	var camera := get_viewport().get_camera_3d()
	Debug.execute("spawn rifleman 1 8")
	await get_tree().create_timer(0.5).timeout
	var soldier: Soldier = null
	for candidate: Soldier in AI.soldiers:
		if soldier == null or candidate.global_position.distance_to(camera.global_position) \
				< soldier.global_position.distance_to(camera.global_position):
			soldier = candidate
	if soldier == null:
		return "no soldier"
	var hits: int = Soundscape.counts.hits
	var kills: int = Soundscape.counts.kills
	for shot in 60:
		if not is_instance_valid(soldier) or soldier.dead:
			break
		var from := camera.global_position
		Ballistics.fire(from, soldier.aim_point() - from, KESTREL, player, [player.get_rid()])
		await get_tree().create_timer(0.08).timeout
	await get_tree().create_timer(0.3).timeout
	if Soundscape.counts.hits <= hits:
		return "no hit cue"
	return "" if Soundscape.counts.kills == kills + 1 else "%d kill cues" % (Soundscape.counts.kills - kills)


func _check(what: String, test: Callable) -> void:
	var problem: String = await test.call()
	if problem == "":
		print("PASS %s" % what)
	else:
		failures += 1
		print("FAIL %s - %s" % [what, problem])
