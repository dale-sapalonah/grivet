class_name Health
extends Node
## A body's health: wraps DamageModel with regeneration after a quiet spell,
## spare plates, invulnerability (`god`) and signals the HUD and AI listen to.

## `info` is the Ballistics hit (plus "zone", "health_damage", "armor_damage").
signal damaged(info: Dictionary)
signal died(info: Dictionary)
signal revived

@export var profile: HealthProfile

var model: DamageModel
var invulnerable := false
var plates_carried := 0
var last_hit: Dictionary = {}

var _since_damage := INF


func _ready() -> void:
	if profile != null:
		setup(profile)


## For bodies whose profile is chosen at spawn (soldiers): set it up then.
func setup(health_profile: HealthProfile) -> void:
	profile = health_profile
	model = DamageModel.new(profile)
	plates_carried = profile.plates_carried


func take_hit(amount: float, zone: DamageModel.Zone, info: Dictionary = {}) -> void:
	if model.dead:
		return
	var result := model.apply(0.0 if invulnerable else amount, zone)
	_since_damage = 0.0
	last_hit = info.duplicate()
	last_hit.merge({"zone": zone, "health_damage": result.health_damage,
			"armor_damage": result.armor_damage}, true)
	damaged.emit(last_hit)
	if result.killed:
		died.emit(last_hit)


func is_dead() -> bool:
	return model.dead


func fraction() -> float:
	return model.health / profile.max_health


func revive() -> void:
	model.reset()
	plates_carried = profile.plates_carried
	_since_damage = INF
	revived.emit()


## Inserts a carried plate if there is room. False when none left or full.
func insert_plate() -> bool:
	if plates_carried <= 0 or model.dead:
		return false
	if model.add_plate():
		plates_carried -= 1
		return true
	return false


func _process(delta: float) -> void:
	if model == null or model.dead or profile.regen_delay <= 0.0:
		return
	_since_damage += delta
	if _since_damage >= profile.regen_delay:
		model.heal(profile.regen_per_second * delta)
