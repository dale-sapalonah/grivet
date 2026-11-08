extends Node
## Mission probe (Operesen Klinim Wof on the port): the intro plays with the
## truck and the player held, skips into play; each objective brings in its
## squad and is met (fights cut short with `mission.next`); the search needs
## time in the container; a death respawns at the last checkpoint; reaching
## the truck plays the outro with the stats. Exit 0 = pass.
##
##   $GODOT --headless --path . res://tests/probes/mission.tscn

const MISSION := preload("res://data/missions/port_raid.tres")

var level: Node3D
var player: Player
var runner: MissionRunner
var failures := 0


func _ready() -> void:
	Settings.requested_mission = MISSION
	level = load(MISSION.level).instantiate()
	add_child(level)
	player = level.get_node("Player")
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		printerr("FAIL watchdog")
		get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	await level.combat_ready
	await get_tree().process_frame
	runner = get_tree().get_first_node_in_group("mission") as MissionRunner
	_check("the mission starts with its intro", runner != null and runner.cinematic and runner._phase == "intro",
			"runner %s" % runner)
	if runner == null:
		return _finish()
	_check("the player is held during the intro", player.process_mode == Node.PROCESS_MODE_DISABLED, "player active")
	_check("the police truck is there", runner._truck != null and runner._truck.is_inside_tree(), "no truck")
	await get_tree().create_timer(1.0).timeout
	Debug.execute("mission.skip")
	await get_tree().process_frame
	await get_tree().process_frame
	_check("skipping the intro starts play", runner._phase == "play" and not runner.cinematic, "phase %s" % runner._phase)
	_check("the player stands by the truck", player.global_position.distance_to(MISSION.player_start) < 1.5,
			"at %s" % player.global_position)
	_check("the first objective brings in its squad", AI.soldiers.size() > 0 and runner.state.index == 0, "%d soldiers" % AI.soldiers.size())
	player.health.invulnerable = true
	await _next_objective()
	_check("clearing the yard moves on to the search", runner.state.index == 1, "objective %d" % runner.state.index)
	var checkpoint: Vector3 = player._spawn.origin
	# The search: needs its seconds inside.
	var search: MissionObjective = MISSION.objectives[1]
	player.global_position = search.point
	await get_tree().create_timer(search.seconds * 0.5).timeout
	_check("half way the search isn't done", runner.state.index == 1 and runner.search_fraction() > 0.3,
			"objective %d, %.2f" % [runner.state.index, runner.search_fraction()])
	var waited := 0.0
	while runner.state.index == 1 and waited < search.seconds * 2.0:
		player.global_position = search.point
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_check("searching long enough finds the guns", runner.state.index == 2, "objective %d" % runner.state.index)
	_check("and brings in the taxi rank squad", AI.soldiers.size() > 0, "no squad")
	checkpoint = player._spawn.origin
	_check("finishing an objective is a checkpoint", checkpoint.distance_to(search.point) < 3.0, "spawn %s" % checkpoint)
	# Die: back at the checkpoint (or the safest spot near it).
	player.health.invulnerable = false
	player.global_position = Vector3(50, 0, 0)
	player.health.take_hit(INF, DamageModel.Zone.HEAD, {})
	waited = 0.0
	while player.dead and waited < 15.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	player.health.invulnerable = true
	_check("a death respawns at the checkpoint", not player.dead and player._spawn.origin.distance_to(checkpoint) < 0.5,
			"dead %s, spawn %s" % [player.dead, player._spawn.origin])
	_check("the death is counted", runner.deaths == 1, "%d deaths" % runner.deaths)
	await _next_objective()
	await _next_objective()
	_check("the town is cleared: on to the extraction", runner.state.index == 4, "objective %d" % runner.state.index)
	player.global_position = MISSION.objectives[4].point + Vector3(2.5, 0, -2.5)
	waited = 0.0
	while runner._phase != "outro" and waited < 5.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_check("reaching the truck completes the mission", runner._phase == "outro" and runner.cinematic, "phase %s" % runner._phase)
	_check("the card counts the enemies down", runner.kills > 0, "%d kills" % runner.kills)
	await get_tree().create_timer(3.2).timeout
	_check("the stats show", runner._stats.visible and runner._stats.text.contains("ENEMIES DOWN"), "stats %s" % runner._stats.text)
	print(runner._status())
	_finish()


## Meets the current objective through the debug command and waits for it.
func _next_objective() -> void:
	var at := runner.state.index
	Debug.execute("mission.next")
	var waited := 0.0
	while runner.state.index == at and waited < 10.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()


func _finish() -> void:
	Settings.requested_mission = null
	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s" % what)
	else:
		failures += 1
		print("FAIL %s - %s" % [what, detail])
