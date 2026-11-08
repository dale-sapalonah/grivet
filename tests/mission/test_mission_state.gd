extends "res://tests/framework/suite.gd"


func _mission() -> Mission:
	var mission := Mission.new()
	var clear := MissionObjective.new()
	clear.kind = MissionObjective.Kind.CLEAR
	clear.stage = 0
	var search := MissionObjective.new()
	search.kind = MissionObjective.Kind.SEARCH
	search.point = Vector3(10, 0, 0)
	search.radius = 2.0
	search.seconds = 3.0
	var extract := MissionObjective.new()
	extract.kind = MissionObjective.Kind.EXTRACT
	extract.point = Vector3(0, 0, 20)
	extract.radius = 4.0
	mission.objectives = [clear, search, extract]
	return mission


func test_clear_waits_for_its_stage() -> void:
	var state := MissionState.new(_mission())
	assert_true(not state.update(Vector3.ZERO, 1.0), "not met before the stage is down")
	state.stage_cleared(1)
	assert_true(not state.update(Vector3.ZERO, 1.0), "another stage doesn't count")
	state.stage_cleared(0)
	assert_true(state.update(Vector3.ZERO, 0.1), "met once its stage is down")
	assert_eq(state.index, 1, "on to the search")


func test_search_needs_time_inside_and_loses_it_outside() -> void:
	var state := MissionState.new(_mission())
	state.stage_cleared(0)
	state.update(Vector3.ZERO, 0.1)
	for i in 20:
		state.update(Vector3(10.5, 0, 0), 0.1)  # 2 s inside
	assert_approx(state.search_fraction(), 2.0 / 3.0, 0.01, "two thirds searched")
	state.update(Vector3(20, 0, 0), 0.5)  # stepping out loses 1 s
	assert_approx(state.searched, 1.0, 0.01, "progress lost outside")
	var met := false
	for i in 25:
		met = met or state.update(Vector3(9.5, 1.0, 0.5), 0.1)
	assert_true(met, "searched long enough")
	assert_eq(state.index, 2, "on to the extraction")


func test_rescue_waits_for_its_stage_like_clear() -> void:
	var mission := Mission.new()
	var rescue := MissionObjective.new()
	rescue.kind = MissionObjective.Kind.RESCUE
	rescue.stage = 2
	mission.objectives = [rescue]
	var state := MissionState.new(mission)
	assert_true(not state.update(Vector3.ZERO, 1.0), "the raskols are still up")
	state.stage_cleared(2)
	assert_true(state.update(Vector3.ZERO, 0.1), "all down: rescued")
	assert_true(state.finished(), "and that was the last objective")


func test_extract_finishes_the_mission() -> void:
	var state := MissionState.new(_mission())
	state.index = 2
	assert_true(not state.update(Vector3(0, 0, 10), 0.1), "too far from the truck")
	assert_true(state.update(Vector3(1, 0, 18), 0.1), "at the truck")
	assert_true(state.finished(), "mission over")
	assert_true(state.current() == null, "no objective left")
