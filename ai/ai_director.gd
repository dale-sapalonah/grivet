extends Node
## Autoloaded as `AI`. What soldiers share: the target (the player, unless
## `notarget`), the cover map and who holds which point, the flank slot, the
## grenade cooldown, shared sightings, sounds (player gunfire, blasts) and
## near misses from Ballistics. Owns enemy spawning, corpse cleanup, AI
## frame-time accounting and the AI debug commands.

signal soldier_died(soldier: Soldier)
signal grenade_thrown(soldier: Soldier)

const SETTINGS := preload("res://data/ai/ai_settings.tres")
const SOLDIER_SCENE := "res://ai/soldier.tscn"
const PROFILES := {"rifleman": "res://data/ai/rifleman.tres", "rusher": "res://data/ai/rusher.tres",
		"machete": "res://data/ai/machete.tres"}
const GRENADE := "res://data/grenades/frag.tres"

var settings: AiSettings = SETTINGS
var soldiers: Array[Soldier] = []
## Spent casings from every soldier's weapon (one shared pool).
var casings := CasingEjector.new()
var cover: CoverMap = null
var nav_map := RID()
var grenade_definition: GrenadeDefinition
var notarget := false
var frozen := false
var show_debug := false
## Smoothed total AI time per physics frame (ms), for budgets and probes.
var frame_ms := 0.0
var grenades_thrown := 0

var _player: Player
var _flankers: Array[Soldier] = []
var _grenade_ready_at := 0.0
var _corpses: Array[Node] = []
var _frame_usec := 0
var _pin_anchor := Vector3.INF
var _pinned_time := 0.0
var _connected_holder: Node = null


func _ready() -> void:
	process_priority = -10  # read last frame's AI time before soldiers add this frame's
	process_physics_priority = -10
	grenade_definition = load(GRENADE)
	casings.max_casings = 60
	add_child(casings)
	var enemy_weapons: Array[WeaponDefinition] = []
	for path: String in PROFILES.values():
		enemy_weapons.append((load(path) as EnemyProfile).weapon)
	casings.prewarm(enemy_weapons)
	Ballistics.bullet_moved.connect(_on_bullet_moved)
	Ballistics.impact.connect(_on_impact)
	Debug.register("spawn", _cmd_spawn, "spawn <rifleman|rusher> [count] [distance]: spawn enemies ahead of you (default 20 m).")
	Debug.register("ai.show", _cmd_show, "Toggle AI state labels above enemies.")
	Debug.register("ai.freeze", _cmd_freeze, "Freeze / unfreeze all enemies.")
	Debug.register("ai.kill", _cmd_kill, "Kill every enemy.")
	Debug.register("notarget", _cmd_notarget, "Enemies ignore you.")
	Debug.register("ai.time", _cmd_time, "AI cost per frame.")


func _physics_process(delta: float) -> void:
	frame_ms = lerpf(frame_ms, _frame_usec / 1000.0, 0.1)
	_frame_usec = 0
	_find_player()
	_track_pinning(delta)


func add_frame_time(usec: int) -> void:
	_frame_usec += usec


## The player, unless dead, absent or `notarget`.
func target() -> Player:
	if notarget or _player == null or not is_instance_valid(_player) or _player.dead:
		return null
	return _player


func register(soldier: Soldier) -> void:
	if not soldiers.has(soldier):
		soldiers.append(soldier)


func unregister(soldier: Soldier) -> void:
	soldiers.erase(soldier)
	_flankers.erase(soldier)
	release_cover(soldier)


## Spawns an enemy of `kind` ("rifleman", "rusher") at `at` under `parent`.
## The player respawned elsewhere: everyone loses track of them (still wary)
## and has to find them again.
func forget_target() -> void:
	for soldier in soldiers:
		soldier.forget_target()


## `stage`, when given, sharpens the soldier: a copy of its profile with the
## stage's aim, reaction, damage and awareness multipliers applied.
func spawn(kind: String, at: Transform3D, parent: Node, stage: CampaignStage = null) -> Soldier:
	var soldier: Soldier = load(SOLDIER_SCENE).instantiate()
	var profile: EnemyProfile = load(PROFILES[kind])
	if stage != null:
		profile = profile.duplicate()
		profile.aim_error_degrees *= stage.aim_error_multiplier
		profile.aim_error_per_10m *= stage.aim_error_multiplier
		profile.reaction_time *= stage.reaction_multiplier
		profile.damage_multiplier *= stage.damage_multiplier
		profile.awareness_gain *= stage.awareness_multiplier
	soldier.profile = profile
	parent.add_child(soldier)
	soldier.global_transform = at
	return soldier


# --- Cover -----------------------------------------------------------------------

func build_cover(space: PhysicsDirectSpaceState3D, map: RID, bounds: AABB) -> int:
	nav_map = map
	cover = CoverMap.new(settings)
	return cover.build(space, map, bounds)


func cover_protection(point: CoverMap.Point, threat: Vector3) -> float:
	return cover.protection(point, threat) if cover != null and point != null else 0.0


func cover_is_full(point: CoverMap.Point, threat: Vector3) -> bool:
	return cover != null and point != null and cover.is_full(point, threat)


func release_cover(soldier: Soldier) -> void:
	if cover != null:
		cover.release(soldier)


## Nobody is sent to `point` for `seconds` (default blocked_cover_seconds):
## someone couldn't reach it, or the enemy can see into it.
func block_cover(point: CoverMap.Point, seconds: float = -1.0) -> void:
	if point != null:
		point.blocked_until = Time.get_ticks_msec() / 1000.0 + (seconds if seconds > 0.0 else settings.blocked_cover_seconds)


## Best cover for `soldier` against its target's last known position.
## mode: "cover" (nearest good), "flank" (wide angle around the target),
## "push" (closer to the target than now), "retreat" (further away).
## The top candidates get a real line-of-sight check from the threat.
func request_cover(soldier: Soldier, mode: String) -> CoverMap.Point:
	if cover == null:
		return null
	var threat := soldier.last_known
	if threat == Vector3.INF:
		var player := target()
		if player == null:
			return null
		threat = player.global_position
	var here := soldier.global_position
	var current_range := CoverScoring.flat_distance(here, threat)
	var flank_from := here if mode == "flank" else Vector3.INF
	var scored: Array = []
	var now := Time.get_ticks_msec() / 1000.0
	var radius := soldier.profile.cover_search_radius
	if mode == "flank":
		radius *= settings.flank_search_multiplier  # going around takes a longer move
	for point in cover.within(here, radius):
		if point.blocked_until > now:
			continue
		var range_to_threat := CoverScoring.flat_distance(point.position, threat)
		if mode == "push" and range_to_threat > current_range - 2.0:
			continue
		if mode == "retreat" and range_to_threat < current_range + 5.0:
			continue
		var occupied := point.reserved_by != null and point.reserved_by != soldier
		var value := CoverScoring.score(settings, point.position, cover.protection(point, threat),
				here, threat, soldier.profile, occupied, flank_from)
		if value > -INF:
			scored.append([value, point])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var space := soldier.get_world_3d().direct_space_state
	var checked := 0
	for entry in scored:
		if checked >= settings.cover_candidates_checked:
			break
		checked += 1
		var point: CoverMap.Point = entry[1]
		var chest := point.position + Vector3.UP * (1.2 if cover.is_full(point, threat) else 0.8)
		var query := PhysicsRayQueryParameters3D.create(threat + Vector3.UP * 1.6, chest, PhysicsLayers.WORLD)
		if space.intersect_ray(query).is_empty():
			continue  # the threat can see it after all
		var path := NavigationServer3D.map_get_path(nav_map, here, point.position, true)
		if path.is_empty() or CoverScoring.flat_distance(path[path.size() - 1], point.position) > settings.cover_reach_tolerance:
			continue  # can't actually get there (sealed room, other side of a wall)
		cover.release(soldier)
		point.reserved_by = soldier
		return point
	return null


# --- Coordination --------------------------------------------------------------

## Is the target aiming roughly at `soldier` (within facing_cone_degrees)?
func target_facing(soldier: Soldier) -> bool:
	var player := target()
	if player == null:
		return false
	var aim := player.aim_transform()
	var to := soldier.aim_point() - aim.origin
	return (-aim.basis.z).angle_to(to) < deg_to_rad(settings.facing_cone_degrees)


func target_reloading() -> bool:
	var holder := get_tree().get_first_node_in_group("player_weapons") as WeaponHolder
	if holder == null or holder.current_weapon() == null:
		return false
	return holder.current_weapon().state in [WeaponModel.State.RELOADING, WeaponModel.State.PUMPING,
			WeaponModel.State.EQUIPPING]


func flank_available(soldier: Soldier) -> bool:
	return _flankers.has(soldier) or _flankers.size() < settings.max_flankers


func take_flank(soldier: Soldier) -> bool:
	if _flankers.has(soldier):
		return true
	if _flankers.size() >= settings.max_flankers:
		return false
	_flankers.append(soldier)
	return true


func release_flank(soldier: Soldier) -> void:
	_flankers.erase(soldier)


func anyone_flanking(except: Soldier) -> bool:
	for soldier in _flankers:
		if soldier != except:
			return true
	return false


func allies_engaging(except: Soldier) -> int:
	var count := 0
	for soldier in soldiers:
		if soldier != except and soldier.brain != null and soldier.brain.action in [
				SoldierBrain.Action.ENGAGE, SoldierBrain.Action.SUPPRESS]:
			count += 1
	return count


func grenade_allowed() -> bool:
	return Time.get_ticks_msec() / 1000.0 >= _grenade_ready_at


func note_grenade(soldier: Soldier) -> void:
	_grenade_ready_at = Time.get_ticks_msec() / 1000.0 + settings.grenade_cooldown
	grenades_thrown += 1
	grenade_thrown.emit(soldier)


## How long the target has stayed within pinned_radius of one spot (s).
func target_pinned_time() -> float:
	return _pinned_time


func share_sighting(spotter: Soldier, position: Vector3) -> void:
	for soldier in soldiers:
		if soldier != spotter and soldier.global_position.distance_to(spotter.global_position) <= settings.share_radius:
			soldier.receive_report(position)


## A sound everyone within `radius` (scaled by their hearing) may notice.
func make_noise(position: Vector3, radius: float, source: Node) -> void:
	for soldier in soldiers.duplicate():
		soldier.hear(position, radius, source)


func add_corpse(ragdoll: Node) -> void:
	_corpses.append(ragdoll)
	while _corpses.size() > settings.max_corpses:
		var oldest: Node = _corpses.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _find_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = get_tree().get_first_node_in_group("player") as Player
	_connected_holder = null
	if _player == null:
		return
	var holder := get_tree().get_first_node_in_group("player_weapons")
	if holder != null and holder != _connected_holder:
		holder.shot_fired.connect(func(weapon: WeaponDefinition) -> void:
			if _player != null and is_instance_valid(_player):
				make_noise(_player.global_position, weapon.shot_loudness, _player))
		_connected_holder = holder


func _track_pinning(delta: float) -> void:
	var player := target()
	if player == null:
		_pinned_time = 0.0
		_pin_anchor = Vector3.INF
		return
	if _pin_anchor == Vector3.INF or player.global_position.distance_to(_pin_anchor) > settings.pinned_radius:
		_pin_anchor = player.global_position
		_pinned_time = 0.0
	else:
		_pinned_time += delta


## Enemy rounds passing close to a soldier suppress them. Friendly fire
## (another soldier's rounds or fragments) is ignored: it must not move a
## soldier's idea of where the enemy is onto a teammate.
func _on_bullet_moved(from: Vector3, to: Vector3, shooter: Node) -> void:
	if soldiers.is_empty() or shooter is Soldier:
		return
	var shooter_position := (shooter as Node3D).global_position if shooter is Node3D else from
	for soldier in soldiers:
		if soldier == shooter:
			continue
		var chest := soldier.global_position + Vector3.UP * 1.2
		var closest := Geometry3D.get_closest_point_to_segment(chest, from, to)
		var distance := chest.distance_to(closest)
		if distance < settings.near_miss_radius:
			soldier.suppress(settings.near_miss_suppression * (1.0 - distance / settings.near_miss_radius),
					shooter_position)


## Rounds striking near a soldier suppress them too.
func _on_impact(info: Dictionary) -> void:
	var shooter: Node = info.get("shooter")
	if info.kind == "exit" or shooter is Soldier:
		return
	var position: Vector3 = info.position
	for soldier in soldiers:
		if soldier == shooter:
			continue
		var distance := soldier.global_position.distance_to(position)
		if distance < settings.impact_near_radius:
			var shooter_position := (shooter as Node3D).global_position if shooter is Node3D else position
			soldier.suppress(settings.impact_near_suppression * (1.0 - distance / settings.impact_near_radius),
					shooter_position)


# --- Debug commands --------------------------------------------------------------

func _cmd_spawn(args: PackedStringArray) -> String:
	if args.is_empty() or not PROFILES.has(args[0]):
		return "usage: spawn <%s> [count] [distance]" % "|".join(PROFILES.keys())
	var player := _player
	if player == null:
		return "no player"
	var count := args[1].to_int() if args.size() > 1 and args[1].is_valid_int() else 1
	var distance := args[2].to_float() if args.size() > 2 and args[2].is_valid_float() else 20.0
	var forward := -player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	for i in count:
		var spot := player.global_position + forward * (distance + 3.0 * i) + forward.cross(Vector3.UP) * (i - count * 0.5) * 2.0
		if nav_map.is_valid():
			spot = NavigationServer3D.map_get_closest_point(nav_map, spot)
		var facing := Transform3D(Basis.looking_at(-forward), spot)
		spawn(args[0], facing, player.get_parent())
	return "spawned %d %s" % [count, args[0]]


func _cmd_show(_args: PackedStringArray) -> String:
	show_debug = not show_debug
	return "AI labels %s" % ("ON" if show_debug else "OFF")


func _cmd_freeze(_args: PackedStringArray) -> String:
	frozen = not frozen
	return "AI %s" % ("frozen" if frozen else "running")


func _cmd_kill(_args: PackedStringArray) -> String:
	var count := soldiers.size()
	for soldier in soldiers.duplicate():
		soldier.health.take_hit(INF, DamageModel.Zone.HEAD, {})
	return "killed %d" % count


func _cmd_time(_args: PackedStringArray) -> String:
	return "%d soldiers, %.2f ms AI per frame" % [soldiers.size(), frame_ms]


func _cmd_notarget(_args: PackedStringArray) -> String:
	notarget = not notarget
	return "notarget %s" % ("ON" if notarget else "OFF")
