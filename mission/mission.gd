class_name Mission
extends Resource
## A mission: a level, an intro (the police truck drives in under a radio
## briefing, the camera flying in), objectives in order, and an extraction at
## the truck. data/missions/<id>.tres. MissionRunner plays it.

@export var title := ""
@export var subtitle := ""
@export_file("*.tscn") var level := ""
## Intro: the truck drives from truck_from to truck_at (facing truck_yaw
## degrees, 0 = -Z) while the camera flies camera_from -> camera_to looking at it.
@export var truck_from := Vector3.ZERO
@export var truck_at := Vector3.ZERO
@export var truck_yaw_degrees := 0.0
@export var camera_from := Vector3(0, 20, 40)
@export var camera_to := Vector3(0, 3, 34)
@export var intro_seconds := 12.0
## The outro's camera ends here, looking at the truck as it leaves.
@export var outro_camera := Vector3(10, 6, 18)
@export var briefing: PackedStringArray = PackedStringArray()
## Where the player stands when the intro ends.
@export var player_start := Vector3.ZERO
@export var player_yaw_degrees := 0.0
@export var objectives: Array[MissionObjective] = []
@export var complete_title := "MISSION COMPLETE"
@export var complete_subtitle := "Mission complete"
