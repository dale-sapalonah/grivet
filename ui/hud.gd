extends Control
## Minimal combat HUD: crosshair sized from the live spread cone (hidden when
## aiming down sights), hit marker, ammo and weapon state. Finds the player's
## WeaponHolder through the "player_weapons" group.

@export var crosshair_color := Color(1, 1, 1, 0.85)
@export var crosshair_length := 8.0
@export var crosshair_thickness := 2.0
@export var crosshair_min_gap := 3.0
## Above this aim blend the crosshair is hidden (iron sights take over).
@export var crosshair_hide_aim := 0.5
@export var hitmarker_color := Color(1, 1, 1, 1)
@export var hitmarker_size := 7.0
@export var hitmarker_time := 0.15
## Show the reload hint when the magazine is at or below this share.
@export var low_ammo_fraction := 0.25

@export_group("Vitals")
@export var vitals_origin := Vector2(32, -64)
@export var health_bar_size := Vector2(220, 10)
@export var plate_gap := 4.0
@export var health_color := Color(0.78, 0.12, 0.08, 0.95)
@export var health_low_color := Color(1.0, 0.3, 0.18, 1.0)
@export var armor_color := Color(0.92, 0.92, 0.9, 0.95)
@export var bar_back_color := Color(0, 0, 0, 0.45)
## Red screen edges from this health share down.
@export var vignette_from := 0.5
@export var vignette_color := Color(0.6, 0.0, 0.0, 0.55)

@export_group("Damage direction")
@export var damage_marker_radius := 130.0
@export var damage_marker_arc_degrees := 40.0
@export var damage_marker_width := 8.0
@export var damage_marker_time := 1.2
@export var damage_color := Color(0.95, 0.15, 0.1, 0.9)

@export_group("Grenade warning")
@export var grenade_warning_range := 8.0
@export var grenade_marker_radius := 95.0
@export var grenade_color := Color(1.0, 0.75, 0.2, 0.95)

var _holder: WeaponHolder
var _player: Player
var _hit_left := 0.0
var _damage_markers: Array[Dictionary] = []  # {"from": Vector3, "left": float}
## Every line announced, in order (for probes).
var shout_log: PackedStringArray = []
var _shouts: Array[Dictionary] = []  # queued: {"text", "subtitle", "color", "seconds"}
var _shout_left := 0.0
var _shout_label: Label
var _shout_subtitle: Label
var _heavy: SystemFont

@onready var _ammo: Label = $Ammo
@onready var _weapon_name: Label = $WeaponName
@onready var _status: Label = $Status


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Ballistics.target_hit.connect(_on_target_hit)
	add_to_group("hud")
	Debug.register("announce", _cmd_announce, "announce <text>: show a big centred line for 30 s (look check).")
	# Grivet's house style: fat outlined capitals, hard drop shadows.
	_heavy = GrivetStyle.heavy()
	_shout_label = _centred_label(_heavy, 128, 18)
	_shout_subtitle = _centred_label(_heavy, 38, 8)
	for readout: Label in [_ammo, _weapon_name, _status]:
		GrivetStyle.style(readout, _heavy, readout.get_theme_font_size("font_size") + 8, GrivetStyle.WHITE, 6)


func _exit_tree() -> void:
	Debug.unregister("announce")


func _cmd_announce(args: PackedStringArray) -> String:
	announce(" ".join(args), Color(1.0, 0.8, 0.1), 30.0, "Subtitle goes here")
	return "announced"


## Queues a big centred line (with an optional smaller one under it): stage
## titles, "KLIN CHOL!", "WARAA!". Each pops in, holds and fades.
func announce(text: String, color: Color, seconds: float = 1.6, subtitle: String = "") -> void:
	_shouts.append({"text": text, "subtitle": subtitle, "color": color, "seconds": seconds})
	shout_log.append(text)


func _centred_label(font: Font, size: int, outline: int) -> Label:
	var label := Label.new()
	GrivetStyle.style(label, font, size, GrivetStyle.WHITE, outline)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	add_child(label)
	return label


func _update_shouts(delta: float) -> void:
	if _shout_left <= 0.0:
		_shout_label.visible = false
		_shout_subtitle.visible = false
		if _shouts.is_empty():
			return
		var shout: Dictionary = _shouts.pop_front()
		_shout_label.text = shout.text
		_shout_label.add_theme_color_override("font_color", shout.color)
		_shout_subtitle.text = "



" + str(shout.subtitle)
		_shout_subtitle.add_theme_color_override("font_color", GrivetStyle.WHITE)
		_shout_left = shout.seconds
		_shout_label.set_meta("seconds", shout.seconds)
	_shout_left -= delta
	var total: float = _shout_label.get_meta("seconds", 1.0)
	var age := total - _shout_left
	# Pop: overshoot then settle; fade in the last quarter second.
	var pop := 1.0 + 0.35 * exp(-age * 9.0) * cos(age * 18.0)
	var fade := clampf(_shout_left / 0.25, 0.0, 1.0)
	_shout_label.pivot_offset = _shout_label.size * 0.5
	_shout_label.scale = Vector2.ONE * pop
	_shout_label.modulate.a = fade
	_shout_subtitle.modulate.a = fade
	_shout_label.visible = true
	_shout_subtitle.visible = _shout_subtitle.text.strip_edges() != ""


func _process(delta: float) -> void:
	_update_shouts(delta)
	if not is_instance_valid(_holder):
		_holder = get_tree().get_first_node_in_group("player_weapons") as WeaponHolder
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player != null:
			_player.health.damaged.connect(_on_player_damaged)
	_hit_left = maxf(_hit_left - delta, 0.0)
	for marker in _damage_markers:
		marker.left -= delta
	_damage_markers = _damage_markers.filter(func(marker: Dictionary) -> bool: return marker.left > 0.0)
	var weapon := _holder.current_weapon() if _holder != null else null
	if weapon == null:
		_ammo.text = ""
		_weapon_name.text = ""
		_status.text = ""
	else:
		var reserve := "∞" if weapon.infinite_ammo else str(weapon.reserve)
		_ammo.text = "%d / %s" % [weapon.ammo, reserve]
		_weapon_name.text = weapon.definition.display_name
		_status.text = _status_text(weapon)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	if _player != null:
		_draw_vignette()
		_draw_damage_markers(center)
		_draw_grenade_warnings(center)
		_draw_vitals()
		if _player.dead:
			_draw_death_screen(center)
			return
	if _holder != null and _holder.current_weapon() != null and _holder.aim_blend < crosshair_hide_aim:
		var gap := maxf(crosshair_min_gap, _spread_pixels(_holder.current_spread))
		for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(center + direction * gap, center + direction * (gap + crosshair_length),
					crosshair_color, crosshair_thickness)
	if _hit_left > 0.0:
		var color := Color(hitmarker_color, _hit_left / hitmarker_time)
		var inner := hitmarker_size * 0.5
		for diagonal in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(center + diagonal * inner, center + diagonal * (inner + hitmarker_size),
					color, crosshair_thickness)


func _status_text(weapon: WeaponModel) -> String:
	match weapon.state:
		WeaponModel.State.RELOADING:
			return "RELOADING"
		WeaponModel.State.PUMPING:
			return ""
	if weapon.ammo == 0 and weapon.reserve == 0 and not weapon.infinite_ammo:
		return "NO AMMO"
	if weapon.ammo <= ceili(weapon.definition.magazine_size * low_ammo_fraction):
		return "R  RELOAD"
	return ""


## Converts a cone half-angle into pixels from screen centre.
func _spread_pixels(degrees: float) -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return 0.0
	var half_fov := deg_to_rad(camera.fov * 0.5)
	return tan(deg_to_rad(degrees)) / tan(half_fov) * size.y * 0.5


func _on_player_damaged(info: Dictionary) -> void:
	var shooter: Object = info.get("shooter")
	var from := Vector3.INF
	if shooter is Node3D and is_instance_valid(shooter):
		from = (shooter as Node3D).global_position
	elif info.has("direction"):
		from = _player.global_position - (info.direction as Vector3) * 10.0
	if from != Vector3.INF:
		_damage_markers.append({"from": from, "left": damage_marker_time})


## Bearing of a world point relative to where the player faces (0 = ahead,
## positive = to the right), radians.
func _bearing(point: Vector3) -> float:
	var to := point - _player.global_position
	var forward := -_player.global_basis.z
	return Vector2(forward.x, forward.z).angle_to(Vector2(to.x, to.z))


func _draw_damage_markers(center: Vector2) -> void:
	var half_arc := deg_to_rad(damage_marker_arc_degrees) * 0.5
	for marker in _damage_markers:
		var angle := _bearing(marker.from) - PI * 0.5  # screen: 0 rad points right, ahead is up
		var color := Color(damage_color, damage_color.a * marker.left / damage_marker_time)
		draw_arc(center, damage_marker_radius, angle - half_arc, angle + half_arc, 16, color, damage_marker_width)


func _draw_grenade_warnings(center: Vector2) -> void:
	var font := ThemeDB.fallback_font
	for grenade in Grenade.live:
		if not is_instance_valid(grenade):
			continue
		var distance := grenade.global_position.distance_to(_player.global_position)
		if distance > grenade_warning_range:
			continue
		var angle := _bearing(grenade.global_position) - PI * 0.5
		var at := center + Vector2(cos(angle), sin(angle)) * grenade_marker_radius
		var urgency := 1.0 - distance / grenade_warning_range
		draw_circle(at, 12.0 + 6.0 * urgency, Color(grenade_color, 0.35 + 0.5 * urgency))
		draw_string(font, at + Vector2(-4, 6), "!", HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color.BLACK)


func _draw_vitals() -> void:
	var health := _player.health
	var origin := Vector2(vitals_origin.x, size.y + vitals_origin.y)
	var fraction := clampf(health.fraction(), 0.0, 1.0)
	draw_rect(Rect2(origin - Vector2(2, 2), health_bar_size + Vector2(4, 4)), GrivetStyle.INK)  # outlined bars
	draw_rect(Rect2(origin, health_bar_size), bar_back_color)
	var color := health_low_color if fraction < vignette_from else health_color
	draw_rect(Rect2(origin, Vector2(health_bar_size.x * fraction, health_bar_size.y)), color)
	# One segment per plate slot above the health bar.
	var slots := health.profile.plate_slots
	var segment := (health_bar_size.x - plate_gap * (slots - 1)) / slots
	var plates := health.model.plates()
	for i in slots:
		var at := origin + Vector2(i * (segment + plate_gap), -health_bar_size.y - plate_gap)
		draw_rect(Rect2(at - Vector2(2, 2), Vector2(segment, health_bar_size.y) + Vector2(4, 4)), GrivetStyle.INK)
		draw_rect(Rect2(at, Vector2(segment, health_bar_size.y)), bar_back_color)
		var fill := clampf(plates - i, 0.0, 1.0)
		draw_rect(Rect2(at, Vector2(segment * fill, health_bar_size.y)), armor_color)
	var line := "PLATES +%d    GRENADES %d" % [health.plates_carried, _holder.grenades_left if _holder != null else 0]
	draw_string_outline(_heavy, origin + Vector2(0, health_bar_size.y + 22), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, GrivetStyle.INK)
	draw_string(_heavy, origin + Vector2(0, health_bar_size.y + 22), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GrivetStyle.WHITE)
	if _player.plate_progress > 0.0:
		var bar := Vector2(160, 6)
		var at := size * 0.5 + Vector2(-bar.x * 0.5, 90)
		draw_rect(Rect2(at, bar), bar_back_color)
		draw_rect(Rect2(at, Vector2(bar.x * _player.plate_progress, bar.y)), armor_color)


func _draw_vignette() -> void:
	var fraction := _player.health.fraction()
	if fraction >= vignette_from:
		return
	var strength := 1.0 - fraction / vignette_from
	var color := Color(vignette_color, vignette_color.a * strength)
	var edge := size.y * 0.12
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, edge)), color)
	draw_rect(Rect2(Vector2(0, size.y - edge), Vector2(size.x, edge)), color)
	draw_rect(Rect2(Vector2.ZERO, Vector2(edge, size.y)), color)
	draw_rect(Rect2(Vector2(size.x - edge, 0), Vector2(edge, size.y)), color)


func _draw_death_screen(center: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.0, 0.0, 0.55))
	var font := ThemeDB.fallback_font
	draw_string(font, center + Vector2(-200, -10), "YOU WERE KILLED", HORIZONTAL_ALIGNMENT_CENTER, 400, 32, health_low_color)
	draw_string(font, center + Vector2(-200, 26), "respawning...", HORIZONTAL_ALIGNMENT_CENTER, 400, 16, health_color)


func _on_target_hit(info: Dictionary) -> void:
	if _holder != null and info.shooter == _holder.player():
		_hit_left = hitmarker_time
