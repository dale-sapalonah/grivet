class_name Soldier
extends CharacterBody3D
## An enemy soldier. Senses the player (sight checks staggered across
## soldiers, hearing via the AI director, near misses), asks the SoldierBrain
## what to do, and carries it out: navigation paths, cover chosen by the
## director, peeking from beside full cover or over half cover, bursts aimed
## through AimModel, grenades on camping targets. Shoots the same weapons
## through the same Ballistics as the player. Dies into a Ragdoll.

@export var profile: EnemyProfile

var brain: SoldierBrain
var weapon: WeaponModel
var awareness := 0.0
var suppression := 0.0
var last_known := Vector3.INF
var time_since_seen := INF
var target_visible := false
var noise_position := Vector3.INF
var cover: CoverMap.Point = null
var cover_mode := ""
var dead := false
## Seconds of flashbang blindness left: no sight, no shooting, cowering.
var blind_left := 0.0
## Times this soldier had to give up on a path because it stopped moving.
var stuck_events := 0

var _settings: AiSettings
var _facts := SoldierBrain.Facts.new()
var _controls := WeaponModel.Controls.new()
var _rng := RandomNumberGenerator.new()
var _perception_timer := 0.0
var _perception_interval := 0.125
var _acquired_time := INF
var _reaction_left := 0.0
var _burst_left := 0
var _burst_pause := 0.0
var _trigger_toggle := false
var _fire_mode := 0  # 0 none, 1 aimed at the target, 2 suppressing the last known position
var _peeking := false
var _peek_timer := 0.0
var _peek_position := Vector3.INF
var _crouch := 0.0
var _want_crouch := false
var _advancing_low := false  # set each frame by the action
var _muzzle_flash: MuzzleFlash
var _action := SoldierBrain.Action.IDLE
var _last_good_position := Vector3.ZERO
var _reported_insane := false
var _think_timer := 0.0
var _think_delta := 0.0
var _pose_delta := 0.0
## Blade instead of a gun: strikes in reach rather than firing.
var _melee := false
var _swing := -1.0  # seconds into the current strike, below zero when not striking
var _swing_landed := false
var _swing_cooldown := 0.0
var _aim_pitch := 0.0
var _step_distance := 0.0
var _move_target := Vector3.INF
var _requested_target := Vector3.INF
var _speed := 0.0
var _grenades := 0
var _flank_cooldown := 0.0
var _hold_timer := 0.0
var _investigate_timer := 0.0
var _progress_anchor := Vector3.ZERO
var _progress_timer := 0.0
var _zone_shapes: Dictionary = {}  # part name -> CollisionShape3D
var _debug_label := Label3D.new()
var _path := PackedVector3Array()
var _path_index := 0
var _cover_retry_at: Dictionary = {}  # cover mode -> time a new request is allowed
var _alerted := false
var _hunker := 0.0
var _under_fire_at := -INF
## The target can see us where we hide: this cover no longer works.
var _cover_compromised := false
var _weave_phase := 0.0
var _strafe_side := 1.0
var _strafe_timer := 0.0

## A path corner counts as reached within this flat distance (m).
const PATH_CORNER_RADIUS := 0.4

@onready var health: Health = $Health
@onready var hitbox: Hitbox = $Hitbox
@onready var mannequin: Mannequin = $Mannequin
@onready var _shot_audio: AudioStreamPlayer3D = $ShotAudio


func _ready() -> void:
	_settings = AI.settings
	_rng.randomize()
	brain = SoldierBrain.new(_settings)
	weapon = WeaponModel.new(profile.weapon)
	health.setup(profile.health)
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	hitbox.health = health
	hitbox.body = self
	_melee = profile.weapon.melee_damage > 0.0
	mannequin.build(profile, _rng.randi_range(0, 59))
	mannequin.swing_windup = profile.weapon.melee_windup
	for part_name: String in Mannequin.PARTS:
		var zone := CollisionShape3D.new()
		zone.shape = mannequin.shapes[part_name][0]
		zone.set_meta("zone", Mannequin.PARTS[part_name][1])
		zone.set_meta("part", part_name)
		if Mannequin.PLATES.has(part_name):
			zone.set_meta("plate", Mannequin.PLATES[part_name])
		hitbox.add_child(zone)
		_zone_shapes[part_name] = zone
	_muzzle_flash = MuzzleFlash.new()
	mannequin.muzzle.add_child(_muzzle_flash)
	_muzzle_flash.setup(_settings.flash_energy, _settings.flash_range, _settings.flash_time, _settings.flash_size)
	collision_layer = PhysicsLayers.ENEMIES
	collision_mask = PhysicsLayers.ENEMY_MOVEMENT
	_perception_interval = 1.0 / _settings.perception_hz
	_perception_timer = _rng.randf() * _perception_interval  # stagger soldiers' sight checks
	_think_timer = _rng.randf() / _settings.think_hz  # and their decisions
	_grenades = profile.grenade_count
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.position = Vector3(0, 2.2, 0)
	_debug_label.fixed_size = true  # same size on screen near or far
	_debug_label.pixel_size = 0.0006
	_debug_label.no_depth_test = true
	add_child(_debug_label)
	_progress_anchor = global_position
	AI.register(self)


func _exit_tree() -> void:
	AI.unregister(self)


## Where the player aims a blast check / what allies look at: torso centre.
func aim_point() -> Vector3:
	return mannequin.parts.torso.global_position + Vector3.UP * 0.32


func eye_point() -> Vector3:
	return global_position + Vector3.UP * lerpf(lerpf(1.65, 1.05, _crouch), 0.9, _hunker)


func _physics_process(delta: float) -> void:
	if dead or AI.frozen:
		return
	if not _sane():
		return
	var started := Time.get_ticks_usec()
	var target := AI.target()
	time_since_seen += delta
	_acquired_time += delta
	_reaction_left -= delta
	_flank_cooldown -= delta
	suppression = move_toward(suppression, 0.0, _settings.suppression_decay * delta)
	if blind_left > 0.0:
		_blinded(delta)
		AI.add_frame_time(Time.get_ticks_usec() - started)
		return
	_perception_timer -= delta
	if _perception_timer <= 0.0:
		_perceive(_perception_interval - _perception_timer, target)
		_perception_timer += _perception_interval
	# Think at think_hz (staggered across soldiers); move and shoot every tick.
	_think_timer -= delta
	_think_delta += delta
	if _think_timer <= 0.0:
		_think_timer += 1.0 / _settings.think_hz
		_update_facts()
		_action = brain.decide(_facts, profile, _think_delta)
		_fire_mode = 0
		_advancing_low = false
		_act(_action, _think_delta, target)
		_think_delta = 0.0
	_update_weapon(delta, target)
	_move(delta)
	AI.add_frame_time(Time.get_ticks_usec() - started)


## Posing and the hit boxes that follow it run once per drawn frame, not per
## physics tick (2-3 times a frame at 120 Hz); far soldiers every other frame.
func _process(delta: float) -> void:
	if dead or AI.frozen:
		return
	var started := Time.get_ticks_usec()
	_pose_delta += delta
	var target := AI.target()
	var distance_squared := global_position.distance_squared_to(target.global_position) if target != null else 0.0
	mannequin.cast_shadows(distance_squared < _settings.shadow_lod_distance * _settings.shadow_lod_distance)
	var far := distance_squared > _settings.pose_lod_distance * _settings.pose_lod_distance
	if far and (Engine.get_process_frames() + get_instance_id()) % 2 == 0:
		return
	_pose(_pose_delta, target)
	_pose_delta = 0.0
	_sync_hitbox()
	_update_debug_label(_action)
	AI.add_frame_time(Time.get_ticks_usec() - started)


# --- Senses --------------------------------------------------------------------

func _perceive(elapsed: float, target: Player) -> void:
	var seen := 0.0
	var line_of_sight := false
	if target != null:
		var eye := eye_point()
		var space := get_world_3d().direct_space_state
		for point in [target.head_point(), target.aim_point()]:
			var query := PhysicsRayQueryParameters3D.create(eye, point, PhysicsLayers.WORLD)
			if space.intersect_ray(query).is_empty():
				line_of_sight = true
				break
		if line_of_sight:
			var offset := target.global_position - global_position
			var forward := -global_basis.z
			var angle := rad_to_deg(Vector2(forward.x, forward.z).angle_to(Vector2(offset.x, offset.z)))
			var moving := Vector2(target.velocity.x, target.velocity.z).length() > 0.5
			seen = PerceptionModel.visibility(profile, _settings, offset.length(), absf(angle),
					target.model.stance, moving)
	awareness = PerceptionModel.update_awareness(awareness, seen, profile, elapsed)
	if _alerted:
		# Once in a fight a soldier stays wary: it hunts the last known
		# position rather than going back to idle.
		awareness = maxf(awareness, profile.suspicious_threshold)
		if awareness < 1.0 and noise_position == Vector3.INF and last_known != Vector3.INF:
			noise_position = last_known
	var was_visible := target_visible
	target_visible = seen > 0.0 and awareness >= 1.0
	if awareness >= 1.0:
		_alerted = true
	if target_visible:
		last_known = target.global_position
		time_since_seen = 0.0
		if not was_visible:
			_acquired_time = 0.0
			_reaction_left = profile.reaction_time
		AI.share_sighting(self, last_known)
	elif seen > 0.0 and awareness >= profile.suspicious_threshold:
		noise_position = target.global_position  # glimpsed: go and look
	_cover_compromised = false
	if target != null and cover != null and _at_cover() and not _peeking:
		# Hiding, yet the target has a clear line to our torso (it moved round
		# us, or the cover is too low): this spot is no good any more.
		var query := PhysicsRayQueryParameters3D.create(target.head_point(), aim_point(), PhysicsLayers.WORLD)
		_cover_compromised = get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Knifed by `attacker` (MeleeMath.can_take_down allowed it): dies at once,
## without a sound the squad can hear.
func take_down(attacker: Node3D) -> void:
	if dead:
		return
	var direction := (global_position - attacker.global_position).normalized()
	health.take_hit(INF, DamageModel.Zone.TORSO, {"shooter": attacker, "direction": direction,
			"position": aim_point(), "kind": "takedown", "energy": 0.2, "on_plate": false})  # in beside the plate


## True if this soldier can be taken down by `attacker` with `knife` now.
func takedown_open(attacker: Vector3, knife: WeaponDefinition) -> bool:
	return not dead and MeleeMath.can_take_down(attacker, global_position, -global_basis.z, knife.melee_range,
			knife.takedown_rear_arc_degrees, awareness >= 1.0 or _alerted, blind_left > 0.0)


## Blinded by a flashbang for `seconds`: knows something is on (alerted) but
## sees nothing, holds still and cowers until the eyes clear.
func flash(seconds: float) -> void:
	if dead:
		return
	blind_left = maxf(blind_left, seconds)
	_alert()
	target_visible = false
	_fire_mode = 0
	_burst_left = 0
	_swing = -1.0
	mannequin.swing = -1.0
	mannequin.flinch(global_basis.z, 2.5)


func _blinded(delta: float) -> void:
	blind_left = maxf(blind_left - delta, 0.0)
	target_visible = false
	_fire_mode = 0
	velocity = Vector3(move_toward(velocity.x, 0.0, 12.0 * delta), velocity.y, move_toward(velocity.z, 0.0, 12.0 * delta))
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) * delta
	move_and_slide()
	if blind_left <= 0.0:
		_perception_timer = 0.0  # look round at once
		_think_timer = 0.0


## A sound at `position` that carries `radius` metres, made by `source`.
func hear(position: Vector3, radius: float, source: Node) -> void:
	if dead or source == self:
		return
	var reach := radius * profile.hearing_multiplier
	var distance := global_position.distance_to(position)
	if distance > reach:
		return
	if not (source is Player):
		awareness = maxf(awareness, profile.suspicious_threshold + 0.1)
		noise_position = position
		return
	if distance < reach * _settings.hearing_precise_fraction:
		_alert()
		if not target_visible:
			last_known = position
			time_since_seen = minf(time_since_seen, 0.5)
	else:
		awareness = maxf(awareness, profile.suspicious_threshold + 0.1)
		var error := _settings.heard_position_error
		noise_position = position + Vector3(_rng.randf_range(-error, error), 0, _rng.randf_range(-error, error))


## Into the fight: fully aware, and wary from now on (awareness never sinks
## below suspicious again). Sight, a squadmate's report, close gunfire, being
## shot at or hit all lead here.
func _alert() -> void:
	awareness = maxf(awareness, 1.0)
	_alerted = true


## Guards against non-finite state (it once flooded the log with "Vector3
## cannot be normalized" and froze the game): reports the first time with
## enough context to find the cause, then puts the soldier back where it was
## last sane. False when it had to.
func _sane() -> bool:
	# The pose counts too: a NaN rotation, aim or body part leaves the position
	# finite but makes every shot and casing NaN.
	var spine: Node3D = mannequin.pivots.spine
	var posed := is_finite(rotation.y) and is_finite(_aim_pitch) \
			and spine.global_transform.is_finite() and mannequin.muzzle.global_position.is_finite()
	if global_position.is_finite() and velocity.is_finite() and posed:
		_last_good_position = global_position
		return true
	if not _reported_insane:
		_reported_insane = true
		push_error("Soldier %s (%s) went non-finite: position %s velocity %s rotation %s aim pitch %s spine %s action %s move target %s last known %s path %d points" % [
				name, profile.display_name, global_position, velocity, rotation, _aim_pitch,
				spine.transform, SoldierBrain.Action.keys()[_action], _move_target,
				last_known, _path.size()])
	global_position = _last_good_position if _last_good_position.is_finite() else global_position
	velocity = Vector3.ZERO
	rotation = Vector3(0.0, rotation.y if is_finite(rotation.y) else 0.0, 0.0)
	_aim_pitch = 0.0
	mannequin.reset_pose()
	_path = PackedVector3Array()
	_move_target = Vector3.INF
	_requested_target = Vector3.INF
	return false


## The target vanished (respawned elsewhere): drop what we knew, stay wary.
func forget_target() -> void:
	last_known = Vector3.INF
	noise_position = Vector3.INF
	target_visible = false
	time_since_seen = INF
	awareness = minf(awareness, profile.suspicious_threshold)


## An ally saw the target at `position`.
func receive_report(position: Vector3) -> void:
	if dead:
		return
	_alert()
	if not target_visible:
		last_known = position
		time_since_seen = minf(time_since_seen, 1.0)


## A round passed close by (amount 0..1 already scaled by distance).
func suppress(amount: float, shooter_position: Vector3) -> void:
	if dead:
		return
	suppression = minf(1.0, suppression + amount)
	_alert()
	_take_fire()
	if not target_visible and time_since_seen > 1.0:
		last_known = shooter_position
		time_since_seen = 1.0


# --- Thinking ------------------------------------------------------------------

func _update_facts() -> void:
	var known := last_known != Vector3.INF
	_facts.awareness = awareness
	_facts.target_visible = target_visible
	_facts.time_since_seen = time_since_seen if known else INF
	_facts.distance = CoverScoring.flat_distance(global_position, last_known) if known else INF
	_facts.has_noise = noise_position != Vector3.INF
	_facts.in_cover = known and _at_cover() and AI.cover_protection(cover, last_known) > 0.0
	_facts.en_route = cover != null and not _at_cover() and cover_mode in ["push", "flank", "retreat"]
	_facts.cover_compromised = _facts.in_cover and _cover_compromised
	_facts.under_fire = _now() - _under_fire_at < _settings.under_fire_memory
	_facts.target_facing_me = AI.target_facing(self)
	_facts.target_reloading = AI.target_reloading()
	_facts.in_retreat_cover = _facts.in_cover and cover_mode == "retreat"
	_facts.suppression = suppression
	_facts.health_fraction = health.fraction()
	_facts.ammo_fraction = float(weapon.ammo) / weapon.definition.magazine_size
	_facts.reloading = weapon.state == WeaponModel.State.RELOADING
	_facts.target_pinned_time = AI.target_pinned_time()
	_facts.can_flank = _flank_cooldown <= 0.0 and AI.flank_available(self) and AI.allies_engaging(self) > 0
	_facts.ally_flanking = AI.anyone_flanking(self)
	_facts.grenades = _grenades
	_facts.grenade_allowed = AI.grenade_allowed() and AI.grenade_definition != null


func _act(action: SoldierBrain.Action, delta: float, target: Player) -> void:
	if action != SoldierBrain.Action.FLANK:
		AI.release_flank(self)
	match action:
		SoldierBrain.Action.IDLE:
			_move_target = Vector3.INF
			_want_crouch = false
		SoldierBrain.Action.INVESTIGATE:
			_investigate(delta)
		SoldierBrain.Action.TAKE_COVER:
			if _cover_compromised and cover != null:
				AI.block_cover(cover, _settings.compromised_block_seconds)  # find somewhere else
				AI.release_cover(self)
				cover = null
				_cover_compromised = false
			_go_to_cover("cover", delta)
		SoldierBrain.Action.RETREAT:
			_go_to_cover("retreat", delta)
		SoldierBrain.Action.FLANK:
			if AI.take_flank(self):
				if _go_to_cover("flank", delta):
					_flank_cooldown = _settings.flank_cooldown  # arrived: flank done
					AI.release_flank(self)
		SoldierBrain.Action.PUSH:
			_push(delta)
		SoldierBrain.Action.ENGAGE:
			_engage_from_cover(delta, false)
		SoldierBrain.Action.SUPPRESS:
			_engage_from_cover(delta, true)
		SoldierBrain.Action.CHARGE:
			_charge(target)
		SoldierBrain.Action.RELOAD:
			_move_target = cover.position if cover != null else Vector3.INF
			_want_crouch = true
			_peeking = false
			_controls.reload_pressed = weapon.state == WeaponModel.State.READY
		SoldierBrain.Action.THROW_GRENADE:
			_throw_grenade()


func _investigate(delta: float) -> void:
	var spot := noise_position if noise_position != Vector3.INF else last_known
	_want_crouch = false
	if spot == Vector3.INF:
		_move_target = Vector3.INF
		return
	_move_target = spot
	if CoverScoring.flat_distance(global_position, spot) < 1.5 or (_path_finished() and _requested_target != Vector3.INF):
		_investigate_timer += delta
		rotate_y(delta * 1.2)  # look around
		if _investigate_timer > 4.0:
			noise_position = Vector3.INF
			_investigate_timer = 0.0
			if time_since_seen > profile.lose_target_time:
				last_known = Vector3.INF  # trail went cold
	else:
		_investigate_timer = 0.0


## Moves to cover chosen for `mode`; returns true once there. Plain "cover"
## keeps any reserved point that still protects; flank / push / retreat ask
## for a new one.
func _go_to_cover(mode: String, _delta: float) -> bool:
	var keep := cover != null and (cover_mode == mode or
			(mode == "cover" and last_known != Vector3.INF and AI.cover_protection(cover, last_known) > 0.0))
	if not keep:
		_choose_cover(mode)
	if cover == null:
		_move_target = Vector3.INF
		_engage_in_open()
		return false
	_move_target = cover.position
	if _at_cover():
		_want_crouch = not AI.cover_is_full(cover, last_known) if last_known != Vector3.INF else false
		return true
	_want_crouch = false
	if profile.role == EnemyProfile.Role.RUSHER and target_visible:
		_fire_mode = 1  # rushers fire on the move
	# In sight of the target: move low, cover to cover, instead of strolling upright.
	_advancing_low = target_visible and profile.advance_crouch > 0.0
	return false


## Asks the director for cover. On failure the soldier keeps the cover it had
## (a failed flank or push must not leave it standing in the open) and waits
## cover_retry_seconds before asking for that kind again.
func _choose_cover(mode: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _cover_retry_at.get(mode, 0.0) > now:
		return
	var chosen := AI.request_cover(self, mode)
	if chosen == null:
		_cover_retry_at[mode] = now + _settings.cover_retry_seconds
		if mode == "flank":
			_flank_cooldown = _settings.flank_cooldown
			AI.release_flank(self)
		return
	cover = chosen
	cover_mode = mode
	_peek_position = Vector3.INF
	_hold_timer = 0.0
	if cover != null and last_known != Vector3.INF:
		_peek_position = _find_peek_position()


## Full cover: a spot just to the side with a view of the target. Half cover:
## standing up in place. Blind cover (no view either side): stay put.
func _find_peek_position() -> Vector3:
	if not AI.cover_is_full(cover, last_known):
		return cover.position
	var to_target := (last_known - cover.position)
	to_target.y = 0.0
	var side := to_target.normalized().cross(Vector3.UP)
	var space := get_world_3d().direct_space_state
	for sign_side in [1.0, -1.0]:
		var spot: Vector3 = cover.position + side * sign_side * _settings.peek_offset
		var on_nav := NavigationServer3D.map_get_closest_point(AI.nav_map, spot)
		if on_nav.distance_to(spot) > 0.3:
			continue
		var query := PhysicsRayQueryParameters3D.create(on_nav + Vector3.UP * 1.5,
				last_known + Vector3.UP * 1.3, PhysicsLayers.WORLD)
		if space.intersect_ray(query).is_empty():
			return on_nav
	return cover.position


func _engage_from_cover(delta: float, suppressing: bool) -> void:
	if cover == null:
		_engage_in_open()
		return
	var pinned := suppression > profile.suppression_tolerance
	_peek_timer -= delta
	if _peek_timer <= 0.0:
		_peeking = not _peeking and not pinned
		_peek_timer = profile.peek_time if _peeking else \
				(profile.hide_time_suppressed if pinned else profile.hide_time)
		# Unpredictable rhythm: a player can't time the next peek.
		_peek_timer *= _rng.randf_range(1.0 - _settings.peek_jitter, 1.0 + _settings.peek_jitter)
	var full := last_known != Vector3.INF and AI.cover_is_full(cover, last_known)
	if _peeking:
		_move_target = _peek_position if _peek_position != Vector3.INF else cover.position
		_want_crouch = false
		if suppressing and last_known != Vector3.INF:
			_fire_mode = 2
		elif target_visible:
			_fire_mode = 1
	else:
		_move_target = cover.position
		_want_crouch = not full


## No cover found: fight where we stand, crouched.
func _engage_in_open() -> void:
	_want_crouch = true
	if target_visible:
		_fire_mode = 1


## Bounding: hold at each cover (fighting from it), then move to cover closer
## to the target once the director grants one. Rushers use it to close in,
## riflemen to get into range. With no cover at all, go straight in.
func _push(delta: float) -> void:
	if cover == null:
		_choose_cover("push")
	if cover == null:
		_move_target = last_known
		if target_visible:
			_fire_mode = 1
		return
	if not _at_cover():
		_go_to_cover(cover_mode, delta)  # same mode: no new request
		return
	_hold_timer += delta
	_engage_from_cover(delta, false)
	if _hold_timer >= profile.hide_time:
		var previous := cover
		_choose_cover("push")
		if cover != previous:
			_hold_timer = 0.0


## Closes in firing, weaving on the way; once close, circles the target
## instead of running into it, switching direction now and then.
func _charge(target: Player) -> void:
	_want_crouch = false
	cover = null
	AI.release_cover(self)
	var goal := last_known if target == null else target.global_position
	if _melee:
		# Straight at them (the weave comes from being shot at), stopping at
		# striking distance rather than walking into them.
		var reach := weapon.definition.melee_range * 0.8
		if CoverScoring.flat_distance(global_position, goal) <= reach:
			_move_target = Vector3.INF
		else:
			var back := Vector3(global_position.x - goal.x, 0.0, global_position.z - goal.z).normalized()
			_move_target = goal + back * reach
		return
	if CoverScoring.flat_distance(global_position, goal) <= _settings.close_strafe_range:
		_strafe_timer -= _think_delta  # called while thinking
		if _strafe_timer <= 0.0:
			_strafe_side = -_strafe_side
			_strafe_timer = _rng.randf_range(0.8, 1.8)
		var away := Vector3(global_position.x - goal.x, 0.0, global_position.z - goal.z).normalized()
		_move_target = goal + (away + away.cross(Vector3.UP) * _strafe_side).normalized() * _settings.close_strafe_range * 0.7
	else:
		_move_target = goal
	if target_visible:
		_fire_mode = 1


func _throw_grenade() -> void:
	if _grenades <= 0 or last_known == Vector3.INF or not AI.grenade_allowed():
		return
	_grenades -= 1
	AI.note_grenade(self)
	var definition := AI.grenade_definition
	var hand: Vector3 = mannequin.pivots.shoulder_r.global_position + Vector3.UP * 0.3
	var error := Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
	var velocity := ThrowMath.launch_velocity(hand, last_known + error, Ballistics.settings.gravity,
			definition.max_throw_speed, definition.arc_angle_min, definition.arc_angle_max)
	Grenade.throw(definition, get_parent(), hand, velocity, self)


func _at_cover() -> bool:
	if cover == null:
		return false
	var spot := _peek_position if _peeking and _peek_position != Vector3.INF else cover.position
	return CoverScoring.flat_distance(global_position, spot) < 0.6 \
			or CoverScoring.flat_distance(global_position, cover.position) < 0.6


# --- Firing --------------------------------------------------------------------

func _update_weapon(delta: float, target: Player) -> void:
	if _melee:
		_update_blade(delta, target)
		return
	var aim_at := _aim_target(target)
	var want_fire := _fire_mode != 0 and _reaction_left <= 0.0 and aim_at != Vector3.INF and _facing(aim_at)
	if not want_fire:
		_burst_left = 0
	elif _burst_left <= 0:
		_burst_pause -= delta
		if _burst_pause <= 0.0:
			_burst_left = _rng.randi_range(profile.burst_min, profile.burst_max)
	var auto := weapon.definition.fire_mode == WeaponDefinition.FireMode.AUTO
	_trigger_toggle = not _trigger_toggle
	_controls.trigger = want_fire and _burst_left > 0 and (auto or _trigger_toggle)
	_controls.sprinting = false
	var shots := weapon.update(_controls, delta)
	_controls.reload_pressed = false
	for i in shots:
		_shoot(aim_at, target)
		_burst_left -= 1
		if _burst_left <= 0:
			_burst_pause = _rng.randf_range(profile.burst_pause_min, profile.burst_pause_max)


## Machete: in reach and facing the target, wind up and chop; the blow lands
## at the end of the windup if the target is still there.
func _update_blade(delta: float, target: Player) -> void:
	var definition := weapon.definition
	_swing_cooldown -= delta
	if _swing >= 0.0:
		_swing += delta
		if not _swing_landed and _swing >= definition.melee_windup:
			_swing_landed = true
			_land_blow(target)
		if _swing >= definition.melee_windup + definition.melee_recover:
			_swing = -1.0
		mannequin.swing = _swing
		return
	mannequin.swing = -1.0
	if target == null or not target_visible or target.dead or _swing_cooldown > 0.0:
		return
	if CoverScoring.flat_distance(global_position, target.global_position) <= definition.melee_range 			and _facing(target.aim_point()):
		_swing = 0.0
		_swing_landed = false
		_swing_cooldown = definition.melee_windup + definition.melee_recover
		_shot_audio.stream = ProceduralAudio.cached("whoosh:%d" % (_rng.randi() % 3),
				func() -> AudioStreamWAV: return ProceduralAudio.blade_whoosh(_rng.randi() % 3))
		_shot_audio.volume_db = -6.0
		_shot_audio.pitch_scale = _rng.randf_range(0.9, 1.1)
		_shot_audio.play()


func _land_blow(target: Player) -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		return
	var to := target.global_position - global_position
	var forward := -global_basis.z
	if Vector2(to.x, to.z).length() > weapon.definition.melee_range * 1.25 or Vector2(forward.x, forward.z).dot(Vector2(to.x, to.z).normalized()) < 0.3:
		return  # dodged: stepped out of reach or round behind
	# Cuts land on arms raised to block as often as on the body.
	var zone := DamageModel.Zone.ARMS if _rng.randf() < 0.5 else DamageModel.Zone.TORSO
	target.health.take_hit(weapon.definition.melee_damage * profile.damage_multiplier, zone,
			{"shooter": self, "direction": to.normalized(), "position": target.aim_point(), "kind": "melee"})
	var chop := AudioStreamPlayer3D.new()
	chop.stream = ProceduralAudio.cached("chop:0", func() -> AudioStreamWAV: return ProceduralAudio.blade_chop(0))
	chop.finished.connect(chop.queue_free)
	add_child(chop)
	chop.global_position = target.aim_point()
	chop.play()


func _aim_target(target: Player) -> Vector3:
	if _melee and target != null and target_visible:
		return target.head_point()  # face to face, not staring at the chest
	if _fire_mode == 1 and target != null and target_visible:
		return target.aim_point()
	if last_known != Vector3.INF:
		return last_known + Vector3.UP * 1.2
	return Vector3.INF


func _shoot(aim_at: Vector3, target: Player) -> void:
	var muzzle := mannequin.muzzle.global_position
	if _fire_mode == 2:
		var spread := profile.suppress_spread
		aim_at += Vector3(_rng.randf_range(-spread, spread), _rng.randf_range(-0.5, 0.5) * spread, _rng.randf_range(-spread, spread))
	var direction := (aim_at - muzzle).normalized()
	var lateral := 0.0
	if target != null:
		var across := target.velocity - direction * target.velocity.dot(direction)
		lateral = across.length()
	var error := AimModel.error_degrees(profile, muzzle.distance_to(aim_at), suppression,
			Vector2(velocity.x, velocity.z).length() > 0.5, lateral, _acquired_time)
	direction = BallisticsMath.random_in_cone(direction, error, _rng)
	var exclude: Array[RID] = [hitbox.get_rid()]
	for pellet in weapon.definition.pellets:
		var pellet_direction := direction
		if weapon.definition.pellets > 1:
			pellet_direction = BallisticsMath.random_in_cone(direction, weapon.definition.pellet_spread_degrees, _rng)
		Ballistics.fire(muzzle, pellet_direction, weapon.definition, self, exclude)
	Soundscape.gunshot(weapon.definition, muzzle)  # close and distant layers, heard late with distance
	_muzzle_flash.flash()
	_eject_casing()
	mannequin.flinch(-global_basis.z, 0.6)


## Spent case out of the right side of the receiver; pump guns kick theirs
## out when the pump comes back.
func _eject_casing() -> void:
	var definition := weapon.definition
	if not definition.casing_ejects:
		return
	if definition.casing_eject_on_pump:
		await get_tree().create_timer(definition.pump_time * 0.4).timeout
		if not is_instance_valid(self) or mannequin.gun == null:
			return
	var gun := mannequin.gun.global_transform
	var port := Transform3D(gun.basis, gun * Vector3(0.03, 0.02, -0.06))
	var jitter := Vector3(randf_range(0.85, 1.15), randf_range(0.85, 1.15), randf_range(0.7, 1.3))
	AI.casings.eject(definition, port, port.basis * (definition.casing_eject_velocity * jitter) + velocity)


func _facing(point: Vector3) -> bool:
	var to := point - global_position
	var forward := -global_basis.z
	return absf(Vector2(forward.x, forward.z).angle_to(Vector2(to.x, to.z))) < deg_to_rad(12.0)


# --- Body ----------------------------------------------------------------------

## Follows a NavigationServer path, judging "reached a corner" on the ground
## plane (the baked navmesh floats above the floor, so 3D distances to path
## points never get small enough). Repaths when the destination moves.
func _move(delta: float) -> void:
	var desired := Vector3.ZERO
	if _move_target != Vector3.INF and not _move_target.is_finite():
		_move_target = Vector3.INF  # never path towards an unknown (infinite) point
	if _move_target != Vector3.INF:
		if _requested_target == Vector3.INF or _requested_target.distance_to(_move_target) > 0.5:
			_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, global_position, _move_target, true)
			_path_index = 0
			_requested_target = _move_target
		while _path_index < _path.size() and CoverScoring.flat_distance(global_position, _path[_path_index]) < PATH_CORNER_RADIUS:
			_path_index += 1
		if not _path_finished():
			var next := _path[_path_index]
			desired = Vector3(next.x - global_position.x, 0.0, next.z - global_position.z).normalized()
			if _should_weave():
				# Under fire in the open: jink side to side instead of running a straight line.
				_weave_phase += delta * _settings.weave_hz * TAU
				desired = desired.rotated(Vector3.UP, sin(_weave_phase) * deg_to_rad(_settings.weave_degrees))
		_check_progress(delta)
	else:
		_requested_target = Vector3.INF
		_progress_timer = 0.0
		_progress_anchor = global_position
	var running := _move_target != Vector3.INF and not _peeking and _fire_mode == 0
	_speed = profile.crouch_speed if _crouch > 0.5 else (profile.run_speed if running else profile.walk_speed)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired * _speed, 20.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity.y -= Ballistics.settings.gravity * delta
	move_and_slide()
	_step(delta)


## Footsteps: one per stride's worth of ground covered, louder running.
func _step(delta: float) -> void:
	if not is_on_floor():
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	_step_distance += speed * delta
	var audio := Soundscape.settings
	if _step_distance < audio.soldier_step_length:
		return
	_step_distance = 0.0
	var running := speed > audio.soldier_run_speed
	Soundscape.footstep(global_position, audio.soldier_run_step_db if running else audio.soldier_step_db,
			audio.soldier_step_unit_size, audio.soldier_step_max_distance)


func _path_finished() -> bool:
	return _path_index >= _path.size()


func _should_weave() -> bool:
	var exposed := target_visible or _now() - _under_fire_at < _settings.under_fire_memory
	var free_to_weave := _fire_mode == 0 or brain.action == SoldierBrain.Action.CHARGE
	return exposed and not _peeking and free_to_weave and CoverScoring.flat_distance(global_position, _move_target) > 2.0


## Hit or nearly hit: stop peeking and get down at once, and stay down a while.
func _take_fire() -> void:
	_under_fire_at = _now()
	if _peeking:
		_peeking = false
		_peek_timer = profile.hide_time_suppressed * _rng.randf_range(0.8, 1.2)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Gives up on a path that stopped making progress (blocked by an ally,
## a bad cover point): drops the cover so a new one is chosen.
func _check_progress(delta: float) -> void:
	if _path_finished():
		_progress_timer = 0.0
		_progress_anchor = global_position
		if CoverScoring.flat_distance(global_position, _move_target) > _settings.cover_reach_tolerance * 2.0:
			_give_up_on_destination()  # the path ended short: unreachable
		return
	_progress_timer += delta
	if global_position.distance_to(_progress_anchor) > 0.5:
		_progress_timer = 0.0
		_progress_anchor = global_position
	elif _progress_timer > _settings.stuck_seconds:
		_give_up_on_destination()


func _give_up_on_destination() -> void:
	stuck_events += 1
	_progress_timer = 0.0
	if cover != null and CoverScoring.flat_distance(_move_target, cover.position) < 1.0:
		AI.block_cover(cover)
	AI.release_cover(self)
	cover = null
	_requested_target = Vector3.INF
	if noise_position != Vector3.INF and CoverScoring.flat_distance(_move_target, noise_position) < 1.0:
		noise_position = Vector3.INF  # can't reach what we were investigating


func _pose(delta: float, target: Player) -> void:
	var crouch_goal := 1.0 if _want_crouch else (profile.advance_crouch if _advancing_low else 0.0)
	_crouch = move_toward(_crouch, crouch_goal, delta * 4.0)
	# Hiding at half cover: fold into a hunched kneel so the head is below the top.
	var hide := _want_crouch and cover != null and _at_cover() and not _peeking
	_hunker = move_toward(_hunker, 1.0 if hide or blind_left > 0.0 else 0.0, delta * 5.0)
	var look_at_point := _aim_target(target) if (_fire_mode != 0 or target_visible) else Vector3.INF
	var heading := Vector3.ZERO
	if look_at_point != Vector3.INF:
		heading = look_at_point - global_position
	elif Vector2(velocity.x, velocity.z).length() > 0.3:
		heading = velocity
	elif last_known != Vector3.INF:
		heading = last_known - global_position
	if Vector2(heading.x, heading.z).length() > 0.1:
		var wanted := atan2(-heading.x, -heading.z)
		var turn := deg_to_rad(profile.turn_speed_degrees) * delta
		rotation.y = rotate_toward(rotation.y, wanted, turn)
	var pitch := 0.0
	if look_at_point != Vector3.INF:
		var from := eye_point()
		var flat := Vector2(look_at_point.x - from.x, look_at_point.z - from.z).length()
		pitch = atan2(look_at_point.y - from.y, flat)
	_aim_pitch = rotate_toward(_aim_pitch, pitch, deg_to_rad(profile.aim_turn_degrees_per_second) * delta)
	var aiming := _fire_mode != 0 or target_visible or brain.action in [SoldierBrain.Action.ENGAGE, SoldierBrain.Action.SUPPRESS]
	mannequin.pose(delta, _crouch, _aim_pitch, Vector2(velocity.x, velocity.z).length(), aiming, _hunker)


func _sync_hitbox() -> void:
	var to_local := hitbox.global_transform.affine_inverse()
	for part_name: String in _zone_shapes:
		var part: Node3D = mannequin.parts[part_name]
		_zone_shapes[part_name].transform = to_local * part.global_transform * mannequin.shapes[part_name][1]


func _on_damaged(info: Dictionary) -> void:
	var direction: Vector3 = info.get("direction", Vector3.ZERO)
	mannequin.flinch(direction, 3.0)
	suppression = minf(1.0, suppression + _settings.hit_suppression)
	_alert()
	_take_fire()
	var shooter: Object = info.get("shooter")
	if shooter is Node3D and not target_visible:
		last_known = (shooter as Node3D).global_position
		time_since_seen = minf(time_since_seen, 0.5)


func _on_died(info: Dictionary) -> void:
	dead = true
	AI.release_cover(self)
	AI.release_flank(self)
	AI.unregister(self)
	var part := "torso"
	var shape_node := hitbox.shape_node(info.get("shape", -1))
	if shape_node != null:
		part = str(shape_node.get_meta("part", "torso"))
	var direction: Vector3 = info.get("direction", -global_basis.z * -1.0)
	var energy: float = info.get("energy", 0.5)
	var push := direction * profile.death_push_speed * (0.5 + energy)
	var ragdoll := Ragdoll.from_mannequin(mannequin, get_parent(), velocity, part, push)
	ragdoll.freeze_after = AI.settings.corpse_freeze_after
	AI.add_corpse(ragdoll)
	AI.soldier_died.emit(self)
	queue_free()


func _update_debug_label(action: SoldierBrain.Action) -> void:
	_debug_label.visible = AI.show_debug
	if not AI.show_debug:
		return
	_debug_label.text = "%s %s\naware %.2f  supp %.2f\nhp %d  armour %d  ammo %d\n%s" % [
			profile.display_name, SoldierBrain.Action.keys()[action], awareness, suppression,
			roundi(health.model.health), roundi(health.model.armor), weapon.ammo,
			"cover %s%s" % ["full" if cover != null and last_known != Vector3.INF and AI.cover_is_full(cover, last_known) else "half",
					" peek" if _peeking else ""] if cover != null else "no cover"]
