class_name TouchStick
extends RefCounted
## Pure maths of the floating move stick (tested headless): where the base
## sits, the move vector (x right, y forward, length 0..1) and whether the
## thumb is in the sprint ring. TouchControls feeds it screen positions.

var tuning: TouchTuning
var active := false
var base := Vector2.ZERO
var thumb := Vector2.ZERO
## Move intent in Input.get_vector terms: x right, y forward.
var vector := Vector2.ZERO
var in_sprint_ring := false


func _init(stick_tuning: TouchTuning) -> void:
	tuning = stick_tuning


func begin(position: Vector2) -> void:
	active = true
	base = position
	thumb = position
	_update()


func drag(position: Vector2) -> void:
	if not active:
		return
	thumb = position
	var offset := thumb - base
	if tuning.stick_follows and offset.length() > tuning.stick_radius:
		base = thumb - offset.normalized() * tuning.stick_radius
	_update()


func end() -> void:
	active = false
	vector = Vector2.ZERO
	in_sprint_ring = false


func _update() -> void:
	var offset := (thumb - base) / tuning.stick_radius
	var length := minf(offset.length(), 1.0)
	if length <= tuning.stick_deadzone:
		vector = Vector2.ZERO
		in_sprint_ring = false
		return
	# Rescale past the deadzone so the first movement starts from zero.
	var strength := (length - tuning.stick_deadzone) / (1.0 - tuning.stick_deadzone)
	var direction := offset.normalized()
	vector = Vector2(direction.x, -direction.y) * strength  # screen y grows down
	in_sprint_ring = length >= tuning.sprint_ring and -direction.y >= tuning.sprint_forward
