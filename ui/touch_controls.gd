class_name TouchControls
extends Control
## On-screen controls for phones and tablets, part of every HUD (hidden unless
## Settings.touch_controls). Left half: a floating move stick (TouchStick;
## pushed to the rim forwards it sprints). Right half: drag to look. Buttons
## (TouchTuning.buttons) press the same InputMap actions as the keyboard and
## mouse, so the player and weapons need no touch code of their own: holds
## go through Input like a key, and every button press is also sent as an
## InputEventAction so _unhandled_input listeners (weapon swap, pause) see it.
##
## During play a touch must not also click: Godot turns touches into mouse
## events and LMB is fire, so mouse emulation is off while unpaused and back
## on in the pause menu (its buttons are mouse driven).
##
## Debug: `touch on|off`, `touch.show` (lists fingers and the stick vector).

const MOVE_ACTIONS := ["move_left", "move_right", "move_back", "move_forward"]

@export var tuning: TouchTuning = preload("res://data/ui/touch_tuning.tres")

var stick: TouchStick
## Fingers we own: index -> {"kind": "stick"|"look"|"button"|"pause", "spec": TouchButtonSpec}.
var _fingers: Dictionary = {}
## Actions currently held by us (action -> number of fingers or latches).
var _held: Dictionary = {}
## TOGGLE buttons that are latched on (action -> true).
var _latched: Dictionary = {}
var _sprinting := false
var _show_debug := false
var _font: SystemFont


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # we read touches in _input, never as GUI clicks
	stick = TouchStick.new(tuning)
	_font = GrivetStyle.heavy()
	add_to_group("touch_controls")
	Settings.changed.connect(_on_setting_changed)
	Debug.register("touch", _cmd_touch, "touch on|off: show or hide the on-screen controls (saved setting).")
	Debug.register("touch.show", _cmd_show, "touch.show: list the fingers on the on-screen controls.")
	_refresh()


func _exit_tree() -> void:
	release_all()
	Input.emulate_mouse_from_touch = true
	Debug.unregister("touch")
	Debug.unregister("touch.show")


func _notification(what: int) -> void:
	# Phones: the back gesture opens (or closes) the pause menu instead of
	# quitting (application/config/quit_on_go_back is off), and leaving the
	# app pauses so a call or notification doesn't get the player killed.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree():
		_send_action("pause", true)
		_send_action("pause", false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and visible and is_inside_tree() and not get_tree().paused:
		release_all()
		_send_action("pause", true)
		_send_action("pause", false)


func _on_setting_changed(key: String) -> void:
	if key == "touch_controls":
		_refresh()


func _refresh() -> void:
	visible = Settings.touch_enabled()
	if not visible:
		release_all()
		Input.emulate_mouse_from_touch = true


func _process(_delta: float) -> void:
	if not visible:
		return
	var playing := _playing()
	Input.emulate_mouse_from_touch = not playing
	if not playing and not _fingers.is_empty():
		release_all()  # the pause menu or console took over mid-touch
	if _show_debug:
		Debug.watch("touch", "%d fingers, stick %s" % [_fingers.size(), stick.vector])
	queue_redraw()


func _playing() -> bool:
	return not get_tree().paused and not Debug.console_open


# --- Touches ---------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible or not _playing():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_down(touch.index, touch.position)
		else:
			_touch_up(touch.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touch_drag(drag.index, drag.position, drag.relative)
		get_viewport().set_input_as_handled()


func _touch_down(index: int, position: Vector2) -> void:
	if _fingers.has(index):
		_touch_up(index)  # a lost release: start over
	if position.distance_to(pause_centre()) <= tuning.pause_button_radius:
		_fingers[index] = {"kind": "pause"}
		_send_action("pause", true)
		_send_action("pause", false)
		return
	var spec := button_at(position)
	if spec != null:
		_fingers[index] = {"kind": "button", "spec": spec}
		_button_down(spec)
	elif position.x < size.x * 0.5:
		if stick.active:
			_fingers[index] = {"kind": "look"}  # a second left thumb looks
		else:
			_fingers[index] = {"kind": "stick"}
			stick.begin(position)
			_apply_stick()
	else:
		_fingers[index] = {"kind": "look"}


func _touch_drag(index: int, position: Vector2, relative: Vector2) -> void:
	if not _fingers.has(index):
		return
	var finger: Dictionary = _fingers[index]
	match finger.kind:
		"stick":
			stick.drag(position)
			_apply_stick()
		"look":
			_look(relative)
		"button":
			var spec: TouchButtonSpec = finger.spec
			if tuning.fire_button_looks and spec.action == "fire":
				_look(relative)


func _touch_up(index: int) -> void:
	if not _fingers.has(index):
		return
	var finger: Dictionary = _fingers[index]
	_fingers.erase(index)
	match finger.kind:
		"stick":
			stick.end()
			_apply_stick()
		"button":
			_button_up(finger.spec)


## Lets go of everything we hold (pause, focus loss, scene change).
func release_all() -> void:
	for index: int in _fingers.keys():
		_touch_up(index)
	for action: String in _latched.keys():
		_release(action)
	_latched.clear()
	if stick != null:
		stick.end()
	for action: String in MOVE_ACTIONS:
		Input.action_release(action)
	if _sprinting:
		Input.action_release("sprint")
		_sprinting = false


# --- Look ------------------------------------------------------------------------

func _look(relative: Vector2) -> void:
	var holder := get_tree().get_first_node_in_group("player_weapons") as WeaponHolder
	if holder == null or holder.player() == null:
		return
	var player := holder.player()
	var motion := relative.limit_length(tuning.max_drag_per_event)
	var sensitivity := tuning.look_radians_per_pixel * float(Settings.get_value("touch_sensitivity"))
	if player.model != null and player.model.aiming:
		sensitivity *= tuning.ads_multiplier
	player.look(motion, sensitivity)
	# The gun's sway expects mouse pixels: scale ours to the same turn.
	holder.add_look(motion * sensitivity / maxf(player.camera_tuning.mouse_sensitivity, 1e-6))


# --- Move stick ------------------------------------------------------------------

## Pushes the stick into the move actions. Input.get_vector applies the
## actions' own deadzone and rescales; we send the raw length that comes back
## out of that as the stick's (already deadzoned) strength.
func _apply_stick() -> void:
	var move := stick.vector
	var raw := Vector2.ZERO
	if move.length() > 0.0:
		var engine_deadzone := InputMap.action_get_deadzone("move_forward")
		raw = move.normalized() * (engine_deadzone + move.length() * (1.0 - engine_deadzone))
	_axis("move_left", "move_right", raw.x)
	_axis("move_back", "move_forward", raw.y)
	if stick.in_sprint_ring != _sprinting:
		_sprinting = stick.in_sprint_ring
		if _sprinting:
			Input.action_press("sprint")  # entering the ring = pressing sprint
		else:
			Input.action_release("sprint")


func _axis(negative: String, positive: String, value: float) -> void:
	if value > 0.0:
		Input.action_release(negative)
		Input.action_press(positive, value)
	elif value < 0.0:
		Input.action_release(positive)
		Input.action_press(negative, -value)
	else:
		Input.action_release(negative)
		Input.action_release(positive)


# --- Buttons ---------------------------------------------------------------------

func button_centre(spec: TouchButtonSpec) -> Vector2:
	return size + spec.offset


func pause_centre() -> Vector2:
	return Vector2(size.x, 0.0) + tuning.pause_button_offset


## The button under a screen position (the nearest if they overlap), or null.
func button_at(position: Vector2) -> TouchButtonSpec:
	var best: TouchButtonSpec = null
	var best_distance := INF
	for spec: TouchButtonSpec in tuning.buttons:
		var distance := position.distance_to(button_centre(spec))
		if distance <= spec.radius and distance < best_distance:
			best = spec
			best_distance = distance
	return best


func is_held(action: String) -> bool:
	return int(_held.get(action, 0)) > 0


func _button_down(spec: TouchButtonSpec) -> void:
	if spec.mode == TouchButtonSpec.Mode.TOGGLE:
		if _latched.has(spec.action):
			_latched.erase(spec.action)
			_release(spec.action)
		else:
			_latched[spec.action] = true
			_hold(spec.action)
	else:
		_hold(spec.action)


func _button_up(spec: TouchButtonSpec) -> void:
	if spec.mode != TouchButtonSpec.Mode.TOGGLE:
		_release(spec.action)


func _hold(action: String) -> void:
	_held[action] = int(_held.get(action, 0)) + 1
	if _held[action] == 1:
		_send_action(action, true)


func _release(action: String) -> void:
	if not is_held(action):
		return
	_held[action] = int(_held[action]) - 1
	if _held[action] == 0:
		_held.erase(action)
		_send_action(action, false)


## Like a key: updates Input's action state (is_action_pressed and friends)
## and reaches _input / _unhandled_input as an InputEventAction.
func _send_action(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	var idle := Color(GrivetStyle.WHITE, tuning.idle_alpha)
	var lit := Color(GrivetStyle.ORANGE, tuning.pressed_alpha)
	# The stick: its base and the thumb, or a faint ring where it rests.
	var base := stick.base if stick.active else Vector2(0.0, size.y) + tuning.stick_rest
	draw_arc(base, tuning.stick_radius, 0.0, TAU, 48, idle, tuning.ring_width, true)
	if stick.active:
		var ring := tuning.stick_radius * tuning.sprint_ring
		draw_arc(base, ring, -PI * 0.5 - 0.6, -PI * 0.5 + 0.6, 16,
				lit if stick.in_sprint_ring else Color(idle, idle.a * 0.6), tuning.ring_width * 2.0, true)
		var knob := base + (stick.thumb - base).limit_length(tuning.stick_radius)
		draw_circle(knob, tuning.stick_radius * 0.38, Color(GrivetStyle.WHITE, tuning.pressed_alpha * 0.6))
	for spec: TouchButtonSpec in tuning.buttons:
		var on := is_held(spec.action)
		var centre := button_centre(spec)
		draw_circle(centre, spec.radius, Color(GrivetStyle.INK, (tuning.pressed_alpha if on else tuning.idle_alpha) * 0.5))
		draw_arc(centre, spec.radius, 0.0, TAU, 40, lit if on else idle, tuning.ring_width, true)
		_draw_label(centre, spec.label, lit if on else Color(GrivetStyle.WHITE, tuning.pressed_alpha))
	var pause := pause_centre()
	draw_circle(pause, tuning.pause_button_radius, Color(GrivetStyle.INK, tuning.idle_alpha * 0.5))
	draw_arc(pause, tuning.pause_button_radius, 0.0, TAU, 32, idle, tuning.ring_width, true)
	var bar := Vector2(tuning.pause_button_radius * 0.18, tuning.pause_button_radius * 0.9)
	for side: float in [-1.0, 1.0]:
		draw_rect(Rect2(pause + Vector2(side * bar.x * 1.4 - bar.x * 0.5, -bar.y * 0.5), bar),
				Color(GrivetStyle.WHITE, tuning.pressed_alpha))


func _draw_label(centre: Vector2, text: String, color: Color) -> void:
	var font_size := tuning.label_size
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := centre + Vector2(-width * 0.5, font_size * 0.35)
	draw_string_outline(_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, GrivetStyle.INK)
	draw_string(_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# --- Debug -----------------------------------------------------------------------

func _cmd_touch(args: PackedStringArray) -> String:
	if args.is_empty() or not args[0] in ["on", "off"]:
		return "usage: touch on|off (now %s)" % ("on" if visible else "off")
	Settings.set_value("touch_controls", args[0] == "on")
	return "touch controls %s" % args[0]


func _cmd_show(_args: PackedStringArray) -> String:
	_show_debug = not _show_debug
	Debug.show_watches = _show_debug or Debug.show_watches
	return "touch watch %s" % ("on" if _show_debug else "off")
