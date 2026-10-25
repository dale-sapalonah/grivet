extends Node
## Windowed soak probe: fights through every stage (god mode, firing bursts,
## turning) and logs frame time, node/object counts, physics bodies, draw calls
## and memory every 10 s, to find what builds up when a session starts to lag.
## Fails if the frame time or node count keeps climbing. Exit 0 = pass.
##
##   $GODOT --path . res://tests/probes/soak.tscn [-- seconds_per_stage=<n>]

const LEVEL := "res://levels/port/port_yard.tscn"
const SAMPLE_SECONDS := 10.0

var level: Node3D
var player: Player
var seconds_per_stage := 60.0
var samples: Array[Dictionary] = []
var _frame_times: PackedFloat32Array = []
var _worst_frame := 0.0
var _corpses_ok := true
var _wounded_ok := true


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seconds_per_stage="):
			seconds_per_stage = float(arg.get_slice("=", 1))
	level = load(LEVEL).instantiate()
	add_child(level)
	player = level.get_node("Player")
	get_tree().create_timer(seconds_per_stage * 4.0 + 120.0).timeout.connect(func() -> void:
		printerr("FAIL watchdog")
		get_tree().quit(2))
	_run.call_deferred()


func _process(delta: float) -> void:
	_frame_times.append(delta)
	_worst_frame = maxf(_worst_frame, delta)


func _run() -> void:
	await level.combat_ready
	Debug.execute("god")
	Debug.execute("ammo.infinite")
	var started := Time.get_ticks_msec()
	_sample("start", 0.0)
	for stage in [1, 2, 3, 4]:
		if stage > 1:
			Debug.execute("stage %d" % stage)
		var stage_start := Time.get_ticks_msec()
		var next_sample := SAMPLE_SECONDS
		while (Time.get_ticks_msec() - stage_start) / 1000.0 < seconds_per_stage:
			await _burst()
			var elapsed := (Time.get_ticks_msec() - stage_start) / 1000.0
			if elapsed >= next_sample:
				next_sample += SAMPLE_SECONDS
				_sample("stage %d" % stage, (Time.get_ticks_msec() - started) / 1000.0)
	await _wounded_far_check()
	await _corpse_check()
	_report()


## Shot soldiers far away (posed every other frame) through slow frames: the
## flinch spring once diverged there and turned a body NaN, which then fired
## NaN bullets and casings that flooded the log. The guard must not be needed.
func _wounded_far_check() -> void:
	Debug.execute("spawn rifleman 4 %d" % int(AI.settings.pose_lod_distance + 5.0))
	await get_tree().create_timer(1.0).timeout
	# Diverging grows the bend long before it reaches INF, so watch its size:
	# a real flinch stays well under a radian.
	var worst := 0.0
	for frame in 120:
		if frame % 10 == 0:
			for soldier: Soldier in AI.soldiers:
				soldier.mannequin.flinch(Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized(), 3.0)
		OS.delay_msec(110)
		await get_tree().process_frame
		for soldier: Soldier in AI.soldiers:
			var flinch: Vector2 = soldier.mannequin._flinch
			worst = maxf(worst, absf(flinch.x) + absf(flinch.y) if flinch.is_finite() else INF)
	var bad := 0
	for soldier: Soldier in AI.soldiers:
		var spine: Node3D = soldier.mannequin.pivots.spine
		if soldier._reported_insane or not spine.global_transform.is_finite():
			bad += 1
	_wounded_ok = bad == 0 and worst < 1.0 and not AI.soldiers.is_empty()
	print("%s %d wounded soldiers stay steady through slow frames: largest flinch %s rad, %d went bad" % [
		"PASS" if _wounded_ok else "FAIL", AI.soldiers.size(),
		("%.3f" % worst) if worst < 1000.0 else String.num_scientific(worst), bad])


## A pile of fresh corpses must stop costing physics once they have fallen:
## jointed ragdolls jitter and never sleep, and ten of them lagged the game.
func _corpse_check() -> void:
	Debug.execute("ai.kill")
	await get_tree().create_timer(1.0).timeout
	Debug.execute("spawn rifleman 10 12")
	await get_tree().create_timer(1.0).timeout
	Debug.execute("ai.kill")
	await get_tree().physics_frame
	var falling := int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	await get_tree().create_timer(AI.settings.corpse_freeze_after + 1.5).timeout
	var resting := int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	var frozen := 0
	var corpses := 0
	for node in get_tree().root.find_children("*", "Ragdoll", true, false):
		corpses += 1
		frozen += 1 if (node as Ragdoll).frozen else 0
	_corpses_ok = corpses > 0 and frozen == corpses and resting < 20
	print("%s %d corpses freeze once fallen: %d frozen, active bodies %d while falling -> %d at rest" % [
		"PASS" if _corpses_ok else "FAIL", corpses, frozen, falling, resting])


## Turn a little, fire a 1 s burst, pause.
func _burst() -> void:
	Debug.execute("look %d %d" % [randi_range(0, 359), randi_range(-6, 4)])
	Input.action_press("fire")
	await get_tree().create_timer(1.0).timeout
	Input.action_release("fire")
	await get_tree().create_timer(0.5).timeout


func _sample(label: String, t: float) -> void:
	var sorted := _frame_times.duplicate()
	sorted.sort()
	var mean := 0.0
	for f in sorted:
		mean += f
	mean = mean / maxf(sorted.size(), 1.0)
	var p95: float = sorted[int(sorted.size() * 0.95)] if sorted.size() > 0 else 0.0
	var sample := {
		"t": t,
		"label": label,
		"mean_ms": mean * 1000.0,
		"p95_ms": p95 * 1000.0,
		"worst_ms": _worst_frame * 1000.0,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"bodies": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"soldiers": AI.soldiers.size(),
	}
	samples.append(sample)
	_frame_times.clear()
	_worst_frame = 0.0
	print("%5.0fs %-8s mean %5.1f ms  p95 %5.1f  worst %6.1f | process %5.1f physics %5.1f | nodes %5d orphans %4d objects %6d res %5d | bodies %3d draws %4d | mem %6.1f MB | soldiers %d" % [
		t, label, sample.mean_ms, sample.p95_ms, sample.worst_ms, sample.process_ms, sample.physics_ms,
		sample.nodes, sample.orphans, sample.objects, sample.resources, sample.bodies, sample.draws,
		sample.mem_mb, sample.soldiers])


## Compares the start and end of each stage: a stage whose frame time or node
## count climbs while it is played is building something up.
func _report() -> void:
	var failures := (0 if _corpses_ok else 1) + (0 if _wounded_ok else 1)
	for stage in [1, 2, 3, 4]:
		var rows := samples.filter(func(s: Dictionary) -> bool: return s.label == "stage %d" % stage)
		if rows.size() < 3:
			continue
		var first: Dictionary = rows[1]  # skip the first: the stage is still loading in
		var last: Dictionary = rows[-1]
		var frame_ok: bool = last.mean_ms < first.mean_ms * 1.3 + 2.0
		var nodes_ok: bool = last.nodes < first.nodes + 200
		var objects_ok: bool = last.objects < first.objects * 1.2 + 500
		var ok := frame_ok and nodes_ok and objects_ok
		if not ok:
			failures += 1
		print("%s stage %d holds steady: frame %.1f -> %.1f ms, nodes %d -> %d, objects %d -> %d" % [
			"PASS" if ok else "FAIL", stage, first.mean_ms, last.mean_ms, first.nodes, last.nodes,
			first.objects, last.objects])
	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)
