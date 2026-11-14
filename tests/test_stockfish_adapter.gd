extends "res://tests/test_case.gd"
## StockfishAdapter, exercised against a fake UCI engine written in Python
## (tests/mock_uci_engine.py). Skipped when no Python interpreter is on PATH.

const ProfileData := preload("res://tools/profile_data.gd")

var _python := ""
var _python_checked := false


func _find_python() -> String:
	if not _python_checked:
		_python_checked = true
		for candidate: String in ["python", "python3", "py"]:
			var output := []
			if OS.execute(candidate, ["--version"], output) == 0:
				_python = candidate
				break
	return _python


func _mock_args() -> PackedStringArray:
	return PackedStringArray(["-u", ProjectSettings.globalize_path("res://tests/mock_uci_engine.py")])


func test_missing_engine_fails_cleanly() -> void:
	var engine := StockfishAdapter.new()
	check(not engine.start(""), "empty path")
	check(not engine.start("C:/no/such/folder/stockfish.exe"), "path that does not exist")
	check(not engine.is_running(), "not running")
	eq(engine.best_move(Board.START_FEN, PackedStringArray(), 100), "", "no move without an engine")
	engine.quit()  # must be a harmless no-op


func test_uci_conversation() -> void:
	var python := _find_python()
	if python == "":
		check(true, "skipped: no Python interpreter found for the mock engine")
		return
	var engine := StockfishAdapter.new()
	check(engine.start(python, _mock_args()), "handshake with the mock engine")
	eq(engine.engine_name, "MockFish 1.0", "engine name parsed from 'id name'")
	check(engine.is_running(), "process is running")
	engine.set_option("Skill Level", 5)
	eq(engine.best_move(Board.START_FEN, PackedStringArray(), 50), "e2e4", "best move from the start")
	eq(engine.best_move(Board.START_FEN, PackedStringArray(["e2e4"]), 50), "e7e5", "moves are passed along")
	engine.quit()
	check(not engine.is_running(), "engine process ended after quit")


func test_program_that_is_not_a_uci_engine() -> void:
	var python := _find_python()
	if python == "":
		check(true, "skipped: no Python interpreter found")
		return
	var engine := StockfishAdapter.new()
	# Exits immediately without ever saying "uciok".
	check(not engine.start(python, PackedStringArray(["-c", "print('hello')"])), "handshake fails")
	check(not engine.is_running(), "cleaned up")


func test_ai_player_uses_external_engine_and_falls_back() -> void:
	var python := _find_python()
	if python == "":
		check(true, "skipped: no Python interpreter found")
		return
	var tree := Engine.get_main_loop() as SceneTree
	var gs := GameState.new()
	var player := AiPlayer.new()
	var got := []
	player.move_ready.connect(func(m: int, info: Dictionary) -> void: got.append([m, info]))

	GameSettings.stockfish_path = python
	GameSettings.stockfish_args = _mock_args()
	player.think(gs, 0)
	var deadline := Time.get_ticks_msec() + 15000
	while got.is_empty() and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	eq(got.size(), 1, "external engine answered")
	if got.size() == 1:
		eq(Move.to_uci(got[0][0]), "e2e4", "the external engine's move is played")
		eq(got[0][1]["engine"], "MockFish 1.0", "info names the engine")

	# A path that doesn't work falls back to the built-in engine.
	got.clear()
	GameSettings.stockfish_path = "C:/no/such/folder/stockfish.exe"
	GameSettings.stockfish_args = PackedStringArray()
	player.think(gs, 0)
	deadline = Time.get_ticks_msec() + 15000
	while got.is_empty() and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	eq(got.size(), 1, "built-in engine answered instead")
	if got.size() == 1:
		eq(got[0][1]["engine"], "built-in", "fell back to the built-in engine")
		check(gs.legal_moves().has(got[0][0]), "and returned a legal move")

	GameSettings.stockfish_path = ""
	GameSettings.stockfish_args = PackedStringArray()


func test_blender_script_profiles_in_sync() -> void:
	# Lives here with the other "external tool" checks: the generated data
	# block in tools/blender_export_pieces.py must match PieceProfiles.
	var embedded: Variant = JSON.parse_string(ProfileData.embedded_json())
	check(embedded is Dictionary, "the Blender script contains a profile data block")
	var current: Variant = JSON.parse_string(JSON.stringify(ProfileData.build()))
	eq(JSON.stringify(embedded, "", true), JSON.stringify(current, "", true),
			"Blender profile data matches PieceProfiles (run tools/sync_blender_profiles.gd)")
