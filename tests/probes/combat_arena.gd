extends Node
## Headless combat probe for the Milestone 3 exit check. Loads the arena,
## lets the squad fight a camping (invulnerable) player, and checks: setup,
## spotting, everyone reaching cover, nobody stuck, the player getting hit,
## a flank, a grenade, a headshot kill into a ragdoll that settles, blast
## damage, death and respawn, and the AI frame-time budget.
## Exit code 0 = all passed.
##
##   $GODOT --headless --path . res://tests/probes/combat_arena.tscn [-- level=res://levels/port/port_yard.tscn]
##   (any level built on the arena's layout and script; default the greybox arena)

const ARENA := "res://levels/greybox/arena.tscn"
const WATCHDOG_SECONDS := 240.0
const AI_BUDGET_MS := 2.0
## A soldier with somewhere to go that moves less than this (m) per second...
const STALL_DISTANCE := 0.3
## ...for this many seconds in a row counts as stuck.
const STUCK_LIMIT := 4

var arena: Node3D
var player: Player
var failures := 0
var _hits_on_player := 0
var _ai_ms_samples: Array[float] = []
var _flanked := false
var _worst_stall := 0
var _worst_stall_detail := ""
var _stall: Dictionary = {}  # soldier -> [last position, seconds stalled]
var _reached_cover: Dictionary = {}  # soldiers that have been in cover (or charged) at least once


func _ready() -> void:
	var level := ARENA
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("level="):
			level = arg.trim_prefix("level=")
	print("level: %s" % level)
	arena = load(level).instantiate()
	add_child(arena)
	player = arena.get_node("Player")
	get_tree().create_timer(WATCHDOG_SECONDS).timeout.connect(func() -> void:
		printerr("FAIL watchdog: probe did not finish in %d s" % WATCHDOG_SECONDS)
		get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	await arena.combat_ready
	player.health.invulnerable = true
	player.health.damaged.connect(func(_info: Dictionary) -> void: _hits_on_player += 1)

	await _check("navmesh, cover map and squad are set up", func() -> String:
		var polygons: int = arena.get_node("Navigation").navigation_mesh.get_polygon_count()
		var ok: bool = polygons > 100 and arena.cover_points > 200 and AI.soldiers.size() == 5
		print("  %d navmesh polygons, %d cover points, %d soldiers" % [polygons, arena.cover_points, AI.soldiers.size()])
		return "" if ok else "polygons %d, cover %d, soldiers %d" % [polygons, arena.cover_points, AI.soldiers.size()])

	await _check("soldiers spot a player standing in the open", func() -> String:
		# Spotted = alerted (awareness reached 1, by sight or a squadmate's report).
		# Awareness itself sags below 1 whenever a soldier moving up loses sight
		# behind cover, so sampling it once a second missed soldiers mid-advance.
		var aware := await _watch(8.0, func() -> bool: return _count(func(s: Soldier) -> bool: return s._alerted) >= 3)
		if not aware:
			_explain_spotting()
		return "" if aware else "only %d alerted" % _count(func(s: Soldier) -> bool: return s._alerted))

	await _check("every soldier gets to cover (or charges in)", func() -> String:
		var settled := await _watch(25.0, func() -> bool:
			return _count(func(s: Soldier) -> bool: return _reached_cover.has(s)) == AI.soldiers.size())
		return "" if settled else "never in cover: %s" % _states(func(s: Soldier) -> bool: return not _reached_cover.has(s)))

	await _check("the squad hits a camping player, flanks and throws a grenade", func() -> String:
		var done := await _watch(60.0, func() -> bool:
			return _hits_on_player > 0 and _flanked and AI.grenades_thrown > 0)
		print("  %d hits on the player, flanked %s, %d grenades" % [_hits_on_player, _flanked, AI.grenades_thrown])
		return "" if done else "hits %d, flanked %s, grenades %d" % [_hits_on_player, _flanked, AI.grenades_thrown])

	await _check("nobody stays stuck (%d s limit)" % STUCK_LIMIT, func() -> String:
		var stuck_events := 0
		for soldier in AI.soldiers:
			stuck_events += soldier.stuck_events
		print("  longest stall %d s, %d give-ups" % [_worst_stall, stuck_events])
		return "" if _worst_stall < STUCK_LIMIT else "stood still %d s: %s" % [_worst_stall, _worst_stall_detail])

	await _check("AI stays within %.1f ms per frame" % AI_BUDGET_MS, func() -> String:
		var total := 0.0
		var worst := 0.0
		for sample in _ai_ms_samples:
			total += sample
			worst = maxf(worst, sample)
		var average := total / maxf(1.0, _ai_ms_samples.size())
		print("  AI average %.2f ms, worst second %.2f ms (%d soldiers)" % [average, worst, AI.soldiers.size()])
		return "" if average < AI_BUDGET_MS else "average %.2f ms" % average)

	await _check("hiding soldiers are really hidden from the player", func() -> String:
		var hidden := 0
		var hiding := 0
		for second in 10:
			await get_tree().create_timer(1.0).timeout
			_sample()
			var space := player.get_world_3d().direct_space_state
			for soldier in AI.soldiers:
				if soldier.cover == null or not soldier._at_cover() or soldier._peeking 						or soldier.brain.action == SoldierBrain.Action.TAKE_COVER:
					continue
				if not AI.cover_is_full(soldier.cover, player.global_position) and soldier._hunker < 0.9:
					continue
				hiding += 1
				var head: Vector3 = soldier.mannequin.parts.head.global_position
				var query := PhysicsRayQueryParameters3D.create(player.head_point(), head, PhysicsLayers.WORLD)
				if not space.intersect_ray(query).is_empty():
					hidden += 1
		print("  %d of %d hiding samples had the head out of the player's sight" % [hidden, hiding])
		return "" if hiding > 0 and hidden >= hiding * 0.8 else "%d of %d hidden" % [hidden, hiding])

	await _check("a near miss makes a peeking soldier duck", func() -> String:
		var peeker: Soldier = null
		for second in 15:
			await get_tree().create_timer(0.5).timeout
			for soldier in AI.soldiers:
				# Peeking and actually out of cover: a soldier still stepping out
				# from behind a container cannot be near-missed.
				if soldier._peeking and _exposed_to_player(soldier):
					peeker = soldier
			if peeker != null:
				break
		if peeker == null:
			return "nobody peeked into the open"
		var head: Vector3 = peeker.mannequin.parts.head.global_position
		var beside := head + peeker.global_basis.x * 0.6 + Vector3.UP * 0.3
		var kestrel := load("res://data/weapons/kestrel.tres") as WeaponDefinition
		var shot_from := player.head_point()
		Ballistics.fire(shot_from, (beside - shot_from).normalized(), kestrel, player, player.bullet_exclude())
		await get_tree().create_timer(0.25).timeout
		if not is_instance_valid(peeker):
			return "peeker vanished"
		if peeker._peeking:
			_explain_near_miss(peeker, shot_from, beside)
		return "" if not peeker._peeking else "still peeking (suppression %.2f)" % peeker.suppression)

	await _check("a soldier flanked in its cover moves", func() -> String:
		var hider: Soldier = null
		for second in 10:
			await get_tree().create_timer(0.5).timeout
			for soldier in AI.soldiers:
				if soldier._facts.in_cover and not soldier._peeking:
					hider = soldier
			if hider != null:
				break
		if hider == null:
			return "nobody holding cover"
		var old_cover := hider.cover
		var old_position := hider.global_position
		# Stand somewhere beside it that its cover doesn't protect against.
		var space := player.get_world_3d().direct_space_state
		var spot := Vector3.INF
		for i in 16:
			var angle := TAU * i / 16.0
			var candidate := NavigationServer3D.map_get_closest_point(AI.nav_map,
					old_position + Vector3(sin(angle), 0, cos(angle)) * 7.0)
			if AI.cover_protection(old_cover, candidate) > 0.0:
				continue
			var query := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 1.6, hider.aim_point(), PhysicsLayers.WORLD)
			if space.intersect_ray(query).is_empty():
				spot = candidate
				break
		if spot == Vector3.INF:
			return "no flanking spot around it"
		player.global_position = spot
		player.velocity = Vector3.ZERO
		await get_tree().create_timer(4.0).timeout
		if not is_instance_valid(hider) or hider.dead:
			return ""  # died trying: it at least didn't sit still
		var moved := hider.global_position.distance_to(old_position)
		print("  flanked soldier moved %.1f m, new cover %s" % [moved, hider.cover != old_cover])
		return "" if moved > 1.5 or hider.cover != old_cover else "stayed put (%s)" % SoldierBrain.Action.keys()[hider.brain.action])

	await _check("a headshot kill becomes a ragdoll that settles on the floor", func() -> String:
		var soldier := AI.soldiers[0]
		AI.frozen = true
		var head: Vector3 = soldier.mannequin.parts.head.global_position + Vector3.UP * 0.12
		# From wherever is open: soldiers face the player with cover in between,
		# and often back up against a container too.
		var from := _clear_shot_at(head, soldier)
		var kestrel := load("res://data/weapons/kestrel.tres") as WeaponDefinition
		for round in 3:
			if is_instance_valid(soldier) and not soldier.dead:
				Ballistics.fire(from, (head - from).normalized(), kestrel, player, player.bullet_exclude())
				await get_tree().create_timer(0.1).timeout
		AI.frozen = false
		if is_instance_valid(soldier) and not soldier.dead:
			var query := PhysicsRayQueryParameters3D.create(from, head + (head - from).normalized() * 0.5,
					PhysicsLayers.BULLETS, player.bullet_exclude())
			var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
			print("  %s at %s, health %.0f; the shot from %s first hits %s" % [soldier.profile.display_name,
					soldier.global_position.snapped(Vector3.ONE * 0.1), soldier.health.model.health, from.snapped(Vector3.ONE * 0.1),
					"nothing" if hit.is_empty() else "%s (%s) at %s" % [(hit.collider as Node).name,
					(hit.collider as Node).get_parent().name, (hit.position as Vector3).snapped(Vector3.ONE * 0.01)]])
			return "still alive after 3 headshots"
		var ragdoll: Ragdoll = null
		for node in arena.get_children():
			if node is Ragdoll:
				ragdoll = node
		if ragdoll == null:
			return "no ragdoll"
		var fastest := 0.0
		for frame in 30:  # the first quarter second: does anything fly off?
			await get_tree().physics_frame
			for body: RigidBody3D in ragdoll.bodies.values():
				fastest = maxf(fastest, body.linear_velocity.length())
		var settled := await _watch(8.0, func() -> bool: return ragdoll.settled())
		var torso_height: float = ragdoll.bodies.torso.global_position.y
		var knees := [ragdoll.bend("thigh_l", "shin_l"), ragdoll.bend("thigh_r", "shin_r")]
		var elbows := [ragdoll.bend("upper_arm_l", "lower_arm_l"), ragdoll.bend("upper_arm_r", "lower_arm_r")]
		print("  ragdoll settled %s, torso at %.2f m, fastest part %.1f m/s, knees %+.0f/%+.0f, elbows %+.0f/%+.0f" % [
				settled, torso_height, fastest, knees[0], knees[1], elbows[0], elbows[1]])
		var natural: bool = knees[0] <= 15.0 and knees[1] <= 15.0 and elbows[0] >= -20.0 and elbows[1] >= -20.0
		var ok := settled and torso_height < 0.6 and fastest < 6.0 and natural
		return "" if ok else "settled %s, torso %.2f m, fastest %.1f m/s, knees %s, elbows %s" % [
				settled, torso_height, fastest, knees, elbows])

	await _check("a grenade at a soldier's feet hurts or kills them", func() -> String:
		if AI.soldiers.is_empty():
			return "no soldiers left"
		var soldier := AI.soldiers[0]
		var before: float = soldier.health.model.health + soldier.health.model.armor
		AI.frozen = true
		var frag := load("res://data/grenades/frag.tres") as GrenadeDefinition
		Grenade.throw(frag, arena, soldier.global_position + Vector3(0.5, 0.3, 0), Vector3.ZERO, player)
		await get_tree().create_timer(frag.fuse_time + 0.3).timeout
		AI.frozen = false
		if not is_instance_valid(soldier) or soldier.dead:
			print("  killed by the blast")
			return ""
		var after: float = soldier.health.model.health + soldier.health.model.armor
		print("  blast took %.0f of %.0f" % [before - after, before])
		return "" if after < before - 50.0 else "only %.0f damage" % (before - after))

	await _check("the player dies and respawns somewhere safe, protected", func() -> String:
		player.health.invulnerable = false
		AI.frozen = true  # respawn is under test, not the squad: no rounds in flight at the new player
		Debug.execute("kill")
		if not player.dead:
			return "kill did not kill"
		await get_tree().create_timer(player.tuning.respawn_delay + 0.5).timeout
		AI.frozen = false
		var nearest := INF
		for soldier in AI.soldiers:
			nearest = minf(nearest, CoverScoring.flat_distance(soldier.global_position, player.global_position))
		var home := player.global_position.distance_to(Vector3(0, 0, 26))
		var safe := home < 1.0 or nearest >= 15.0
		var ok := not player.dead and is_equal_approx(player.health.fraction(), 1.0) and safe and player.health.protected_left > 0.0
		return "" if ok else "dead %s, health %.2f, nearest enemy %.1f m, protected %.1f s" % [player.dead, player.health.fraction(), nearest, player.health.protected_left])

	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)


## A firing point 3 m from `target` in open air with a clear line to it:
## behind the soldier, either side, in front, or straight above.
func _clear_shot_at(target: Vector3, soldier: Soldier) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	var basis := soldier.global_basis
	for direction in [basis.z, basis.x, -basis.x, -basis.z, Vector3.UP]:
		var from: Vector3 = target + direction * 3.0 + Vector3.UP * 0.2
		var inside := PhysicsPointQueryParameters3D.new()
		inside.position = from
		inside.collision_mask = PhysicsLayers.WORLD
		if not space.intersect_point(inside).is_empty():
			continue
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(from, target, PhysicsLayers.WORLD)).is_empty():
			return from
	return target + Vector3.UP * 3.0


## The player has a clear line to the soldier's head.
func _exposed_to_player(soldier: Soldier) -> bool:
	var head: Vector3 = soldier.mannequin.parts.head.global_position
	var query := PhysicsRayQueryParameters3D.create(player.head_point(), head, PhysicsLayers.WORLD)
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Why soldiers have not spotted the player: each one's awareness, distance,
## view angle and what (if anything) blocks its eye line.
func _explain_spotting() -> void:
	var space := player.get_world_3d().direct_space_state
	for soldier in AI.soldiers:
		var blocked := "clear"
		for point in [player.head_point(), player.aim_point()]:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(soldier.eye_point(), point, PhysicsLayers.WORLD))
			blocked = "clear" if hit.is_empty() else "blocked by %s at %s" % [(hit.collider as Node).name, (hit.position as Vector3).snapped(Vector3.ONE * 0.1)]
			if hit.is_empty():
				break
		var offset := player.global_position - soldier.global_position
		var forward := -soldier.global_basis.z
		var angle := rad_to_deg(Vector2(forward.x, forward.z).angle_to(Vector2(offset.x, offset.z)))
		print("  %s at %s: alerted %s, awareness %.2f, %.1f m, %.0f deg off its facing, %s, action %s" % [soldier.profile.display_name,
				soldier.global_position.snapped(Vector3.ONE * 0.1), soldier._alerted, soldier.awareness, offset.length(), angle, blocked,
				SoldierBrain.Action.keys()[soldier.brain.action]])


## Why a near miss did not make the peeker duck: where the shot went.
func _explain_near_miss(peeker: Soldier, from: Vector3, beside: Vector3) -> void:
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + (beside - from).normalized() * 200.0,
			PhysicsLayers.BULLETS, player.bullet_exclude())
	var hit := space.intersect_ray(query)
	var what := "nothing" if hit.is_empty() else "%s at %s (%.1f m short of the peeker)" % [(hit.collider as Node).name,
			(hit.position as Vector3).snapped(Vector3.ONE * 0.1), from.distance_to(beside) - from.distance_to(hit.position)]
	print("  peeker %s at %s, %.1f m away, suppression %.2f; the shot first hits %s" % [peeker.profile.display_name,
			peeker.global_position.snapped(Vector3.ONE * 0.1), from.distance_to(beside), peeker.suppression, what])


## Steps one second at a time for up to `seconds`, sampling AI cost, flanks
## and stalls, until `done` returns true. Returns whether it did.
func _watch(seconds: float, done: Callable) -> bool:
	for i in ceili(seconds):
		await get_tree().create_timer(1.0).timeout
		_sample()
		if done.call():
			return true
	return false


func _sample() -> void:
	_ai_ms_samples.append(AI.frame_ms)
	for soldier in AI.soldiers:
		if soldier._facts.in_cover or soldier.brain.action == SoldierBrain.Action.CHARGE:
			_reached_cover[soldier] = true
		if soldier.brain.action == SoldierBrain.Action.FLANK and soldier.cover != null and soldier.cover_mode == "flank":
			_flanked = true
		var moving_somewhere: bool = soldier._move_target != Vector3.INF \
				and CoverScoring.flat_distance(soldier.global_position, soldier._move_target) > 1.0
		var entry: Array = _stall.get(soldier, [soldier.global_position, 0])
		if moving_somewhere and soldier.global_position.distance_to(entry[0]) < STALL_DISTANCE:
			entry[1] += 1
			if entry[1] > _worst_stall:
				_worst_stall = entry[1]
				_worst_stall_detail = "%s %s at %s heading for %s (path %d/%d)" % [soldier.profile.display_name,
						SoldierBrain.Action.keys()[soldier.brain.action], soldier.global_position.snappedf(0.1),
						soldier._move_target.snappedf(0.1), soldier._path_index, soldier._path.size()]
		else:
			entry[1] = 0
		entry[0] = soldier.global_position
		_stall[soldier] = entry


func _count(test: Callable) -> int:
	var count := 0
	for soldier in AI.soldiers:
		if test.call(soldier):
			count += 1
	return count


func _states(which: Callable) -> String:
	var states := PackedStringArray()
	for soldier in AI.soldiers:
		if which.call(soldier):
			states.append("%s %s" % [soldier.profile.display_name, SoldierBrain.Action.keys()[soldier.brain.action]])
	return ", ".join(states)


func _check(title: String, body: Callable) -> void:
	var detail: String = await body.call()
	if detail.is_empty():
		print("PASS %s" % title)
	else:
		failures += 1
		printerr("FAIL %s - %s" % [title, detail])
