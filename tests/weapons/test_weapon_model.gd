extends "res://tests/framework/suite.gd"

const Model := preload("res://weapons/weapon_model.gd")
const KESTREL := preload("res://data/weapons/kestrel.tres")
const HAMMERHEAD := preload("res://data/weapons/hammerhead.tres")
const VANTA := preload("res://data/weapons/vanta.tres")
const DT := 1.0 / 120.0

var controls := Model.Controls.new()


func ready_weapon(definition: WeaponDefinition) -> WeaponModel:
	var weapon := Model.new(definition)
	run(weapon, definition.equip_time + DT)
	return weapon


## Runs the weapon for `seconds` plus one tick (timers that land exactly on a
## tick boundary need it after float accumulation), returning total shots.
## Press flags last one tick.
func run(weapon: WeaponModel, seconds: float) -> int:
	var shots := 0
	for i in roundi(seconds / DT) + 1:
		shots += weapon.update(controls, DT)
		controls.reload_pressed = false
		controls.inspect_pressed = false
	return shots


func pull_trigger(weapon: WeaponModel) -> int:
	controls.trigger = true
	var shots := run(weapon, DT)
	controls.trigger = false
	run(weapon, DT)
	return shots


func test_cannot_fire_while_equipping() -> void:
	var weapon := Model.new(KESTREL)
	controls.trigger = true
	assert_eq(run(weapon, KESTREL.equip_time * 0.5), 0)


func test_auto_fire_rate_matches_rpm() -> void:
	var weapon := ready_weapon(KESTREL)
	controls.trigger = true
	var shots := run(weapon, 1.0)
	var expected := KESTREL.rounds_per_minute / 60.0
	assert_true(absf(shots - expected) <= 1.0, "shots=%d expected~%.1f" % [shots, expected])


func test_semi_fires_once_per_pull() -> void:
	var weapon := ready_weapon(VANTA)
	controls.trigger = true
	assert_eq(run(weapon, 1.0), 1, "held trigger")
	controls.trigger = false
	run(weapon, 0.2)
	assert_eq(pull_trigger(weapon), 1, "second pull")


func test_pump_blocks_until_pumped() -> void:
	var weapon := ready_weapon(HAMMERHEAD)
	assert_eq(pull_trigger(weapon), 1, "first")
	assert_eq(weapon.state, Model.State.PUMPING, "pumping")
	assert_eq(pull_trigger(weapon), 0, "during pump")
	run(weapon, HAMMERHEAD.pump_time)
	assert_eq(pull_trigger(weapon), 1, "after pump")


func test_magazine_empties_and_trigger_starts_reload() -> void:
	var weapon := ready_weapon(KESTREL)
	controls.trigger = true
	assert_eq(run(weapon, 5.0), KESTREL.magazine_size, "whole mag")
	controls.trigger = false
	run(weapon, DT)
	pull_trigger(weapon)
	assert_eq(weapon.state, Model.State.RELOADING, "auto reload")
	assert_true(weapon.reload_is_empty, "empty reload")


func test_empty_reload_fills_magazine() -> void:
	var weapon := ready_weapon(KESTREL)
	weapon.ammo = 0
	controls.reload_pressed = true
	run(weapon, KESTREL.reload_empty_time + DT)
	assert_eq(weapon.ammo, KESTREL.magazine_size, "ammo")
	assert_eq(weapon.reserve, KESTREL.reserve_ammo - KESTREL.magazine_size, "reserve")


func test_tactical_reload_keeps_chambered_round() -> void:
	var weapon := ready_weapon(KESTREL)
	weapon.ammo = 10
	controls.reload_pressed = true
	run(weapon, KESTREL.reload_tactical_time + DT)
	assert_eq(weapon.ammo, KESTREL.magazine_size + 1)


func test_reload_limited_by_reserve() -> void:
	var weapon := ready_weapon(VANTA)
	weapon.ammo = 0
	weapon.reserve = 4
	controls.reload_pressed = true
	run(weapon, VANTA.reload_empty_time + DT)
	assert_eq(weapon.ammo, 4, "ammo")
	assert_eq(weapon.reserve, 0, "reserve")


func test_cannot_fire_while_reloading() -> void:
	var weapon := ready_weapon(KESTREL)
	weapon.ammo = 5
	controls.reload_pressed = true
	run(weapon, DT)
	controls.trigger = true
	assert_eq(run(weapon, KESTREL.reload_tactical_time * 0.5), 0)


func test_shell_reload_adds_one_at_a_time_and_can_be_interrupted() -> void:
	var weapon := ready_weapon(HAMMERHEAD)
	weapon.ammo = 2
	controls.reload_pressed = true
	run(weapon, HAMMERHEAD.reload_start_time + HAMMERHEAD.shell_insert_time * 2.0 + DT)
	assert_eq(weapon.ammo, 4, "two shells in")
	assert_eq(pull_trigger(weapon), 1, "trigger interrupts the reload and fires")
	assert_eq(weapon.state, Model.State.PUMPING, "pumping after the shot")
	assert_eq(weapon.ammo, 3, "ammo")


func test_sprinting_blocks_fire_then_recovers() -> void:
	var weapon := ready_weapon(KESTREL)
	controls.sprinting = true
	controls.trigger = true
	assert_eq(run(weapon, 0.5), 0, "while sprinting")
	controls.sprinting = false
	assert_eq(run(weapon, KESTREL.sprint_to_fire_time * 0.5), 0, "sprint-to-fire delay")
	assert_true(run(weapon, KESTREL.sprint_to_fire_time) > 0, "after delay")


func test_infinite_ammo_never_drains() -> void:
	var weapon := ready_weapon(KESTREL)
	weapon.infinite_ammo = true
	controls.trigger = true
	run(weapon, 5.0)
	assert_eq(weapon.ammo, KESTREL.magazine_size)


func test_inspect_is_cancelled_by_trigger() -> void:
	var weapon := ready_weapon(KESTREL)
	controls.inspect_pressed = true
	run(weapon, DT)
	assert_eq(weapon.state, Model.State.INSPECTING, "inspecting")
	controls.trigger = true
	run(weapon, DT)
	assert_eq(weapon.state, Model.State.READY, "cancelled")
