class_name CameraTuning
extends Resource
## First-person camera feel. data/player/camera_tuning.tres is the source of truth.

@export_group("Look")
## Radians of rotation per mouse pixel.
@export var mouse_sensitivity := 0.0022
@export var ads_sensitivity_multiplier := 0.7
@export var pitch_limit_degrees := 88.0

@export_group("Field of view (vertical degrees)")
@export var base_fov := 65.0
@export var sprint_fov_add := 4.0
@export var tac_sprint_fov_add := 8.0
@export var slide_fov_add := 6.0
@export var ads_fov_multiplier := 0.8
@export var fov_blend_speed := 8.0

@export_group("Head bob (m)")
## Distance covered per footstep; one vertical bob per step.
@export var step_length := 0.8
@export var bob_walk := 0.02
@export var bob_sprint := 0.04
@export var bob_tac_sprint := 0.055
@export var bob_crouch_multiplier := 0.6
@export var bob_prone_multiplier := 1.2
@export var bob_ads_multiplier := 0.25
@export var bob_blend_speed := 6.0
## Below this horizontal speed (m/s) the bob fades out.
@export var bob_min_speed := 0.1

@export_group("Lean and roll")
@export var lean_offset := 0.45
@export var lean_angle_degrees := 12.0
## Space kept between the leaning camera and a wall.
@export var lean_wall_margin := 0.15
@export var strafe_roll_degrees := 1.2
@export var roll_blend_speed := 8.0

@export_group("Weapon kick (camera only)")
@export var kick_spring := 220.0
@export var kick_damping := 22.0
## Converts a weapon's visual_kick_degrees into spring velocity.
@export var kick_impulse := 33.0

@export_group("Landing dip")
@export var landing_min_speed := 4.0
@export var landing_max_speed := 14.0
@export var landing_kick := 0.1
@export var landing_spring := 140.0
@export var landing_damping := 16.0
