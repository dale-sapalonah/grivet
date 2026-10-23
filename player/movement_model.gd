class_name MovementModel
extends RefCounted
## Pure movement state machine: stance, gait, timers and lean. No nodes or
## physics, so it runs and is tested headless. The Player feeds it input
## intent plus facts about the world each physics tick, then applies the
## resulting speed and height with physics.

enum Stance { STAND, CROUCH, PRONE }
enum Gait { WALK, SPRINT, TAC_SPRINT, SLIDE, MANTLE }


## What the player is asking for this tick. Press flags are true only on the
## tick the button went down.
class Intent:
	var move := Vector2.ZERO  # x = right, y = forward, length <= 1
	var sprint_pressed := false
	var crouch_pressed := false
	var prone_pressed := false
	var aiming := false
	var lean := 0.0  # -1 left, 0 none, 1 right


## Facts the physics layer measured this tick.
class World:
	var grounded := true
	var horizontal_speed := 0.0
	var can_stand := true
	var can_crouch := true


var tuning: MovementTuning
var stance: Stance = Stance.STAND
var gait: Gait = Gait.WALK
var aiming := false
var lean := 0.0
## True only on the tick a slide begins, so the Player can add the boost.
var slide_started := false

var _slide_time_left := 0.0
var _slide_cooldown := 0.0
var _tac_time_left := 0.0
var _tac_cooldown := 0.0
var _landing_slow_left := 0.0


func _init(movement_tuning: MovementTuning) -> void:
	tuning = movement_tuning


func update(intent: Intent, world: World, delta: float) -> void:
	slide_started = false
	_tick_timers(delta)
	if gait == Gait.MANTLE:
		return
	aiming = intent.aiming
	_update_stance(intent, world)
	_update_gait(intent, world)
	_update_lean(intent, delta)


func is_sprinting() -> bool:
	return gait == Gait.SPRINT or gait == Gait.TAC_SPRINT


func target_speed() -> float:
	var speed: float
	match gait:
		Gait.SPRINT:
			speed = tuning.sprint_speed
		Gait.TAC_SPRINT:
			speed = tuning.tac_sprint_speed
		Gait.SLIDE, Gait.MANTLE:
			return 0.0
		_:
			match stance:
				Stance.CROUCH:
					speed = tuning.crouch_speed
				Stance.PRONE:
					speed = tuning.prone_speed
				_:
					speed = tuning.walk_speed
			if aiming:
				speed *= tuning.ads_speed_multiplier
	if _landing_slow_left > 0.0:
		speed *= tuning.hard_landing_speed_multiplier
	return speed


func target_height() -> float:
	match stance:
		Stance.CROUCH:
			return tuning.crouch_height
		Stance.PRONE:
			return tuning.prone_height
	return tuning.stand_height


func eye_height() -> float:
	match stance:
		Stance.CROUCH:
			return tuning.crouch_eye_height
		Stance.PRONE:
			return tuning.prone_eye_height
	return tuning.stand_eye_height


## Returns true if the body should jump. From crouch or prone, jump stands
## up one stance instead. Jumping out of a slide keeps the sprint.
func try_jump(world: World) -> bool:
	if gait == Gait.MANTLE or not world.grounded:
		return false
	if gait == Gait.SLIDE:
		if not world.can_stand:
			return false
		stance = Stance.STAND
		gait = Gait.SPRINT
		_slide_cooldown = tuning.slide_cooldown
		return true
	match stance:
		Stance.PRONE:
			if world.can_crouch:
				stance = Stance.CROUCH
			return false
		Stance.CROUCH:
			if world.can_stand:
				stance = Stance.STAND
			return false
	return true


func land(impact_speed: float) -> void:
	if impact_speed >= tuning.hard_landing_speed:
		_landing_slow_left = tuning.hard_landing_slow_time


func begin_mantle() -> void:
	gait = Gait.MANTLE
	lean = 0.0


func end_mantle(can_stand: bool) -> void:
	gait = Gait.WALK
	stance = Stance.STAND if can_stand else Stance.CROUCH


func _tick_timers(delta: float) -> void:
	_slide_cooldown = maxf(_slide_cooldown - delta, 0.0)
	_tac_cooldown = maxf(_tac_cooldown - delta, 0.0)
	_landing_slow_left = maxf(_landing_slow_left - delta, 0.0)
	if gait == Gait.SLIDE:
		_slide_time_left -= delta
	if gait == Gait.TAC_SPRINT:
		_tac_time_left -= delta


func _update_stance(intent: Intent, world: World) -> void:
	if intent.crouch_pressed:
		if gait == Gait.SLIDE:
			_end_slide()
		elif is_sprinting() and world.grounded and _slide_cooldown <= 0.0 \
				and world.horizontal_speed >= tuning.slide_min_speed:
			_start_slide()
		else:
			match stance:
				Stance.STAND:
					stance = Stance.CROUCH
					_stop_sprint()
				Stance.CROUCH:
					if world.can_stand:
						stance = Stance.STAND
				Stance.PRONE:
					if world.can_crouch:
						stance = Stance.CROUCH
	elif intent.prone_pressed:
		if stance == Stance.PRONE:
			if world.can_stand:
				stance = Stance.STAND
			elif world.can_crouch:
				stance = Stance.CROUCH
		else:
			stance = Stance.PRONE
			gait = Gait.WALK


func _update_gait(intent: Intent, world: World) -> void:
	if gait == Gait.SLIDE:
		if _slide_time_left <= 0.0 or not world.grounded \
				or world.horizontal_speed < tuning.slide_end_speed:
			_end_slide()
		return
	var pushing_forward := intent.move.y >= tuning.sprint_forward_threshold
	if intent.sprint_pressed:
		if gait == Gait.SPRINT and _tac_cooldown <= 0.0:
			gait = Gait.TAC_SPRINT
			_tac_time_left = tuning.tac_sprint_duration
		elif gait == Gait.WALK and pushing_forward and not intent.aiming:
			if stance == Stance.STAND or world.can_stand:
				stance = Stance.STAND
				gait = Gait.SPRINT
	if is_sprinting() and (not pushing_forward or intent.aiming or stance != Stance.STAND):
		_stop_sprint()
	elif gait == Gait.TAC_SPRINT and _tac_time_left <= 0.0:
		gait = Gait.SPRINT
		_tac_cooldown = tuning.tac_sprint_cooldown


func _update_lean(intent: Intent, delta: float) -> void:
	var can_lean := gait == Gait.WALK and stance != Stance.PRONE
	var target := clampf(intent.lean, -1.0, 1.0) if can_lean else 0.0
	lean = move_toward(lean, target, tuning.lean_speed * delta)


func _start_slide() -> void:
	gait = Gait.SLIDE
	stance = Stance.CROUCH
	_slide_time_left = tuning.slide_duration
	slide_started = true


func _end_slide() -> void:
	gait = Gait.WALK
	_slide_cooldown = tuning.slide_cooldown


func _stop_sprint() -> void:
	if gait == Gait.TAC_SPRINT:
		_tac_cooldown = tuning.tac_sprint_cooldown
	if is_sprinting():
		gait = Gait.WALK
