class_name Squadmate
extends CharacterBody3D
## The player's squadmate. Follows off the player's shoulder along the
## navmesh, engages the enemy it can see (closest first) with the same
## weapons, aim error (AimModel) and Ballistics as everyone else, crouched
## while it shoots, and never fires with the player near its line of fire.
## Enemies don't hunt it, but its shots draw their fire (they hear it and
## turn on whoever hit them) and stray rounds hit it. Shot down it stays down
## for squad_downed_seconds, then gets back up; a new stage regroups it.
## Tuning: AiSettings squad_*, look and aim: data/ai/squadmate.tres.

@export var profile: EnemyProfile

var weapon: WeaponModel
## The enemy it is engaging (seen within squad_engage_range), or null.
var target: Soldier
var downed := false
var downed_left := 0.0
## Rounds it has fired (probes).
var shots_fired := 0

var _settings: AiSettings
var _controls := WeaponModel.Controls.new()
var _rng := RandomNumberGenerator.new()
var _sight_timer := 0.0
var _acquired_time := INF
var _reaction_left := 0.0
var _burst_left := 0
var _burst_pause := 0.0
var _trigger_toggle := false
var _crouch := 0.0
var _aim_pitch := 0.0
var _pose_delta := 0.0
var _path := PackedVector3Array()
var _path_index := 0
var _requested := Vector3.INF
var _move_target := Vector3.INF
var _step_distance := 0.0
var _zone_shapes: Dictionary = {}  # part name -> CollisionShape3D
var _muzzle_flash: MuzzleFlash
var _reported_insane := false

## A path corner counts as reached within this flat distance (m).
const PATH_CORNER_RADIUS := 0.4

@onready var health: Health = $Health
@onready var hitbox: Hitbox = $Hitbox
@onready var mannequin: Mannequin = $Mannequin


func _ready() -> void:
	_settings = AI.settings
	_rng.randomize()
	weapon = WeaponModel.new(profile.weapon)
	weapon.infinite_ammo = true
	health.setup(profile.health)
	health.died.connect(_on_downed)
	hitbox.health = health
	hitbox.body = self
	mannequin.build(profile, _rng.randi_range(0, 59))
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
	_sight_timer = _rng.randf() / _settings.squad_sight_hz
	add_to_group("allies")
	Debug.register("squad", _cmd_squad, "Squadmate status.")
	Debug.register("squad.regroup", func(_args: PackedStringArray) -> String:
		regroup()
		return "regrouped at %s" % global_position, "Bring the squadmate to your side.")
	Debug.register("squad.off", func(_args: PackedStringArray) -> String:
		AI.settings.squad_enabled = false
		queue_free()
		return "squadmate gone until the game restarts", "Remove the squadmate.")
	Debug.register("squad.down", func(_args: PackedStringArray) -> String:
		health.take_hit(INF, DamageModel.Zone.HEAD, {})
		return "squadmate down for %.0f s" % downed_left, "Shoot the squadmate down (look check).")


func _exit_tree() -> void:
	for command in ["squad", "squad.regroup", "squad.down", "squad.off"]:
		Debug.unregister(command)


func aim_point() -> Vector3:
	return mannequin.parts.torso.global_position + Vector3.UP * 0.32


func eye_point() -> Vector3:
	return global_position + Vector3.UP * lerpf(1.65, 1.05, _crouch)


## Puts it beside the player (a new stage, or it fell far behind), on its feet.
func regroup() -> void:
	var player := _player()
	if player == null:
		return
	if downed:
		_get_up()
	global_position = _follow_slot(player)
	velocity = Vector3.ZERO
	_path = PackedVector3Array()
	_requested = Vector3.INF
	target = null
	rotation.y = player.rotation.y


func _player() -> Player:
	var player := get_tree().get_first_node_in_group("player") as Player
	return player if player != null and not player.dead else null


func _physics_process(delta: float) -> void:
	if not _sane():
		return
	if downed:
		_update_downed(delta)
		return
	var player := _player()
	_reaction_left -= delta
	_acquired_time += delta
	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer += 1.0 / _settings.squad_sight_hz
		_pick_target()
	_choose_destination(player)
	_update_weapon(delta, player)
	_move(delta)


## Closest enemy it can see within squad_engage_range; a new one costs a
## reaction time and a wild first burst (AimModel), as for the enemy.
func _pick_target() -> void:
	var space := get_world_3d().direct_space_state
	var eye := eye_point()
	var best: Soldier = null
	var best_distance := _settings.squad_engage_range
	for soldier: Soldier in AI.soldiers:
		if soldier.dead or not is_instance_valid(soldier):
			continue
		var distance := eye.distance_to(soldier.aim_point())
		if distance >= best_distance:
			continue
		var query := PhysicsRayQueryParameters3D.create(eye, soldier.aim_point(), PhysicsLayers.WORLD)
		if space.intersect_ray(query).is_empty():
			best = soldier
			best_distance = distance
	if best != target:
		target = best
		_acquired_time = 0.0
		_reaction_left = profile.reaction_time


func _choose_destination(player: Player) -> void:
	if player == null:
		_move_target = Vector3.INF
		return
	var distance := CoverScoring.flat_distance(global_position, player.global_position)
	if distance > _settings.squad_regroup_distance and not _seen_by(player):
		regroup()
		return
	var fighting := is_instance_valid(target)
	# In a fight it holds its ground unless the player is getting away.
	var leash := _settings.squad_follow_max * (2.0 if fighting else 1.0)
	if distance > leash:
		_move_target = _follow_slot(player)
	elif distance < _settings.squad_follow_min or fighting:
		_move_target = Vector3.INF


## Off the player's right shoulder and a little behind, on the navmesh.
func _follow_slot(player: Player) -> Vector3:
	var basis := player.global_basis
	var slot := player.global_position + basis.x * _settings.squad_follow_side_offset + basis.z * 1.5
	var map := get_world_3d().navigation_map
	var on_mesh := NavigationServer3D.map_get_closest_point(map, slot)
	if not on_mesh.is_finite() or on_mesh == Vector3.ZERO and slot.length() > 1.0:
		return player.global_position
	return Vector3(on_mesh.x, player.global_position.y, on_mesh.z)


func _seen_by(player: Player) -> bool:
	var query := PhysicsRayQueryParameters3D.create(player.head_point(), aim_point(), PhysicsLayers.WORLD)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- Weapon --------------------------------------------------------------------

func _update_weapon(delta: float, player: Player) -> void:
	var aim_at := target.aim_point() if is_instance_valid(target) and not target.dead else Vector3.INF
	var want_fire := aim_at != Vector3.INF and _reaction_left <= 0.0 and _facing(aim_at) \
			and _clear_of(player, aim_at)
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
	for i in shots:
		_shoot(aim_at)
		_burst_left -= 1
		if _burst_left <= 0:
			_burst_pause = _rng.randf_range(profile.burst_pause_min, profile.burst_pause_max)


## No shot with the player within squad_friendly_fire_clearance of the line.
func _clear_of(player: Player, aim_at: Vector3) -> bool:
	if player == null:
		return true
	var muzzle := mannequin.muzzle.global_position
	for point in [player.aim_point(), player.head_point()]:
		var closest := Geometry3D.get_closest_point_to_segment(point, muzzle, aim_at)
		if closest.distance_to(point) < _settings.squad_friendly_fire_clearance:
			return false
	return true


func _shoot(aim_at: Vector3) -> void:
	var muzzle := mannequin.muzzle.global_position
	var direction := (aim_at - muzzle).normalized()
	var lateral := 0.0
	if is_instance_valid(target):
		var across := target.velocity - direction * target.velocity.dot(direction)
		lateral = across.length()
	var error := AimModel.error_degrees(profile, muzzle.distance_to(aim_at), 0.0,
			Vector2(velocity.x, velocity.z).length() > 0.5, lateral, _acquired_time)
	direction = BallisticsMath.random_in_cone(direction, error, _rng)
	var exclude: Array[RID] = [hitbox.get_rid()]
	for pellet in weapon.definition.pellets:
		var pellet_direction := direction
		if weapon.definition.pellets > 1:
			pellet_direction = BallisticsMath.random_in_cone(direction, weapon.definition.pellet_spread_degrees, _rng)
		Ballistics.fire(muzzle, pellet_direction, weapon.definition, self, exclude)
	Soundscape.gunshot(weapon.definition, muzzle)
	AI.make_noise(muzzle, weapon.definition.shot_loudness, self)
	_muzzle_flash.flash()
	mannequin.flinch(-global_basis.z, 0.6)
	shots_fired += 1


func _facing(point: Vector3) -> bool:
	var to := point - global_position
	var forward := -global_basis.z
	return absf(Vector2(forward.x, forward.z).angle_to(Vector2(to.x, to.z))) < deg_to_rad(12.0)


# --- Down and up ---------------------------------------------------------------

func _on_downed(_info: Dictionary) -> void:
	downed = true
	downed_left = _settings.squad_downed_seconds
	target = null
	_burst_left = 0
	_move_target = Vector3.INF
	health.invulnerable = true  # down, not dead: it gets back up


func _update_downed(delta: float) -> void:
	downed_left -= delta
	velocity = Vector3(0.0, velocity.y, 0.0)
	if not is_on_floor():
		velocity.y -= Ballistics.settings.gravity * delta
	move_and_slide()
	if downed_left <= 0.0:
		_get_up()


func _get_up() -> void:
	downed = false
	downed_left = 0.0
	health.revive()
	health.model.health = health.profile.max_health * _settings.squad_revive_health
	health.invulnerable = false


# --- Body ----------------------------------------------------------------------

## As Soldier._move: a NavigationServer path, corners judged on the ground plane.
func _move(delta: float) -> void:
	var desired := Vector3.ZERO
	if _move_target != Vector3.INF:
		if _requested == Vector3.INF or _requested.distance_to(_move_target) > 0.75:
			_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, global_position, _move_target, true)
			_path_index = 0
			_requested = _move_target
		while _path_index < _path.size() and CoverScoring.flat_distance(global_position, _path[_path_index]) < PATH_CORNER_RADIUS:
			_path_index += 1
		if _path_index < _path.size():
			var next := _path[_path_index]
			desired = Vector3(next.x - global_position.x, 0.0, next.z - global_position.z).normalized()
		else:
			_move_target = Vector3.INF
	else:
		_requested = Vector3.INF
	var far := _player() != null and CoverScoring.flat_distance(global_position, _player().global_position) > _settings.squad_follow_max * 1.5
	var speed := profile.crouch_speed if _crouch > 0.5 else (profile.run_speed if far else profile.walk_speed * 1.4)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired * speed, 20.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity.y -= Ballistics.settings.gravity * delta
	move_and_slide()
	_step(delta)


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


func _process(delta: float) -> void:
	_pose_delta += delta
	var player := _player()
	var distance_squared := global_position.distance_squared_to(player.global_position) if player != null else 0.0
	mannequin.cast_shadows(distance_squared < _settings.shadow_lod_distance * _settings.shadow_lod_distance)
	_pose(_pose_delta, player)
	_pose_delta = 0.0
	_sync_hitbox()


func _pose(delta: float, player: Player) -> void:
	var fighting := is_instance_valid(target) and not downed
	var moving := Vector2(velocity.x, velocity.z).length() > 0.3
	var crouch_goal := 1.0 if downed or (fighting and not moving) else 0.0
	_crouch = move_toward(_crouch, crouch_goal, delta * 4.0)
	var heading := Vector3.ZERO
	if fighting:
		heading = target.aim_point() - global_position
	elif moving:
		heading = velocity
	elif player != null:
		heading = -player.global_basis.z  # watch the way the player looks
	if not downed and Vector2(heading.x, heading.z).length() > 0.1:
		var wanted := atan2(-heading.x, -heading.z)
		rotation.y = rotate_toward(rotation.y, wanted, deg_to_rad(profile.turn_speed_degrees) * delta)
	var pitch := 0.0
	if fighting:
		var from := eye_point()
		var aim := target.aim_point()
		pitch = atan2(aim.y - from.y, Vector2(aim.x - from.x, aim.z - from.z).length())
	_aim_pitch = rotate_toward(_aim_pitch, pitch, deg_to_rad(profile.aim_turn_degrees_per_second) * delta)
	mannequin.pose(delta, _crouch, _aim_pitch, Vector2(velocity.x, velocity.z).length(), fighting, 1.0 if downed else 0.0)


func _sync_hitbox() -> void:
	var to_local := hitbox.global_transform.affine_inverse()
	for part_name: String in _zone_shapes:
		var part: Node3D = mannequin.parts[part_name]
		_zone_shapes[part_name].transform = to_local * part.global_transform * mannequin.shapes[part_name][1]


## Non-finite state (see Soldier._sane): report once, put it back by the player.
func _sane() -> bool:
	if global_position.is_finite() and velocity.is_finite() and rotation.is_finite():
		return true
	if not _reported_insane:
		_reported_insane = true
		push_error("Squadmate went non-finite: position %s velocity %s - regrouped" % [global_position, velocity])
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	regroup()
	return false


func _cmd_squad(_args: PackedStringArray) -> String:
	var player := _player()
	return "%s: %s, health %.0f, %.1f m from you, target %s, %d shots" % [profile.display_name,
			"down %.0f s" % downed_left if downed else "up", health.model.health,
			CoverScoring.flat_distance(global_position, player.global_position) if player != null else -1.0,
			target.profile.display_name if is_instance_valid(target) else "none", shots_fired]
