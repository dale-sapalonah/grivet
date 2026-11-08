class_name MissionObjective
extends Resource
## One step of a mission (Mission.objectives, in order).

## CLEAR: put down the squad of `stage`. SEARCH: stay within `radius` of
## `point` for `seconds` (stepping out loses progress). REACH: get within
## `radius` of `point`. EXTRACT: as REACH, and it ends the mission. RESCUE: as
## CLEAR, with civilians in the fight (detained, human shields, panicking);
## hurting one fails the mission.
enum Kind { CLEAR, SEARCH, REACH, EXTRACT, RESCUE }

@export var kind: Kind = Kind.CLEAR
## Shown on the HUD.
@export var text := ""
## The campaign stage whose squad comes in when this objective begins (-1:
## none). A CLEAR objective is met when that squad is down.
@export var stage := -1
## Where it is (the HUD's waypoint): the search spot, the place to reach, or
## for CLEAR a place to head for; Vector3.ZERO hides the waypoint.
@export var point := Vector3.ZERO
@export var radius := 3.0
@export var seconds := 0.0
## Radio lines shown when it begins ("WHO: words").
@export var radio: PackedStringArray = PackedStringArray()
## On completion the player respawns here from now on, healed and re-armed.
@export var checkpoint := true

@export_group("Rescue")
## Spots as Vector3(x, facing degrees, z) (the facing in y, like safe_spots).
## Kneeling hostages; raskols holding a hostage as a shield (spawned as
## captor_kind); civilians panicking and running about from these spots.
@export var detained: PackedVector3Array = PackedVector3Array()
@export var shields: PackedVector3Array = PackedVector3Array()
@export var panicked: PackedVector3Array = PackedVector3Array()
@export var captor_kind := "rifleman"
