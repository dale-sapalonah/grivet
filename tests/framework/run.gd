extends SceneTree
## Headless test runner. Finds every res://tests/**/test_*.gd and runs each
## test_* method. Exit code 0 = all passed, 1 = failures.
##
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/framework/run.gd

const TEST_ROOT := "res://tests"


func _initialize() -> void:
	var passed := 0
	var failed := 0
	for path in _find_test_files(TEST_ROOT):
		var script: GDScript = load(path)
		if script == null:
			printerr("FAIL %s: could not load" % path)
			failed += 1
			continue
		for method in script.get_script_method_list():
			var test_name: String = method.name
			if not test_name.begins_with("test_"):
				continue
			var suite: Object = script.new()
			suite.call(test_name)
			if suite.failures.is_empty():
				passed += 1
				print("PASS %s::%s" % [path.get_file(), test_name])
			else:
				failed += 1
				for failure in suite.failures:
					printerr("FAIL %s::%s - %s" % [path.get_file(), test_name, failure])
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 or passed == 0 else 0)


func _find_test_files(dir_path: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for sub in dir.get_directories():
		if sub != "framework":
			found.append_array(_find_test_files(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
	return found
