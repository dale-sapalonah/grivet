extends Node
## Squadmate probe (port): it stands by the player at the start, keeps up when
## the player moves, finds and shoots an enemy in view, holds fire with the
## player in its line of fire, gets back up after being shot down, and
## regroups at the next stage. Exit 0 = pass.
##
##   $GODOT --headless --path . res://tests/probes/squadmate.tscn

const LEVEL := "res://levels/port/port_yard.tscn"

var level: Node3D
var player: Player
var mate: Squadmate
var failures := 0


func _ready() -> void:
	level = load(LEVEL).instantiate()
	add_child(level)
	player = level.get_node("Player")
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		printerr("FAIL watchdog")
		get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	await level.combat_ready
	await get_tree().physics_frame
	player.health.invulnerable = true
	mate = get_tree().get_first_node_in_group("allies") as Squadmate
	_check("a squadmate stands by the player at the start", mate != null and _gap() < AI.settings.squad_follow_max + 1.0,
			"gap %.1f m" % (_gap() if mate != null else -1.0))
	if mate == null:
		return _finish()
	# Clear the field: nobody to fight while we test following.
	Debug.execute("ai.kill")
	await get_tree().create_timer(0.5).timeout
	var away := _open_point(player.global_position, 14.0)
	player.global_position = away
	await get_tree().create_timer(10.0).timeout
	_check("it keeps up when the player moves off", _gap() < AI.settings.squad_follow_max + 1.5, "gap %.1f m" % _gap())
	# One enemy in the open, in its sight, frozen so it doesn't fight back.
	var enemy_at := _open_point(mate.global_position, 18.0, mate.eye_point())
	var enemy := AI.spawn("rifleman", Transform3D(Basis.IDENTITY, enemy_at), level)
	for i in 4:
		await get_tree().process_frame  # posed, so its hit zones sit on its body
	AI.frozen = true
	await get_tree().physics_frame
	# The player stands right in the line of fire: it must hold.
	var line_point := mate.global_position.lerp(enemy_at, 0.35)
	var waited := 0.0
	var before := mate.shots_fired
	while waited < 3.0:
		player.global_position = Vector3(line_point.x, player.global_position.y, line_point.z)
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_check("it holds fire with the player in the way", mate.shots_fired == before,
			"%d shots through the player" % (mate.shots_fired - before))
	# Out of the way: it should open up and kill the enemy.
	var side := (enemy_at - mate.global_position).cross(Vector3.UP).normalized()
	player.global_position = mate.global_position + side * 3.0 + Vector3.UP * 0.2
	waited = 0.0
	while is_instance_valid(enemy) and not enemy.dead and waited < 20.0:
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_check("it shoots an enemy it can see", mate.shots_fired > before, "never fired")
	_check("and kills it", not is_instance_valid(enemy) or enemy.dead, "enemy alive after 20 s, %d shots, health %.0f armour %.0f, %.1f m" % [mate.shots_fired,
			enemy.health.model.health, enemy.health.model.armor, mate.global_position.distance_to(enemy.global_position)] if is_instance_valid(enemy) else "")
	AI.frozen = false
	# Shot down: stays down, then gets up.
	AI.settings.squad_downed_seconds = 2.0
	Debug.execute("squad.down")
	await get_tree().physics_frame
	_check("shot down, it goes down", mate.downed, "not down")
	await get_tree().create_timer(2.5).timeout
	_check("and gets back up", not mate.downed and mate.health.model.health > 0.0, "still down")
	# The next stage regroups it at the player's new start.
	Debug.execute("stage 2")
	await get_tree().create_timer(1.0).timeout
	_check("a new stage regroups it by the player", _gap() < AI.settings.squad_follow_max + 1.0, "gap %.1f m" % _gap())
	_finish()


func _gap() -> float:
	return CoverScoring.flat_distance(mate.global_position, player.global_position)


## A navmesh point about `distance` m from `from` with a clear line from
## `eye` (default: from + 1.6 m up) to it.
func _open_point(from: Vector3, distance: float, eye: Vector3 = Vector3.INF) -> Vector3:
	var space := level.get_world_3d().direct_space_state
	var map := level.get_world_3d().navigation_map
	if eye == Vector3.INF:
		eye = from + Vector3.UP * 1.6
	for i in 24:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 24.0)
		var point := NavigationServer3D.map_get_closest_point(map, from + direction * distance)
		var ground := Vector3(point.x, from.y, point.z)
		if CoverScoring.flat_distance(ground, from) < distance * 0.7:
			continue
		var query := PhysicsRayQueryParameters3D.create(eye, ground + Vector3.UP * 1.3, PhysicsLayers.WORLD)
		if space.intersect_ray(query).is_empty():
			return ground
	return from + Vector3.FORWARD * distance


func _finish() -> void:
	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s" % what)
	else:
		failures += 1
		print("FAIL %s - %s" % [what, detail])
