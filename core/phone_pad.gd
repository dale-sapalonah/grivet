extends Node
## Autoloaded as `PhonePad`: a phone as an extra controller (tools/phonepad).
## Connects to the PhonePad server's localhost game socket, decodes the
## phone's packets (PhonePadProtocol) and feeds Grivet's own input system, so
## keyboard and mouse keep working and the two combine:
##   - held/polled actions (move, fire, aim, jump, sprint, crouch...) through
##     Input.action_press / action_release, movement with analog strength;
##   - next/previous weapon and pause as InputEventAction events (their
##     handlers react to events, not to polled state);
##   - look as synthetic InputEventMouseMotion, so Player applies sensitivity,
##     the ADS multiplier, invert Y and the pitch limit exactly as for a mouse.
## Look is summed per packet, never scaled by frame time: frame-rate independent.
## Haptics go back to the phone on firing, taking damage, kills and death.
## No OS-level input injection: only this game sees the phone.

const TUNING_PATH := "res://data/input/phone_pad_tuning.tres"
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_back", &"move_forward"]
## Fired as events on their press edge (handlers use event.is_action_pressed).
const EVENT_BITS := [PhonePadProtocol.BIT_NEXT_WEAPON, PhonePadProtocol.BIT_PREVIOUS_WEAPON, PhonePadProtocol.BIT_PAUSE]
## Press edges that also send ui_accept: skips mission cinematics, retries after MISSION FAILED.
const CONTINUE_BITS := PhonePadProtocol.BIT_FIRE | PhonePadProtocol.BIT_JUMP

var tuning: PhonePadTuning = load(TUNING_PATH)
var protocol := PhonePadProtocol.new()
## Phones connected to the server (it announces the count).
var controllers := 0
var enabled := true
## Look applied so far in degrees of phone turn (probes check it).
var look_applied := Vector2.ZERO
## Haptic messages sent (probes check them).
var haptics_sent := 0

var _socket: WebSocketPeer
var _url := ""
var _retry_left := 0.0
var _applied := 0  # buttons this node holds down
var _move_applied := Vector2.ZERO
var _state_left := 0.0
var _fire_cooldown := 0.0
var _player: Player
var _holder: WeaponHolder
var _last_hit_soldier := 0
var _last_hit_time := -INF
var _server_pid := -1  # a server this game started (the menu's PHONE CONTROLLER page)

const SERVER_DIR := "res://tools/phonepad"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # pause / resume from the phone
	_url = tuning.url
	var port := OS.get_environment("PHONEPAD_GAME_PORT")
	if port.is_valid_int():
		_url = _url.replace(":8080/", ":%s/" % port)
	enabled = bool(Settings.get_value("phone_pad"))
	Settings.changed.connect(_on_setting_changed)
	Ballistics.target_hit.connect(_on_target_hit)
	AI.soldier_died.connect(_on_soldier_died)
	Debug.register("phone", _cmd_phone, "PhonePad status; `phone buzz` vibrates the phone, `phone off|on` toggles it.")


func is_connected_to_server() -> bool:
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


## The server's localhost-only list of controller URLs with QR modules.
func links_url() -> String:
	return _url.replace("ws://", "http://").get_slice("/ws", 0) + "/api/controller-links"


## Starts the PhonePad server (hidden, stopped when Grivet quits) unless one is
## already up. Returns "" or what is wrong, for the menu to show. Turns the
## phone controller setting on. Needs Node.js and the packages that
## `Play Grivet with Phone.bat` installs on its first run.
func start_server() -> String:
	if not enabled:
		Settings.set_value("phone_pad", true)
	if is_connected_to_server() or (_server_pid > 0 and OS.is_process_running(_server_pid)):
		return ""
	var folder := ProjectSettings.globalize_path(SERVER_DIR)
	if not DirAccess.dir_exists_absolute(folder.path_join("node_modules")):
		return "PHONEPAD ISN'T INSTALLED YET: RUN Play Grivet with Phone.bat ONCE"
	# A server launched by the .bat but not yet connected to exits at once (port in use).
	_server_pid = OS.create_process("node", [folder.path_join("server.js")])
	if _server_pid <= 0:
		_server_pid = -1
		return "NODE.JS NOT FOUND: INSTALL NODE 18 OR NEWER (nodejs.org)"
	print("PhonePad: started the server (pid %d)" % _server_pid)
	_retry_left = minf(_retry_left, 0.5)  # connect as soon as it is up
	return ""


func _exit_tree() -> void:
	if _server_pid > 0 and OS.is_process_running(_server_pid):
		OS.kill(_server_pid)  # only the server this game started


## Vibrates the phone (pattern in ms: on, off, on...). Quietly does nothing without one.
func haptic(pattern: PackedInt32Array) -> void:
	if not is_connected_to_server() or controllers <= 0 or pattern.is_empty():
		return
	_socket.send_text(JSON.stringify({"t": "haptic", "pattern": Array(pattern)}))
	haptics_sent += 1


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_poll_socket(delta)
	var now := Time.get_ticks_msec()
	var buttons := protocol.take_buttons(now, tuning.timeout_ms)
	var live := protocol.is_live(now, tuning.timeout_ms)
	if Debug.console_open:
		buttons = 0  # the console has the keyboard; the phone waits too
	_apply_buttons(buttons)
	_apply_move(protocol.move if live and not Debug.console_open else Vector2.ZERO)
	_apply_look(protocol.take_look())
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	_bind_player()
	_state_left -= delta
	if _state_left <= 0.0:
		_state_left = tuning.state_interval
		_send_state()


func _poll_socket(delta: float) -> void:
	if _socket == null:
		_retry_left -= delta
		if _retry_left > 0.0:
			return
		_retry_left = tuning.reconnect_seconds
		_socket = WebSocketPeer.new()
		if _socket.connect_to_url(_url) != OK:
			_socket = null
		return
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			var now := Time.get_ticks_msec()
			while _socket.get_available_packet_count() > 0:
				var data := _socket.get_packet()
				if _socket.was_string_packet():
					_on_text(data.get_string_from_utf8())
				else:
					protocol.receive(data, now)
		WebSocketPeer.STATE_CLOSED:
			_socket = null  # server gone: try again quietly
			controllers = 0
			protocol.reset()
			_retry_left = tuning.reconnect_seconds


func _on_text(text: String) -> void:
	var message: Variant = JSON.parse_string(text)
	if message is Dictionary and message.get("t") == "controllers":
		var count := int(message.get("count", 0))
		if count > controllers:
			print("PhonePad: phone connected")
		controllers = count


func _apply_buttons(buttons: int) -> void:
	var pressed := buttons & ~_applied
	var released := _applied & ~buttons
	for bit: int in PhonePadProtocol.ACTIONS:
		var action: StringName = PhonePadProtocol.ACTIONS[bit]
		if bit in EVENT_BITS:
			if pressed & bit or released & bit:
				_send_action_event(action, bool(pressed & bit))
		elif pressed & bit:
			Input.action_press(action)
		elif released & bit:
			Input.action_release(action)
	if pressed & CONTINUE_BITS:
		_send_action_event(&"ui_accept", true)
		_send_action_event(&"ui_accept", false)
	_applied = buttons


func _send_action_event(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


## Movement keeps its analog strength. Input.get_vector applies a circular
## deadzone (a quarter of the four actions' deadzones summed) and rescales
## past it, so the length is pre-stretched to come out of get_vector unchanged.
func _apply_move(move: Vector2) -> void:
	if move == _move_applied:
		return
	_move_applied = move
	var stretched := Vector2.ZERO
	var length := minf(move.length(), 1.0)
	if length > 0.001:
		var deadzone := 0.0
		for action in MOVE_ACTIONS:
			deadzone += InputMap.action_get_deadzone(action) * 0.25
		stretched = move.normalized() * lerpf(deadzone + 0.001, 1.0, length)
	_axis(&"move_left", &"move_right", stretched.x)
	_axis(&"move_back", &"move_forward", stretched.y)


func _axis(negative: StringName, positive: StringName, value: float) -> void:
	if value > 0.0:
		Input.action_release(negative)
		Input.action_press(positive, value)
	elif value < 0.0:
		Input.action_release(positive)
		Input.action_press(negative, -value)
	else:
		Input.action_release(negative)
		Input.action_release(positive)


func _apply_look(degrees: Vector2) -> void:
	if degrees == Vector2.ZERO or Debug.console_open:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return  # menus have the mouse; turning there would only move the cursor
	look_applied += degrees
	var event := InputEventMouseMotion.new()
	event.relative = degrees * tuning.look_pixels_per_degree
	event.screen_relative = event.relative
	Input.parse_input_event(event)


func _send_state() -> void:
	if not is_connected_to_server() or controllers <= 0:
		return
	var state := {"t": "state", "paused": get_tree().paused, "over": false}
	if is_instance_valid(_player) and _player.health != null and _player.health.model != null:
		state.hp = _player.health.fraction()
		var max_armor := _player.health.model.max_armor()
		state.energy = _player.health.model.armor / max_armor if max_armor > 0.0 else 0.0
	_socket.send_text(JSON.stringify(state))


# --- Haptic events ----------------------------------------------------------------

func _bind_player() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player != null and _player.health != null:
			_player.health.damaged.connect(_on_player_damaged)
			_player.health.died.connect(func(_info: Dictionary) -> void: haptic(tuning.death_pattern))
	if not is_instance_valid(_holder):
		_holder = get_tree().get_first_node_in_group("player_weapons") as WeaponHolder
		if _holder != null:
			_holder.shot_fired.connect(_on_shot_fired)


func _on_shot_fired(_weapon: WeaponDefinition) -> void:
	if _fire_cooldown > 0.0:
		return
	_fire_cooldown = tuning.fire_min_interval
	haptic(tuning.fire_pattern)


func _on_player_damaged(info: Dictionary) -> void:
	var amount := float(info.get("health_damage", 0.0)) + float(info.get("armor_damage", 0.0))
	if amount <= 0.0 or (is_instance_valid(_player) and _player.dead):
		return
	haptic(tuning.heavy_damage_pattern if amount >= tuning.heavy_damage else tuning.damage_pattern)


func _on_target_hit(info: Dictionary) -> void:
	if not is_instance_valid(_player) or info.get("shooter") != _player:
		return
	var node: Node = info.get("target") as Node
	while node != null and not (node is Soldier):
		node = node.get_parent()
	if node != null:
		_last_hit_soldier = node.get_instance_id()
		_last_hit_time = Time.get_ticks_msec() / 1000.0


func _on_soldier_died(soldier: Soldier) -> void:
	var shot := soldier.get_instance_id() == _last_hit_soldier \
			and Time.get_ticks_msec() / 1000.0 - _last_hit_time <= tuning.kill_credit_seconds
	var knifed := is_instance_valid(_holder) and _holder.knife_time >= 0.0
	if shot or knifed:
		haptic(tuning.kill_pattern)


# --- Settings and debug ------------------------------------------------------------

func _on_setting_changed(key: String) -> void:
	if key == "phone_pad":
		_set_enabled(bool(Settings.get_value("phone_pad")))


func _set_enabled(on: bool) -> void:
	enabled = on
	if on:
		return
	if _socket != null:
		_socket.close()
		_socket = null
	controllers = 0
	protocol.reset()
	_apply_buttons(0)
	_apply_move(Vector2.ZERO)
	_retry_left = 0.0


func _cmd_phone(args: PackedStringArray) -> String:
	if args.size() > 0:
		match args[0]:
			"buzz":
				haptic(tuning.kill_pattern)
				return "buzz sent" if controllers > 0 else "no phone connected"
			"on", "off":
				Settings.set_value("phone_pad", args[0] == "on")
	var state := "off"
	if enabled:
		state = "connected" if is_connected_to_server() else "waiting for the PhonePad server (%s)" % _url
	return "PhonePad %s, phones %d, packets %d (v%d, %d stale), last seq %d, look %.1f/%.1f deg, haptics %d" % [
			state, controllers, protocol.packets, protocol.last_version, protocol.dropped, protocol.last_seq,
			look_applied.x, look_applied.y, haptics_sent]
