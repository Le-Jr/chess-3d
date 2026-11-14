class_name GameSettings
extends RefCounted
## Choices made in the main menu, read by the game scene. Plain static state
## (no autoload needed), saved to user://settings.cfg.

enum Mode { HOTSEAT, VS_AI }

const SETTINGS_FILE := "user://settings.cfg"
## Folders scanned for extra piece sets (.tres PieceSet resources, .glb models).
const PIECE_SET_DIRS := ["res://piece_sets", "user://piece_sets"]

static var mode: Mode = Mode.HOTSEAT
## The human's color in VS_AI mode.
static var human_color: int = Piece.WHITE
## 0 = Easy, 1 = Medium, 2 = Hard.
static var ai_level: int = 1
## One of MaterialPresets.Preset.
static var material_preset: int = MaterialPresets.Preset.CLASSIC_WOOD
## Path of the piece set to use (.tres PieceSet or .glb); "" = procedural.
static var piece_set_path: String = ""
## Hot-seat: swing the camera to the other side after every move.
static var auto_rotate_camera: bool = true
## Turn off to make moves instant (also used by the tests).
static var animations: bool = true
## Optional path to a Stockfish executable. When set (and it starts), the
## computer opponent uses it instead of the built-in engine.
static var stockfish_path: String = ""
## Extra command-line arguments for that executable (normally none).
static var stockfish_args := PackedStringArray()


## The PieceSet selected in the menu, with the selected material preset
## applied. Falls back to the procedural set if the file can't be loaded.
static func make_piece_set() -> PieceSet:
	var piece_set: PieceSet = null
	if piece_set_path != "":
		piece_set = PieceSet.load_from(piece_set_path)
		if piece_set == null:
			push_warning("Could not load piece set '%s'; using the procedural set." % piece_set_path)
	if piece_set == null:
		piece_set = PieceSet.new()
	if piece_set.apply_materials:
		piece_set.use_preset(material_preset)
	return piece_set


## [{"name": ..., "path": ...}] for the built-in set plus everything found in
## PIECE_SET_DIRS.
static func available_piece_sets() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"name": "Procedural (built-in)", "path": ""}]
	for dir_path: String in PIECE_SET_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		var files := dir.get_files()
		files.sort()
		for file in files:
			# Exported builds list imported files as "name.glb.import" / "name.tres.remap".
			var clean := file.trim_suffix(".import").trim_suffix(".remap")
			var ext := clean.get_extension().to_lower()
			if ext in ["tres", "res", "glb", "gltf"]:
				var entry := {"name": clean.get_basename().capitalize(), "path": dir_path.path_join(clean)}
				if not out.has(entry):
					out.append(entry)
	return out


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "mode", int(mode))
	cfg.set_value("game", "human_color", human_color)
	cfg.set_value("game", "ai_level", ai_level)
	cfg.set_value("game", "auto_rotate_camera", auto_rotate_camera)
	cfg.set_value("look", "material_preset", material_preset)
	cfg.set_value("look", "piece_set_path", piece_set_path)
	cfg.set_value("engine", "stockfish_path", stockfish_path)
	cfg.save(SETTINGS_FILE)


static func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) != OK:
		return
	mode = clampi(cfg.get_value("game", "mode", 0), 0, 1) as Mode
	human_color = Piece.BLACK if cfg.get_value("game", "human_color", Piece.WHITE) == Piece.BLACK else Piece.WHITE
	ai_level = clampi(cfg.get_value("game", "ai_level", 1), 0, ChessAI.LEVELS.size() - 1)
	auto_rotate_camera = bool(cfg.get_value("game", "auto_rotate_camera", true))
	material_preset = clampi(cfg.get_value("look", "material_preset", 0), 0, MaterialPresets.preset_count() - 1)
	piece_set_path = str(cfg.get_value("look", "piece_set_path", ""))
	stockfish_path = str(cfg.get_value("engine", "stockfish_path", ""))
