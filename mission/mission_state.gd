class_name MissionState
extends RefCounted
## Where a mission stands: the current objective and its search progress.
## Pure (no nodes): MissionRunner feeds it the player's position and the
## stages cleared; tested headless.

var mission: Mission
var index := 0
## Seconds searched at the current SEARCH objective.
var searched := 0.0
var _cleared: Dictionary = {}  # stage index -> true


func _init(of: Mission) -> void:
	mission = of


func current() -> MissionObjective:
	return mission.objectives[index] if index < mission.objectives.size() else null


func finished() -> bool:
	return index >= mission.objectives.size()


func stage_cleared(stage: int) -> void:
	_cleared[stage] = true


## Share of the current search done (0 when not searching).
func search_fraction() -> float:
	var objective := current()
	if objective == null or objective.kind != MissionObjective.Kind.SEARCH or objective.seconds <= 0.0:
		return 0.0
	return clampf(searched / objective.seconds, 0.0, 1.0)


## Steps the current objective with the player at `player`; true when it was
## just met (the state has moved on to the next).
func update(player: Vector3, delta: float) -> bool:
	var objective := current()
	if objective == null:
		return false
	var inside := Vector2(player.x - objective.point.x, player.z - objective.point.z).length() <= objective.radius
	var met := false
	match objective.kind:
		MissionObjective.Kind.CLEAR, MissionObjective.Kind.RESCUE:
			met = _cleared.has(objective.stage)
		MissionObjective.Kind.SEARCH:
			# Stepping out loses progress twice as fast as it was gained.
			searched = searched + delta if inside else maxf(searched - delta * 2.0, 0.0)
			met = searched >= objective.seconds
		MissionObjective.Kind.REACH, MissionObjective.Kind.EXTRACT:
			met = inside
	if met:
		index += 1
		searched = 0.0
	return met
