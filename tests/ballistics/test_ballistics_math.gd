extends "res://tests/framework/suite.gd"

const SETTINGS := preload("res://data/ballistics/ballistics_settings.tres")
const KESTREL := preload("res://data/weapons/kestrel.tres")
const HAMMERHEAD := preload("res://data/weapons/hammerhead.tres")
const VANTA := preload("res://data/weapons/vanta.tres")
const DT := 1.0 / 120.0


func can_penetrate(weapon: WeaponDefinition, surface_id: String, thickness: float) -> bool:
	var surface := SETTINGS.surface(surface_id)
	return weapon.penetration_power >= BallisticsMath.penetration_cost(surface, thickness)


func test_drop_matches_free_fall() -> void:
	# Fly 100 m horizontally; drop should match g t^2 / 2 for the flight time.
	var position := Vector3.ZERO
	var velocity := Vector3(0, 0, -VANTA.muzzle_velocity)
	var elapsed := 0.0
	while -position.z < 100.0:
		var stepped := BallisticsMath.step(position, velocity, SETTINGS.gravity, DT)
		position = stepped[0]
		velocity = stepped[1]
		elapsed += DT
	var expected := 0.5 * SETTINGS.gravity * elapsed * elapsed
	assert_approx(-position.y, expected, 0.02, "drop at 100 m")
	assert_approx(elapsed, 100.0 / VANTA.muzzle_velocity, DT, "flight time")


func test_damage_falls_off_between_start_and_end() -> void:
	assert_eq(BallisticsMath.damage_at(KESTREL, 5.0), KESTREL.damage, "close")
	assert_approx(BallisticsMath.damage_at(KESTREL, 500.0),
			KESTREL.damage * KESTREL.min_damage_multiplier, 1e-4, "far")
	var middle := BallisticsMath.damage_at(KESTREL,
			(KESTREL.damage_falloff_start + KESTREL.damage_falloff_end) * 0.5)
	assert_true(middle < KESTREL.damage and middle > KESTREL.damage * KESTREL.min_damage_multiplier, "between")


func test_rifle_penetration_table() -> void:
	assert_true(can_penetrate(KESTREL, "wood", 0.05), "5 cm wood")
	assert_true(can_penetrate(KESTREL, "wood", 0.2), "20 cm wood")
	assert_true(can_penetrate(KESTREL, "steel", 0.005), "5 mm steel")
	assert_true(not can_penetrate(KESTREL, "concrete", 0.3), "30 cm concrete stops it")
	assert_true(not can_penetrate(KESTREL, "flesh", 0.3), "target dummy stops it")


func test_pistol_and_shotgun_penetrate_less() -> void:
	assert_true(can_penetrate(VANTA, "wood", 0.05), "pistol 5 cm wood")
	assert_true(not can_penetrate(VANTA, "wood", 0.2), "pistol stopped by 20 cm wood")
	assert_true(not can_penetrate(HAMMERHEAD, "steel", 0.005), "pellet stopped by steel")


func test_ricochet_only_at_grazing_angles() -> void:
	var steel := SETTINGS.surface("steel")
	var wall_normal := Vector3.BACK
	var grazing := Vector3(1, 0, -0.1).normalized()  # ~5.7 degrees off the wall
	var square := Vector3.FORWARD
	assert_true(BallisticsMath.should_ricochet(steel, grazing, wall_normal), "grazing steel")
	assert_true(not BallisticsMath.should_ricochet(steel, square, wall_normal), "square-on steel")
	assert_true(not BallisticsMath.should_ricochet(SETTINGS.surface("wood"), grazing, wall_normal), "wood never")
	var bounced := BallisticsMath.reflect(grazing, wall_normal)
	assert_approx(bounced.z, -grazing.z, 1e-5, "reflected away from wall")
	assert_approx(bounced.x, grazing.x, 1e-5, "keeps along-wall motion")


func test_light_rounds_glance_off_steeper_surfaces() -> void:
	var steel := SETTINGS.surface("steel")
	var light := BallisticsMath.ricochet_angle(steel, VANTA.impact_energy,
			SETTINGS.ricochet_light_angle_multiplier, SETTINGS.ricochet_heavy_angle_multiplier)
	var heavy := BallisticsMath.ricochet_angle(steel, KESTREL.impact_energy,
			SETTINGS.ricochet_light_angle_multiplier, SETTINGS.ricochet_heavy_angle_multiplier)
	assert_true(light > heavy, "pistol %.1f deg vs rifle %.1f deg" % [light, heavy])
	# A 16 degree glance: the pistol round deflects, the rifle round digs in.
	var direction := Vector3(1, 0, -tan(deg_to_rad(16.0))).normalized()
	assert_true(BallisticsMath.should_ricochet(steel, direction, Vector3.BACK, light), "pistol deflects")
	assert_true(not BallisticsMath.should_ricochet(steel, direction, Vector3.BACK, heavy), "rifle does not")


func test_impact_energy_falls_with_speed() -> void:
	assert_approx(BallisticsMath.impact_energy(KESTREL, KESTREL.muzzle_velocity), KESTREL.impact_energy, 1e-5, "full")
	assert_approx(BallisticsMath.impact_energy(KESTREL, KESTREL.muzzle_velocity * 0.5),
			KESTREL.impact_energy * 0.25, 1e-5, "half speed is a quarter of the energy")


func test_spread_cone_stays_inside_angle() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var forward := Vector3(0.3, -0.2, -1).normalized()
	var widest := 0.0
	for i in 500:
		var direction := BallisticsMath.random_in_cone(forward, 3.0, rng)
		widest = maxf(widest, rad_to_deg(direction.angle_to(forward)))
	assert_true(widest <= 3.0 + 1e-3, "inside cone: %.3f" % widest)
	assert_true(widest > 2.5, "uses the cone: %.3f" % widest)


func test_unknown_surface_uses_default() -> void:
	assert_eq(SETTINGS.surface("no_such_surface"), SETTINGS.default_surface)
