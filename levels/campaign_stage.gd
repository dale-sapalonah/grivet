class_name CampaignStage
extends Resource
## One stage of the campaign: where the player starts, which spawn markers
## (metadata `level` = `marker_level`) field the enemy, and how sharp they
## are. Multipliers scale each spawned soldier's EnemyProfile.

@export var title := ""
## Line shown under the title.
@export var subtitle := ""
@export var marker_level := 1
## Player start: position, and facing (degrees, 0 = north / -Z).
@export var player_start := Vector3(0, 0, 26)
@export var player_yaw_degrees := 0.0

@export_group("Difficulty")
## Below 1 = more accurate.
@export var aim_error_multiplier := 1.0
## Below 1 = quicker on the trigger.
@export var reaction_multiplier := 1.0
@export var damage_multiplier := 1.0
## Above 1 = spots the player sooner.
@export var awareness_multiplier := 1.0
