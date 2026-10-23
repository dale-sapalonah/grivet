extends Node
## Default bindings, registered at startup so project.godot stays free of
## serialized InputEvents. Physical keycodes keep WASD in place on any layout.
## A rebinding menu comes with the settings screen (Milestone 6).

const KEYS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_C, KEY_CTRL],
	"prone": [KEY_Z],
	"lean_left": [KEY_Q],
	"lean_right": [KEY_E],
	"pause": [KEY_ESCAPE],
	"toggle_console": [KEY_QUOTELEFT],
}
const MOUSE_BUTTONS := {
	"aim": [MOUSE_BUTTON_RIGHT],
	"fire": [MOUSE_BUTTON_LEFT],
}


func _enter_tree() -> void:
	for action: String in KEYS:
		_ensure_action(action)
		for keycode: Key in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
	for action: String in MOUSE_BUTTONS:
		_ensure_action(action)
		for button: MouseButton in MOUSE_BUTTONS[action]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)


func _ensure_action(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)
