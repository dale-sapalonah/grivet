extends CanvasLayer
## FPS counter, optional watch readout and the ` (backtick) console that
## runs commands registered on the Debug autoload.

var _mouse_mode_before := Input.MOUSE_MODE_CAPTURED

@onready var _stats: Label = $Stats
@onready var _console: Control = $Console
@onready var _log: RichTextLabel = $Console/Layout/Log
@onready var _command_line: LineEdit = $Console/Layout/Input


func _ready() -> void:
	_console.hide()
	_command_line.text_submitted.connect(_on_submitted)
	_log.add_text("Type 'help' for commands.\n")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_console"):
		_set_console_open(not Debug.console_open)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var lines := PackedStringArray(["FPS %d" % Engine.get_frames_per_second()])
	if Debug.show_watches:
		for key: String in Debug.watches:
			lines.append("%s: %s" % [key, Debug.watches[key]])
	_stats.text = "\n".join(lines)


func _set_console_open(open: bool) -> void:
	Debug.console_open = open
	_console.visible = open
	if open:
		_mouse_mode_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_command_line.clear()
		_command_line.grab_focus()
	else:
		_command_line.release_focus()
		Input.mouse_mode = _mouse_mode_before


func _on_submitted(text: String) -> void:
	_command_line.clear()
	if text.strip_edges().is_empty():
		return
	_log.add_text("> %s\n" % text)
	var output := Debug.execute(text)
	if not output.is_empty():
		_log.add_text(output + "\n")
