extends Node
## Headless traversal probe for the Milestone 1 exit check. Loads the greybox
## course, drives the player with real input actions and checks where it
## ends up. Exit code 0 = every route passed. Runs as a scene (not -s) so
## autoloads such as Debug exist, exactly as in the game.
##
##   $GODOT --headless --path . res://tests/probes/movement_course.tscn

const COURSE := "res://levels/greybox/movement_course.tscn"
const PHYSICS_HZ := 120
## A script error inside a route kills the coroutine; never hang CI on it.
const WATCHDOG_SECONDS := 120.0

var player: Player
var failures := 0
var _seen_gaits := {}


func _ready() -> void:
	var course: Node = load(COURSE).instantiate()
	add_child(course)
	player = course.get_node("Player")
	get_tree().create_timer(WATCHDOG_SECONDS).timeout.connect(func() -> void:
		printerr("FAIL watchdog: probe did not finish in %d s" % WATCHDOG_SECONDS)
		get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	await get_tree().physics_frame
	await _route("stairs up to 1.2 m landing", Vector3(-14, 0, -2), func() -> String:
		await _hold(["move_forward"], 1.3)
		return _expect(player.global_position.y > 1.15, "y=%.2f" % player.global_position.y))

	await _route("walk over 0.15 m and 0.3 m curbs", Vector3(-2, 0, -2), func() -> String:
		await _hold(["move_forward"], 1.5)
		return _expect(player.global_position.z < -6.5, "z=%.2f" % player.global_position.z))

	for crate in [[-10.0, 1.0], [-16.0, 1.4], [-22.0, 1.8]]:
		await _route("mantle %.1f m crate" % crate[1], Vector3(-8, 0, crate[0]), func() -> String:
			await _hold(["move_forward"], 0.8)  # walk up to the face
			await _tap("jump", ["move_forward"])
			await _hold([], 0.6)  # finish the climb and stay on top
			var y := player.global_position.y
			return _expect(absf(y - crate[1]) < 0.1 and _seen_gaits.has(MovementModel.Gait.MANTLE),
					"y=%.2f gaits: %s" % [y, _gait_names()]))

	# Jump + grab reaches jump height + mantle_max_height (~2.65 m), so the
	# unclimbable wall is 3 m.
	await _route("cannot mantle 3.0 m wall even with jump-grab", Vector3(-8, 0, -28), func() -> String:
		await _hold(["move_forward"], 0.8)
		await _tap("jump", ["move_forward"])
		await _hold(["move_forward", "jump"], 1.2)
		return _expect(player.global_position.y < 0.1 and not _seen_gaits.has(MovementModel.Gait.MANTLE),
				"y=%.2f gaits: %s" % [player.global_position.y, _gait_names()]))

	await _route("crouch through 1.35 m tunnel", Vector3(-2, 0, -10.5), func() -> String:
		await _tap("crouch")
		await _hold(["move_forward"], 3.5)
		return _expect(player.global_position.z < -16.5, "z=%.2f" % player.global_position.z))

	await _route("stand blocked inside tunnel", Vector3(-2, 0, -10.5), func() -> String:
		await _tap("crouch")
		await _hold(["move_forward"], 1.2)
		await _tap("crouch")
		await _hold([], 0.2)
		return _expect(player.model.stance == MovementModel.Stance.CROUCH, _stance()))

	await _route("prone under 0.8 m crawl gap", Vector3(-2, 0, -21.3), func() -> String:
		await _tap("prone")
		await _hold(["move_forward"], 6.5)
		return _expect(player.global_position.z < -25.7, "z=%.2f" % player.global_position.z))

	await _route("sprint, tactical sprint, slide", Vector3(-2, 0, 4), func() -> String:
		await _tap("sprint", ["move_forward"])
		await _hold(["move_forward"], 0.6)
		await _tap("sprint", ["move_forward"])
		await _hold(["move_forward"], 0.4)
		await _tap("crouch", ["move_forward"])
		await _hold(["move_forward"], 0.3)
		var ok := _seen_gaits.has(MovementModel.Gait.TAC_SPRINT) and _seen_gaits.has(MovementModel.Gait.SLIDE)
		return _expect(ok, "gaits seen: %s" % _gait_names()))

	await _route("crate then container roof", Vector3(14, 0, -2.5), func() -> String:
		await _hold(["move_forward"], 0.5)
		await _tap("jump", ["move_forward"])
		await _hold(["move_forward"], 0.8)
		await _tap("jump", ["move_forward"])
		await _hold(["move_forward"], 0.8)
		var y := player.global_position.y
		return _expect(absf(y - 2.6) < 0.1, "y=%.2f" % y))

	await _route("walk up 20 degree ramp", Vector3(21, 0, -2.5), func() -> String:
		await _hold(["move_forward"], 2.5)
		return _expect(player.global_position.y > 2.0, "y=%.2f" % player.global_position.y))

	await _route("hard landing from 4 m tower", Vector3(-19, 4.05, -13), func() -> String:
		await _hold(["move_forward"], 1.5)
		return _expect(player.global_position.y < 0.05 and player.is_on_floor(),
				"y=%.2f grounded=%s" % [player.global_position.y, player.is_on_floor()]))

	print("\n%s: %d route(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)


func _route(title: String, start: Vector3, body: Callable) -> void:
	_reset_player(start)
	await _hold([], 0.3)  # settle onto the floor
	var detail: String = await body.call()
	_release_all()
	if detail.is_empty():
		print("PASS %s" % title)
	else:
		failures += 1
		printerr("FAIL %s - %s" % [title, detail])


func _reset_player(start: Vector3) -> void:
	_release_all()
	player.model = MovementModel.new(player.tuning)
	player.global_position = start
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	_seen_gaits.clear()


## Holds the given actions for `seconds` of physics time.
func _hold(actions: Array, seconds: float) -> void:
	for action: String in actions:
		Input.action_press(action)
	for i in roundi(seconds * PHYSICS_HZ):
		await get_tree().physics_frame
		_seen_gaits[player.model.gait] = true
		if OS.has_environment("PROBE_TRACE"):
			print("  %s y=%.2f z=%.2f floor=%s" % [MovementModel.Gait.keys()[player.model.gait],
					player.global_position.y, player.global_position.z, player.is_on_floor()])
	for action: String in actions:
		Input.action_release(action)


## Presses an action for exactly one physics tick while holding `also`.
func _tap(action: String, also: Array = []) -> void:
	for other: String in also:
		Input.action_press(other)
	await get_tree().physics_frame
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)
	for other: String in also:
		Input.action_release(other)


func _release_all() -> void:
	for action: String in InputMap.get_actions():
		Input.action_release(action)


func _expect(condition: bool, detail: String) -> String:
	return "" if condition else detail


func _stance() -> String:
	return "stance=%s" % MovementModel.Stance.keys()[player.model.stance]


func _gait_names() -> String:
	var names := PackedStringArray()
	for gait: int in _seen_gaits:
		names.append(MovementModel.Gait.keys()[gait])
	return ", ".join(names)
