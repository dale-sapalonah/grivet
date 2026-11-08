extends Node3D
## Windowed look check for the animated Mixamo skins: rows of bodies standing,
## walking, strafing, running, crouched, aiming up, reloading and firing, with
## their hit shapes drawn as wireframes over them (they must sit on the drawn
## body) and the gun in the hands. Not a pass/fail probe.
##
##   $GODOT --path . res://tests/probes/anim_look.tscn -- out=<dir> [profile=leader]

const POSES := [
	["idle", Vector3.ZERO, 0.0, 0.0, ""],
	["walk", Vector3(0, 0, -1.4), 0.0, 0.0, ""],
	["strafe", Vector3(-1.35, 0, 0), 0.0, 0.0, ""],
	["run", Vector3(0, 0, -4.6), 0.0, 0.0, ""],
	["crouch", Vector3.ZERO, 1.0, 0.0, ""],
	["aim up", Vector3.ZERO, 0.0, 0.5, ""],
	["reload", Vector3.ZERO, 0.0, 0.0, "reload"],
	["fire", Vector3.ZERO, 0.0, 0.0, "fire"],
]

var out := "user://"
var profile_name := "rifleman"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out = arg.trim_prefix("out=")
		elif arg.begins_with("profile="):
			profile_name = arg.trim_prefix("profile=")
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.34, 0.38)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	add_child(sun)
	var camera := Camera3D.new()
	add_child(camera)
	camera.fov = 40.0
	var wire := StandardMaterial3D.new()
	wire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wire.albedo_color = Color(1, 0.9, 0.1)
	wire.no_depth_test = true
	var profile: EnemyProfile = load("res://data/ai/%s.tres" % profile_name)
	var bodies: Array[Mannequin] = []
	for i in POSES.size():
		var body := Mannequin.new()
		add_child(body)
		body.build(profile, 1)
		body.position = Vector3(-3.85 + i * 1.1, 0, 0)
		body.rotation_degrees.y = 150.0
		for part_name: String in Mannequin.PARTS:
			var shape: Array = body.shapes[part_name]
			var outline := MeshInstance3D.new()
			outline.mesh = (shape[0] as Shape3D).get_debug_mesh()
			outline.material_override = wire
			outline.transform = shape[1]
			(body.parts[part_name] as Node3D).add_child(outline)
		bodies.append(body)
	print("animated: ", bodies[0].animated())
	for frame in 50:
		for i in bodies.size():
			var pose: Array = POSES[i]
			var body := bodies[i]
			if frame == 20 and pose[4] != "":
				body.act(pose[4])
			body.move_velocity = body.global_basis * pose[1]
			body.pose(1.0 / 30.0, pose[2], pose[3], (pose[1] as Vector3).length(), true)
		await get_tree().process_frame
	await _shot(camera, Vector3(0, 1.3, 9.0), Vector3(0, 0.95, 0), "anim_%s_row.png" % profile_name)
	await _shot(camera, Vector3(-2.8, 1.5, 3.2), Vector3(-2.8, 1.0, 0), "anim_%s_close.png" % profile_name)
	get_tree().quit(0)


func _shot(camera: Camera3D, from: Vector3, at: Vector3, file: String) -> void:
	camera.position = from
	camera.look_at(at)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(file))
	print("saved ", out.path_join(file))
