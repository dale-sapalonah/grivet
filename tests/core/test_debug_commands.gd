extends "res://tests/framework/suite.gd"

const Registry := preload("res://core/debug_commands.gd")


func test_registered_command_receives_args() -> void:
	var registry := Registry.new()
	registry.register("echo", func(args: PackedStringArray): return " ".join(args))
	assert_eq(registry.execute("echo hello world"), "hello world")
	registry.free()


func test_unknown_command_reports_error() -> void:
	var registry := Registry.new()
	assert_eq(registry.execute("nope"), "Unknown command: nope")
	registry.free()


func test_help_lists_commands() -> void:
	var registry := Registry.new()
	registry.register("god", func(_args): return null, "Toggle invulnerability.")
	var help := registry.execute("help")
	assert_true(help.contains("god - Toggle invulnerability."), "help missing god: " + help)
	registry.free()
