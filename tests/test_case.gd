extends RefCounted
## Minimal test-suite base class. Suites extend this file and define methods
## named `test_*`; tests/run_tests.gd discovers and runs them.

## Set by the runner when started with `-- --full` (enables the slow tests).
var full := false

var checks := 0
var failures: Array[String] = []
var _current := ""


func begin(test_name: String) -> void:
	_current = test_name


func check(cond: bool, msg: String = "") -> void:
	checks += 1
	if not cond:
		failures.append("%s: %s" % [_current, msg if msg != "" else "check failed"])


func eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	checks += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: %s - expected <%s>, got <%s>" % [_current, msg, str(expected), str(actual)])
