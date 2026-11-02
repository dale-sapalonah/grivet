extends "res://tests/framework/suite.gd"

const Stick := preload("res://ui/touch_stick.gd")
const TUNING := preload("res://data/ui/touch_tuning.tres")

var stick := Stick.new(TUNING)
var radius: float = TUNING.stick_radius


func _push(offset: Vector2) -> void:
	stick.begin(Vector2(300, 600))
	stick.drag(Vector2(300, 600) + offset)


func test_resting_thumb_does_not_move() -> void:
	_push(Vector2(0, -radius * TUNING.stick_deadzone * 0.9))
	assert_eq(stick.vector, Vector2.ZERO, "inside the deadzone")


func test_up_on_screen_is_forward() -> void:
	_push(Vector2(0, -radius * 0.6))
	assert_true(stick.vector.y > 0.0 and absf(stick.vector.x) < 1e-5, "up = forward, got %s" % stick.vector)
	_push(Vector2(radius * 0.6, 0))
	assert_true(stick.vector.x > 0.0 and absf(stick.vector.y) < 1e-5, "right = right, got %s" % stick.vector)


func test_strength_starts_at_zero_past_the_deadzone_and_caps_at_one() -> void:
	_push(Vector2(0, -radius * (TUNING.stick_deadzone + 0.01)))
	assert_true(stick.vector.length() < 0.05, "just past the deadzone is slow: %f" % stick.vector.length())
	_push(Vector2(0, -radius * 3.0))
	assert_approx(stick.vector.length(), 1.0, 1e-4, "full deflection")


func test_sprint_ring_only_forwards() -> void:
	_push(Vector2(0, -radius))
	assert_true(stick.in_sprint_ring, "full forward sprints")
	_push(Vector2(radius, 0))
	assert_true(not stick.in_sprint_ring, "full sideways does not sprint")
	_push(Vector2(0, -radius * 0.5))
	assert_true(not stick.in_sprint_ring, "half forward does not sprint")


func test_base_follows_a_thumb_past_the_rim() -> void:
	stick.begin(Vector2(300, 600))
	stick.drag(Vector2(300, 600 - radius * 2.0))
	assert_approx(stick.base.distance_to(stick.thumb), radius, 1e-3, "base trails at one radius")
	# Coming back by half a radius now steers backwards at once, not after
	# undoing the overshoot.
	stick.drag(stick.thumb + Vector2(0, radius * 1.5))
	assert_true(stick.vector.y < 0.0, "pulling back after an overshoot moves back: %s" % stick.vector)


func test_release_stops() -> void:
	_push(Vector2(0, -radius))
	stick.end()
	assert_eq(stick.vector, Vector2.ZERO)
	assert_true(not stick.in_sprint_ring and not stick.active)


func test_buttons_do_not_overlap_and_stay_on_a_phone_screen() -> void:
	# The narrowest canvas the mobile stretch makes is 1600 x 900 (16:9).
	var screen := Vector2(1600, 900)
	var buttons: Array = TUNING.buttons
	assert_true(buttons.size() >= 6, "fire, aim, reload, jump, crouch, grenade at least")
	for i in buttons.size():
		var a: TouchButtonSpec = buttons[i]
		var centre := screen + a.offset
		assert_true(Rect2(Vector2.ZERO, screen).grow(-a.radius).has_point(centre), "%s off screen" % a.label)
		assert_true(centre.x > screen.x * 0.5, "%s is on the stick's half" % a.label)
		assert_true(InputMap.has_action(a.action) or a.action in ["fire", "aim", "reload", "jump", "crouch",
				"grenade", "next_weapon", "plate"], "%s presses unknown action %s" % [a.label, a.action])
		for j in range(i + 1, buttons.size()):
			var b: TouchButtonSpec = buttons[j]
			assert_true(centre.distance_to(screen + b.offset) >= a.radius + b.radius,
					"%s overlaps %s" % [a.label, b.label])
