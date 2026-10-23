extends RefCounted
## Base class for test files. Each method named test_* is one test case and
## gets a fresh instance. Assertions record failures instead of stopping.

var failures: PackedStringArray = []


func assert_true(condition: bool, message: String = "expected true") -> void:
	if not condition:
		failures.append(message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		failures.append("%sexpected <%s>, got <%s>" % [
			message + ": " if message else "", expected, actual])
