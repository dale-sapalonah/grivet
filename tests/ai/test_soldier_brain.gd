extends "res://tests/framework/suite.gd"

const SETTINGS := preload("res://data/ai/ai_settings.tres")
const RIFLEMAN := preload("res://data/ai/rifleman.tres")
const RUSHER := preload("res://data/ai/rusher.tres")
const Action := SoldierBrain.Action


## A rifleman in a firefight, in good cover, at mid range, seeing the target.
func fighting() -> SoldierBrain.Facts:
	var facts := SoldierBrain.Facts.new()
	facts.awareness = 1.2
	facts.target_visible = true
	facts.time_since_seen = 0.0
	facts.distance = 20.0
	facts.in_cover = true
	facts.health_fraction = 1.0
	facts.ammo_fraction = 1.0
	return facts


func wanted(facts: SoldierBrain.Facts, profile: EnemyProfile = RIFLEMAN) -> Action:
	return SoldierBrain.new(SETTINGS).wanted_action(facts, profile)


func test_unaware_soldier_idles() -> void:
	assert_eq(wanted(SoldierBrain.Facts.new()), Action.IDLE)


func test_suspicion_or_noise_means_investigate() -> void:
	var facts := SoldierBrain.Facts.new()
	facts.awareness = RIFLEMAN.suspicious_threshold + 0.05
	assert_eq(wanted(facts), Action.INVESTIGATE, "suspicious")
	var heard := SoldierBrain.Facts.new()
	heard.has_noise = true
	assert_eq(wanted(heard), Action.INVESTIGATE, "heard something")


func test_exposed_rifleman_takes_cover() -> void:
	var facts := fighting()
	facts.in_cover = false
	assert_eq(wanted(facts), Action.TAKE_COVER)


func test_rifleman_in_cover_engages() -> void:
	assert_eq(wanted(fighting()), Action.ENGAGE)


func test_out_of_range_rifleman_bounds_forward() -> void:
	var facts := fighting()
	facts.distance = RIFLEMAN.preferred_range_max + 10.0
	assert_eq(wanted(facts), Action.PUSH)


func test_rifleman_flanks_a_pinned_target() -> void:
	var facts := fighting()
	facts.can_flank = true
	facts.target_pinned_time = RIFLEMAN.flank_after_pinned + 1.0
	assert_eq(wanted(facts), Action.FLANK, "pinned target, slot free")
	facts.suppression = 0.9
	assert_true(wanted(facts) != Action.FLANK, "not while suppressed")


func test_suppresses_while_an_ally_flanks() -> void:
	var facts := fighting()
	facts.target_visible = false
	facts.time_since_seen = 1.0
	facts.ally_flanking = true
	assert_eq(wanted(facts), Action.SUPPRESS)


func test_reloads_behind_cover_not_in_the_open() -> void:
	var facts := fighting()
	facts.ammo_fraction = 0.0
	assert_eq(wanted(facts), Action.RELOAD, "in cover")
	facts.in_cover = false
	assert_eq(wanted(facts), Action.TAKE_COVER, "exposed: get to cover first")


func test_badly_hurt_rifleman_retreats() -> void:
	var facts := fighting()
	facts.health_fraction = RIFLEMAN.retreat_health * 0.5
	assert_eq(wanted(facts), Action.RETREAT, "hurt")
	facts.in_retreat_cover = true
	assert_eq(wanted(facts), Action.ENGAGE, "already fell back: fight from there")


func test_camping_target_gets_a_grenade() -> void:
	var facts := fighting()
	facts.grenades = 1
	facts.grenade_allowed = true
	facts.target_pinned_time = RIFLEMAN.grenade_camp_time + 1.0
	assert_eq(wanted(facts), Action.THROW_GRENADE, "camping in range")
	facts.distance = RIFLEMAN.grenade_range_min * 0.5
	assert_true(wanted(facts) != Action.THROW_GRENADE, "too close to throw")


func test_rusher_pushes_then_charges() -> void:
	var facts := fighting()
	facts.distance = RUSHER.charge_range + 10.0
	assert_eq(wanted(facts, RUSHER), Action.PUSH, "far: bound forward")
	facts.distance = RUSHER.charge_range - 1.0
	assert_eq(wanted(facts, RUSHER), Action.CHARGE, "close: go in")


func test_rusher_waits_for_an_opening_when_watched() -> void:
	var facts := fighting()
	facts.distance = RUSHER.charge_range - 1.0
	facts.target_facing_me = true
	assert_eq(wanted(facts, RUSHER), Action.PUSH, "watched: keep using cover")
	facts.target_reloading = true
	assert_eq(wanted(facts, RUSHER), Action.CHARGE, "target reloading: go")
	facts.target_reloading = false
	facts.distance = SETTINGS.point_blank_range - 0.5
	assert_eq(wanted(facts, RUSHER), Action.CHARGE, "point blank: go anyway")


func test_rusher_under_fire_while_watched_takes_cover() -> void:
	var facts := fighting()
	facts.distance = RUSHER.charge_range - 1.0
	facts.target_facing_me = true
	facts.under_fire = true
	facts.in_cover = false
	assert_eq(wanted(facts, RUSHER), Action.TAKE_COVER)


func test_hurt_rusher_falls_back() -> void:
	var facts := fighting()
	facts.distance = 15.0
	facts.health_fraction = RUSHER.retreat_health * 0.5
	assert_eq(wanted(facts, RUSHER), Action.RETREAT)


func test_pinned_rusher_hugs_cover() -> void:
	var facts := fighting()
	facts.distance = 20.0
	facts.suppression = RUSHER.suppression_tolerance + 0.1
	assert_eq(wanted(facts, RUSHER), Action.ENGAGE, "in cover: stay")
	facts.in_cover = false
	assert_eq(wanted(facts, RUSHER), Action.TAKE_COVER, "exposed")


func test_bound_in_progress_is_not_interrupted() -> void:
	var brain := SoldierBrain.new(SETTINGS)
	var facts := fighting()
	facts.distance = RIFLEMAN.preferred_range_max + 10.0
	brain.decide(facts, RIFLEMAN, 1.0)
	assert_eq(brain.action, Action.PUSH, "started bounding")
	facts.in_cover = false
	facts.en_route = true
	brain.decide(facts, RIFLEMAN, 1.0)
	assert_eq(brain.action, Action.PUSH, "still bounding while en route")


func test_compromised_cover_means_move() -> void:
	var facts := fighting()
	facts.cover_compromised = true
	assert_eq(wanted(facts), Action.TAKE_COVER, "rifleman")
	facts.distance = 20.0
	assert_eq(wanted(facts, RUSHER), Action.TAKE_COVER, "rusher")


func test_no_flank_while_under_fire() -> void:
	var facts := fighting()
	facts.can_flank = true
	facts.target_pinned_time = RIFLEMAN.flank_after_pinned + 1.0
	facts.under_fire = true
	assert_true(wanted(facts) != Action.FLANK)


func test_decisions_commit_but_danger_is_immediate() -> void:
	var brain := SoldierBrain.new(SETTINGS)
	var facts := fighting()
	brain.decide(facts, RIFLEMAN, 1.0)
	assert_eq(brain.action, Action.ENGAGE, "engaging")
	facts.ally_flanking = true
	facts.target_visible = false
	facts.time_since_seen = 1.0
	brain.decide(facts, RIFLEMAN, SETTINGS.decision_commit_time * 0.25)
	assert_eq(brain.action, Action.ENGAGE, "non-urgent change waits")
	facts.in_cover = false
	brain.decide(facts, RIFLEMAN, 0.01)
	assert_eq(brain.action, Action.TAKE_COVER, "exposure switches at once")
