class_name StockfishAdapter
extends RefCounted
## Optional: plays through an external UCI engine (e.g. Stockfish) instead
## of the built-in ChessAI, talking over pipes via OS.execute_with_pipe.
##
## All calls block while waiting for the engine, so use it from a worker
## thread (AiPlayer does). Typical use:
##
##   var engine := StockfishAdapter.new()
##   if engine.start("C:/tools/stockfish.exe"):
##       engine.set_option("Skill Level", 8)
##       var uci := engine.best_move(start_fen, moves_so_far, 1000)   # "e2e4"
##       engine.quit()

## Per difficulty level: Stockfish "Skill Level" (0-20) and time per move.
const LEVELS := [
	{"skill": 1, "movetime_ms": 300},
	{"skill": 8, "movetime_ms": 1000},
	{"skill": 20, "movetime_ms": 2500},
]

const _STARTUP_TIMEOUT_MS := 5000
const _POLL_MS := 4

## Name the engine reported ("id name ..."), once started.
var engine_name := ""
## Set from another thread to make a running best_move() give up early.
var abort := false

var _pid := -1
var _stdio: FileAccess
var _stderr: FileAccess
var _buffer := ""


## Launches the engine and performs the UCI handshake. Returns false if the
## program can't be started or doesn't answer like a UCI engine.
func start(path: String, args: PackedStringArray = PackedStringArray()) -> bool:
	quit()
	if path == "":
		return false
	# A bare command name ("stockfish") is looked up on PATH by the OS; an
	# explicit path must exist.
	if (path.contains("/") or path.contains("\\")) and not FileAccess.file_exists(path):
		return false
	var info := OS.execute_with_pipe(path, args, false)
	if info.is_empty() or info.get("pid", -1) <= 0:
		return false
	_pid = info["pid"]
	_stdio = info["stdio"]
	_stderr = info.get("stderr")
	_buffer = ""

	_send("uci")
	var lines := _read_until("uciok", _STARTUP_TIMEOUT_MS)
	if lines.is_empty():
		quit()
		return false
	for line in lines:
		if line.begins_with("id name "):
			engine_name = line.trim_prefix("id name ").strip_edges()
	_send("isready")
	if _read_until("readyok", _STARTUP_TIMEOUT_MS).is_empty():
		quit()
		return false
	return true


func is_running() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)


func set_option(option_name: String, value: Variant) -> void:
	_send("setoption name %s value %s" % [option_name, str(value)])


## Asks for the best move in the position reached from `start_fen` after
## `moves` (UCI strings). Returns the move in UCI notation ("e2e4",
## "e7e8q"), or "" if the engine has no move or stopped responding.
func best_move(start_fen: String, moves: PackedStringArray, movetime_ms: int) -> String:
	if not is_running():
		return ""
	var position := "position fen " + start_fen
	if not moves.is_empty():
		position += " moves " + " ".join(moves)
	_send(position)
	_send("go movetime %d" % movetime_ms)
	var lines := _read_until("bestmove", movetime_ms + 5000, true)
	if lines.is_empty():
		return ""
	var parts := lines[lines.size() - 1].split(" ", false)
	if parts.size() < 2 or parts[1] == "(none)":
		return ""
	return parts[1]


## Shuts the engine down (asks nicely, then kills it if it lingers).
func quit() -> void:
	if _pid <= 0:
		return
	if _stdio != null and OS.is_process_running(_pid):
		_send("quit")
		var deadline := Time.get_ticks_msec() + 500
		while OS.is_process_running(_pid) and Time.get_ticks_msec() < deadline:
			OS.delay_msec(_POLL_MS)
	if OS.is_process_running(_pid):
		OS.kill(_pid)
	if _stdio != null:
		_stdio.close()
	if _stderr != null:
		_stderr.close()
	_stdio = null
	_stderr = null
	_pid = -1


func _send(command: String) -> void:
	if _stdio == null:
		return
	_stdio.store_string(command + "\n")
	_stdio.flush()


# Collects output lines until one starts with `token`. Returns the lines read
# (the matching one last), or an empty array on timeout / engine exit.
# With `stop_on_abort`, a pending abort sends "stop" so the engine answers
# with its best move so far.
func _read_until(token: String, timeout_ms: int, stop_on_abort: bool = false) -> PackedStringArray:
	var lines := PackedStringArray()
	var deadline := Time.get_ticks_msec() + timeout_ms
	var stop_sent := false
	while Time.get_ticks_msec() < deadline:
		var chunk := _stdio.get_buffer(4096)
		if chunk.size() > 0:
			_buffer += chunk.get_string_from_utf8()
			var newline := _buffer.find("\n")
			while newline != -1:
				var line := _buffer.substr(0, newline).strip_edges()
				_buffer = _buffer.substr(newline + 1)
				if line != "":
					lines.append(line)
					if line.begins_with(token):
						return lines
				newline = _buffer.find("\n")
			continue
		if not OS.is_process_running(_pid):
			break
		if stop_on_abort and abort and not stop_sent:
			_send("stop")
			stop_sent = true
			deadline = mini(deadline, Time.get_ticks_msec() + 1000)
		OS.delay_msec(_POLL_MS)
	return PackedStringArray()
