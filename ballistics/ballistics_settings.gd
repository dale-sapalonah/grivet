class_name BallisticsSettings
extends Resource
## World-wide ballistics tuning and the surface table.
## data/ballistics/ballistics_settings.tres is the source of truth.

@export var gravity := 9.81
@export var max_bullets := 512
## Penetrations plus ricochets one bullet may go through before it stops.
@export var max_surface_events := 4
## Nudge past a surface so the next ray does not re-hit it (m).
@export var surface_epsilon := 0.01
@export var tracer_length := 3.0
@export var tracer_color := Color(1.0, 0.85, 0.5, 0.9)
## How long `ballistics.trace` keeps flight paths on screen (s).
@export var trace_persist_seconds := 4.0
## Ricochet angle scale for the lightest (impact_energy 0) and heaviest (1)
## rounds: low-momentum rounds deflect at steeper angles.
@export var ricochet_light_angle_multiplier := 1.5
@export var ricochet_heavy_angle_multiplier := 0.75

@export_group("Impact effects")
@export var hole_size := 0.05
## Concrete craters grow with energy up to this multiple of hole_size.
@export var crater_max_scale := 2.2
## Bullet holes are recycled oldest-first past this count.
@export var hole_pool_size := 200
## Particle bursts (sparks, splinters, chips) and dust puffs in flight at once.
@export var debris_pool_size := 20
@export var dust_pool_size := 10
@export var spark_count := 10
@export var spark_lifetime := 0.35
@export var spark_speed_min := 1.5
@export var spark_speed_max := 4.5
@export var splinter_count := 14
@export var splinter_lifetime := 0.7
@export var chip_count_heavy := 18
@export var dust_lifetime := 1.4

@export_group("Impact sound")
## Distant hits are heard later than they are seen (m/s).
@export var speed_of_sound := 343.0
@export var impact_sound_pool_size := 24
## Distinct takes per sound so repeated hits don't sound identical.
@export var impact_sound_variants := 2
## Mass and energy are rounded to this step to share generated sounds.
@export var impact_sound_step := 0.25
@export var impact_sound_unit_size := 8.0
@export var impact_sound_max_distance := 150.0
## At most impact_sounds_per_window per surface every impact_sound_window
## seconds, so a shotgun blast is one hit sound, not nine.
@export var impact_sound_window := 0.03
@export var impact_sounds_per_window := 2
@export var ricochet_volume_db := -6.0
## Volume and pitch at impact_energy 0 (light rounds) and 1 (heavy rounds).
@export var light_round_volume_db := -8.0
@export var light_round_pitch := 0.9
@export var heavy_round_pitch := 1.08

@export_group("Surfaces")
@export var default_surface: SurfaceMaterial
## Surface id (the collider's `surface` metadata) -> SurfaceMaterial.
@export var surfaces: Dictionary = {}


func surface(id: String) -> SurfaceMaterial:
	return surfaces.get(id, default_surface)
