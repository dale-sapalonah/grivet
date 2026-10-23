extends Node3D
## Firing range level: registers range-only debug commands.


func _ready() -> void:
	Debug.register("targets.reset", _cmd_reset, "Clear hit counts on every range target.")


func _exit_tree() -> void:
	Debug.unregister("targets.reset")


func _cmd_reset(_args: PackedStringArray) -> String:
	var targets := get_tree().get_nodes_in_group("targets")
	for target: TargetDummy in targets:
		target.reset()
	return "reset %d targets" % targets.size()
