extends "res://tests/framework/suite.gd"

const PLAYER := preload("res://data/damage/player.tres")
const RIFLEMAN := preload("res://data/damage/rifleman.tres")
const Zone := DamageModel.Zone


func test_zone_multipliers() -> void:
	var model := DamageModel.new(RIFLEMAN)
	model.armor = 0.0
	model.apply(10.0, Zone.HEAD)
	assert_approx(model.health, RIFLEMAN.max_health - 10.0 * RIFLEMAN.head_multiplier, 1e-4, "head")
	var legs := DamageModel.new(RIFLEMAN)
	legs.apply(10.0, Zone.LEGS)
	assert_approx(legs.health, RIFLEMAN.max_health - 10.0 * RIFLEMAN.legs_multiplier, 1e-4, "legs")


func test_plates_soak_torso_hits_until_broken() -> void:
	var model := DamageModel.new(RIFLEMAN)
	var result := model.apply(30.0, Zone.TORSO)
	assert_eq(result.health_damage, 0.0, "plate takes it all")
	assert_approx(model.armor, RIFLEMAN.plate_points - 30.0, 1e-4, "plate worn")
	result = model.apply(30.0, Zone.TORSO)
	assert_approx(result.armor_damage, RIFLEMAN.plate_points - 30.0, 1e-4, "plate breaks")
	assert_approx(result.health_damage, 30.0 - (RIFLEMAN.plate_points - 30.0), 1e-4, "overflow to health")


func test_abdomen_is_not_armoured() -> void:
	var model := DamageModel.new(RIFLEMAN)
	var result := model.apply(30.0, Zone.ABDOMEN)
	assert_eq(result.armor_damage, 0.0, "plates don't cover it")
	assert_approx(result.health_damage, 30.0 * RIFLEMAN.abdomen_multiplier, 1e-4, "straight to health")


func test_close_buckshot_kills_an_armoured_rifleman_in_one_or_two_shots() -> void:
	# A realistic close-range spread: pellets across chest, abdomen and arms.
	var hammerhead := preload("res://data/weapons/hammerhead.tres")
	var model := DamageModel.new(RIFLEMAN)
	var zones := [Zone.TORSO, Zone.TORSO, Zone.TORSO, Zone.ABDOMEN, Zone.ABDOMEN, Zone.ARMS, Zone.TORSO, Zone.LEGS]
	var shots := 0
	while not model.dead and shots < 5:
		for zone in zones:
			model.apply(hammerhead.damage, zone)
		shots += 1
	assert_true(shots <= 2, "shots to kill: %d" % shots)


func test_headshots_bypass_plates() -> void:
	var model := DamageModel.new(RIFLEMAN)
	model.apply(20.0, Zone.HEAD)
	assert_eq(model.armor, RIFLEMAN.plates_start * RIFLEMAN.plate_points, "armour untouched")
	assert_true(model.health < RIFLEMAN.max_health, "health hit")


func test_kill_and_no_damage_after_death() -> void:
	var model := DamageModel.new(RIFLEMAN)
	var result := model.apply(1000.0, Zone.HEAD)
	assert_true(result.killed and model.dead, "killed")
	assert_eq(model.apply(10.0, Zone.TORSO).health_damage, 0.0, "dead bodies take no more")


func test_rifle_time_to_kill_is_reasonable() -> void:
	# Kestrel body shots against an armoured rifleman: 5-7 rounds; headshots: 2.
	var kestrel := preload("res://data/weapons/kestrel.tres")
	var body := DamageModel.new(RIFLEMAN)
	var shots := 0
	while not body.dead:
		body.apply(kestrel.damage, Zone.TORSO)
		shots += 1
	assert_true(shots >= 5 and shots <= 7, "torso shots to kill: %d" % shots)
	var head := DamageModel.new(RIFLEMAN)
	shots = 0
	while not head.dead:
		head.apply(kestrel.damage, Zone.HEAD)
		shots += 1
	assert_eq(shots, 2, "headshots to kill")


func test_plates_insert_up_to_slots() -> void:
	var model := DamageModel.new(PLAYER)
	model.armor = 0.0
	for i in PLAYER.plate_slots:
		assert_true(model.add_plate(), "plate %d fits" % i)
	assert_true(not model.add_plate(), "full")
	assert_eq(model.armor, PLAYER.plate_slots * PLAYER.plate_points, "max armour")


func test_heal_caps_at_max() -> void:
	var model := DamageModel.new(PLAYER)
	model.armor = 0.0
	model.apply(50.0, Zone.TORSO)
	model.heal(1000.0)
	assert_eq(model.health, PLAYER.max_health)
