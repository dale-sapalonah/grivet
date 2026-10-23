extends "res://tests/framework/suite.gd"

const Model := preload("res://player/movement_model.gd")
const TUNING := preload("res://data/player/movement_tuning.tres")
const DT := 1.0 / 120.0

var model := Model.new(TUNING)
var intent := Model.Intent.new()
var world := Model.World.new()


func tick(seconds: float = DT) -> void:
	var steps := maxi(1, roundi(seconds / DT))
	for i in steps:
		model.update(intent, world, DT)
		intent.sprint_pressed = false
		intent.crouch_pressed = false
		intent.prone_pressed = false


func start_sprinting() -> void:
	intent.move = Vector2(0, 1)
	world.horizontal_speed = TUNING.sprint_speed
	intent.sprint_pressed = true
	tick()


func test_sprint_needs_forward_input() -> void:
	intent.sprint_pressed = true
	tick()
	assert_eq(model.gait, Model.Gait.WALK, "standing still")
	start_sprinting()
	assert_eq(model.gait, Model.Gait.SPRINT, "pushing forward")


func test_sprint_ends_when_forward_released() -> void:
	start_sprinting()
	intent.move = Vector2.ZERO
	tick()
	assert_eq(model.gait, Model.Gait.WALK)


func test_aiming_cancels_sprint() -> void:
	start_sprinting()
	intent.aiming = true
	tick()
	assert_eq(model.gait, Model.Gait.WALK)


func test_tac_sprint_runs_out_then_cools_down() -> void:
	start_sprinting()
	intent.sprint_pressed = true
	tick()
	assert_eq(model.gait, Model.Gait.TAC_SPRINT, "second press")
	tick(TUNING.tac_sprint_duration + DT)
	assert_eq(model.gait, Model.Gait.SPRINT, "after duration")
	intent.sprint_pressed = true
	tick()
	assert_eq(model.gait, Model.Gait.SPRINT, "during cooldown")
	tick(TUNING.tac_sprint_cooldown)
	intent.sprint_pressed = true
	tick()
	assert_eq(model.gait, Model.Gait.TAC_SPRINT, "after cooldown")


func test_crouch_while_sprinting_fast_slides() -> void:
	start_sprinting()
	intent.crouch_pressed = true
	model.update(intent, world, DT)
	assert_eq(model.gait, Model.Gait.SLIDE, "gait")
	assert_eq(model.stance, Model.Stance.CROUCH, "stance")
	assert_true(model.slide_started, "slide_started flag")
	intent.crouch_pressed = false
	tick(TUNING.slide_duration + DT)
	assert_eq(model.gait, Model.Gait.WALK, "slide ends")
	assert_eq(model.stance, Model.Stance.CROUCH, "ends crouched")


func test_slide_ends_when_too_slow() -> void:
	start_sprinting()
	intent.crouch_pressed = true
	tick()
	world.horizontal_speed = TUNING.slide_end_speed - 0.1
	tick()
	assert_eq(model.gait, Model.Gait.WALK)


func test_crouch_when_walking_just_crouches() -> void:
	intent.move = Vector2(0, 1)
	world.horizontal_speed = TUNING.walk_speed
	intent.crouch_pressed = true
	tick()
	assert_eq(model.gait, Model.Gait.WALK, "gait")
	assert_eq(model.stance, Model.Stance.CROUCH, "stance")


func test_cannot_stand_under_low_ceiling() -> void:
	intent.crouch_pressed = true
	tick()
	world.can_stand = false
	intent.crouch_pressed = true
	tick()
	assert_eq(model.stance, Model.Stance.CROUCH)


func test_prone_exits_to_crouch_when_blocked() -> void:
	intent.prone_pressed = true
	tick()
	assert_eq(model.stance, Model.Stance.PRONE, "went prone")
	world.can_stand = false
	intent.prone_pressed = true
	tick()
	assert_eq(model.stance, Model.Stance.CROUCH, "got up to crouch")


func test_speed_follows_stance_and_aim() -> void:
	assert_eq(model.target_speed(), TUNING.walk_speed, "walk")
	intent.aiming = true
	tick()
	assert_eq(model.target_speed(), TUNING.walk_speed * TUNING.ads_speed_multiplier, "aim")
	intent.aiming = false
	intent.crouch_pressed = true
	tick()
	assert_eq(model.target_speed(), TUNING.crouch_speed, "crouch")
	assert_eq(model.target_height(), TUNING.crouch_height, "crouch height")


func test_lean_only_when_walking() -> void:
	intent.lean = 1.0
	tick(1.0)
	assert_eq(model.lean, 1.0, "walking lean")
	start_sprinting()
	tick(1.0)
	assert_eq(model.lean, 0.0, "sprinting lean")


func test_hard_landing_slows_briefly() -> void:
	model.land(TUNING.hard_landing_speed + 1.0)
	assert_true(model.target_speed() < TUNING.walk_speed, "slowed")
	tick(TUNING.hard_landing_slow_time + DT)
	assert_eq(model.target_speed(), TUNING.walk_speed, "recovered")


func test_soft_landing_does_not_slow() -> void:
	model.land(TUNING.hard_landing_speed - 1.0)
	assert_eq(model.target_speed(), TUNING.walk_speed)


func test_jump_from_crouch_stands_instead() -> void:
	intent.crouch_pressed = true
	tick()
	assert_true(not model.try_jump(world), "no jump")
	assert_eq(model.stance, Model.Stance.STAND)


func test_slide_jump_keeps_sprint() -> void:
	start_sprinting()
	intent.crouch_pressed = true
	tick()
	assert_true(model.try_jump(world), "jumps")
	assert_eq(model.gait, Model.Gait.SPRINT, "gait")
	assert_eq(model.stance, Model.Stance.STAND, "stance")


func test_mantle_ignores_input_until_done() -> void:
	model.begin_mantle()
	intent.prone_pressed = true
	tick()
	assert_eq(model.stance, Model.Stance.STAND, "ignored prone")
	model.end_mantle(false)
	assert_eq(model.gait, Model.Gait.WALK, "gait")
	assert_eq(model.stance, Model.Stance.CROUCH, "low headroom ends crouched")
