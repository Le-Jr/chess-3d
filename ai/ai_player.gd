class_name AiPlayer
extends RefCounted
## Runs the computer opponent on a background Thread so the UI never freezes.
## (In a build without thread support - a web export made with "Thread
## Support" off - it searches on the main thread instead, one frame after
## think(), and the picture stalls while it does.)
##
##   var ai := AiPlayer.new()
##   ai.move_ready.connect(func(move, info): ...)
##   ai.think(game_state, level)     # returns immediately
##   ai.cancel()                     # e.g. on undo / new game
##
## Uses the built-in ChessAI, or an external UCI engine when
## GameSettings.stockfish_path is set (falling back to the built-in engine
## if that program can't be started or gives no usable move).
##
## `move_ready` is always emitted on the main thread. A cancelled search
## never emits.

## `info` holds "engine" (name) plus, for the built-in engine, the
## dictionary returned by ChessAI.search (score, depth, nodes, time_ms).
signal move_ready(move: int, info: Dictionary)

## The computer never answers faster than this, so its moves don't feel abrupt.
const MIN_THINK_MS := 350

var _thread: Thread
var _engine: ChessAI
var _external: StockfishAdapter
## Set to search on the main thread even where threads exist (tests).
static var force_main_thread := false

var _token := 0
var _blocking := false  # a main-thread search is queued or running


func is_thinking() -> bool:
	return _thread != null or _blocking


## Whether searches can run on their own thread in this build.
static func has_threads() -> bool:
	return not force_main_thread and not OS.has_feature("nothreads")


## Starts searching the current position of `state` at difficulty `level`
## (index into ChessAI.LEVELS). Any search already running is cancelled.
func think(state: GameState, level: int) -> void:
	cancel()
	ChessAI.ensure_tables()
	_token += 1
	_engine = ChessAI.new()
	_external = StockfishAdapter.new() if GameSettings.stockfish_path != "" else null
	# The thread gets its own copies of everything it needs; the game's
	# board is never touched from the worker.
	var job := {
		"token": _token,
		"level": level,
		"board": state.board.clone(),
		"history": state.position_hashes(),
		"start_fen": state.start_fen,
		"moves": _uci_moves(state),
		"engine_path": GameSettings.stockfish_path,
		"engine_args": GameSettings.stockfish_args,
	}
	if not has_threads():
		_blocking = true
		_search_on_main_thread(_engine, job)
		return
	_thread = Thread.new()
	_thread.start(_search.bind(_engine, _external, job))


# No threads: let two frames draw ("Computer is thinking..."), then search.
func _search_on_main_thread(engine: ChessAI, job: Dictionary) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	await loop.process_frame
	await loop.process_frame
	if job["token"] != _token:
		return
	var result: Dictionary = engine.choose_move(job["board"], job["level"], job["history"])
	result["engine"] = "built-in"
	if job["token"] != _token:
		return
	_blocking = false
	_engine = null
	move_ready.emit(result["move"], result)


## Stops the running search (if any) and discards its result.
func cancel() -> void:
	_token += 1
	if _engine != null:
		_engine.stop()
	if _external != null:
		_external.abort = true
	if _thread != null:
		_thread.wait_to_finish()
	_thread = null
	_blocking = false
	_engine = null
	_external = null


static func _uci_moves(state: GameState) -> PackedStringArray:
	var out := PackedStringArray()
	for m in state.move_history:
		out.append(Move.to_uci(m))
	return out


# Runs on the worker thread.
func _search(engine: ChessAI, external: StockfishAdapter, job: Dictionary) -> void:
	var started := Time.get_ticks_msec()
	var result := {}
	if external != null:
		result = _search_external(external, job)
	if result.is_empty() and (external == null or not external.abort):
		result = engine.choose_move(job["board"], job["level"], job["history"])
		result["engine"] = "built-in"
	if result.is_empty():
		result = {"move": Move.NONE, "engine": "none"}
	var spare := MIN_THINK_MS - (Time.get_ticks_msec() - started)
	if spare > 0:
		OS.delay_msec(spare)
	_finished.call_deferred(job["token"], result)


# Asks the external UCI engine; returns {} if it is unavailable or its
# answer is not a legal move.
func _search_external(external: StockfishAdapter, job: Dictionary) -> Dictionary:
	var result := {}
	if external.start(job["engine_path"], job["engine_args"]):
		var params: Dictionary = StockfishAdapter.LEVELS[clampi(job["level"], 0, StockfishAdapter.LEVELS.size() - 1)]
		external.set_option("Skill Level", params["skill"])
		var uci := external.best_move(job["start_fen"], job["moves"], params["movetime_ms"])
		for m in MoveGenerator.generate_legal(job["board"]):
			if Move.to_uci(m) == uci:
				result = {"move": m, "engine": external.engine_name}
				break
	external.quit()
	return result


# Back on the main thread.
func _finished(token: int, result: Dictionary) -> void:
	if token != _token:
		return  # cancelled; cancel() already joined the thread
	_thread.wait_to_finish()
	_thread = null
	_engine = null
	_external = null
	move_ready.emit(result["move"], result)
