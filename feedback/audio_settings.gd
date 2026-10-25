class_name AudioSettings
extends Resource
## Tuning for the soundscape (Soundscape autoload): gunshot layers by
## distance, bullet snaps, the enclosure-driven reverb, footsteps and the
## player-feedback cues. Sounds themselves are ProceduralAudio recipes.

@export_group("Players")
## Pooled 3D one-shot players (gunshot layers, snaps, footsteps).
@export var pool_size := 32
## Sounds further than this (m) from the listener are not played at all.
@export var max_hear_distance := 450.0

@export_group("Gunshots")
## Close layer (crack, body, mechanism) falls off like a near sound.
@export var shot_close_unit_size := 12.0
## Distant layer (low boom, rolling echoes) barely falls off: it is what a
## shot sounds like across the yard.
@export var shot_distant_unit_size := 90.0
## The distant layer starts to come in here (m) and has replaced the close
## layer's character by `shot_distant_full`.
@export var shot_distant_start := 15.0
@export var shot_distant_full := 110.0
## Distant layer level relative to the weapon's shot_volume_db.
@export var shot_distant_db := -3.0
## The player's own shot also gets a quiet rolling tail (outdoor echo).
@export var own_shot_tail_db := -14.0
@export var distant_shot_length := 1.6

@export_group("Bullet snaps")
## An enemy round passing within this (m) of the listener's head cracks past.
@export var snap_radius := 3.5
@export var snap_volume_db := -2.0
@export var snap_unit_size := 3.0
## Two snaps closer together than this (s) collapse into one.
@export var snap_min_interval := 0.045
@export var snap_variants := 4

@export_group("Acoustics")
## The listener's surroundings are re-measured this often (s) with rays.
@export var probe_interval := 0.25
@export var probe_rays := 8
## Rays reach this far (m); a miss counts as open space.
@export var probe_range := 40.0
## An upward ray hitting within this (m) means a roof overhead.
@export var roof_height := 9.0
## Reverb settles towards a new space at this rate (1/s).
@export var blend_speed := 3.0
## Wet level in the open and fully enclosed (alley between containers).
@export var open_wet := 0.12
@export var enclosed_wet := 0.32
@export var roof_wet_bonus := 0.12
## Room size for near walls and far walls.
@export var small_room := 0.25
@export var large_room := 0.85
## High-frequency loss: open air soaks up highs; steel walls throw them back.
@export var open_damping := 0.7
@export var enclosed_damping := 0.25
## Slap-back echo: pre-delay from the round trip to the walls, clamped (ms).
@export var min_predelay_ms := 12.0
@export var max_predelay_ms := 240.0
## Repeats of the slap (flutter) in the open and enclosed.
@export var open_echo_feedback := 0.35
@export var enclosed_echo_feedback := 0.15
@export var reverb_hipass := 0.15

@export_group("Footsteps")
@export var footstep_variants := 4
## Player step levels (dB) by gait.
@export var step_walk_db := -15.0
@export var step_sprint_db := -9.0
@export var step_crouch_db := -24.0
@export var step_unit_size := 4.0
## Soldiers: distance (m) per footstep, level, and how far they are played.
@export var soldier_step_length := 0.75
@export var soldier_step_db := -11.0
@export var soldier_run_step_db := -6.0
## Above this speed (m/s) a soldier's steps are running steps.
@export var soldier_run_speed := 3.5
@export var soldier_step_max_distance := 45.0
@export var soldier_step_unit_size := 5.0
## Height (m) of the ray that finds what is underfoot.
@export var ground_probe := 1.2

@export_group("Feedback cues")
@export var hit_confirm_db := -10.0
@export var kill_cue_db := -12.0
## Below this fraction of health the player breathes hard.
@export var low_health_fraction := 0.3
@export var breath_db := -14.0
@export var breath_period := 1.9
@export var breath_variants := 3
## A blast within this (m) dulls the world and rings the ears.
@export var deafen_radius := 9.0
## Longest ringing / muffling (s), at the blast itself.
@export var deafen_seconds := 3.5
## Low-pass cutoff (Hz) at full deafness; it opens back up as the ears recover.
@export var deafen_lowpass_hz := 500.0
@export var ear_ring_db := -12.0
