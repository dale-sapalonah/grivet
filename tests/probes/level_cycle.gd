extends Node
## Windowed crash probe for real-session paths the other probes skip: fight in
## a level (firing, enemies firing back, casings, impacts), then free it
## mid-fight and load the next, as the `map` command does, and quit at the end.
## Exit code 0 and no crash = pass; a native crash shows as a non-zero exit.
##
##   $GODOT --path . res://tests/probes/level_cycle.tscn

const LEVELS := ["res://levels/port/port_yard.tscn", "res://levels/greybox/arena.tscn",
		"res://levels/port/port_yard.tscn"]
const SECONDS_PER_LEVEL := 6.0

var _level: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for path: String in LEVELS:
		if _level != null:
			Input.action_release("fire")
			_level.queue_free()
			await get_tree().process_frame
		_level = load(path).instantiate()
		add_child(_level)
		print("loaded %s" % path)
		await get_tree().create_timer(1.0).timeout
		Debug.execute("god")
		Debug.execute("ammo.infinite")
		Input.action_press("fire")
		await get_tree().create_timer(SECONDS_PER_LEVEL).timeout
	Input.action_release("fire")
	print("PASS: cycled %d levels" % LEVELS.size())
	get_tree().quit(0)
