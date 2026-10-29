extends Node3D
## Windowed look check: rifleman, rusher and machete with their Blender-made
## bodies, then the same built in code, same pose and light, photographed from
## the front and three-quarter. Not a pass/fail probe.
##
##   $GODOT --path . res://tests/probes/body_compare.tscn -- out=<dir>

const PROFILES := [preload("res://data/ai/rifleman.tres"), preload("res://data/ai/rusher.tres"), preload("res://data/ai/machete.tres")]

var out := "user://"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out = arg.trim_prefix("out=")
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.34, 0.38)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var camera := Camera3D.new()
	add_child(camera)
	camera.fov = 40.0
	# Rifleman, rusher, machete: the Blender bodies, then the same built in code.
	var rows := {true: [], false: []}
	for blender in [true, false]:
		for i in PROFILES.size():
			var profile: EnemyProfile = PROFILES[i].duplicate()
			if not blender:
				profile.body_model = null
			var body := Mannequin.new()
			add_child(body)
			body.build(profile, 1)
			body.position = Vector3(-1.1 + i * 1.1, 0, 0)
			body.rotation_degrees.y = 180.0  # face the camera (+Z)
			for k in 3:
				body.pose(0.1, 0.0, 0.0, 0.0, true)
			(rows[blender] as Array).append(body)
	for blender in [true, false]:
		for body: Node3D in rows[true]:
			body.visible = blender
		for body: Node3D in rows[false]:
			body.visible = not blender
		var tag := "blender" if blender else "code"
		await _shot(camera, Vector3(0, 1.3, 5.2), Vector3(0, 1.0, 0), "body_row_%s.png" % tag)
		await _shot(camera, Vector3(2.2, 1.6, 2.6), Vector3(0.6, 1.1, 0), "body_quarter_%s.png" % tag)
		await _shot(camera, Vector3(1.4, 1.6, 1.5), Vector3(0.55, 1.35, 0), "body_shoulders_%s.png" % tag)
	get_tree().quit(0)


func _shot(camera: Camera3D, at: Vector3, target: Vector3, file: String) -> void:
	camera.look_at_from_position(at, target)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(file))
