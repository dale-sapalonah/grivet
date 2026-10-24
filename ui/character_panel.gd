class_name CharacterPanel
extends SubViewportContainer
## One illustrated panel of the title art: a small 3D scene in its own world
## (a posed character or the taxi against a bold colour, hard key light, a
## coloured rim light) rendered for a few frames, then frozen, and drawn
## through comic_panel.gdshader.

enum Subject { RIFLE_AIM, MACHETE_SWING, SHOTGUN, TAXI, MACHETE_CLOSE, RIFLE_FIRE }

const COMIC := preload("res://ui/comic_panel.gdshader")
const PROFILES := {"rifleman": "res://data/ai/rifleman.tres", "rusher": "res://data/ai/rusher.tres",
		"machete": "res://data/ai/machete.tres"}

var subject: Subject = Subject.RIFLE_AIM
var backdrop := Color(0.9, 0.45, 0.1)
var variant := 0

var _viewport := SubViewport.new()
var _mannequin: Mannequin
var _frames := 0


func _ready() -> void:
	stretch = true
	var comic := ShaderMaterial.new()
	comic.shader = COMIC
	material = comic
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_build_scene()


func _process(delta: float) -> void:
	_frames += 1
	if _mannequin != null:
		_pose(delta)
	if _frames > 12:
		# Art, not animation: keep the last frame and stop rendering.
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		set_process(false)


func _build_scene() -> void:
	var world := Node3D.new()
	_viewport.add_child(world)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = backdrop
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = backdrop.lerp(Color.WHITE, 0.3)
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.light_color = Color(1.0, 0.95, 0.85)
	key.rotation_degrees = Vector3(-30, -35, 0)
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 1.2
	rim.light_color = backdrop.lerp(Color.WHITE, 0.4)
	rim.rotation_degrees = Vector3(-10, 150, 0)
	world.add_child(rim)
	var camera := Camera3D.new()
	world.add_child(camera)
	var target := Vector3.ZERO
	match subject:
		Subject.TAXI:
			var taxi := KamfotTaxi.new()
			world.add_child(taxi)
			taxi.build("T 9925")
			taxi.rotation_degrees.y = 150.0
			camera.fov = 42.0
			camera.position = Vector3(3.2, 0.9, 4.2)
			# Aim above the car: it sits in the lower half, under the logo.
			target = Vector3(0, 1.9, 0)
			camera.look_at(target)
		_:
			var kind := "rifleman"
			if subject in [Subject.MACHETE_SWING, Subject.MACHETE_CLOSE]:
				kind = "machete"
			elif subject == Subject.SHOTGUN:
				kind = "rusher"
			_mannequin = Mannequin.new()
			world.add_child(_mannequin)
			_mannequin.build(load(PROFILES[kind]), variant)
			_mannequin.rotation_degrees.y = 200.0 if subject != Subject.RIFLE_FIRE else 230.0
			var close := subject in [Subject.MACHETE_CLOSE, Subject.RIFLE_FIRE]
			# Close-ups at face height; full figures from low down, filling the frame.
			camera.fov = 32.0 if close else 34.0
			camera.position = Vector3(0.0, 1.55, 1.45) if close else Vector3(0.35, 0.75, 2.45)
			target = Vector3(0.0, 1.45, 0.0) if close else Vector3(0.0, 1.05, 0.0)
			camera.look_at(target)
			if subject == Subject.RIFLE_FIRE:
				var flash := MuzzleFlash.new()
				_mannequin.muzzle.add_child(flash)
				flash.setup(6.0, 4.0, 10.0, 0.5)
				flash.flash.call_deferred()
	# A sunburst behind the subject, facing the camera: rays of a lighter shade.
	var burst := _sunburst()
	world.add_child(burst)
	var away := (target - camera.position).normalized()
	burst.position = target + away * 3.5
	burst.look_at(camera.position)


func _pose(delta: float) -> void:
	match subject:
		Subject.MACHETE_SWING:
			_mannequin.swing = _mannequin.swing_windup * 0.95  # blade overhead, about to fall
			_mannequin.pose(delta, 0.15, 0.0, 3.0, false)
		Subject.MACHETE_CLOSE:
			_mannequin.swing = -1.0
			_mannequin.pose(delta, 0.0, 0.1, 0.0, false)
		Subject.SHOTGUN:
			_mannequin.pose(delta, 0.3, -0.1, 0.0, false)
		_:
			_mannequin.pose(delta, 0.0, 0.05, 0.0, true)


func _sunburst() -> MeshInstance3D:
	var rays := MeshBaker.new()
	var light := backdrop.lerp(Color.WHITE, 0.25)
	for i in 12:
		var angle := i * TAU / 12.0
		rays.add(MeshBaker.prism(PackedVector2Array([Vector2(0, 0), Vector2(cos(angle - 0.12), sin(angle - 0.12)) * 9.0,
				Vector2(cos(angle + 0.12), sin(angle + 0.12)) * 9.0]), 0.01), Transform3D.IDENTITY, light)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var instance := MeshInstance3D.new()
	instance.mesh = rays.commit(material)
	return instance
