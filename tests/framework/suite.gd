extends RefCounted
## Base class for test files. Each method named test_* is one test case and
## gets a fresh instance. Assertions record failures instead of stopping.

var failures: PackedStringArray = []


func assert_true(condition: bool, message: String = "expected true") -> void:
	if not condition:
		failures.append(message)


func assert_approx(actual: float, expected: float, tolerance: float = 1e-4, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%sexpected <%s> ± %s, got <%s>" % [
			message + ": " if message else "", expected, tolerance, actual])


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		failures.append("%sexpected <%s>, got <%s>" % [
			message + ": " if message else "", expected, actual])
