extends Node
## Renders a level on the real GPU for a few seconds, reports the average and
## worst frame time, and saves a screenshot. Not headless.
##
##   $GODOT --path . res://tests/probes/frame_capture.tscn -- [shot=<abs path.png>] [scene=res://...] [fire] [aim] [weapon=<id>] [hide_gun] [cmd=<console_command>]...
##   (cmd= runs a console command at start; underscores stand for spaces, e.g. cmd=god cmd=ai.show)
##
## Every option is named (positional arguments shift silently when a shell
## drops an empty one, which once overwrote a scene with a PNG). Defaults to
## the main scene and no screenshot. `fire` holds the trigger with infinite
## ammo (worst case: flash, tracers, impacts); `aim` holds ADS; `hide_gun`
## hides the view model to isolate its cost. Screenshots are refused inside
## the project (res:// or a relative path).

const WARMUP_FRAMES := 60
const MAX_WARMUP_FRAMES := 1200
const MEASURE_FRAMES := 480


## Swallows every real input event. The capture window can take focus while
## someone is using the PC; their clicks and scrolls must not fire or switch
## weapons mid-measurement. Added last to the root so it sees events first.
class InputSink:
	extends Node

	func _input(_event: InputEvent) -> void:
		get_viewport().set_input_as_handled()


var _frame := 0
var _times: PackedFloat32Array = []
var _screenshot := ""
var _fire := false
var _weapon := ""
var _hide_gun := false
var _commands := PackedStringArray()
var _measure_from := -1


func _ready() -> void:
	# Polled actions (fire, aim) read the Input singleton, which events update
	# before any node can swallow them, so unbind real devices entirely; the
	# probe drives actions with Input.action_press instead.
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
	get_tree().root.add_child.call_deferred(InputSink.new())
	var scene_path: String = ProjectSettings.get_setting("application/run/main_scene")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shot="):
			_screenshot = arg.trim_prefix("shot=")
			if not (_screenshot.is_absolute_path() and not _screenshot.begins_with("res://")
					and _screenshot.get_extension() == "png"):
				printerr("refusing screenshot path %s: give an absolute .png path outside the project" % _screenshot)
				get_tree().quit(2)
				return
		elif arg.begins_with("scene="):
			scene_path = arg.trim_prefix("scene=")
		elif arg == "fire":
			_fire = true
		elif arg == "aim":
			Input.action_press("aim")
		elif arg.begins_with("weapon="):
			_weapon = arg.trim_prefix("weapon=")
		elif arg == "hide_gun":
			_hide_gun = true
		elif arg.begins_with("cmd="):
			_commands.append(arg.trim_prefix("cmd=").replace("_", " "))
		else:
			printerr("unknown option %s" % arg)
			get_tree().quit(2)
			return
	add_child(load(scene_path).instantiate())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	_frame += 1
	if _frame == 2 and not _weapon.is_empty():
		Debug.execute("give " + _weapon)
	if _frame == 2:
		for command in _commands:
			Debug.execute(command)
	if _frame == 2 and _hide_gun:
		var holder := get_tree().get_first_node_in_group("player_weapons") as Node3D
		if holder != null:
			holder.visible = false
	# Measure steady-state play: wait out the startup sound build on the worker
	# thread too (it competes for the CPU for a few seconds after launch).
	if _measure_from < 0:
		if _frame >= WARMUP_FRAMES and (Ballistics.effects().sounds_ready() or _frame >= MAX_WARMUP_FRAMES):
			_measure_from = _frame
			if _fire:
				Debug.execute("ammo.infinite")
				Input.action_press("fire")
		return
	_times.append(delta)
	if _times.size() < MEASURE_FRAMES:
		return
	var total := 0.0
	var worst := 0.0
	for t in _times:
		total += t
		worst = maxf(worst, t)
	var average := total / _times.size()
	print("frames=%d avg=%.2f ms (%.0f fps) worst=%.2f ms bullets_in_flight=%d draw_calls=%d objects=%d primitives=%d" % [
			_times.size(), average * 1000.0, 1.0 / average, worst * 1000.0, Ballistics.active_bullets(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	if not _screenshot.is_empty():
		get_viewport().get_texture().get_image().save_png(_screenshot)
		print("screenshot: %s" % _screenshot)
	Input.action_release("fire")
	Input.action_release("aim")
	get_tree().quit()
