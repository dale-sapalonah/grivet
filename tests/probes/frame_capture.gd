extends Node
## Renders the movement course on the real GPU for a few seconds, reports the
## average and worst frame time, and saves a screenshot. Not headless.
##
##   $GODOT --path . res://tests/probes/frame_capture.tscn -- <screenshot.png>

const COURSE := "res://levels/greybox/movement_course.tscn"
const WARMUP_FRAMES := 60
const MEASURE_FRAMES := 480

var _frame := 0
var _times: PackedFloat32Array = []


func _ready() -> void:
	add_child(load(COURSE).instantiate())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	_frame += 1
	if _frame <= WARMUP_FRAMES:
		return
	_times.append(delta)
	if _times.size() < MEASURE_FRAMES:
		return
	var total := 0.0
	var worst := 0.0
	for t in _times:
		total += t
		worst = maxf(worst, t)
	var average := total / _times.size()
	print("frames=%d avg=%.2f ms (%.0f fps) worst=%.2f ms" % [_times.size(), average * 1000.0, 1.0 / average, worst * 1000.0])
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		get_viewport().get_texture().get_image().save_png(args[0])
		print("screenshot: %s" % args[0])
	get_tree().quit()
