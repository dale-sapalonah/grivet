extends Node
## Straggler probe (Gordons): with only a couple of soldiers left and no
## contact for straggler_reveal_seconds, they are marked and come hunting the
## player (closer over time). Exit 0 = pass.
##
##   $GODOT --headless --path . res://tests/probes/stragglers.tscn

const LEVEL := "res://levels/gordons/gordons_market.tscn"

var level: Node3D
var player: Player
var failures := 0


func _ready() -> void:
	level = load(LEVEL).instantiate()
	add_child(level)
	player = level.get_node("Player")
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		printerr("FAIL watchdog")
		get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	await level.combat_ready
	player.health.invulnerable = true
	AI.settings.straggler_reveal_seconds = 3.0
	# Leave two, far apart from the player: stand them down so nobody sees anyone.
	while AI.soldiers.size() > 2:
		AI.soldiers[0].health.take_hit(INF, DamageModel.Zone.HEAD, {})
		await get_tree().physics_frame
	player.global_position = Vector3(-60, 0, -40)  # the far corner of the car park
	await get_tree().physics_frame
	var before := _mean_distance()
	_check("not marked while contact is fresh", not AI.stragglers_revealed(), "marked at once")
	await get_tree().create_timer(4.0).timeout
	_check("the last few are marked after a quiet spell", AI.stragglers_revealed(), "not marked")
	await get_tree().create_timer(14.0).timeout
	var after := _mean_distance()
	_check("marked stragglers come hunting the player", after < before - 8.0, "mean distance %.1f -> %.1f m" % [before, after])
	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)


func _mean_distance() -> float:
	var total := 0.0
	for soldier in AI.soldiers:
		total += CoverScoring.flat_distance(soldier.global_position, player.global_position)
	return total / maxf(AI.soldiers.size(), 1.0)


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s" % what)
	else:
		failures += 1
		print("FAIL %s - %s" % [what, detail])
