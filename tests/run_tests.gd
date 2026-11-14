extends SceneTree
## Headless test runner.
##
##   godot --headless --path . --import            (once, builds the class cache)
##   godot --headless --path . -s tests/run_tests.gd
##   godot --headless --path . -s tests/run_tests.gd -- --full      (slow perft too)
##   godot --headless --path . -s tests/run_tests.gd -- perft       (name filter)
##
## Exit code 0 when everything passes, 1 otherwise.

const SUITES := [
	"res://tests/test_perft.gd",
	"res://tests/test_fen.gd",
	"res://tests/test_rules.gd",
	"res://tests/test_san.gd",
	"res://tests/test_pieces.gd",
	"res://tests/test_game_scene.gd",
	"res://tests/test_ai.gd",
	"res://tests/test_menu_and_sets.gd",
	"res://tests/test_stockfish_adapter.gd",
]


func _initialize() -> void:
	# The root viewport only enters the tree after _initialize returns; wait a
	# frame so scenes added by the tests get their _ready callbacks.
	await process_frame
	var full := false
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--full":
			full = true
		elif not arg.begins_with("-"):
			filter = arg

	var total_tests := 0
	var total_checks := 0
	var failed: Array[String] = []
	var started := Time.get_ticks_msec()

	for path: String in SUITES:
		if filter != "" and not path.contains(filter):
			continue
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failed.append("%s: could not load suite" % path)
			continue
		print("\n== %s" % path.get_file())
		var suite: Object = script.new()
		suite.full = full
		for method in suite.get_method_list():
			var mname: String = method["name"]
			if not mname.begins_with("test_"):
				continue
			total_tests += 1
			var before: int = suite.failures.size()
			var checks_before: int = suite.checks
			var t0 := Time.get_ticks_msec()
			suite.begin(mname)
			@warning_ignore("redundant_await")
			await suite.call(mname)  # tests may be coroutines (animation tests wait for timers)
			var ms := Time.get_ticks_msec() - t0
			var ok: bool = suite.failures.size() == before
			# A test that ran zero checks almost certainly aborted on a
			# script error, so count it as a failure.
			if ok and suite.checks == checks_before:
				suite.failures.append("%s: no checks ran (script error?)" % mname)
				ok = false
			print("  [%s] %s (%d ms)" % ["PASS" if ok else "FAIL", mname, ms])
		total_checks += suite.checks
		for f: String in suite.failures:
			failed.append("%s: %s" % [path.get_file(), f])

	print("\n%d tests, %d checks, %d failures, %.1f s" % [
		total_tests, total_checks, failed.size(), (Time.get_ticks_msec() - started) / 1000.0])
	for f in failed:
		print("  FAILED " + f)
	print("RESULT: %s" % ("FAILED" if not failed.is_empty() or total_tests == 0 else "OK"))
	quit(1 if not failed.is_empty() or total_tests == 0 else 0)
