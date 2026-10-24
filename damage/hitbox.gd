class_name Hitbox
extends AnimatableBody3D
## What bullets actually hit on a person: one CollisionShape3D child per body
## part, each tagged with metadata `zone` = "head" / "torso" / "arms" / "legs".
## Lives on the hitboxes layer, so movement capsules never stop rounds. The
## owning body moves the shapes to follow its pose (stance, ragdoll-free).
## Ballistics finds apply_damage() here and passes the struck shape index.

## The Health that takes the damage.
@export var health: Health
## The character this hitbox belongs to (Player or Soldier), for "who was hit".
var body: Node


func _ready() -> void:
	sync_to_physics = false
	collision_layer = PhysicsLayers.HITBOXES
	collision_mask = 0
	if not has_meta("surface"):
		set_meta("surface", "flesh")


func apply_damage(hit: Dictionary) -> void:
	if health == null:
		return
	var damage: float = hit.damage
	# Enemies hit the player for less (EnemyProfile.damage_multiplier, fairness).
	var shooter: Object = hit.get("shooter")
	if body is Player and shooter is Soldier:
		damage *= (shooter as Soldier).profile.damage_multiplier
	health.take_hit(damage, zone_of(hit.get("shape", -1)), hit)


## The node for a struck shape index (for its metadata, e.g. "part").
func shape_node(shape_index: int) -> Node:
	if shape_index < 0:
		return null
	return shape_owner_get_owner(shape_find_owner(shape_index)) as Node


func zone_of(shape_index: int) -> DamageModel.Zone:
	if shape_index < 0:
		return DamageModel.Zone.TORSO
	var shape_owner := shape_find_owner(shape_index)
	var node := shape_owner_get_owner(shape_owner) as Node
	if node == null:
		return DamageModel.Zone.TORSO
	return DamageModel.zone_from_name(str(node.get_meta("zone", "torso")))
