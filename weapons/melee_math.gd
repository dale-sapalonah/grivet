class_name MeleeMath
extends RefCounted
## Pure rules for the player's knife.


## A silent one-hit takedown: the victim within `reach` (flat metres) and
## either unaware of the attacker, blinded, or with the attacker inside its
## rear arc (`rear_arc_degrees` either side of straight behind it).
static func can_take_down(attacker: Vector3, victim: Vector3, victim_forward: Vector3, reach: float,
		rear_arc_degrees: float, victim_aware: bool, victim_blind: bool) -> bool:
	var offset := Vector2(attacker.x - victim.x, attacker.z - victim.z)
	if offset.length() > reach:
		return false
	if victim_blind or not victim_aware:
		return true
	var forward := Vector2(victim_forward.x, victim_forward.z)
	if forward.length() < 0.001 or offset.length() < 0.001:
		return true  # standing on top of it
	var from_front := rad_to_deg(forward.angle_to(offset))
	return absf(from_front) >= 180.0 - rear_arc_degrees


## Index of the closest candidate the attacker can reach in front of it
## (within `reach` and `cone_degrees` either side of `facing`), or -1.
static func pick_target(attacker: Vector3, facing: Vector3, candidates: Array[Vector3], reach: float,
		cone_degrees: float) -> int:
	var best := -1
	var best_distance := INF
	var look := Vector2(facing.x, facing.z).normalized()
	for i in candidates.size():
		var offset := Vector2(candidates[i].x - attacker.x, candidates[i].z - attacker.z)
		var distance := offset.length()
		if distance > reach or distance >= best_distance:
			continue
		if distance > 0.3 and rad_to_deg(absf(look.angle_to(offset))) > cone_degrees:
			continue
		best = i
		best_distance = distance
	return best
