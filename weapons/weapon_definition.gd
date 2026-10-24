class_name WeaponDefinition
extends Resource
## Everything that makes one weapon. One .tres per weapon under data/weapons/;
## adding a weapon means adding a file here, not code.

enum FireMode { AUTO, SEMI, PUMP }
enum ReloadMode { MAGAZINE, PER_SHELL }
## Which placeholder shape set the view model builds.
enum ViewStyle { RIFLE, SHOTGUN, PISTOL }

@export var id := ""
@export var display_name := ""

@export_group("Action")
@export var fire_mode: FireMode = FireMode.AUTO
@export var rounds_per_minute := 600.0
@export var magazine_size := 30
@export var reserve_ammo := 90
## A tactical reload keeps the chambered round (magazine_size + 1).
@export var chamber_round := true

@export_group("Timing (s)")
@export var reload_mode: ReloadMode = ReloadMode.MAGAZINE
@export var reload_tactical_time := 2.0
@export var reload_empty_time := 2.5
## PER_SHELL: time before the first shell goes in.
@export var reload_start_time := 0.4
@export var shell_insert_time := 0.5
@export var pump_time := 0.6
@export var equip_time := 0.5
@export var inspect_time := 2.5
## Delay between leaving a sprint and being able to fire.
@export var sprint_to_fire_time := 0.2
@export var ads_time := 0.25

@export_group("Projectile")
@export var pellets := 1
@export var pellet_spread_degrees := 0.0
@export var damage := 25.0
@export var damage_falloff_start := 20.0
@export var damage_falloff_end := 50.0
@export var min_damage_multiplier := 0.7
## Metres per second.
@export var muzzle_velocity := 800.0
@export var gravity_scale := 1.0
@export var max_range := 300.0
## Spent by surfaces the bullet passes through (see SurfaceMaterial).
@export var penetration_power := 20.0

@export_group("Recoil")
## Per-shot aim kick in degrees: x = up, y = right. Same every magazine.
@export var recoil_pattern := PackedVector2Array([Vector2(0.5, 0.0)])
## Once past the end, the pattern repeats from this index.
@export var recoil_loop_from := 0
## Pause after which the pattern starts over.
@export var recoil_reset_time := 0.3
@export var recoil_ads_multiplier := 0.7
## Camera-only kick (degrees) that springs back; does not move the aim.
@export var visual_kick_degrees := 1.0
## View model push-back per shot (m).
@export var view_kick_back := 0.03

@export_group("Spread (degrees)")
@export var spread_hip := 3.0
@export var spread_ads := 0.2
@export var spread_moving_add := 2.0
@export var spread_crouch_multiplier := 0.8
@export var spread_prone_multiplier := 0.6
@export var spread_per_shot := 0.25
@export var spread_max_bloom := 2.0
@export var spread_recovery_per_second := 6.0
## Share of bloom still applied when fully aimed.
@export var bloom_ads_multiplier := 0.3

@export_group("View model (m)")
@export var view_style: ViewStyle = ViewStyle.RIFLE
@export var ads_fov_multiplier := 0.8
@export var hip_offset := Vector3(0.16, -0.17, -0.32)
## How far in front of the eye the rear sight sits when aiming.
@export var ads_distance := 0.2
@export var sprint_offset := Vector3(0.08, -0.22, -0.28)
## Elbows, from each wrist, in view space: where the forearms run to.
@export var right_elbow_offset := Vector3(0.06, -0.2, 0.26)
@export var left_elbow_offset := Vector3(-0.14, -0.22, 0.22)
@export var sprint_rotation_degrees := Vector3(-12.0, 35.0, 10.0)
@export var receiver_size := Vector3(0.05, 0.08, 0.36)
@export var barrel_length := 0.3
@export var barrel_radius := 0.012
@export var magazine_mesh_size := Vector3(0.03, 0.14, 0.06)
@export var has_pump := false
@export var body_color := Color(0.16, 0.17, 0.16)
## Grip, stock and handguard (polymer or wood).
@export var furniture_color := Color(0.1, 0.1, 0.1)
@export var sway_amount := 0.0006
@export var sway_limit := 0.03

@export_group("Casings")
@export var casing_ejects := true
## Pump guns throw the hull when racked, not when fired.
@export var casing_eject_on_pump := false
@export var casing_radius := 0.0045
@export var casing_length := 0.045
@export var casing_color := Color(0.78, 0.6, 0.25)
@export var casing_metallic := 0.9
## Gun-local throw (m/s): x = right, y = up, z = back toward the shooter.
@export var casing_eject_velocity := Vector3(2.2, 1.4, 0.5)
## Ring of the case itself; brass is bright, plastic hulls are low.
@export var casing_clink_hz := 4200.0
@export var casing_volume_db := -16.0
## Plastic shotgun hull (hollow tock with a brass-base tick) instead of a
## ringing brass case.
@export var casing_hollow := false

@export_group("Placeholder audio")
@export var shot_sound_length := 0.25
@export var shot_thump_hz := 70.0
@export var shot_volume_db := -6.0
## How far (m) enemies hear this weapon fire.
@export var shot_loudness := 90.0
## Brightness of the action's clicks (magazine, bolt, pump).
@export var mech_click_hz := 3000.0
@export var mech_volume_db := -10.0
## 0..1 how hard a round hits for impact sounds: light calibres give a dull
## thud, heavy ones a sharper crack.
@export var impact_energy := 0.6
