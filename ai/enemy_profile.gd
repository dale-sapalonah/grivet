class_name EnemyProfile
extends Resource
## Everything that makes one kind of enemy: weapon, toughness, senses, aim,
## fire discipline and tactics. One .tres per type under data/ai/; a new
## enemy type is a new file, not code.

enum Role {
	RIFLEMAN,  ## Holds cover at range, suppresses, flanks in pairs.
	RUSHER,    ## Closes distance through cover while others pin the target.
	MELEE,     ## Machete: sprints in weaving and strikes; ducks only when pinned.
}

enum Outfit {
	MILITARY,  ## Camouflage uniform, helmet, plate carrier, boots.
	CIVILIAN,  ## T-shirt, shorts, sandals, a bilum across the chest.
	POLICE,  ## Light-blue shirt, navy trousers and beret (needs body_model: soldier_police.glb).
}

@export var display_name := "Rifleman"
@export var role: Role = Role.RIFLEMAN
@export var weapon: WeaponDefinition
@export var health: HealthProfile
@export var outfit: Outfit = Outfit.MILITARY
@export var uniform_color := Color(0.33, 0.36, 0.28)
## Civilian outfits pick a shirt from these per soldier (uniform_color unused).
@export var shirt_colors: PackedColorArray = PackedColorArray()
@export var shorts_color := Color(0.12, 0.13, 0.16)
## Police: badge and buckle metal.
@export var badge_color := Color(0.85, 0.62, 0.2)
@export var gear_color := Color(0.14, 0.15, 0.13)
## Second and third camouflage colours (uniform_color is the first).
@export var camo_b := Color(0.22, 0.24, 0.17)
@export var camo_c := Color(0.45, 0.42, 0.32)
## Melanesian skin tones by default: the fight is in Port Moresby.
@export var skin_color := Color(0.33, 0.22, 0.16)
## Face covered (gear colour) instead of bare skin.
@export var balaclava := false
## A body modelled in Blender (tools/blender/build_soldier.py): one mesh per
## Mannequin part, vertex colours carrying material classes that are painted
## from this profile. Unset: the body is built in code.
@export var body_model: PackedScene

@export_group("Movement (m/s)")
@export var walk_speed := 2.0
@export var run_speed := 4.6
@export var crouch_speed := 1.5
## Moving between cover with the target in sight: advance this low (0 = upright,
## 1 = full crouch) at crouch_speed instead of walking upright. 0 = never.
@export var advance_crouch := 0.0
@export var turn_speed_degrees := 300.0

@export_group("Perception")
@export var sight_range := 70.0
@export var fov_degrees := 130.0
## Within this distance anything outside the view cone is still noticed (slower).
@export var peripheral_range := 6.0
## Awareness gained per second at visibility 1 (combat starts at awareness 1).
@export var awareness_gain := 1.8
@export var awareness_decay := 0.2
@export var suspicious_threshold := 0.3
@export var hearing_multiplier := 1.0
## Seconds without contact before the last known position is considered stale.
@export var lose_target_time := 8.0

@export_group("Aim")
## Delay between first seeing the target and the first shot.
@export var reaction_time := 0.45
@export var aim_error_degrees := 1.6
@export var aim_error_per_10m := 0.35
## The first burst after acquiring a target is wilder, giving the player a moment.
@export var first_burst_error_multiplier := 2.5
@export var first_burst_duration := 0.9
@export var moving_error_multiplier := 1.6
@export var target_moving_error_multiplier := 1.4
@export var suppressed_error_multiplier := 2.5
@export var aim_turn_degrees_per_second := 220.0

@export_group("Fire discipline")
@export var burst_min := 3
@export var burst_max := 6
@export var burst_pause_min := 0.35
@export var burst_pause_max := 0.9
## Damage scale against the player (fairness).
@export var damage_multiplier := 0.7
## Suppressive fire scatters this far (m) around the last known position.
@export var suppress_spread := 1.5

@export_group("Tactics")
## Distance band to the target this enemy likes to fight from.
@export var preferred_range_min := 12.0
@export var preferred_range_max := 35.0
@export var peek_time := 1.6
@export var hide_time := 1.4
@export var hide_time_suppressed := 3.0
## Suppression (0..1) above which it stops peeking and hugs cover.
@export var suppression_tolerance := 0.6
## Target pinned this long (s) before a flank is attempted.
@export var flank_after_pinned := 4.0
## Health share below which it falls back.
@export var retreat_health := 0.3
## Rushers charge straight in once this close (m).
@export var charge_range := 9.0
@export var grenade_count := 1
## Target camping in the same place this long (s) earns a grenade.
@export var grenade_camp_time := 6.0
@export var grenade_range_min := 8.0
@export var grenade_range_max := 30.0
@export var cover_search_radius := 20.0

@export_group("Death")
## Speed (m/s) the killing round adds to the struck body part, scaled by
## 0.5 + its energy. Real bullets carry little momentum: bodies slump, not fly.
@export var death_push_speed := 1.5
