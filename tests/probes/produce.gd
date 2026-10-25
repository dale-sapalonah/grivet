extends Node
## Market produce probe (Gordons): the tables are stocked; a round through a
## fruit bursts that one (and flies on); a grenade among the stalls bursts
## everything near it; the next stage restocks. Exit 0 = pass.
##
##   $GODOT --headless --path . res://tests/probes/produce.tscn

const LEVEL := "res://levels/gordons/gordons_market.tscn"
const KESTREL := preload("res://data/weapons/kestrel.tres")
const FRAG := preload("res://data/grenades/frag.tres")

var level: Node3D
var player: Player
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
	Debug.execute("ai.kill")
	player.health.invulnerable = true
	var produce: MarketProduce = level.get_node("Produce")
	var total := produce.unit_count()
	_check("the stalls are stocked (%d heaps and fruit)" % total, total > 400 and produce.intact() == total, "%d intact of %d" % [produce.intact(), total])
	# Shoot one: from beside it, level, through its middle.
	var target := produce.unit_center(10)
	var from := target + Vector3(0, 0.05, 3.0)
	await get_tree().physics_frame
	Ballistics.fire(from, target - from, KESTREL, player, [])
	await get_tree().create_timer(0.3).timeout
	_check("a round through a fruit bursts it", produce.intact() < total, "still %d intact" % produce.intact())
	var after_shot := produce.intact()
	# A grenade on the floor between two rows.
	Grenade.throw(FRAG, level, Vector3(target.x, target.y - 0.8, target.z + 1.6), Vector3.ZERO, player)
	await get_tree().create_timer(FRAG.fuse_time + 0.4).timeout
	_check("a grenade among the stalls bursts everything near it", produce.intact() <= after_shot - 5,
			"%d -> %d intact" % [after_shot, produce.intact()])
	Debug.execute("stage 2")
	for i in 30:
		await get_tree().physics_frame
	_check("the next stage restocks the stalls", produce.intact() == total, "%d intact of %d" % [produce.intact(), total])
	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s" % what)
	else:
		failures += 1
		print("FAIL %s - %s" % [what, detail])
