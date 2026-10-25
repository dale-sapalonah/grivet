extends Node
## Autoloaded as `Settings`: the player's options, saved to user://settings.cfg
## and applied live. The menus edit these through set_value(); everything
## else reads them (or gets them pushed, like volumes and render scale).

signal changed(key: String)

const PATH := "user://settings.cfg"
## Name -> default. Ranges and labels live with the menu that edits them.
const DEFAULTS := {
	"master_volume": 0.9,
	"music_volume": 0.55,
	"music_on": true,
	"sfx_volume": 0.9,
	"sfx_on": true,
	"mouse_sensitivity": 1.0,
	"invert_y": false,
	"fov": 65.0,
	"render_scale": 0.75,
	"shadows": 2,  # 0 off, 1 low, 2 medium
	# 0 PERFORMANCE (the 60 fps look); 1 BALANCED: + glow and smoother shadow
	# filtering; 2 HIGH: + PCSS soft shadows, TAA, 4x MSAA, SSAO, SSIL,
	# volumetric fog with sun shafts and shadowed street lamps. HIGH is far
	# beyond integrated graphics (about 16 fps on the HD 630).
	"graphics": 1,
	"fullscreen": false,
	"show_fps": true,
}

var values: Dictionary = DEFAULTS.duplicate()
## Not saved: the stage the menu picked for the next game.
var requested_stage := 0
## The shared camera tuning the player reads (edited in place).
var camera_tuning: CameraTuning = load("res://data/player/camera_tuning.tres")
var _base_sensitivity := 0.0


func _ready() -> void:
	_base_sensitivity = camera_tuning.mouse_sensitivity
	_ensure_buses()
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		for key: String in DEFAULTS:
			values[key] = config.get_value("settings", key, DEFAULTS[key])
	Debug.register("setting", _cmd_setting, "setting <key> <value>: change a saved setting (e.g. setting shadows 1).")
	get_tree().node_added.connect(_on_node_added)
	# Earlier autoloads (Ballistics, AI) made their sound players before us.
	for node in get_tree().root.find_children("*", "", true, false):
		_on_node_added(node)
	for key: String in values:
		_apply(key)


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	values[key] = value
	_apply(key)
	_save()
	changed.emit(key)


func reset_to_defaults() -> void:
	for key: String in DEFAULTS:
		set_value(key, DEFAULTS[key])


func _cmd_setting(args: PackedStringArray) -> String:
	if args.size() < 2 or not values.has(args[0]):
		return "usage: setting <%s> <value>" % "|".join(values.keys())
	set_value(args[0], str_to_var(args[1]))
	return "%s = %s" % [args[0], values[args[0]]]


func _save() -> void:
	var config := ConfigFile.new()
	for key: String in values:
		config.set_value("settings", key, values[key])
	config.save(PATH)


func _apply(key: String) -> void:
	var value: Variant = values[key]
	match key:
		"master_volume":
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(value), 0.0001)))
		"music_volume", "music_on":
			var bus := AudioServer.get_bus_index("Music")
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(float(values.music_volume), 0.0001)))
			AudioServer.set_bus_mute(bus, not bool(values.music_on))
		"sfx_volume", "sfx_on":
			for bus_name in ["SFX", "Cues"]:
				var bus := AudioServer.get_bus_index(bus_name)
				AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(float(values.sfx_volume), 0.0001)))
				AudioServer.set_bus_mute(bus, not bool(values.sfx_on))
		"mouse_sensitivity":
			camera_tuning.mouse_sensitivity = _base_sensitivity * float(value)
		"invert_y":
			camera_tuning.invert_y = bool(value)
		"fov":
			camera_tuning.base_fov = float(value)
		"render_scale":
			get_tree().root.scaling_3d_scale = float(value)
		"graphics":
			_apply_graphics()
		"shadows":
			RenderingServer.directional_shadow_atlas_set_size(1024 if int(value) == 1 else 2048, true)
			for light in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
				_shadow(light as DirectionalLight3D)
		"fullscreen":
			if DisplayServer.get_name() != "headless":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(value) else DisplayServer.WINDOW_MODE_WINDOWED)


## Levels load after settings: switch their sun's shadows to match. Every
## sound player left on Master is a sound effect: route it to SFX, so effects
## and music have their own volume and mute (music players name their bus).
func _on_node_added(node: Node) -> void:
	if node is DirectionalLight3D:
		_shadow(node as DirectionalLight3D)
		_grade_sun(node as DirectionalLight3D)
	elif node is WorldEnvironment:
		_grade_environment.call_deferred(node)
	elif node is SpotLight3D and node.is_in_group("street_light"):
		_grade_lamp(node as SpotLight3D)
	elif node is AudioStreamPlayer3D or node is AudioStreamPlayer or node is AudioStreamPlayer2D:
		if node.get("bus") == &"Master":
			node.set("bus", &"SFX")


func _shadow(light: DirectionalLight3D) -> void:
	if not light.has_meta("shadows_designed"):
		light.set_meta("shadows_designed", light.shadow_enabled)
	light.shadow_enabled = bool(light.get_meta("shadows_designed")) and int(values.shadows) > 0


# --- Graphics quality ---------------------------------------------------------------

func _high() -> bool:
	return int(values.get("graphics", 1)) >= 2


func _balanced() -> bool:
	return int(values.get("graphics", 1)) >= 1


func _apply_graphics() -> void:
	var root := get_tree().root
	root.msaa_3d = Viewport.MSAA_4X if _high() else Viewport.MSAA_DISABLED
	root.use_taa = _high()
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	var soft := RenderingServer.SHADOW_QUALITY_SOFT_HIGH if _high() else (RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if _balanced() else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(soft)
	for node in root.find_children("*", "WorldEnvironment", true, false):
		_grade_environment(node)
	for node in root.find_children("*", "DirectionalLight3D", true, false):
		_grade_sun(node as DirectionalLight3D)
	for node in get_tree().get_nodes_in_group("street_light"):
		_grade_lamp(node as SpotLight3D)


## HIGH: contact shadows (SSAO) and bounce light (SSIL), bloom, and a thin
## volumetric haze tinted like the sky that catches the low sun in shafts.
## Each level's own values are kept and restored for PERFORMANCE.
func _grade_environment(node: Node) -> void:
	var world := node as WorldEnvironment
	if world == null or world.environment == null:
		return
	var environment := world.environment
	const KEYS := ["ssao_enabled", "ssao_intensity", "ssao_radius", "ssao_power", "ssil_enabled", "ssil_intensity",
			"glow_enabled", "glow_intensity", "glow_bloom", "glow_hdr_threshold", "volumetric_fog_enabled",
			"volumetric_fog_density", "volumetric_fog_albedo", "volumetric_fog_anisotropy", "volumetric_fog_length", "fog_density"]
	if not environment.has_meta("designed"):
		var designed := {}
		for key: String in KEYS:
			designed[key] = environment.get(key)
		environment.set_meta("designed", designed)
	var original: Dictionary = environment.get_meta("designed")
	for key: String in KEYS:
		environment.set(key, original[key])
	if not _balanced():
		return
	environment.glow_enabled = true
	environment.glow_intensity = 0.5
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.0
	if not _high():
		return
	environment.ssao_enabled = true
	environment.ssao_intensity = 2.8
	environment.ssao_radius = 1.2
	environment.ssao_power = 1.6
	environment.ssil_enabled = true
	environment.ssil_intensity = 1.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.6
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.0
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.015
	environment.volumetric_fog_albedo = Color(0.62, 0.42, 0.36)  # the sunset haze
	environment.volumetric_fog_anisotropy = 0.6  # light scatters forward: shafts towards the sun
	environment.volumetric_fog_length = 80.0
	environment.fog_density = original["fog_density"] * 0.5  # the volume carries most of the haze now


## HIGH: soft contact-hardening sun shadows (PCSS) and light shafts.
func _grade_sun(sun: DirectionalLight3D) -> void:
	sun.light_angular_distance = 1.2 if _high() else 0.0  # PCSS: about 5 ms on the HD 630
	sun.light_volumetric_fog_energy = 1.4 if _high() else 1.0


## HIGH: street lamps cast soft shadows (only the few nearest are lit at once).
func _grade_lamp(lamp: SpotLight3D) -> void:
	lamp.shadow_enabled = _high()
	lamp.light_size = 0.25 if _high() else 0.0
	lamp.shadow_blur = 1.5


func _ensure_buses() -> void:
	# Cues: the player's own feedback sounds (hit, kill, breathing, ringing
	# ears); beside SFX so a blast's muffling and the reverb leave them alone.
	for bus_name in ["Music", "SFX", "Cues"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var bus := AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus, bus_name)
			AudioServer.set_bus_send(bus, "Master")
