extends Node
## Hostage probe (Gordons, HOSTAGES AT GORDONS): the rescue brings in kneeling
## hostages, raskols holding human shields and a panicking crowd that runs; a
## well placed head shot drops a captor without touching the hostage, who is
## freed; the next objective brings in more; shooting a civilian fails the
## mission. Exit 0 = pass.
##
##   $GODOT --headless --path . res://tests/probes/hostages.tscn

const MISSION := preload("res://data/missions/gordons_hostages.tres")
const KESTREL := preload("res://data/weapons/kestrel.tres")

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
	Debug.execute("mission.skip")
	await get_tree().create_timer(0.5).timeout
	player.health.invulnerable = true
	var first: MissionObjective = MISSION.objectives[0]
	var expected := first.detained.size() + first.shields.size() + first.panicked.size()
	var civilians := _civilians()
	_check("the rescue brings in its civilians", civilians.size() == expected, "%d of %d" % [civilians.size(), expected])
	var captors: Array[Soldier] = []
	for soldier in AI.soldiers:
		if is_instance_valid(soldier.hostage):
			captors.append(soldier)
	_check("raskols hold hostages as shields", captors.size() == first.shields.size(), "%d captors" % captors.size())
	var kinds := {}
	for civilian in civilians:
		kinds[civilian.profile.display_name + (" child" if civilian.child else "")] = true
	_check("men, women and children among them", kinds.size() >= 3, "%s" % [kinds.keys()])
	var running: Array[Civilian] = []
	var starts: Array[Vector3] = []
	for civilian in civilians:
		if civilian.state == Civilian.State.PANIC:
			running.append(civilian)
			starts.append(civilian.global_position)
	await get_tree().create_timer(3.0).timeout
	var moved := 0
	for i in running.size():
		if is_instance_valid(running[i]) and running[i].global_position.distance_to(starts[i]) > 2.0:
			moved += 1
	_check("the panicking ones run", moved >= running.size() / 2, "%d of %d moved" % [moved, running.size()])
	# A head shot past the hostage: stand square in front of the captor.
	AI.frozen = true
	var captor: Soldier = captors[0]
	var hostage: Civilian = captor.hostage
	await get_tree().physics_frame
	var shield_gap := hostage.global_position.distance_to(captor.global_position)
	_check("the shield is held close in front", shield_gap < 0.7 and (hostage.global_position - captor.global_position).dot(-captor.global_basis.z) > 0.2,
			"%.2f m" % shield_gap)
	var front := captor.global_position - captor.global_basis.z * 8.0
	player.global_position = Vector3(front.x, captor.global_position.y, front.z)
	await get_tree().physics_frame
	var head: Vector3 = captor.mannequin.parts.head.global_position + Vector3.UP * 0.12
	var eye := player.head_point() + Vector3.UP * 0.1
	Ballistics.fire(eye, (head - eye).normalized(), KESTREL, player, player.bullet_exclude())
	await get_tree().create_timer(0.4).timeout
	_check("a well placed shot drops the captor", not is_instance_valid(captor) or captor.dead, "captor still up")
	_check("without touching the hostage", runner.civilians_hurt_by_player == 0 and is_instance_valid(hostage) and hostage.health.model.health >= hostage.health.profile.max_health,
			"%d hurt by the player" % runner.civilians_hurt_by_player)
	_check("the freed hostage runs", is_instance_valid(hostage) and hostage.state == Civilian.State.PANIC, "state %s" % (hostage.state if is_instance_valid(hostage) else -1))
	AI.frozen = false
	var at := runner.state.index
	Debug.execute("mission.next")
	var waited := 0.0
	while runner.state.index == at and waited < 10.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_check("all raskols down: on to the market floor", runner.state.index == 1, "objective %d" % runner.state.index)
	_check("with more civilians", runner.civilians_total > expected, "%d in all" % runner.civilians_total)
	_check("the player hurt nobody so far (enemy fire may)", runner.civilians_hurt_by_player == 0 and runner._phase == "play", "%d by the player" % runner.civilians_hurt_by_player)
	# Shoot a civilian: the mission is lost.
	var victim: Civilian = _civilians()[0]
	AI.frozen = true
	var aim := victim.aim_point()
	var from := aim + Vector3(0, 0.3, 6.0)
	player.global_position = from - Vector3.UP * 1.6
	await get_tree().physics_frame
	Ballistics.fire(from, (aim - from).normalized(), KESTREL, player, player.bullet_exclude())
	await get_tree().create_timer(0.4).timeout
	_check("hurting a civilian fails the mission", runner._phase == "failed" and runner._title.text == "MISSION FAILED",
			"phase %s, hurt %d" % [runner._phase, runner.civilians_hurt])
	Settings.requested_mission = null
	AI.frozen = false
	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)


func _civilians() -> Array[Civilian]:
	var list: Array[Civilian] = []
	for node in get_tree().get_nodes_in_group("civilians"):
		list.append(node as Civilian)
	return list


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s" % what)
	else:
		failures += 1
		print("FAIL %s - %s" % [what, detail])
