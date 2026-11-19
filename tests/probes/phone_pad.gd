extends Node
## PhonePad probe (windowed: mouse look needs a captured mouse). Starts the
## PhonePad server and a simulated phone (tools/phonepad/sim/phone_sim.js, a
## Node client over WSS), loads the arena and checks that the phone moves,
## looks (every degree arrives although the sim drops packets), fires, taps
## reload and next weapon (single-packet taps are latched), that 500 ms of
## silence releases it, and that keyboard and mouse still work and combine
## with it. Exit 0 = pass. Needs Node 18+ and `npm ci --ignore-scripts` in tools/phonepad.
##
##   $GODOT --path . res://tests/probes/phone_pad.tscn
## Ports other than 8444/8081 (one already taken)? Set PHONEPAD_GAME_PORT and
## PHONEPAD_HTTPS_PORT first: the server, the sim and the PhonePad autoload all read them.

const LEVEL := "res://levels/greybox/arena.tscn"

var level: Node3D
var player: Player
var holder: WeaponHolder
var failures := 0
var server_pid := -1
var sim: Dictionary = {}
var reload_presses := 0
var saw_reloading := false
var _watch_reload := false


func _ready() -> void:
	get_tree().create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		printerr("FAIL watchdog")
		_stop_processes()
		get_tree().quit(2))
	var phonepad := ProjectSettings.globalize_path("res://tools/phonepad")
	server_pid = OS.create_process("node", [phonepad.path_join("server.js")])
	if server_pid <= 0:
		print("FAIL could not start node")
		get_tree().quit(1)
		return
	level = load(LEVEL).instantiate()
	add_child(level)
	player = level.get_node("Player")
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	if not _watch_reload or holder == null:
		return
	if Input.is_action_just_pressed("reload"):
		reload_presses += 1
	if holder.current_weapon() != null and holder.current_weapon().state == WeaponModel.State.RELOADING:
		saw_reloading = true


func _run() -> void:
	await level.combat_ready
	# The sim starts its timeline on the game's first state message: start it
	# only now, or it plays while the level is still baking its navmesh.
	sim = OS.execute_with_pipe("node", [ProjectSettings.globalize_path("res://tools/phonepad/sim/phone_sim.js")], false)
	PhonePad._set_enabled(true)
	Debug.execute("god")
	AI.frozen = true
	holder = get_tree().get_first_node_in_group("player_weapons") as WeaponHolder
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var tree := get_tree()
	while PhonePad.protocol.packets == 0:
		await tree.physics_frame
	var t0 := Time.get_ticks_msec()
	var t := func() -> float: return (Time.get_ticks_msec() - t0) / 1000.0
	print("first phone packet; server %s, phones %d" % [PhonePad.is_connected_to_server(), PhonePad.controllers])
	var start := player.global_position
	var forward := -player.global_basis.z

	# Phone stick forward, keyboard D added on top for a while.
	await _until(t, 0.5)
	_key(KEY_D, true)
	await _until(t, 1.3)
	var local := player.global_basis.inverse() * player.velocity
	_check("phone forward + keyboard D combine", -local.z > 1.0 and local.x > 1.0, "local velocity %s" % local)
	_key(KEY_D, false)
	await _until(t, 1.42)
	# Baseline for the turn, taken before it starts (the sim's clock leads ours slightly).
	var yaw0 := player.rotation.y
	var look0 := PhonePad.look_applied.x
	var wish := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	_check("releasing D leaves the phone's forward held", wish.y > 0.9 and absf(wish.x) < 0.05, "vector %s" % wish)
	await _until(t, 1.55)
	var moved := (player.global_position - start).dot(forward)
	_check("the phone stick walks the player forward", moved > 1.0, "%.2f m" % moved)

	# Turn: 30 degrees of phone, every 7th packet dropped on the phone side.
	await _until(t, 2.85)
	var turned := PhonePad.look_applied.x - look0
	var expected := -30.0 * PhonePad.tuning.look_pixels_per_degree * Settings.camera_tuning.mouse_sensitivity
	var yaw := wrapf(player.rotation.y - yaw0, -PI, PI)
	_check("every degree of look arrives despite dropped packets", absf(turned - 30.0) < 0.05, "%.2f deg" % turned)
	_check("look turns the player like a mouse would", absf(yaw - expected) < 0.02, "yaw %.3f rad, expected %.3f" % [yaw, expected])

	# Fire.
	var shots0 := holder.shots_fired
	var haptics0 := PhonePad.haptics_sent
	await _until(t, 3.55)
	_check("FIRE shoots", holder.shots_fired > shots0, "shots %d -> %d" % [shots0, holder.shots_fired])
	_check("firing buzzes the phone", PhonePad.haptics_sent > haptics0, "haptics %d -> %d" % [haptics0, PhonePad.haptics_sent])

	# Single-packet taps.
	_watch_reload = true
	await _until(t, 3.95)
	_watch_reload = false
	_check("a one-packet RELOAD tap is seen once", reload_presses == 1, "%d presses" % reload_presses)
	_check("and starts a reload", saw_reloading, "no RELOADING state")
	var slot := holder.current
	await _until(t, 4.4)
	_check("a one-packet NEXT WEAPON tap switches weapon", holder.current != slot, "slot %d -> %d" % [slot, holder.current])

	# One packet with FIRE + forward, then silence: released within 500 ms.
	await _until(t, 4.75)
	var held_after_last := Input.is_action_pressed("fire")
	await _until(t, 5.3)
	var released := not Input.is_action_pressed("fire") and Input.get_vector("move_left", "move_right", "move_back", "move_forward") == Vector2.ZERO
	_check("the last packet holds until the timeout", held_after_last, "fire not held at 4.75 s")
	_check("500 ms of silence releases the phone", released, "fire %s" % Input.is_action_pressed("fire"))

	# Keyboard and mouse on their own still work.
	start = player.global_position
	forward = -player.global_basis.z
	_key(KEY_W, true)
	await tree.create_timer(0.8).timeout
	_key(KEY_W, false)
	moved = (player.global_position - start).dot(forward)
	_check("keyboard W still walks", moved > 1.0, "%.2f m" % moved)
	yaw0 = player.rotation.y
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 0)
	Input.parse_input_event(motion)
	await tree.process_frame
	await tree.process_frame
	yaw = wrapf(player.rotation.y - yaw0, -PI, PI)
	expected = -100.0 * Settings.camera_tuning.mouse_sensitivity
	_check("the mouse still turns", absf(yaw - expected) < 0.01, "yaw %.3f, expected %.3f" % [yaw, expected])
	shots0 = holder.shots_fired
	await tree.create_timer(1.2).timeout  # let the weapon switch finish
	shots0 = holder.shots_fired
	_click(true)
	await tree.create_timer(0.4).timeout
	_click(false)
	_check("the left mouse button still fires", holder.shots_fired > shots0, "shots %d -> %d" % [shots0, holder.shots_fired])

	# Haptics for damage and kills (the sim stays connected, silent).
	player.health.invulnerable = false
	player.health.protected_left = 0.0
	var sent := PhonePad.haptics_sent
	player.health.take_hit(20.0, DamageModel.Zone.TORSO, {})
	_check("taking damage buzzes the phone", PhonePad.haptics_sent == sent + 1, "%d -> %d" % [sent, PhonePad.haptics_sent])
	player.health.invulnerable = true
	var soldier: Soldier = AI.soldiers[0]
	PhonePad._on_target_hit({"shooter": player, "target": soldier.hitbox})
	sent = PhonePad.haptics_sent
	soldier.health.take_hit(INF, DamageModel.Zone.HEAD, {})
	await tree.physics_frame
	_check("a kill after the player's hit buzzes the phone", PhonePad.haptics_sent == sent + 1, "%d -> %d" % [sent, PhonePad.haptics_sent])
	sent = PhonePad.haptics_sent
	AI.soldiers[0].health.take_hit(INF, DamageModel.Zone.HEAD, {})
	await tree.physics_frame
	_check("someone else's kill doesn't", PhonePad.haptics_sent == sent, "%d -> %d" % [sent, PhonePad.haptics_sent])

	# PAUSE from the phone opens the pause menu, and again resumes.
	await _tap(PhonePadProtocol.BIT_PAUSE)
	_check("phone PAUSE pauses the game", tree.paused, "not paused")
	await _tap(PhonePadProtocol.BIT_PAUSE)
	_check("phone PAUSE again resumes", not tree.paused, "still paused")

	await tree.create_timer(0.5).timeout
	var sim_out := _read_sim()
	print(sim_out.strip_edges())
	var buzzes := sim_out.count("SIM haptic")
	_check("the phone received every haptic", buzzes == PhonePad.haptics_sent and buzzes > 0, "%d received, %d sent" % [buzzes, PhonePad.haptics_sent])
	print(Debug.execute("phone"))
	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	_stop_processes()
	tree.quit(1 if failures else 0)


## Feeds one packet with `bit` pressed and one released, as the phone's pulse does.
func _tap(bit: int) -> void:
	var protocol := PhonePad.protocol
	protocol.receive(PhonePadProtocol.encode_v2(protocol.last_seq + 1, bit, Vector2.ZERO, Vector2.ZERO), Time.get_ticks_msec())
	protocol.receive(PhonePadProtocol.encode_v2(protocol.last_seq + 1, 0, Vector2.ZERO, Vector2.ZERO), Time.get_ticks_msec())
	for i in 4:
		await get_tree().process_frame


func _until(clock: Callable, seconds: float) -> void:
	while clock.call() < seconds:
		await get_tree().physics_frame


func _key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func _click(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)


func _read_sim() -> String:
	var out := ""
	var pipe: FileAccess = sim.get("stdio")
	if pipe != null:
		var buffer := pipe.get_buffer(65536)
		out = buffer.get_string_from_utf8()
	return out


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", what, "" if ok else " (%s)" % detail])
	if not ok:
		failures += 1


func _stop_processes() -> void:
	if sim.has("pid") and OS.is_process_running(sim.pid):
		OS.kill(sim.pid)
	if server_pid > 0 and OS.is_process_running(server_pid):
		OS.kill(server_pid)
