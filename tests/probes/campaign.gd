extends Node
## Headless campaign probe: checks a buai bundle heals, then plays the port's
## stages by clearing each squad
## (ai.kill) and checks the flow: each stage spawns its own squad, a cleared
## stage shouts KLIN CHOL! and WARAA!, the player is moved to the next start
## healed and re-armed, and the last stage ends with the final shout.
## Exit code 0 = all passed.
##
##   $GODOT --headless --path . res://tests/probes/campaign.tscn

const LEVEL := "res://levels/port/port_yard.tscn"
const WATCHDOG_SECONDS := 200.0

var level: Node3D
var player: Player
var failures := 0
var _shouts: PackedStringArray = []


func _ready() -> void:
	level = load(LEVEL).instantiate()
	var campaign: Campaign = level.campaign.duplicate()
	campaign.next_stage_delay = 0.5
	level.campaign = campaign
	add_child(level)
	player = level.get_node("Player")
	get_tree().create_timer(WATCHDOG_SECONDS).timeout.connect(func() -> void:
		printerr("FAIL watchdog: probe did not finish in %d s" % WATCHDOG_SECONDS)
		get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	await level.combat_ready
	var hud := get_tree().get_first_node_in_group("hud")
	# The HUD logs every announced line; read what each clear adds.
	await _check_gate_floor()
	await _check_buai()
	player.health.invulnerable = true
	var campaign: Campaign = level.campaign
	for index in campaign.stages.size():
		var stage := campaign.stages[index]
		var expected := 0
		for marker: Node3D in get_tree().get_nodes_in_group("enemy_spawn"):
			if int(marker.get_meta("level", 1)) == stage.marker_level:
				expected += 1
		_check("stage %d fields its squad (%d)" % [index + 1, expected], AI.soldiers.size() == expected,
				"%d soldiers" % AI.soldiers.size())
		if index > 0:
			# At the stage start, or wherever the spawn picker found that's safe.
			var nearest := INF
			var seen := false
			var space := player.get_world_3d().direct_space_state
			for soldier in AI.soldiers:
				nearest = minf(nearest, CoverScoring.flat_distance(soldier.global_position, player.global_position))
				var ray := PhysicsRayQueryParameters3D.create(soldier.eye_point(), player.head_point(), PhysicsLayers.WORLD)
				seen = seen or space.intersect_ray(ray).is_empty()
			_check("stage %d starts the player out of sight of the enemy, healed" % (index + 1),
					not seen and nearest >= 15.0 and is_equal_approx(player.health.fraction(), 1.0),
					"nearest %.1f m, seen %s, health %.2f" % [nearest, seen, player.health.fraction()])
		var shouts_before: int = hud.shout_log.size()
		Debug.execute("ai.kill")
		await get_tree().process_frame
		await get_tree().process_frame
		var queued: PackedStringArray = hud.shout_log.slice(shouts_before)
		_check("stage %d cleared: %s" % [index + 1, ", ".join(campaign.cleared_shouts)],
				campaign.cleared_shouts[0] in queued and campaign.cleared_shouts[1] in queued, "shouted %s" % [queued])
		if index == campaign.stages.size() - 1:
			_check("the last stage ends with %s" % campaign.final_shout, campaign.final_shout in queued, "shouted %s" % [queued])
		else:
			# Wait for the next squad.
			for i in 300:
				await get_tree().physics_frame
				if not AI.soldiers.is_empty():
					break
	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)


## The gate between the yard and the town has ground under it (a player fell
## through a gap there once).
func _check_gate_floor() -> void:
	var space := player.get_world_3d().direct_space_state
	var holes := 0
	for x in range(30, 36):
		for z in [-2.5, 0.0, 2.5]:
			var from := Vector3(x + 0.5, 2.0, z)
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0, PhysicsLayers.WORLD)).is_empty():
				holes += 1
	_check("the gate into town has ground under it", holes == 0, "%d spots with no floor" % holes)


## Hurt, then stand on a buai bundle: it heals and is used up.
func _check_buai() -> void:
	var bundles := get_tree().get_nodes_in_group("buai")
	if bundles.is_empty():
		_check("buai bundles are laid out", false, "none")
		return
	var bundle := bundles[0] as Node3D
	var count := bundles.size()
	player.health.take_hit(50.0, DamageModel.Zone.ARMS)
	var before := player.health.model.health
	player.global_position = bundle.global_position
	for i in 20:
		await get_tree().physics_frame
	_check("chewing buai heals (%d bundles out)" % count, player.health.model.health > before and not is_instance_valid(bundle),
			"health %.0f -> %.0f" % [before, player.health.model.health])
	player.global_position = Vector3(0, 0, 26)


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s" % what)
	else:
		failures += 1
		print("FAIL %s - %s" % [what, detail])
