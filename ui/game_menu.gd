class_name GameMenu
extends Control
## Grivet's menus, built in code. TITLE mode is the start screen: six
## illustrated character panels (CharacterPanel) in a grid with black gutters,
## the GRIVET logo over them and the menu beneath. PAUSE mode sits over the
## game, opened with Esc, and freezes the tree. Both share the settings page,
## which edits the Settings autoload.

enum Mode { TITLE, PAUSE }

const GAME_SCENE := "res://levels/port/port_yard.tscn"
const GUTTER := 8.0

## [key, label, min, max, step] sliders and [key, label] toggles on the settings page.
const SLIDERS := [["master_volume", "MASTER VOLUME", 0.0, 1.0, 0.05], ["music_volume", "MUSIC VOLUME", 0.0, 1.0, 0.05],
		["sfx_volume", "SOUND EFFECTS VOLUME", 0.0, 1.0, 0.05], ["mouse_sensitivity", "MOUSE SENSITIVITY", 0.25, 3.0, 0.05],
		["fov", "FIELD OF VIEW", 55.0, 95.0, 1.0], ["render_scale", "RENDER SCALE (SHARPER = SLOWER)", 0.5, 1.0, 0.05]]
const TOGGLES := [["music_on", "MUSIC"], ["sfx_on", "SOUND EFFECTS"], ["invert_y", "INVERT MOUSE Y"],
		["fullscreen", "FULLSCREEN"], ["show_fps", "SHOW FPS"]]
## The title art: [subject, backdrop, variant] left to right, top to bottom.
const PANELS := [[CharacterPanel.Subject.RIFLE_AIM, Color(0.95, 0.5, 0.12), 0],
		[CharacterPanel.Subject.TAXI, Color(0.95, 0.78, 0.15), 0],
		[CharacterPanel.Subject.SHOTGUN, Color(0.1, 0.55, 0.55), 0],
		[CharacterPanel.Subject.MACHETE_SWING, Color(0.5, 0.25, 0.65), 1],
		[CharacterPanel.Subject.MACHETE_CLOSE, Color(0.8, 0.15, 0.1), 3],
		[CharacterPanel.Subject.RIFLE_FIRE, Color(0.15, 0.32, 0.7), 0]]

@export var mode: Mode = Mode.TITLE

var _heavy: SystemFont
var _script: SystemFont
var _pages: Dictionary = {}  # name -> Control
var _campaign: Campaign = preload("res://data/levels/campaign.tres")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_heavy = GrivetStyle.heavy()
	_script = GrivetStyle.script()
	if mode == Mode.TITLE:
		_build_art()
		_build_logo()
	_build_pages()
	if mode == Mode.TITLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		MusicPlayer.play_set("menu")
		_show("main")
	else:
		visible = false


func _input(event: InputEvent) -> void:
	if mode != Mode.PAUSE or not event.is_action_pressed("pause") or Debug.console_open:
		return
	get_viewport().set_input_as_handled()
	if visible:
		_resume()
	else:
		_pause()


func _draw() -> void:
	if mode == Mode.PAUSE:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.7))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), GrivetStyle.INK)  # the gutters


# --- Art -----------------------------------------------------------------------------

func _build_art() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.offset_left = GUTTER
	grid.offset_top = GUTTER
	grid.offset_right = -GUTTER
	grid.offset_bottom = -GUTTER
	grid.add_theme_constant_override("h_separation", int(GUTTER))
	grid.add_theme_constant_override("v_separation", int(GUTTER))
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grid)
	for entry: Array in PANELS:
		var panel := CharacterPanel.new()
		panel.subject = entry[0]
		panel.backdrop = entry[1]
		panel.variant = entry[2]
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(panel)


## The logo: a black strip, the name in fat outlined capitals, the city in
## brush script slanting across underneath.
func _build_logo() -> void:
	var logo := VBoxContainer.new()
	logo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	logo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	logo.offset_top = 60.0
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	logo.add_theme_constant_override("separation", -34)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	var strip := PanelContainer.new()
	var strip_box := StyleBoxFlat.new()
	strip_box.bg_color = GrivetStyle.INK
	strip_box.content_margin_left = 18
	strip_box.content_margin_right = 18
	strip.add_theme_stylebox_override("panel", strip_box)
	strip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	strip.add_child(GrivetStyle.label("PAPUA NEW GUINEA", _heavy, 30, GrivetStyle.WHITE, 0))
	logo.add_child(strip)
	logo.add_child(GrivetStyle.label("GRIVET", _heavy, 210, GrivetStyle.WHITE, 30))
	var city := GrivetStyle.label("Port Moresby", _script, 84, GrivetStyle.ORANGE, 14)
	city.rotation_degrees = -5.0
	city.pivot_offset = Vector2(260, 50)
	logo.add_child(city)


# --- Pages ------------------------------------------------------------------------

func _build_pages() -> void:
	var main := _page("main", mode == Mode.PAUSE)
	if mode == Mode.TITLE:
		main.add_child(_item("START GAME", func() -> void: _start(0)))
		main.add_child(_item("STAGES", func() -> void: _show("stages")))
	else:
		main.add_child(GrivetStyle.label("PAUSED", _heavy, 120, GrivetStyle.WHITE, 18))
		main.add_child(_item("RESUME", _resume))
	main.add_child(_item("SETTINGS", func() -> void: _show("settings")))
	if mode == Mode.PAUSE:
		main.add_child(_item("MAIN MENU", _to_title))
	main.add_child(_item("QUIT", func() -> void: get_tree().quit()))

	var stages := _page("stages", true)
	stages.add_child(GrivetStyle.label("STAGES", _heavy, 90, GrivetStyle.WHITE, 14))
	for i in _campaign.stages.size():
		var stage := _campaign.stages[i]
		stages.add_child(_item("%d. %s" % [i + 1, stage.title], func() -> void: _start(i), stage.subtitle))
	stages.add_child(_item("BACK", func() -> void: _show("main")))

	var settings := _page("settings", true)
	settings.add_child(GrivetStyle.label("SETTINGS", _heavy, 90, GrivetStyle.WHITE, 14))
	for toggle: Array in TOGGLES:
		var box := CheckBox.new()
		box.text = toggle[1]
		box.button_pressed = bool(Settings.get_value(toggle[0]))
		var key: String = toggle[0]
		box.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
		GrivetStyle.style(box, _heavy, 28, GrivetStyle.WHITE, 6)
		box.add_theme_color_override("font_hover_color", GrivetStyle.ORANGE)
		box.add_theme_color_override("font_pressed_color", GrivetStyle.WHITE)
		settings.add_child(box)
	for slider: Array in SLIDERS:
		settings.add_child(_slider(slider[0], slider[1], slider[2], slider[3], slider[4]))
	var graphics := OptionButton.new()
	for label in ["GRAPHICS: PERFORMANCE", "GRAPHICS: BALANCED", "GRAPHICS: HIGH (SLOW ON THIS PC)"]:
		graphics.add_item(label)
	graphics.selected = int(Settings.get_value("graphics"))
	graphics.item_selected.connect(func(index: int) -> void: Settings.set_value("graphics", index))
	GrivetStyle.style(graphics, _heavy, 26, GrivetStyle.WHITE, 6)
	settings.add_child(graphics)
	var shadows := OptionButton.new()
	for label in ["SHADOWS: OFF", "SHADOWS: LOW", "SHADOWS: MEDIUM"]:
		shadows.add_item(label)
	shadows.selected = int(Settings.get_value("shadows"))
	shadows.item_selected.connect(func(index: int) -> void: Settings.set_value("shadows", index))
	GrivetStyle.style(shadows, _heavy, 26, GrivetStyle.WHITE, 6)
	settings.add_child(shadows)
	settings.add_child(_item("BACK", func() -> void: _show("main")))


## A page: a centred column; `backed` pages sit on a dark panel over the art.
func _page(page_name: String, backed: bool) -> Control:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	var holder: Control = column
	if backed:
		var panel := PanelContainer.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.0, 0.0, 0.0, 0.78)
		box.border_color = GrivetStyle.ORANGE
		box.set_border_width_all(3)
		box.set_content_margin_all(26)
		panel.add_theme_stylebox_override("panel", box)
		panel.add_child(column)
		holder = panel
	var bottom := mode == Mode.TITLE and not backed
	holder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM if bottom else Control.PRESET_CENTER)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_BOTH
	if bottom:
		holder.offset_bottom = -40.0
	holder.visible = false
	add_child(holder)
	_pages[page_name] = holder
	return column


func _show(page_name: String) -> void:
	for key: String in _pages:
		_pages[key].visible = key == page_name


## A menu line: outlined capitals that turn orange under the mouse, with an
## optional small line beneath.
func _item(text: String, action: Callable, hint: String = "") -> Button:
	var button := Button.new()
	button.text = text if hint == "" else "%s\n%s" % [text, hint]
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	GrivetStyle.style(button, _heavy, 46 if hint == "" else 30, GrivetStyle.WHITE, 9)
	for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, GrivetStyle.ORANGE)
	return button


func _slider(key: String, label_text: String, low: float, high: float, step: float) -> Control:
	var row := VBoxContainer.new()
	var label := GrivetStyle.label("", _heavy, 24, GrivetStyle.WHITE, 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = float(Settings.get_value(key))
	slider.custom_minimum_size = Vector2(520, 22)
	var percent := high <= 1.0 and low >= 0.0 and step < 1.0 and key.ends_with("volume")
	var show_value := func(value: float) -> void:
		var shown := ("%d%%" % roundi(value * 100.0)) if percent else (("%.0f" % value) if step >= 1.0 else ("%.2f" % value))
		label.text = "%s  %s" % [label_text, shown]
	show_value.call(slider.value)
	slider.value_changed.connect(func(value: float) -> void:
		show_value.call(value)
		Settings.set_value(key, value))
	row.add_child(label)
	row.add_child(slider)
	return row


# --- Actions ---------------------------------------------------------------------

func _start(stage: int) -> void:
	Settings.requested_stage = stage
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func _pause() -> void:
	visible = true
	_show("main")
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	queue_redraw()


func _resume() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
