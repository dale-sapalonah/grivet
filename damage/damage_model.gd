class_name DamageModel
extends RefCounted
## Pure damage bookkeeping: zone multipliers, torso armour plates that soak
## damage until broken, health, death. No nodes, so it is tested headless;
## the Health node wraps it with regeneration and signals.

## TORSO is the chest (under the plates); ABDOMEN is stomach and pelvis, unarmoured.
enum Zone { HEAD, TORSO, ARMS, LEGS, ABDOMEN }

const ZONE_NAMES := {"head": Zone.HEAD, "torso": Zone.TORSO, "arms": Zone.ARMS, "legs": Zone.LEGS,
		"abdomen": Zone.ABDOMEN}

var profile: HealthProfile
var health := 0.0
var armor := 0.0
var dead := false


func _init(health_profile: HealthProfile) -> void:
	profile = health_profile
	reset()


func reset() -> void:
	health = profile.max_health
	armor = profile.plates_start * profile.plate_points
	dead = false


## Applies `amount` of raw damage to `zone`. `on_plate`: the round struck
## the plate itself (a torso hit beside it, e.g. the flank, goes straight to
## health). A stopped round still passes blunt trauma. Returns what happened:
## {"multiplier", "armor_damage", "health_damage", "killed"}.
func apply(amount: float, zone: Zone, on_plate: bool = true) -> Dictionary:
	var result := {"multiplier": multiplier(zone), "armor_damage": 0.0, "health_damage": 0.0, "killed": false}
	if dead or amount <= 0.0:
		return result
	var damage: float = amount * result.multiplier
	if armor > 0.0 and covers(zone) and on_plate:
		var absorbed := minf(armor, damage)
		armor -= absorbed
		damage -= absorbed * (1.0 - profile.blunt_trauma)
		result.armor_damage = absorbed
	health -= damage
	result.health_damage = damage
	if health <= 0.0:
		health = 0.0
		dead = true
		result.killed = true
	return result


func multiplier(zone: Zone) -> float:
	match zone:
		Zone.HEAD:
			return profile.head_multiplier
		Zone.ARMS:
			return profile.arms_multiplier
		Zone.LEGS:
			return profile.legs_multiplier
		Zone.ABDOMEN:
			return profile.abdomen_multiplier
	return profile.torso_multiplier


## Plates cover the chest only (not the abdomen); headshots bypass them
## when the profile says so.
func covers(zone: Zone) -> bool:
	return zone == Zone.TORSO or (zone == Zone.HEAD and not profile.headshots_bypass_armor)


func heal(amount: float) -> void:
	if not dead:
		health = minf(health + amount, profile.max_health)


func max_armor() -> float:
	return profile.plate_slots * profile.plate_points


func plates() -> float:
	return armor / profile.plate_points if profile.plate_points > 0.0 else 0.0


## Inserts one plate's worth of armour. False when already full.
func add_plate() -> bool:
	if armor >= max_armor() - 0.001:
		return false
	armor = minf(armor + profile.plate_points, max_armor())
	return true


static func zone_from_name(zone_name: String) -> Zone:
	return ZONE_NAMES.get(zone_name, Zone.TORSO)
