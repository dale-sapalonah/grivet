extends Node
## Windowed probe: fire every weapon (hip and aimed) and check the first-person
## gun, arms, camera and ejected casings stay finite. A non-finite view model
## once made the gun and hands vanish on firing, then lag. Exit 0 = pass.
##
##   $GODOT --path . res://tests/probes/view_model_fire.tscn

const LEVEL := "res://levels/port/port_yard.tscn"
const WEAPONS := ["kestrel", "hammerhead", "vanta"]

var level: Node3D
var player: Player
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
	Debug.execute("god")
	Debug.execute("notarget")
	Debug.execute("ammo.infinite")
	for weapon in WEAPONS:
		for aiming in [false, true]:
			Debug.execute("give " + weapon)
			await get_tree().create_timer(0.8).timeout
			if aiming:
				Input.action_press("aim")
			Input.action_press("fire")
			var first_bad := ""
			for frame in 240:
				await get_tree().process_frame
				# A hitch then a run of slow frames (a busy PC, a low preset) while
				# firing: the kick springs get huge deltas.
				if frame == 40:
					OS.delay_msec(400)
				elif frame > 40 and frame < 70:
					OS.delay_msec(110)
				var bad := _non_finite()
				if bad != "" and first_bad == "":
					first_bad = "frame %d: %s" % [frame, bad]
			Input.action_release("fire")
			Input.action_release("aim")
			_check("%s %s: view model, arms, camera and casings stay finite" % [weapon, "aimed" if aiming else "from the hip"],
					first_bad == "", first_bad)
	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	get_tree().quit(1 if failures else 0)


## The first non-finite transform found among what firing touches, or "".
func _non_finite() -> String:
	var camera := get_viewport().get_camera_3d()
	if camera != null and not _finite(camera.global_transform):
		return "camera %s" % camera.global_transform
	var holder := get_tree().get_first_node_in_group("player_weapons") as Node
	if holder == null:
		return ""
	for node in holder.find_children("*", "Node3D", true, false):
		var spatial := node as Node3D
		if not spatial.is_inside_tree() or spatial.top_level and not spatial.visible:
			continue
		if not _finite(spatial.global_transform):
			return "%s (%s) %s" % [spatial.get_path(), spatial.get_class(), spatial.global_transform]
	return ""


func _finite(at: Transform3D) -> bool:
	return at.origin.is_finite() and at.basis.x.is_finite() and at.basis.y.is_finite() and at.basis.z.is_finite()


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s" % what)
	else:
		failures += 1
		print("FAIL %s - %s" % [what, detail])
