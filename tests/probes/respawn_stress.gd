extends Node
## Headless respawn probe: let the squad engage, kill the player mid-fight,
## let them respawn (enemies forget them), and check that no soldier ends up
## with a non-finite position, velocity or move target (that once flooded the
## log with "Vector3 cannot be normalized" and froze the game). Exit 0 = pass.
##
##   $GODOT --headless --path . res://tests/probes/respawn_stress.tscn
##   (also windowed, without --headless, to exercise 3D audio)

const LEVEL := "res://levels/port/port_yard.tscn"
const ROUNDS := 3
## Stages to fight through (by number), one per round after the first.

var level: Node3D
var player: Player
var failures := 0


func _ready() -> void:
	level = load(LEVEL).instantiate()
	add_child(level)
	player = level.get_node("Player")
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		printerr("FAIL watchdog")
		get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	await level.combat_ready
	for round in ROUNDS:
		if round > 0:
			Debug.execute("stage %d" % [1, 3, 4][round])  # town, machetes, everyone
		await get_tree().create_timer(6.0).timeout  # let them find and fight the player
		Debug.execute("kill")
		var bad := 0
		for second in 8:
			await get_tree().create_timer(1.0).timeout
			for soldier in AI.soldiers:
				var target: Vector3 = soldier._move_target
				if not soldier.global_position.is_finite() or not soldier.velocity.is_finite() \
						or (target != Vector3.INF and not target.is_finite()):
					bad += 1
		# What matters here is finite state; the player may well be dead again
		# by now in a hot stage.
		var ok := bad == 0 and player.global_position.is_finite() and player.velocity.is_finite()
		print("%s round %d: %d non-finite soldier samples, player finite %s" % ["PASS" if ok else "FAIL", round + 1, bad, player.global_position.is_finite()])
		if not ok:
			failures += 1
	# A long hitch (alt-tab, a slow load) hands the next frame a huge delta:
	# springs integrated with it must not blow up the camera or the bodies.
	await get_tree().process_frame
	OS.delay_msec(2500)
	for i in 30:
		await get_tree().process_frame
	var camera := get_viewport().get_camera_3d()
	var finite := camera == null or (camera.global_transform.origin.is_finite() and camera.global_transform.basis.x.is_finite())
	for soldier in AI.soldiers:
		finite = finite and soldier.mannequin.pivots.spine.global_transform.basis.x.is_finite()
	print("%s a 2.5 s hitch leaves the camera and soldiers finite" % ("PASS" if finite else "FAIL"))
	if not finite:
		failures += 1
	# A soldier poisoned with NaN must be put back (and reported), not left
	# to flood the physics engine.
	if not AI.soldiers.is_empty():
		var soldier: Soldier = AI.soldiers[0]
		soldier.velocity = Vector3(NAN, 0.0, NAN)
		for i in 10:
			await get_tree().physics_frame
		var recovered := soldier.global_position.is_finite() and soldier.velocity.is_finite()
		print("%s a soldier given a NaN velocity recovers" % ("PASS" if recovered else "FAIL"))
		if not recovered:
			failures += 1
	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)
