extends "res://tests/framework/suite.gd"

const Model := preload("res://weapons/weapon_model.gd")
const KESTREL := preload("res://data/weapons/kestrel.tres")
const DT := 1.0 / 120.0
const WEAPON_FILES := ["kestrel", "hammerhead", "vanta"]


func fire_burst(seconds: float) -> Array[Vector2]:
	var weapon := Model.new(KESTREL)
	var controls := Model.Controls.new()
	for i in roundi((KESTREL.equip_time + DT) / DT):
		weapon.update(controls, DT)
	controls.trigger = true
	var kicks: Array[Vector2] = []
	for i in roundi(seconds / DT):
		weapon.update(controls, DT)
		kicks.append_array(weapon.last_kicks)
	return kicks


func test_recoil_pattern_repeats_exactly() -> void:
	var first := fire_burst(2.0)
	var second := fire_burst(2.0)
	assert_true(first.size() >= 20, "burst long enough: %d" % first.size())
	assert_eq(first, second)


func test_pattern_loops_after_the_end() -> void:
	var weapon := Model.new(KESTREL)
	var size := KESTREL.recoil_pattern.size()
	assert_eq(weapon.recoil_kick(size), KESTREL.recoil_pattern[KESTREL.recoil_loop_from], "first looped")
	assert_eq(weapon.recoil_kick(size + 1), KESTREL.recoil_pattern[KESTREL.recoil_loop_from + 1], "second looped")


func test_pattern_restarts_after_pause() -> void:
	var weapon := Model.new(KESTREL)
	var controls := Model.Controls.new()
	for i in roundi((KESTREL.equip_time + DT) / DT):
		weapon.update(controls, DT)
	controls.trigger = true
	for i in roundi(0.5 / DT):
		weapon.update(controls, DT)
	assert_true(weapon.recoil_index > 0, "advanced")
	controls.trigger = false
	for i in roundi((KESTREL.recoil_reset_time + 0.05) / DT):
		weapon.update(controls, DT)
	assert_eq(weapon.recoil_index, 0, "reset")


func test_aiming_and_stance_tighten_spread() -> void:
	var weapon := Model.new(KESTREL)
	var hip := weapon.spread_degrees(0.0, 0.0, 1.0)
	var aimed := weapon.spread_degrees(1.0, 0.0, 1.0)
	var moving := weapon.spread_degrees(0.0, 1.0, 1.0)
	var crouched := weapon.spread_degrees(0.0, 0.0, KESTREL.spread_crouch_multiplier)
	assert_approx(hip, KESTREL.spread_hip, 1e-4, "hip")
	assert_approx(aimed, KESTREL.spread_ads, 1e-4, "aimed")
	assert_true(moving > hip, "moving widens")
	assert_true(crouched < hip, "crouch tightens")


func test_sustained_fire_blooms_then_recovers() -> void:
	var weapon := Model.new(KESTREL)
	var controls := Model.Controls.new()
	for i in roundi((KESTREL.equip_time + DT) / DT):
		weapon.update(controls, DT)
	controls.trigger = true
	for i in roundi(0.5 / DT):
		weapon.update(controls, DT)
	assert_true(weapon.spread_degrees(0.0, 0.0, 1.0) > KESTREL.spread_hip, "bloomed")
	controls.trigger = false
	for i in roundi(1.0 / DT):
		weapon.update(controls, DT)
	assert_eq(weapon.bloom, 0.0, "recovered")


func test_every_weapon_file_is_sane() -> void:
	for id: String in WEAPON_FILES:
		var definition := load("res://data/weapons/%s.tres" % id) as WeaponDefinition
		assert_true(definition != null, "%s loads" % id)
		if definition == null:
			continue
		assert_eq(definition.id, id, "%s id matches file" % id)
		assert_true(definition.rounds_per_minute > 0.0, "%s rpm" % id)
		assert_true(definition.magazine_size > 0, "%s magazine" % id)
		assert_true(not definition.recoil_pattern.is_empty(), "%s pattern" % id)
		assert_true(definition.recoil_loop_from < definition.recoil_pattern.size(), "%s loop index" % id)
		assert_true(definition.muzzle_velocity > 0.0 and definition.pellets > 0, "%s projectile" % id)
		assert_true(definition.damage_falloff_end > definition.damage_falloff_start, "%s falloff" % id)
		if definition.fire_mode == WeaponDefinition.FireMode.PUMP:
			assert_true(60.0 / definition.rounds_per_minute <= definition.pump_time,
					"%s fire-rate cap must not be slower than the pump" % id)
