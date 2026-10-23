class_name TargetDummy
extends CSGBox3D
## Range target. Counts hits and damage and flashes when shot. Bullets treat
## it as flesh (stops every round). Hit zones and ragdolls come with
## Milestone 3's damage system.

@export var base_color := Color(0.75, 0.2, 0.18)
@export var hit_color := Color(1.0, 0.9, 0.3)
@export var flash_time := 0.12

var hits := 0
var total_damage := 0.0
var last_hit: Dictionary = {}

var _material := StandardMaterial3D.new()
var _flash_left := 0.0


func _ready() -> void:
	if not has_meta("surface"):
		set_meta("surface", "flesh")
	_material.albedo_color = base_color
	material = _material
	add_to_group("targets")


func apply_damage(hit: Dictionary) -> void:
	hits += 1
	total_damage += hit.damage
	last_hit = hit
	_flash_left = flash_time


func reset() -> void:
	hits = 0
	total_damage = 0.0
	last_hit = {}


func _process(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left -= delta
	_material.albedo_color = hit_color if _flash_left > 0.0 else base_color
