class_name GrenadeDefinition
extends Resource
## A throwable. data/grenades/<id>.tres is the source of truth.

@export var id := "frag"
@export var display_name := "Frag"
@export var fuse_time := 3.5
## The player's throw speed along the aim (m/s), plus a little loft.
@export var throw_speed := 16.0
@export var throw_loft := 3.0
## Strongest throw an enemy can make (m/s) when solving an arc to a target.
@export var max_throw_speed := 18.0
## Launch angles (degrees) tried when solving an arc, lowest first.
@export var arc_angle_min := 25.0
@export var arc_angle_max := 60.0
@export var mass := 0.4
@export var radius := 0.04
@export var bounce := 0.3
@export var friction := 0.7
@export var player_carry := 2

@export_group("Blast")
@export var blast_radius := 7.0
@export var max_damage := 160.0
## Damage = max_damage * (1 - distance / blast_radius) ^ falloff_power.
@export var falloff_power := 1.5
## Speed (m/s) the blast gives loose bodies (ragdoll parts) at the centre,
## the same for light and heavy parts so limbs don't fly off alone.
@export var blast_push_speed := 6.0
@export var fragment_count := 36
@export var fragment: WeaponDefinition
## How far enemies hear the blast (m).
@export var loudness := 150.0
@export var volume_db := 2.0
@export var shake_degrees := 3.0
@export var shake_radius := 15.0
