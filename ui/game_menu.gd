class_name GameMenu
extends Control
## Grivet's menus, built in code. TITLE mode is the start screen, a
## crime-sandbox box-art collage (original: no borrowed logo, font or art):
## a Port Moresby sunset drawn behind everything (sky, sun, hills, a few
## towers, the harbour, palm silhouettes), the two officers in front of a
## Kamfot taxi cut out in the middle, four tilted white-framed comic panels
## of the gangs and the city at the sides, the GRIVET / PORT MORESBY logo
## over the top and the menu in a bar along the bottom. PAUSE mode sits over the
## game, opened with Esc, and freezes the tree. Both share the settings page,
## which edits the Settings autoload.

enum Mode { TITLE, PAUSE }

## The maps: [name, scene, campaign]. Each map's campaign is its stages.
const MAPS := [["PORT YARD", "res://levels/port/port_yard.tscn", preload("res://data/levels/campaign.tres")],
		["GORDONS MARKET", "res://levels/gordons/gordons_market.tscn", preload("res://data/levels/gordons_campaign.tres")]]
const LOGO_SHADER := preload("res://ui/logo_gradient.gdshader")

## [key, label, min, max, step] sliders and [key, label] toggles on the settings page.
const SLIDERS := [["master_volume", "MASTER VOLUME", 0.0, 1.0, 0.05], ["music_volume", "MUSIC VOLUME", 0.0, 1.0, 0.05],
		["sfx_volume", "SOUND EFFECTS VOLUME", 0.0, 1.0, 0.05], ["mouse_sensitivity", "MOUSE SENSITIVITY", 0.25, 3.0, 0.05],
		["fov", "FIELD OF VIEW", 55.0, 95.0, 1.0], ["render_scale", "RENDER SCALE (SHARPER = SLOWER)", 0.5, 1.0, 0.05]]
const TOGGLES := [["music_on", "MUSIC"], ["sfx_on", "SOUND EFFECTS"], ["voices_on", "ENEMY VOICES (SHOUTS, CRIES)"], ["invert_y", "INVERT MOUSE Y"],
		["fullscreen", "FULLSCREEN"], ["show_fps", "SHOW FPS"]]
## The side panels: [subject, backdrop, variant, rect (fractions of the
## screen: x, y, width, height), tilt degrees]. The gangs (the taxi is in the middle).
const PANELS := [[CharacterPanel.Subject.MACHETE_CLOSE, Color(0.8, 0.15, 0.1), 3, Rect2(0.035, 0.05, 0.27, 0.42), -2.5],
		[CharacterPanel.Subject.SHOTGUN, Color(0.1, 0.55, 0.55), 0, Rect2(0.045, 0.5, 0.26, 0.38), 1.8],
		[CharacterPanel.Subject.RIFLE_FIRE, Color(0.15, 0.32, 0.7), 0, Rect2(0.695, 0.05, 0.27, 0.42), 2.2],
		[CharacterPanel.Subject.MACHETE_SWING, Color(0.5, 0.25, 0.65), 1, Rect2(0.69, 0.5, 0.26, 0.38), -1.6]]
## The officers in the middle, on the sunset (fractions of the screen).
const HEROES := Rect2(0.28, 0.2, 0.44, 0.72)
## Sunset, top of the sky to the horizon.
const SKY := [Color(0.13, 0.08, 0.3), Color(0.5, 0.18, 0.5), Color(0.92, 0.38, 0.45), Color(1.0, 0.62, 0.32), Color(1.0, 0.8, 0.45)]
const SILHOUETTE := Color(0.13, 0.04, 0.16)
const HILLS := Color(0.38, 0.16, 0.38)
const TOWERS := Color(0.27, 0.1, 0.3)
const SEA := [Color(0.48, 0.2, 0.42), Color(0.2, 0.07, 0.2)]
const FRAME := 7.0
## Horizon height (share of the screen from the top).
const HORIZON := 0.7

@export var mode: Mode = Mode.TITLE

var _heavy: SystemFont
var _script: SystemFont
var _pages: Dictionary = {}  # name -> Control


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
		_draw_sunset()


# --- Art -----------------------------------------------------------------------------

func _build_art() -> void:
	resized.connect(queue_redraw)
	for entry: Array in PANELS:
		# A white frame with a hard black shadow, tilted a little, the panel inside.
		var frame := PanelContainer.new()
		var box := StyleBoxFlat.new()
		box.bg_color = GrivetStyle.WHITE
		box.set_content_margin_all(FRAME)
		box.shadow_color = Color(0, 0, 0, 0.75)
		box.shadow_offset = Vector2(8, 10)
		box.shadow_size = 1
		frame.add_theme_stylebox_override("panel", box)
		_place(frame, entry[3])
		frame.rotation_degrees = entry[4]
		frame.resized.connect(func() -> void: frame.pivot_offset = frame.size * 0.5)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var panel := CharacterPanel.new()
		panel.subject = entry[0]
		panel.backdrop = entry[1]
		panel.variant = entry[2]
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(panel)
		add_child(frame)
	var heroes := CharacterPanel.new()
	heroes.subject = CharacterPanel.Subject.HEROES
	heroes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(heroes, HEROES)
	add_child(heroes)


## Anchors a control to a rect given in fractions of the screen.
func _place(control: Control, area: Rect2) -> void:
	control.anchor_left = area.position.x
	control.anchor_top = area.position.y
	control.anchor_right = area.end.x
	control.anchor_bottom = area.end.y


## The backdrop: a sunset over the harbour, the sun low, hills and a few
## towers against it, palm silhouettes at both edges. Drawn, not rendered.
func _draw_sunset() -> void:
	var w := size.x
	var h := size.y
	var horizon := h * HORIZON
	var stops := SKY.size() - 1
	for i in stops:
		var top := horizon * i / stops
		var bottom := horizon * (i + 1) / stops
		draw_polygon(PackedVector2Array([Vector2(0, top), Vector2(w, top), Vector2(w, bottom), Vector2(0, bottom)]),
				PackedColorArray([SKY[i], SKY[i], SKY[i + 1], SKY[i + 1]]))
	# The sun, sinking behind the hills, with a softer glow round it.
	var sun := Vector2(w * 0.5, horizon - h * 0.04)
	draw_circle(sun, h * 0.2, Color(1.0, 0.75, 0.45, 0.35))
	draw_circle(sun, h * 0.14, Color(1.0, 0.88, 0.55))
	# Far hills: the ranges behind the town.
	var hills := PackedVector2Array([Vector2(0, horizon)])
	for i in 41:
		var rise := 0.05 + 0.03 * sin(i * 0.55) + 0.02 * sin(i * 1.7 + 1.0)
		hills.append(Vector2(w * i / 40.0, horizon - h * rise))
	hills.append(Vector2(w, horizon))
	draw_colored_polygon(hills, HILLS)
	# A few towers of the town, either side of the sun.
	for tower in [[0.36, 0.05, 0.16], [0.4, 0.035, 0.22], [0.43, 0.04, 0.13], [0.56, 0.03, 0.12], [0.6, 0.05, 0.18], [0.64, 0.03, 0.1]]:
		draw_rect(Rect2(w * tower[0], horizon - h * tower[2], w * tower[1], h * tower[2]), TOWERS)
	# The harbour, with the sun's track across it.
	draw_polygon(PackedVector2Array([Vector2(0, horizon), Vector2(w, horizon), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([SEA[0], SEA[0], SEA[1], SEA[1]]))
	for i in 9:
		var y := horizon + h * (0.015 + i * 0.03)
		var half := w * (0.09 - i * 0.007)
		draw_rect(Rect2(sun.x - half, y, half * 2.0, h * 0.008), Color(1.0, 0.75, 0.45, 0.5 - i * 0.04))
	# Palms framing it, leaning in from both edges.
	_palm(Vector2(w * 0.02, h), h * 0.95, 0.12)
	_palm(Vector2(w * 0.1, h), h * 0.72, 0.2)
	_palm(Vector2(w * 0.98, h), h * 0.9, -0.14)
	_palm(Vector2(w * 0.9, h), h * 0.68, -0.22)


## A palm silhouette: a curved trunk from `base`, `height` tall, leaning by
## `lean` (share of the height, + to the right), and a crown of drooping fronds.
func _palm(base: Vector2, height: float, lean: float) -> void:
	var trunk := PackedVector2Array()
	var top := base
	for i in 13:
		var t := i / 12.0
		top = base + Vector2(lean * height * t * t, -height * t)
		trunk.append(top)
	draw_polyline(trunk, SILHOUETTE, height * 0.028, true)
	for i in 9:
		var angle := -PI * 0.5 + (i - 4) * 0.42 + lean
		var reach := height * (0.28 if i % 2 == 0 else 0.22)
		var tip := top + Vector2(cos(angle), sin(angle)) * reach + Vector2(0, reach * 0.35)
		var side := Vector2(-sin(angle), cos(angle)) * height * 0.025
		var middle := top.lerp(tip, 0.5) + Vector2(0, -reach * 0.1)
		draw_colored_polygon(PackedVector2Array([top, middle + side, tip, middle - side]), SILHOUETTE)


## The logo: GRIVET in fat capitals filled with a sunset gradient (orange to
## gold, logo_gradient.gdshader), a thick black outline, PORT MORESBY under it.
func _build_logo() -> void:
	var logo := VBoxContainer.new()
	logo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	logo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	logo.offset_top = 6.0
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	logo.add_theme_constant_override("separation", -40)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	for line in [["GRIVET", 190, 28], ["PORT MORESBY", 78, 14]]:
		var label := GrivetStyle.label(line[0], _heavy, line[1], Color.WHITE, line[2])
		label.add_theme_color_override("font_outline_color", GrivetStyle.INK)
		var gradient := ShaderMaterial.new()
		gradient.shader = LOGO_SHADER
		gradient.set_shader_parameter("line_height", float(line[1]) * 1.2)
		label.material = gradient
		logo.add_child(label)


# --- Pages ------------------------------------------------------------------------

func _build_pages() -> void:
	var main := _page("main", mode == Mode.PAUSE)
	if mode == Mode.TITLE:
		main.add_child(_item("START GAME", func() -> void: _show("maps")))
		main.add_child(_item("STAGES", func() -> void: _show("stages")))
	else:
		main.add_child(GrivetStyle.label("PAUSED", _heavy, 120, GrivetStyle.WHITE, 18))
		main.add_child(_item("RESUME", _resume))
	main.add_child(_item("SETTINGS", func() -> void: _show("settings")))
	if mode == Mode.PAUSE:
		main.add_child(_item("MAIN MENU", _to_title))
	main.add_child(_item("QUIT", func() -> void: get_tree().quit()))

	var maps := _page("maps", true)
	maps.add_child(GrivetStyle.label("CHOOSE A MAP", _heavy, 90, GrivetStyle.WHITE, 14))
	for map: Array in MAPS:
		var scene: String = map[1]
		maps.add_child(_item(map[0], func() -> void: _start(0, scene), (map[2] as Campaign).stages[0].subtitle))
	maps.add_child(_item("BACK", func() -> void: _show("main")))

	var stages := _page("stages", true)
	stages.add_child(GrivetStyle.label("STAGES", _heavy, 90, GrivetStyle.WHITE, 14))
	for m in MAPS.size():
		var map: Array = MAPS[m]
		var scene: String = map[1]
		var campaign: Campaign = map[2]
		stages.add_child(_item(map[0], func() -> void: _show("stages_%d" % m), "%d stages" % campaign.stages.size()))
		var page := _page("stages_%d" % m, true)
		page.add_child(GrivetStyle.label(map[0], _heavy, 80, GrivetStyle.WHITE, 14))
		for i in campaign.stages.size():
			var stage := campaign.stages[i]
			page.add_child(_item("%d. %s" % [i + 1, stage.title], func() -> void: _start(i, scene), stage.subtitle))
		page.add_child(_item("BACK", func() -> void: _show("stages")))
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
## The title's main page is a row in a dark bar along the bottom instead.
func _page(page_name: String, backed: bool) -> Control:
	var bottom := mode == Mode.TITLE and not backed
	var column: BoxContainer = HBoxContainer.new() if bottom else VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 56 if bottom else 4)
	var holder: Control = column
	if bottom:
		var bar := PanelContainer.new()
		var strip := StyleBoxFlat.new()
		strip.bg_color = Color(GrivetStyle.INK, 0.85)
		strip.content_margin_left = 30
		strip.content_margin_right = 30
		bar.add_theme_stylebox_override("panel", strip)
		bar.add_child(column)
		holder = bar
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
	holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_CENTER)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_BOTH
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

func _start(stage: int, scene: String) -> void:
	Settings.requested_stage = stage
	get_tree().paused = false
	get_tree().change_scene_to_file(scene)


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
