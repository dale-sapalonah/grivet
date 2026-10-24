class_name MovementTuning
extends Resource
## Every movement number. data/player/movement_tuning.tres is the source of
## truth; the defaults here only matter for a freshly created resource.

@export_group("Speeds (m/s)")
@export var walk_speed := 4.0
@export var sprint_speed := 6.4
@export var tac_sprint_speed := 8.0
@export var crouch_speed := 2.4
@export var prone_speed := 0.9
@export var ads_speed_multiplier := 0.6
## Forward input (0..1) needed to start and keep sprinting.
@export var sprint_forward_threshold := 0.5

@export_group("Acceleration (m/s²)")
@export var ground_acceleration := 45.0
@export var ground_deceleration := 35.0
@export var air_acceleration := 6.0
@export var gravity := 18.0
@export var jump_velocity := 5.2

@export_group("Tactical sprint (s)")
@export var tac_sprint_duration := 2.5
@export var tac_sprint_cooldown := 4.0

@export_group("Slide")
@export var slide_min_speed := 5.5
@export var slide_boost := 1.8
@export var slide_friction := 5.0
@export var slide_duration := 0.9
@export var slide_end_speed := 2.5
@export var slide_cooldown := 0.5

@export_group("Body (m)")
@export var radius := 0.3
@export var stand_height := 1.8
@export var crouch_height := 1.2
@export var prone_height := 0.6
@export var stand_eye_height := 1.65
@export var crouch_eye_height := 1.05
@export var prone_eye_height := 0.42
@export var stance_blend_speed := 10.0
@export var step_height := 0.35
@export var floor_snap := 0.3
@export var max_slope_degrees := 46.0
## Gap kept between headroom probes and the floor/walls.
@export var probe_margin := 0.05

@export_group("Mantle")
@export var mantle_min_height := 0.5
@export var mantle_max_height := 1.9
@export var mantle_reach := 0.8
@export var mantle_duration := 0.45
## Share of the mantle spent rising before moving forward onto the ledge.
@export var mantle_rise_fraction := 0.7
## Minimum dot between a ledge's surface normal and up.
@export var mantle_min_ledge_flatness := 0.7

@export_group("Lean")
@export var lean_speed := 6.0

@export_group("Landing")
@export var hard_landing_speed := 9.0
@export var hard_landing_slow_time := 0.35
@export var hard_landing_speed_multiplier := 0.5

@export_group("Death and respawn")
@export var respawn_delay := 3.0
## Hits do no damage for this long after spawning, and enemies lose track of you.
@export var spawn_protection_seconds := 3.0
## Below this height the player has fallen out of the level and respawns.
@export var fall_reset_height := -20.0
@export var death_eye_height := 0.3
@export var death_roll_degrees := 35.0
@export var death_blend_speed := 4.0

@export_group("Prone hitbox (body lies along the view)")
@export var prone_head_offset := Vector3(0, 0.3, -0.45)
@export var prone_torso_offset := Vector3(0, 0.22, 0.0)
@export var prone_legs_offset := Vector3(0, 0.15, 0.7)

@export_group("Debug")
@export var noclip_speed := 12.0
