extends Node
## Windowed probe: boots the title menu (the main scene), starts the game the
## way the menu's button does, then plays: mouse look, firing, moving. Every
## frame it scans the whole tree for a Node3D with a non-finite transform and
## reports the first ones it sees (path, class, frame). Playtests flooded the
## log with non-finite errors from the moment the level loaded, which probes
## that load the level directly never saw. Exit 0 = pass.
##
##   $GODOT --path . res://tests/probes/menu_to_game.tscn [-- seconds=<n>] [map=<index into GameMenu.MAPS>]

const MENU := "res://ui/main_menu.tscn"

var seconds := 40.0
var map := 0


class Watcher extends Node:
	var frame := 0
	var reports: Array[String] = []
	var seen := {}
	var log_errors := 0

	func _process(_delta: float) -> void:
		frame += 1
		if reports.size() >= 12:
			return
		for node in get_tree().root.find_children("*", "Node3D", true, false):
			var spatial := node as Node3D
			if not spatial.is_inside_tree():
				continue
			var local := spatial.transform
			if _finite(local) and _finite(spatial.global_transform):
				continue
			var key := str(spatial.get_path())
			if seen.has(key):
				continue
			seen[key] = true
			# The deepest node whose own (local) transform is bad is the culprit;
			# its children only inherit it.
			var own := "own transform bad" if not _finite(local) else "inherits a bad parent"
			reports.append("frame %d: %s (%s) %s: local %s" % [frame, key, spatial.get_class(), own, local])
			print("NONFINITE " + reports[-1])

	static func _finite(at: Transform3D) -> bool:
		return at.origin.is_finite() and at.basis.x.is_finite() and at.basis.y.is_finite() and at.basis.z.is_finite()


var watcher := Watcher.new()


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			seconds = float(arg.get_slice("=", 1))
		elif arg.begins_with("map="):
			map = int(arg.get_slice("=", 1))
	watcher.name = "NonFiniteWatcher"
	get_tree().root.add_child.call_deferred(watcher)
	get_tree().create_timer(seconds + 90.0, true, false, true).timeout.connect(func() -> void:
		printerr("FAIL watchdog")
		get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	# Survive the scene change: move onto the root and hand the current-scene
	# slot to a stand-in that the change frees instead.
	var tree := get_tree()
	var stand_in := Node.new()
	tree.root.add_child(stand_in)
	tree.current_scene = stand_in
	tree.change_scene_to_file(MENU)
	await tree.create_timer(3.0).timeout
	var menu := tree.root.find_children("*", "GameMenu", true, false)
	if menu.is_empty():
		print("FAIL no GameMenu on the title screen")
		tree.quit(1)
		return
	print("menu up at frame %d, starting %s stage 2" % [watcher.frame, GameMenu.MAPS[map][0]])
	menu[0].call("_start", 1, GameMenu.MAPS[map][1])
	var level: Node = null
	while level == null or not level.has_signal("combat_ready"):
		await tree.process_frame
		level = tree.current_scene
	await level.combat_ready
	print("level ready at frame %d" % watcher.frame)
	Debug.execute("god")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var step := 0
	while Time.get_ticks_msec() < end:
		step += 1
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(randf_range(-30.0, 30.0), randf_range(-8.0, 8.0))
		Input.parse_input_event(motion)
		if step % 90 == 0:
			Input.action_press("fire")
		elif step % 90 == 50:
			Input.action_release("fire")
		if step % 240 == 0:
			Input.action_press("move_forward")
		elif step % 240 == 120:
			Input.action_release("move_forward")
		await tree.process_frame
	Input.action_release("fire")
	Input.action_release("move_forward")
	var bus := AudioServer.get_bus_index("Music")
	var track: AudioStreamPlayer = MusicPlayer._track
	var music_ok: bool = track.playing and track.stream != null and track.stream == MusicPlayer._covert or track.stream == MusicPlayer._tension
	print("%s in-game music plays: playing %s, stream %s, track %.1f dB, bus %.1f dB muted %s, set %s" % [
		"PASS" if music_ok else "FAIL", track.playing, "covert" if track.stream == MusicPlayer._covert else ("tension" if track.stream == MusicPlayer._tension else str(track.stream)),
		track.volume_db, AudioServer.get_bus_volume_db(bus), AudioServer.is_bus_mute(bus), MusicPlayer._set])
	var ok := watcher.reports.is_empty() and music_ok
	print("\n%s: %d non-finite node(s) seen" % ["PASS" if ok else "FAIL", watcher.reports.size()])
	tree.quit(0 if ok else 1)
