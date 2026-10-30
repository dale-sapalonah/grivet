extends Node
## Knife probe (arena): from behind an aware soldier the HUD offers a takedown
## and F kills it silently (the rest of the squad doesn't hear it); face to
## face the knife only cuts. Exit 0 = pass.
##
##   $GODOT --headless --path . res://tests/probes/knife.tscn

const LEVEL := "res://levels/greybox/arena.tscn"

var level: Node3D
var player: Player
var holder: WeaponHolder
var failures := 0


func _ready() -> void:
	level = load(LEVEL).instantiate()
	add_child(level)
	player = level.get_node("Player")
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		printerr("FAIL watchdog")
		get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	await level.combat_ready
	player.health.invulnerable = true
	holder = get_tree().get_first_node_in_group("player_weapons") as WeaponHolder
	while AI.soldiers.size() > 2:
		AI.soldiers[0].health.take_hit(INF, DamageModel.Zone.HEAD, {})
		await get_tree().physics_frame
	var victim: Soldier = AI.soldiers[0]
	var witness: Soldier = AI.soldiers[1]
	# Behind an alerted soldier that looks away (-Z), 1.2 m back.
	await _stage(victim, Vector3(0, 0, 1.2), true)
	_check("the HUD offers a takedown from behind", holder.takedown_target == victim, "target %s" % holder.takedown_target)
	var awareness_before := witness.awareness
	await _strike()
	_check("the takedown kills at once", not is_instance_valid(victim) or victim.dead, "still alive")
	_check("silently: the other soldier isn't alerted", not witness._alerted and witness.awareness < 1.0,
			"alerted %s, awareness %.2f -> %.2f" % [witness._alerted, awareness_before, witness.awareness])
	# Face to face with an alerted soldier: a cut, not a kill.
	victim = witness
	await _stage(victim, Vector3(0, 0, -1.2), true)
	_check("no takedown offered face to face", holder.takedown_target == null, "offered one")
	var health := victim.health.model.health + victim.health.model.armor
	await _strike()
	var after := victim.health.model.health + victim.health.model.armor if is_instance_valid(victim) and not victim.dead else 0.0
	_check("face to face the knife cuts but doesn't kill", not victim.dead and after < health, "%.0f -> %.0f dead %s" % [health, after, victim.dead])
	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)


## Puts `victim` on the player's spawn line, alerted, looking along -Z, and the
## player `offset` from it, facing it.
func _stage(victim: Soldier, offset: Vector3, alerted: bool) -> void:
	var at := player.global_position + Vector3(0, 0, -3.0)
	for i in 6:
		victim.global_position = at
		victim.rotation.y = 0.0
		victim.velocity = Vector3.ZERO
		if alerted:
			victim._alert()
		player.global_position = at + offset
		var to := at - player.global_position
		player.set_look(atan2(-to.x, -to.z), 0.0)
		await get_tree().physics_frame


func _strike() -> void:
	holder.strike()
	var waited := 0.0
	while holder.knife_time >= 0.0 and waited < 2.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	await get_tree().physics_frame


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s" % what)
	else:
		failures += 1
		print("FAIL %s - %s" % [what, detail])
