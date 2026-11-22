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
@export_group("Knife")
## The knife hand comes up from knife_rest, stabs out to knife_thrust at the
## end of the windup and goes back; the gun drops out of view meanwhile.
@export var knife_rest := Vector3(0.25, -0.3, -0.25)
@export var knife_thrust := Vector3(0.1, -0.15, -0.5)
@export var knife_gun_drop := 0.45
## Share of the strike spent reaching out (the rest is the pull back).
@export var knife_reach_share := 0.3
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

## How far a pistol's slide runs back at the peak of a shot's recoil (m).
@export var slide_travel := 0.018
## Scales the gun models' metalness in first person: fully metallic parts
## mirror the dusk sky and read black this close.
@export var gun_metallic_scale := 0.5
## A fill light on the gun and arms only (view space, above right of the eye).
@export var view_fill_color := Color(1.0, 0.92, 0.82)
@export var view_fill_energy := 0.9
@export var view_fill_range := 1.2
@export var view_fill_position := Vector3(0.25, 0.2, 0.05)

@export_group("Rigged arms")
## The player's arms (a rigged model, SkinnedViewArms); unset: shapes (ViewArms).
@export var arms_model: PackedScene
## Share of a grip's curl the finger joints bend (the model's fingers are longer).
@export var arms_curl_scale := 0.55
## The trigger finger's bend, laid along the frame.
@export var arms_trigger_curl_degrees := 25.0
## The thumb's bend across the grip.
@export var arms_thumb_curl_degrees := 50.0
## The palm surface below the hand bones (m) and its gap to the grip.
@export var arms_palm_depth := 0.012
@export var arms_palm_gap := 0.012
## The right shoulder in view space (m; the left mirrors it): the arms reach
## from here (two-bone IK). Further than the arm reaches, it follows the hand.
@export var arms_shoulder := Vector3(0.19, -0.27, 0.1)
## Which way the elbows bend (view space, the right one; x mirrors): down and out.
@export var arms_elbow_pole := Vector3(0.5, -1.0, 0.1)
## Share of the hand's twist the forearm takes.
@export var arms_forearm_twist := 0.5
## A support hand rolled about the barrel from its hold (degrees): under, not beside.
@export var arms_support_roll_degrees := 45.0
## Closing the clip-posed hands on the gun (SkinnedViewArms): a finger's
## radius for the contact test, the gap left between palm skin and the gun,
## how far either side of the palm to look for the gun, the step each joint
## closes by, and each joint's limit past the clip's shape (degrees: base,
## middle, tip).
@export var arms_finger_radius := 0.0075
@export var arms_palm_skin := 0.009
@export var arms_palm_search := 0.06
@export var arms_close_step_degrees := 2.0
## Finger joints (Docs/HandBiomechanics.md): ranges from straight (degrees),
## the tip joint's coupling to the middle joint (about 0.7 measured), the
## knuckle's share while both close together, and how much of the first
## phalanx (from the knuckle) is inside the palm and not tested for contact.
@export var arms_mcp_max_degrees := 85.0
@export var arms_pip_max_degrees := 100.0
@export var arms_dip_max_degrees := 75.0
@export var arms_dip_pip_coupling := 0.7
@export var arms_mcp_share := 0.6
@export var arms_knuckle_skip := 0.3
## Added to each phalanx's measured flesh in the contact test (m): a skin's gap.
@export var arms_flesh_margin := 0.001
## Wrapping a finger: the angle step of its pose search (degrees) and how
## far past the held part to start the ray that finds its far side (m).
@export var arms_wrap_step_degrees := 3.0
@export var arms_wrap_search := 0.12
## How far a hand may back off its grip to clear the gun (m).
@export var arms_clear_max := 0.025
## No phalanx is taken as thicker than this from its bone (m).
@export var arms_flesh_max := 0.016
## Which share of a phalanx's skin vertices the contact tube must enclose.
@export var arms_flesh_percentile := 0.9
## Fingers close their joints together in this ratio (base, middle, tip),
## then each settles up to arms_settle_degrees more onto the surface.
@export var arms_curl_ratio := Vector3(1.0, 1.1, 0.55)
@export var arms_settle_degrees := 40.0
## Share of that the fingertip joint may settle (it lies along the surface).
@export var arms_tip_settle_share := 0.4
## How far a clip-shaped finger may open to get clear of the gun before closing.
@export var arms_open_max_degrees := 45.0
## How far down the index finger's last segment its pad is (0..1), the
## point put on the trigger.
@export var arms_trigger_pad := 0.85
@export var arms_finger_max_degrees := Vector3(60, 70, 60)
@export var arms_thumb_max_degrees := Vector3(40, 60, 70)
## The support thumb swung out round the left side of the handguard before it
## closes (degrees: about its curl axis, then spread about the palm normal).
@export var arms_support_thumb_swing := Vector2(8, -45)
## Share of the thumb limits the support thumb may still close by on its side.
@export var arms_support_thumb_close := 0.3
## A pistol's shooting thumb swung forward along the frame (as the support one).
@export var arms_pistol_thumb_swing := Vector2(-30, 0)
## The shooting hand tilted up at the wrist toward the gun (degrees).
@export var arms_wrist_lift_degrees := 15.0
## The shooting hand moved back along the gun and down its grip (m, gun
## frame), so the grip sits inside the closed fingers.
@export var arms_grip_back := 0.02
@export var arms_grip_down := 0.0
## The shooting hand turned outward about the grip (degrees).
@export var arms_grip_yaw_degrees := 15.0
## A rifle or shotgun shooting thumb swung forward round the grip's far side.
@export var arms_grip_thumb_swing := Vector2(0, 35)
## Thumb segments shortened to this share of the model's (both hands).
@export var arms_thumb_length := 0.72
## A pistol's support hand wraps the shooting hand's fist: a cylinder this
## wide and long round the grip (m).
@export var arms_cup_radius := 0.042
@export var arms_cup_height := 0.11
