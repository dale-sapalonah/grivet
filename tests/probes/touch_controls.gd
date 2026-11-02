extends Node
## Touch controls probe: loads the firing range with the on-screen controls
## on (not saved) and plays it with synthetic screen touches the way a phone
## sends them: the move stick walks and sprints, a right-half drag looks, FIRE
## shoots (and steers while held), AIM latches, SWAP changes weapon, and the
## pause button pauses with mouse emulation back on for the menu.
## Exit 0 = pass.
##
##   $GODOT --headless --path . res://tests/probes/touch_controls.tscn

const RANGE := "res://levels/greybox/firing_range.tscn"

var level: Node
var player: Player
var holder: WeaponHolder
var touch: TouchControls
var failures := 0
var _was_on := false
var _last: Dictionary = {}  # finger -> last position


func _ready() -> void:
	_was_on = bool(Settings.get_value("touch_controls"))
	Settings.values["touch_controls"] = true  # in memory only: never saved by the probe
	level = load(RANGE).instantiate()
	add_child(level)
	player = level.get_node("Player")
	holder = player.get_node("Head/CameraRig/Camera3D/WeaponHolder")
	touch = get_tree().get_first_node_in_group("touch_controls") as TouchControls
	get_tree().create_timer(60.0, true).timeout.connect(func() -> void:
		printerr("FAIL watchdog")
		get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	await _frames(10)
	if touch != null and touch.size.x < 1000.0:
		# Headless windows are 64x64 (--resolution is ignored), where every
		# button overlaps: lay the controls out on the 1600x900 canvas.
		touch.set_anchors_preset(Control.PRESET_TOP_LEFT)
		touch.size = Vector2(1600, 900)
		await _frames(2)
	_check("controls show", touch != null and touch.visible, "TouchControls missing or hidden")
	if touch == null:
		_finish()
		return
	_check("touches are not mouse clicks in play", not Input.emulate_mouse_from_touch, "mouse emulation still on")
	holder.current_weapon().infinite_ammo = true

	# Stick: thumb down on the left, pushed half way up -> walk forwards.
	var start := player.global_position
	var forward := -player.global_basis.z
	var thumb := Vector2(touch.size.x * 0.2, touch.size.y * 0.7)
	_touch(0, thumb, true)
	await _frames(2)
	_drag(0, thumb + Vector2(0, -touch.tuning.stick_radius * 0.5))
	await _seconds(0.6)
	var walked := (player.global_position - start).dot(forward)
	_check("half stick walks forwards", walked > 0.5, "moved %.2f m" % walked)
	_check("half stick does not sprint", not player.model.is_sprinting(), "sprinting")
	_drag(0, thumb + Vector2(0, -touch.tuning.stick_radius * 1.2))
	await _seconds(0.4)
	_check("full forward sprints", player.model.is_sprinting(), "not sprinting at the rim")
	_touch(0, thumb, false)
	await _seconds(0.6)
	_check("letting go stops", Vector2(player.velocity.x, player.velocity.z).length() < 0.5,
			"still moving %.2f m/s" % player.velocity.length())

	# Look: drag on the right half (away from the buttons).
	var yaw := player.rotation.y
	var spot := Vector2(touch.size.x * 0.62, touch.size.y * 0.25)
	_check("look spot is not a button", touch.button_at(spot) == null, "a button sits there")
	_touch(1, spot, true)
	await _frames(2)
	_drag(1, spot + Vector2(100, 0))
	await _frames(2)
	_touch(1, spot + Vector2(100, 0), false)
	await _frames(2)
	var expected := -100.0 * touch.tuning.look_radians_per_pixel * float(Settings.get_value("touch_sensitivity"))
	_check("right-half drag turns right", absf(angle_difference(yaw, player.rotation.y) - expected) < 0.01,
			"yaw moved %.4f, expected %.4f" % [angle_difference(yaw, player.rotation.y), expected])

	# Fire: hold the button, drag it a little to steer.
	var fire := _button("fire")
	var shots := [0]
	holder.shot_fired.connect(func(_weapon: WeaponDefinition) -> void: shots[0] += 1)
	yaw = player.rotation.y
	_touch(2, touch.button_centre(fire), true)
	await _seconds(0.4)
	_drag(2, touch.button_centre(fire) + Vector2(-40, 0))
	await _seconds(0.2)
	_check("FIRE held shoots", shots[0] >= 2, "%d shots" % shots[0])
	_check("FIRE drag steers", angle_difference(yaw, player.rotation.y) > 0.05, "yaw moved %.4f" % angle_difference(yaw, player.rotation.y))
	_touch(2, touch.button_centre(fire), false)
	await _frames(3)
	_check("FIRE lifted stops", not Input.is_action_pressed("fire"), "fire still pressed")

	# Aim latches on a tap and lets go on the next.
	var aim := _button("aim")
	await _tap(3, touch.button_centre(aim))
	await _seconds(0.1)
	_check("AIM tap aims", player.model.aiming, "not aiming")
	await _tap(3, touch.button_centre(aim))
	await _seconds(0.1)
	_check("second AIM tap stops aiming", not player.model.aiming, "still aiming")

	# Swap goes through _unhandled_input (next_weapon).
	var slot := holder.current
	await _tap(4, touch.button_centre(_button("next_weapon")))
	await _frames(3)
	_check("SWAP changes weapon", holder.current != slot, "still slot %d" % slot)

	# Pause: the menu takes over and touches click again.
	await _tap(5, touch.pause_centre())
	await _frames(3)
	_check("pause button pauses", get_tree().paused, "not paused")
	_check("menu gets mouse emulation", Input.emulate_mouse_from_touch, "emulation still off while paused")
	get_tree().paused = false
	_finish()


func _finish() -> void:
	Settings.values["touch_controls"] = _was_on
	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)


func _button(action: String) -> TouchButtonSpec:
	for spec: TouchButtonSpec in touch.tuning.buttons:
		if spec.action == action:
			return spec
	push_error("no %s button" % action)
	return null


func _touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	_last[index] = position
	Input.parse_input_event(event)


func _drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = position - _last.get(index, position)
	_last[index] = position
	Input.parse_input_event(event)


func _tap(index: int, position: Vector2) -> void:
	_touch(index, position, true)
	await _frames(3)
	_touch(index, position, false)
	await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s" % what)
	else:
		failures += 1
		print("FAIL %s - %s" % [what, detail])
