class_name WeaponModel
extends RefCounted
## Pure weapon state machine: ammo, fire rate, reloads, pump, equip, inspect,
## recoil pattern and spread bloom. No nodes, so it runs and is tested
## headless. The WeaponHolder feeds it controls each physics tick, then turns
## the shots it returns into bullets and the kicks into aim movement.

enum State { READY, RELOADING, PUMPING, EQUIPPING, INSPECTING }


## Controls for one tick.
class Controls:
	var trigger := false
	var reload_pressed := false
	var inspect_pressed := false
	var sprinting := false


var definition: WeaponDefinition
var state: State = State.EQUIPPING
var ammo := 0
var reserve := 0
var infinite_ammo := false
var recoil_index := 0
## Extra spread (degrees) from sustained fire; decays when not firing.
var bloom := 0.0
## Recoil kicks (x = up, y = right, degrees) for the shots of the last update.
var last_kicks: Array[Vector2] = []
## True while the current reload started from an empty magazine.
var reload_is_empty := false

var _state_time_left := 0.0
var _state_duration := 0.0
var _cooldown := 0.0
var _since_last_shot := INF
var _trigger_was_down := false
var _sprint_recover := 0.0


func _init(weapon: WeaponDefinition) -> void:
	definition = weapon
	ammo = weapon.magazine_size
	reserve = weapon.reserve_ammo
	begin_equip()


func begin_equip() -> void:
	_enter(State.EQUIPPING, definition.equip_time)
	_trigger_was_down = true  # a held trigger from the last weapon must be released


## Advances one tick and returns how many shots fired.
func update(controls: Controls, delta: float) -> int:
	last_kicks.clear()
	var trigger_pressed := controls.trigger and not _trigger_was_down
	_trigger_was_down = controls.trigger
	_cooldown -= delta
	_since_last_shot += delta
	bloom = move_toward(bloom, 0.0, definition.spread_recovery_per_second * delta)
	if _since_last_shot > definition.recoil_reset_time:
		recoil_index = 0
	if controls.sprinting:
		_sprint_recover = definition.sprint_to_fire_time
	else:
		_sprint_recover = maxf(_sprint_recover - delta, 0.0)

	match state:
		State.EQUIPPING, State.PUMPING:
			_state_time_left -= delta
			if _state_time_left <= 0.0:
				state = State.READY
		State.INSPECTING:
			_state_time_left -= delta
			if _state_time_left <= 0.0 or controls.trigger or controls.reload_pressed:
				state = State.READY
		State.RELOADING:
			_update_reload(controls, trigger_pressed, delta)

	var shots := 0
	if state == State.READY:
		if controls.reload_pressed:
			try_reload()
		elif controls.inspect_pressed:
			_enter(State.INSPECTING, definition.inspect_time)
		else:
			shots = _try_fire(controls, trigger_pressed)
	if shots == 0:
		_cooldown = maxf(_cooldown, 0.0)
	return shots


func try_reload() -> bool:
	if state != State.READY and state != State.INSPECTING:
		return false
	if ammo >= _capacity(ammo > 0) or (reserve <= 0 and not infinite_ammo):
		return false
	reload_is_empty = ammo == 0
	if definition.reload_mode == WeaponDefinition.ReloadMode.PER_SHELL:
		_enter(State.RELOADING, definition.reload_start_time + definition.shell_insert_time)
	elif reload_is_empty:
		_enter(State.RELOADING, definition.reload_empty_time)
	else:
		_enter(State.RELOADING, definition.reload_tactical_time)
	return true


## 0..1 through the current timed state (reload, pump, equip, inspect).
func state_progress() -> float:
	if _state_duration <= 0.0:
		return 1.0
	return clampf(1.0 - _state_time_left / _state_duration, 0.0, 1.0)


## The aim kick of shot number `index` in the pattern.
func recoil_kick(index: int) -> Vector2:
	var pattern := definition.recoil_pattern
	if pattern.is_empty():
		return Vector2.ZERO
	if index < pattern.size():
		return pattern[index]
	var loop_from := clampi(definition.recoil_loop_from, 0, pattern.size() - 1)
	var loop_length := pattern.size() - loop_from
	return pattern[loop_from + (index - pattern.size()) % loop_length]


## Cone half-angle in degrees. aim_blend 0 = hip, 1 = fully aimed.
## move_fraction is speed / walk speed (0..1).
func spread_degrees(aim_blend: float, move_fraction: float, stance_multiplier: float) -> float:
	var spread := lerpf(definition.spread_hip, definition.spread_ads, aim_blend)
	spread += definition.spread_moving_add * clampf(move_fraction, 0.0, 1.0) * (1.0 - aim_blend)
	spread *= stance_multiplier
	spread += bloom * lerpf(1.0, definition.bloom_ads_multiplier, aim_blend)
	return spread


func _try_fire(controls: Controls, trigger_pressed: bool) -> int:
	if controls.sprinting or _sprint_recover > 0.0:
		return 0
	if ammo <= 0:
		if trigger_pressed:
			try_reload()  # pulling the trigger on empty starts a reload
		return 0
	var wants_fire := controls.trigger if definition.fire_mode == WeaponDefinition.FireMode.AUTO \
			else trigger_pressed
	if not wants_fire:
		return 0
	var interval := 60.0 / definition.rounds_per_minute
	var shots := 0
	while _cooldown <= 0.0 and ammo > 0:
		_cooldown += interval
		if not infinite_ammo:
			ammo -= 1
		last_kicks.append(recoil_kick(recoil_index))
		recoil_index += 1
		bloom = minf(bloom + definition.spread_per_shot, definition.spread_max_bloom)
		_since_last_shot = 0.0
		shots += 1
		if definition.fire_mode != WeaponDefinition.FireMode.AUTO:
			break
	if shots > 0 and definition.fire_mode == WeaponDefinition.FireMode.PUMP:
		_enter(State.PUMPING, definition.pump_time)
	return shots


func _update_reload(controls: Controls, trigger_pressed: bool, delta: float) -> void:
	_state_time_left -= delta
	if definition.reload_mode == WeaponDefinition.ReloadMode.PER_SHELL:
		# Firing interrupts a shell-by-shell reload once a shell is in.
		if trigger_pressed and ammo > 0:
			_finish_shell_reload()
			return
		if _state_time_left > 0.0:
			return
		_take_from_reserve(1)
		if ammo < definition.magazine_size and (reserve > 0 or infinite_ammo):
			_enter(State.RELOADING, definition.shell_insert_time)
		else:
			_finish_shell_reload()
	elif _state_time_left <= 0.0:
		_take_from_reserve(_capacity(not reload_is_empty) - ammo)
		state = State.READY


func _finish_shell_reload() -> void:
	if reload_is_empty:
		_enter(State.PUMPING, definition.pump_time)  # chamber the first shell
	else:
		state = State.READY


func _take_from_reserve(count: int) -> void:
	var taken := count if infinite_ammo else mini(count, reserve)
	ammo += taken
	if not infinite_ammo:
		reserve -= taken


func _capacity(keeps_chambered_round: bool) -> int:
	var extra := 1 if definition.chamber_round and keeps_chambered_round else 0
	return definition.magazine_size + extra


func _enter(new_state: State, duration: float) -> void:
	state = new_state
	_state_time_left = duration
	_state_duration = duration
