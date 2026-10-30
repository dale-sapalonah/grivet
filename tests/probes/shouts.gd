extends Node
## Shouts probe (arena): soldiers shout on spotting the player, threaten when
## close, never talk over each other (gap_seconds), cry out when flashbanged,
## and the HUD shows the words; shouts play their yelled version, a hit
## soldier grunts or groans and a killed one cries out. Exit 0 = pass.
##
##   $GODOT --headless --path . res://tests/probes/shouts.tscn

const LEVEL := "res://levels/greybox/arena.tscn"
const FLASH := preload("res://data/grenades/flash.tres")

var level: Node3D
var player: Player
var failures := 0
var _times: Array[float] = []
var _seen := 0


func _ready() -> void:
	level = load(LEVEL).instantiate()
	add_child(level)
	player = level.get_node("Player")
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		printerr("FAIL watchdog")
		get_tree().quit(2))
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	while _seen < AI.shout_log.size():
		_times.append(Time.get_ticks_msec() / 1000.0)
		_seen += 1


func _run() -> void:
	await level.combat_ready
	player.health.invulnerable = true
	while not Soundscape.ready_to_play():  # yelled shouts and pain are built at start
		await get_tree().create_timer(0.25).timeout
	var book := AI.settings.shouts
	await get_tree().create_timer(20.0).timeout
	_check("they shout when they spot the player", _said_any("spot"), "log %s" % [AI.shout_log])
	# Walk up close to the nearest soldier in view.
	var nearest: Soldier = null
	for soldier in AI.soldiers:
		if nearest == null or soldier.global_position.distance_to(player.global_position) < nearest.global_position.distance_to(player.global_position):
			nearest = soldier
	var before := AI.shout_log.size()
	var waited := 0.0
	while waited < 25.0 and not _said_any("threat", before) and not _said_any("melee", before):
		if is_instance_valid(nearest) and not nearest.dead:
			var to := (player.global_position - nearest.global_position)
			to.y = 0.0
			player.global_position = nearest.global_position + to.normalized() * minf(to.length(), 8.0)
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_check("close up they threaten", _said_any("threat", before) or _said_any("melee", before), "nothing in %.0f s: %s" % [waited, AI.shout_log.slice(before)])
	var gaps_ok := true
	for i in range(1, _times.size()):
		if _times[i] - _times[i - 1] < book.gap_seconds - 0.05:
			gaps_ok = false
	_check("nobody talks over anybody", gaps_ok, "times %s" % [_times])
	# A flashbang at a soldier's feet: it cries out.
	await get_tree().create_timer(book.gap_seconds + 0.2).timeout
	before = AI.shout_log.size()
	var victim: Soldier = AI.soldiers[0]
	var grenade := Grenade.throw(FLASH, level, victim.eye_point() - victim.global_basis.z * 1.0, Vector3.ZERO, player)
	grenade.freeze = true
	await grenade.exploded
	await get_tree().physics_frame
	_check("a flashbanged soldier cries out", _said_any("blind", before), "log %s" % [AI.shout_log.slice(before)])
	var hud := get_tree().get_first_node_in_group("hud")
	_check("the HUD shows the last shout", hud != null and hud._subtitle == AI.shout_log[AI.shout_log.size() - 1], "hud %s" % (hud._subtitle if hud else "none"))
	# Pain: a wounding hit makes it cry out, a kill leaves a cry where it fell.
	var hurt: Soldier = AI.soldiers[0]
	hurt._next_pain_at = 0.0
	hurt.health.take_hit(10.0, DamageModel.Zone.ARMS, {"direction": Vector3.FORWARD})
	var voice: AudioStreamPlayer3D = hurt._voice
	_check("a hit soldier grunts, winces or groans", voice != null and voice.playing and _is_pain(voice.stream, ["grunt", "wince", "groan"]),
			"voice %s" % voice)
	await get_tree().create_timer(book.gap_seconds + 0.1).timeout
	var shouter: Soldier = AI.soldiers[0]
	shouter.next_shout_at = 0.0
	AI.shout(shouter, "threat")
	_check("shouts play the yelled version", shouter._voice.stream != null and shouter._voice.stream.resource_path == "",
			"plays the plain recording %s" % shouter._voice.stream.resource_path)
	# The ENEMY VOICES switch: off, nobody speaks and the Voices bus is muted.
	Settings.set_value("voices_on", false)
	shouter.next_shout_at = 0.0
	await get_tree().create_timer(book.gap_seconds + 0.1).timeout
	var said := AI.shout(shouter, "threat")
	_check("with ENEMY VOICES off nobody speaks", not said and AudioServer.is_bus_mute(AudioServer.get_bus_index("Voices")),
			"shouted %s, bus muted %s" % [said, AudioServer.is_bus_mute(AudioServer.get_bus_index("Voices"))])
	Settings.set_value("voices_on", true)
	_check("switched back on they shout again", AI.shout(shouter, "blind", true), "silent")
	_check("voices go through the Voices bus", shouter._voice.bus == &"Voices", "bus %s" % shouter._voice.bus)
	var dying: Soldier = AI.soldiers[0]
	dying.health.take_hit(INF, DamageModel.Zone.HEAD, {"direction": Vector3.FORWARD})
	await get_tree().physics_frame
	var cried := false
	for node in level.find_children("*", "AudioStreamPlayer3D", true, false):
		cried = cried or (node.playing and _is_pain(node.stream, ["death"]))
	_check("a killed soldier cries out", cried, "no death cry playing")
	print("\nshouted: %s" % [AI.shout_log])
	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)


func _is_pain(stream: AudioStream, kinds: Array) -> bool:
	for kind in kinds:
		for variant in AI.settings.shouts.pain_variants:
			if stream != null and stream == ProceduralAudio.fetch("pain:%s:%d" % [kind, variant]):
				return true
	return false


func _said_any(situation: String, from: int = 0) -> bool:
	for i in range(from, AI.shout_log.size()):
		for line in AI.settings.shouts.lines:
			if line.text == AI.shout_log[i] and line.situation == situation:
				return true
	return false


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s" % what)
	else:
		failures += 1
		print("FAIL %s - %s" % [what, detail])
