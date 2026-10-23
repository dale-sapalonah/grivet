extends "res://tests/framework/suite.gd"


func test_player_scene_has_rig_and_tuning() -> void:
	var player: Node = load("res://player/player.tscn").instantiate()
	assert_true(player is Player, "root is Player")
	assert_true(player.get_node_or_null("Head/CameraRig/Camera3D") is Camera3D, "camera")
	assert_true((player as Player).tuning is MovementTuning, "movement tuning")
	assert_true((player as Player).camera_tuning is CameraTuning, "camera tuning")
	player.free()


func test_movement_course_loads() -> void:
	var course: Node = load("res://levels/greybox/movement_course.tscn").instantiate()
	assert_true(course.get_node_or_null("Player") is Player, "player placed")
	course.free()
