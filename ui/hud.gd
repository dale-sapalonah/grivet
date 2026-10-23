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

var _holder: WeaponHolder
var _hit_left := 0.0

@onready var _ammo: Label = $Ammo
@onready var _weapon_name: Label = $WeaponName
@onready var _status: Label = $Status


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Ballistics.target_hit.connect(_on_target_hit)


func _process(delta: float) -> void:
	if not is_instance_valid(_holder):
		_holder = get_tree().get_first_node_in_group("player_weapons") as WeaponHolder
	_hit_left = maxf(_hit_left - delta, 0.0)
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


func _on_target_hit(info: Dictionary) -> void:
	if _holder != null and info.shooter == _holder.player():
		_hit_left = hitmarker_time
