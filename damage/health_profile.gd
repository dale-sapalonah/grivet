class_name HealthProfile
extends Resource
## How much punishment a body takes and how it recovers. One .tres per kind
## of body (player, rifleman, rusher) under data/damage/.

@export var max_health := 100.0
## Seconds without damage before health regenerates; 0 = no regeneration.
@export var regen_delay := 4.0
@export var regen_per_second := 40.0

@export_group("Armour plates (torso)")
@export var plate_slots := 3
@export var plate_points := 50.0
@export var plates_start := 3
## Spare plates carried, inserted with the plate key (player) over plate_insert_time.
@export var plates_carried := 0
@export var plate_insert_time := 1.0
## Headshots go straight to health.
@export var headshots_bypass_armor := true
## Fraction of a round stopped by a plate that still reaches health (blunt
## trauma: bruising, cracked ribs). Rounds that miss the plate do full damage.
@export var blunt_trauma := 0.0

@export_group("Hit zone damage multipliers")
@export var head_multiplier := 2.5
@export var torso_multiplier := 1.0
@export var arms_multiplier := 0.75
@export var legs_multiplier := 0.75
@export var abdomen_multiplier := 1.0
