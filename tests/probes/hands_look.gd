extends Node3D
## Windowed look check for the first-person hands on a gun: close-ups of the
## shooting hand and the support hand from the left, the right and below, on
## a plain lit backdrop, with the hands' internal skeleton drawn over them
## (bones as yellow lines, joints as red dots, seen through everything). Not a
## pass/fail probe.
##
##   $GODOT --path . res://tests/probes/hands_look.tscn -- out=<dir> [weapon=kestrel] [no_skeleton] [wireframe]
## Writes hands_<weapon>_<grip|support>_<left|right|below>.png.

var out := "user://"
var weapon_id := "kestrel"
var skeleton_overlay := true
var wire_tag := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out = arg.trim_prefix("out=")
		elif arg.begins_with("weapon="):
			weapon_id = arg.trim_prefix("weapon=")
		elif arg == "no_skeleton":
			skeleton_overlay = false
		elif arg == "wireframe":
			get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
			wire_tag = "_wire"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.75, 0.77, 0.8)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	add_child(sun)
	var view := WeaponViewModel.new()
	view.tuning = load("res://data/weapons/view_model_tuning.tres")
	add_child(view)
	var definition: WeaponDefinition = load("res://data/weapons/%s.tres" % weapon_id)
	view.build(definition)
	var weapon := WeaponModel.new(definition)
	for i in 40:
		view.update_pose(1.0 / 30.0, weapon, 0.0, false, Vector2.ZERO)
		await get_tree().process_frame
	if skeleton_overlay:
		_draw_skeleton(view)
	await get_tree().process_frame
	var gun := view.get_child(0) as Node3D
	var pump := gun.find_child("Pump", true, false) as Node3D
	var support := definition.model.support
	if pump != null:
		support = (pump.get_parent() as Node3D).position + support
	var targets := {"grip": gun.transform * definition.model.grip, "support": gun.transform * support}
	var camera := Camera3D.new()
	camera.fov = 38.0
	camera.near = 0.01
	add_child(camera)
	for target: String in targets:
		var at: Vector3 = targets[target]
		for view_from in [["left", Vector3(-0.32, 0.04, 0.0)], ["right", Vector3(0.32, 0.04, 0.0)], ["below", Vector3(0.02, -0.32, 0.04)]]:
			camera.position = at + (view_from[1] as Vector3)
			camera.look_at(at, Vector3.UP if view_from[0] != "below" else Vector3.FORWARD)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var file := out.path_join("hands_%s_%s_%s%s.png" % [weapon_id, target, view_from[0], wire_tag])
			get_viewport().get_texture().get_image().save_png(file)
	print("saved hands_%s_*.png in %s" % [weapon_id, out])
	get_tree().quit(0)


## Lines along every hand bone (wrist to finger and thumb tips) and dots at
## the joints, drawn on top.
func _draw_skeleton(view: Node3D) -> void:
	var skeleton := view.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var lines := ImmediateMesh.new()
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color(1, 0.85, 0.1)
	line_material.no_depth_test = true
	line_material.render_priority = 10
	var dot_material := line_material.duplicate() as StandardMaterial3D
	dot_material.albedo_color = Color(1, 0.15, 0.1)
	var dot := SphereMesh.new()
	dot.radius = 0.0028
	dot.height = 0.0056
	lines.surface_begin(Mesh.PRIMITIVE_LINES, line_material)
	for bone in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(bone)
		if not ("Hand" in name):
			continue
		var at := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		var parent := skeleton.get_bone_parent(bone)
		if parent >= 0:
			lines.surface_add_vertex(skeleton.global_transform * skeleton.get_bone_global_pose(parent).origin)
			lines.surface_add_vertex(at)
		var marker := MeshInstance3D.new()
		marker.mesh = dot
		marker.material_override = dot_material
		add_child(marker)
		marker.global_position = at
	lines.surface_end()
	var overlay := MeshInstance3D.new()
	overlay.mesh = lines
	add_child(overlay)
