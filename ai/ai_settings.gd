class_name AiSettings
extends Resource
## World-wide AI tuning. data/ai/ai_settings.tres is the source of truth.

@export_group("Perception")
## Sight checks per second per soldier (staggered across soldiers).
@export var perception_hz := 8.0
## Decisions (facts, brain, the action's plan) per second. Movement and the
## trigger still run every physics tick; thinking doesn't need 120 Hz.
@export var think_hz := 30.0
## Beyond this (m) from the player a soldier is posed every other frame.
@export var pose_lod_distance := 40.0
## Beyond this (m) a soldier casts no shadow (a shadow pass per soldier part).
@export var shadow_lod_distance := 25.0
## Allies within this distance learn what a spotter sees.
@export var share_radius := 30.0
@export var stance_visibility_stand := 1.0
@export var stance_visibility_crouch := 0.65
@export var stance_visibility_prone := 0.35
@export var moving_visibility := 1.3
@export var still_visibility := 0.8
## Distance (m) at which visibility halves.
@export var visibility_half_distance := 15.0

@export_group("Hearing (m)")
## How far a shot is heard is its weapon's shot_loudness; within this share
## of that the listener knows where the shooter is, beyond it only roughly.
@export var hearing_precise_fraction := 0.5
@export var heard_position_error := 6.0

@export_group("Suppression")
## Rounds passing within this distance (m) of a soldier suppress them.
@export var near_miss_radius := 1.6
@export var near_miss_suppression := 0.3
@export var impact_near_radius := 2.5
@export var impact_near_suppression := 0.15
@export var suppression_decay := 0.35

@export_group("Under fire")
## Suppression added by taking a hit.
@export var hit_suppression := 0.6
## A soldier counts as under fire this long (s) after a hit or near miss.
@export var under_fire_memory := 1.5
## Cover the enemy can see into is avoided for this long (s).
@export var compromised_block_seconds := 4.0
## Running under fire in the open weaves this far either side (degrees)...
@export var weave_degrees := 25.0
## ...this many times a second.
@export var weave_hz := 1.1
## Peek and hide times vary by up to this share either way.
@export var peek_jitter := 0.35
## The target counts as facing a soldier within this angle of its aim (degrees).
@export var facing_cone_degrees := 25.0
## Rushers charge regardless inside this distance (m)...
@export var point_blank_range := 4.0
## ...and circle the target rather than run into it inside this one.
@export var close_strafe_range := 5.0

@export_group("Cover map")
@export var cover_grid_spacing := 1.0
## On a level with several floors, a navmesh point within this (m) of a
## floor's height belongs to it.
@export var cover_floor_tolerance := 1.2
## Cover more than this (m) above or below a soldier is on another storey:
## not considered (a stair climb away, and "hidden" only by the floor slab).
@export var cover_max_climb := 2.5
@export var cover_probe_length := 0.9
## Half cover must be solid at this height (waist): a hunched soldier hides behind it.
@export var cover_low_height := 0.95
@export var cover_high_height := 1.55
## Cover must block rays this far (m) either side of a soldier's middle too:
## a thin column or pole hides less than a wall.
@export var cover_body_half_width := 0.25
## A cover direction protects against threats within this angle of it.
@export var cover_protect_angle := 40.0
@export var half_cover_value := 0.6
@export var peek_offset := 0.7
## How many top-scored candidates get a real line-of-sight check.
@export var cover_candidates_checked := 6
## A path must end within this distance (m) of a cover point for it to count as reachable.
@export var cover_reach_tolerance := 0.6
## After a failed cover request, wait this long (s) before asking for that kind again.
@export var cover_retry_seconds := 2.0

@export_group("Cover scoring")
@export var protection_weight := 2.0
@export var travel_cost_per_metre := 0.08
@export var too_close_cost_per_metre := 0.15
@export var too_far_cost_per_metre := 0.08
@export var occupied_cost := 5.0
@export var flank_weight := 2.0
## A flanking position must open at least this angle (degrees) around the threat.
@export var flank_min_angle := 45.0

@export_group("Decisions")
## Seconds a non-urgent decision is kept before it may change.
@export var decision_commit_time := 0.8
## Reload behind cover once the magazine is below this share (and no target in sight).
@export var reload_in_cover_below := 0.3
@export var flank_max_suppression := 0.3
@export var flank_min_health := 0.5
## Seconds after a flank before the same soldier may flank again.
@export var flank_cooldown := 15.0
## Flank cover is searched this many times further than ordinary cover.
@export var flank_search_multiplier := 2.0
## Keep suppressing a last known position this long after losing sight (s).
@export var suppress_memory := 4.0
## Target counts as pinned while it stays within this distance (m).
@export var pinned_radius := 2.5

@export_group("Coordination")
@export var max_flankers := 1
@export var grenade_cooldown := 8.0
@export var max_corpses := 10
## Stragglers: with this many soldiers or fewer left and no contact (seen, or
## anyone shot) for straggler_reveal_seconds, the HUD marks them and they come
## hunting the player, told where the player is every straggler_hunt_interval.
@export var straggler_count := 3
@export var straggler_reveal_seconds := 25.0
@export var straggler_hunt_interval := 8.0
## A corpse stops simulating (freezes where it lies) once it has settled, or
## this long after death at most (s): jointed ragdolls jitter and never sleep,
## and ten of them at 120 ticks/s lagged the game. Blasts wake them.
@export var corpse_freeze_after := 5.0
@export var stuck_seconds := 2.5
## A cover point someone failed to reach is skipped for this long (s).
@export var blocked_cover_seconds := 10.0

@export_group("Shouts")
## What the enemy shouts and how often (Tok Pisin lines with their voices).
@export var shouts: ShoutBook

@export_group("Squadmate")
## Campaign maps field the player's squadmate (the `squad.off` command and
## the combat probe turn it off: the enemy AI is tested against the player alone).
@export var squad_enabled := true
## The player's squadmate keeps between these distances (m) of the player,
## off the player's shoulder (follow_side_offset m to the side).
@export var squad_follow_min := 2.5
@export var squad_follow_max := 6.0
@export var squad_follow_side_offset := 2.0
## Engages enemies it can see within this range (m), sight checked squad_sight_hz times a second.
@export var squad_engage_range := 55.0
@export var squad_sight_hz := 5.0
## Holds fire while the player is within this distance (m) of its line of fire.
@export var squad_friendly_fire_clearance := 1.2
## Shot down it stays down this long, then gets back up with this share of its health.
@export var squad_downed_seconds := 12.0
@export var squad_revive_health := 0.6
## Further than this from the player (m) and out of the player's sight, it catches up at once.
@export var squad_regroup_distance := 40.0

@export_group("Muzzle flash")
## Enemy muzzle flashes light up their surroundings: a give-away at dusk.
@export var flash_energy := 10.0
@export var flash_range := 10.0
@export var flash_time := 0.05
@export var flash_size := 0.4
