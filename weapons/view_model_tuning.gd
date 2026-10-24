class_name ViewModelTuning
extends Resource
## How the first-person gun moves, shared by every weapon.
## data/weapons/view_model_tuning.tres is the source of truth.

@export var pose_blend_speed := 14.0
@export_group("Kick spring")
@export var kick_spring := 260.0
@export var kick_damping := 24.0
## Converts a weapon's kick (m / degrees) into spring velocity.
@export var kick_impulse := 30.0
@export_group("Animation")
@export var equip_drop := 0.3
@export var reload_tilt_degrees := 28.0
@export var reload_magazine_drop := 0.25
@export var inspect_yaw_degrees := 50.0
@export var inspect_roll_degrees := 35.0
@export var pump_travel := 0.09

@export_group("Animation timing (share of the state)")
## Magazine leaves between these points (the release click plays at the start)...
@export var magazine_out_start := 0.15
@export var magazine_out_end := 0.45
## ...and goes back in between these (the seat click plays at the end).
@export var magazine_in_start := 0.6
@export var magazine_in_end := 0.85
## Empty reloads finish with the bolt going home here.
@export var bolt_release_at := 0.92
## Pump travels back until here (rear-stop clack, hull ejects)...
@export var pump_back_end := 0.4
## ...and forward between these (locking "CHK" at the end).
@export var pump_forward_start := 0.55
@export var pump_forward_end := 0.88
@export_group("Muzzle flash")
@export var flash_time := 0.05
@export var flash_energy := 4.0
@export var flash_range := 6.0
@export var flash_size := 0.14
@export_group("Arms")
@export var glove_color := Color(0.55, 0.45, 0.32)
@export var glove_pad_color := Color(0.36, 0.3, 0.21)
@export var skin_color := Color(0.55, 0.4, 0.31)
@export var sleeve_camo_a := Color(0.47, 0.42, 0.33)
@export var sleeve_camo_b := Color(0.32, 0.3, 0.22)
@export var sleeve_camo_c := Color(0.58, 0.53, 0.42)
## The support hand leaves the weapon for the magazine this long before the
## magazine starts out, and returns after it is seated (share of the reload).
@export var reload_hand_lead := 0.12

@export_group("Iron sights (m)")
@export var sight_post_height := 0.02
## Fraction of the post height that sits below the sight line.
@export var sight_line_fraction := 0.85
