class_name DebugCommandRegistry
extends Node
## Console command registry. Every system registers its debug commands here
## (god, give, spawn, ai.show, ...). Autoloaded as `Debug`.
##
## A command is a Callable taking the argument list (PackedStringArray) and
## returning a String to print, or null for no output.

## True while the in-game console has focus; gameplay ignores input then.
var console_open := false
## When true the debug overlay lists every watch below the FPS counter.
var show_watches := false
## Live values systems publish for the overlay (key -> value).
var watches: Dictionary = {}

var _commands: Dictionary = {}  # name -> {"callable": Callable, "help": String}


func _init() -> void:
	register("help", _cmd_help, "List all commands.")


func register(command: String, callable: Callable, help: String = "") -> void:
	_commands[command] = {"callable": callable, "help": help}


func unregister(command: String) -> void:
	_commands.erase(command)


func has_command(command: String) -> bool:
	return _commands.has(command)


func execute(line: String) -> String:
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	var command := parts[0]
	if not _commands.has(command):
		return "Unknown command: %s" % command
	var result: Variant = _commands[command].callable.call(parts.slice(1))
	return "" if result == null else str(result)


func watch(key: String, value: Variant) -> void:
	watches[key] = value


func _cmd_help(_args: PackedStringArray) -> String:
	var names := _commands.keys()
	names.sort()
	var lines := PackedStringArray()
	for command in names:
		lines.append("%s - %s" % [command, _commands[command].help])
	return "\n".join(lines)
