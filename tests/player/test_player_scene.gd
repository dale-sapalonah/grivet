extends "res://tests/framework/suite.gd"


func test_player_scene_has_rig_and_tuning() -> void:
	var player: Node = load("res://player/player.tscn").instantiate()
	assert_true(player is Player, "root is Player")
	assert_true(player.get_node_or_null("Head/CameraRig/Camera3D") is Camera3D, "camera")
	assert_true((player as Player).tuning is MovementTuning, "movement tuning")
	assert_true((player as Player).camera_tuning is CameraTuning, "camera tuning")
	var holder := player.get_node_or_null("Head/CameraRig/Camera3D/WeaponHolder") as WeaponHolder
	assert_true(holder != null, "weapon holder under the camera")
	if holder != null:
		assert_eq(holder.loadout.size(), 3, "three weapons in the loadout")
	player.free()


func test_firing_range_loads() -> void:
	var packed := load("res://levels/greybox/firing_range.tscn") as PackedScene
	assert_true(packed != null, "range scene loads")
	if packed == null:
		return
	var range_scene: Node = packed.instantiate()
	assert_true(range_scene.get_node_or_null("Player") is Player, "player placed")
	assert_true(range_scene.get_node_or_null("Target100") is TargetDummy, "100 m target")
	assert_eq(range_scene.get_node("Steel5mm").get_meta("surface", ""), "steel", "panel surface tag")
	range_scene.free()


func test_movement_course_loads() -> void:
	var packed := load("res://levels/greybox/movement_course.tscn") as PackedScene
	assert_true(packed != null, "course scene loads")
	if packed == null:
		return
	var course: Node = packed.instantiate()
	assert_true(course.get_node_or_null("Player") is Player, "player placed")
	course.free()
