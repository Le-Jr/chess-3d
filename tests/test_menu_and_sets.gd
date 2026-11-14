extends "res://tests/test_case.gd"
## Main menu, material presets, settings persistence and PieceSet swapping
## (including a .glb round trip).

const PieceExporter := preload("res://tools/piece_exporter.gd")
const TEST_GLB := "user://test_pieces.glb"


func _reset_settings() -> void:
	GameSettings.mode = GameSettings.Mode.HOTSEAT
	GameSettings.human_color = Piece.WHITE
	GameSettings.ai_level = 1
	GameSettings.material_preset = MaterialPresets.Preset.CLASSIC_WOOD
	GameSettings.piece_set_path = ""
	GameSettings.auto_rotate_camera = true
	GameSettings.animations = true
	GameSettings.stockfish_path = ""


func test_material_presets() -> void:
	eq(MaterialPresets.preset_count(), 3, "three presets")
	var seen := {}
	for preset in MaterialPresets.preset_count():
		var white := MaterialPresets.piece_material(preset, Piece.WHITE)
		var black := MaterialPresets.piece_material(preset, Piece.BLACK)
		check(white.albedo_color.get_luminance() > black.albedo_color.get_luminance() + 0.3,
				"%s: white pieces are clearly lighter than black" % MaterialPresets.NAMES[preset])
		check(MaterialPresets.board_light(preset).albedo_color.get_luminance()
				> MaterialPresets.board_dark(preset).albedo_color.get_luminance() + 0.15,
				"%s: light squares are lighter than dark squares" % MaterialPresets.NAMES[preset])
		check(not seen.has(white.albedo_color), "presets look different")
		seen[white.albedo_color] = true
		var piece_set := PieceSet.procedural(preset)
		eq((piece_set.white_material as StandardMaterial3D).albedo_color, white.albedo_color,
				"PieceSet.procedural uses the preset")


func test_settings_round_trip() -> void:
	_reset_settings()
	var backup := ""
	if FileAccess.file_exists(GameSettings.SETTINGS_FILE):
		backup = FileAccess.get_file_as_string(GameSettings.SETTINGS_FILE)

	GameSettings.mode = GameSettings.Mode.VS_AI
	GameSettings.human_color = Piece.BLACK
	GameSettings.ai_level = 2
	GameSettings.material_preset = MaterialPresets.Preset.MARBLE
	GameSettings.piece_set_path = "user://piece_sets/mine.glb"
	GameSettings.auto_rotate_camera = false
	GameSettings.save()
	_reset_settings()
	GameSettings.load_saved()
	eq(GameSettings.mode, GameSettings.Mode.VS_AI, "mode saved")
	eq(GameSettings.human_color, Piece.BLACK, "color saved")
	eq(GameSettings.ai_level, 2, "level saved")
	eq(GameSettings.material_preset, int(MaterialPresets.Preset.MARBLE), "preset saved")
	eq(GameSettings.piece_set_path, "user://piece_sets/mine.glb", "piece set saved")
	eq(GameSettings.auto_rotate_camera, false, "auto-rotate saved")

	# Put the player's real settings back.
	if backup != "":
		var f := FileAccess.open(GameSettings.SETTINGS_FILE, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.SETTINGS_FILE))
	_reset_settings()


func test_missing_piece_set_falls_back_to_procedural() -> void:
	_reset_settings()
	check(PieceSet.load_from("res://piece_sets/does_not_exist.glb") == null, "missing glb -> null")
	check(PieceSet.load_from("res://piece_sets/does_not_exist.tres") == null, "missing tres -> null")
	check(GameSettings.available_piece_sets()[0]["path"] == "", "procedural set is always offered first")


func test_glb_round_trip_as_piece_set() -> void:
	_reset_settings()
	eq(PieceExporter.export_glb(TEST_GLB, 16), OK, "procedural set exports to .glb")
	check(FileAccess.file_exists(TEST_GLB), "file written")

	var piece_set := PieceSet.from_glb(TEST_GLB)
	check(piece_set != null, "glb loads as a PieceSet")
	if piece_set == null:
		return
	for type in range(Piece.PAWN, Piece.KING + 1):
		var source := piece_set.source_for(type)
		check(source is Mesh or source is PackedScene, "%s found in the glb" % PieceExporter.NAMES[type])

	piece_set.use_preset(MaterialPresets.Preset.MARBLE)
	for type in range(Piece.PAWN, Piece.KING + 1):
		var node := piece_set.instantiate(Piece.BLACK | type)
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		if node is MeshInstance3D:
			meshes.append(node)
		eq(meshes.size(), 1, "%s has one mesh" % PieceExporter.NAMES[type])
		if meshes.size() == 1:
			var mi := meshes[0] as MeshInstance3D
			var aabb := mi.mesh.get_aabb()
			check(absf(aabb.end.y - PieceProfiles.height(type)) < 0.03,
					"%s keeps its height through the round trip" % PieceExporter.NAMES[type])
			check(absf(aabb.get_center().x) < 0.05 and absf(mi.position.x) < 0.001,
					"%s is centered on its square" % PieceExporter.NAMES[type])
			eq(mi.get_surface_override_material(0), piece_set.black_material, "body material applied")
			var felt_surfaces := 0
			for s in mi.mesh.get_surface_count():
				if mi.get_surface_override_material(s) == piece_set.felt_material:
					felt_surfaces += 1
			eq(felt_surfaces, 1, "%s felt surface recognised by name" % PieceExporter.NAMES[type])
		node.free()

	# The game picks the set up through GameSettings.
	GameSettings.piece_set_path = TEST_GLB
	var from_settings := GameSettings.make_piece_set()
	check(from_settings.source_for(Piece.KNIGHT) != null, "GameSettings loads the glb set")
	_reset_settings()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_GLB))


func test_game_uses_selected_set_and_preset() -> void:
	_reset_settings()
	GameSettings.material_preset = MaterialPresets.Preset.STYLIZED_FLAT
	GameSettings.animations = false
	var packed: PackedScene = load("res://scenes/game.tscn")
	var game := packed.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(game)
	var expected := MaterialPresets.piece_material(MaterialPresets.Preset.STYLIZED_FLAT, Piece.WHITE)
	eq((game.piece_set.white_material as StandardMaterial3D).albedo_color, expected.albedo_color,
			"pieces use the selected preset")
	var tiles: MeshInstance3D = game.board_view._tiles
	eq((tiles.get_surface_override_material(0) as StandardMaterial3D).albedo_color,
			MaterialPresets.board_light(MaterialPresets.Preset.STYLIZED_FLAT).albedo_color,
			"board uses the matching material")
	game.get_parent().remove_child(game)
	game.free()
	_reset_settings()


func test_main_menu() -> void:
	_reset_settings()
	var backup := ""
	if FileAccess.file_exists(GameSettings.SETTINGS_FILE):
		backup = FileAccess.get_file_as_string(GameSettings.SETTINGS_FILE)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.SETTINGS_FILE))

	var packed: PackedScene = load("res://ui/main_menu.tscn")
	var menu := packed.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(menu)
	eq(menu._preview_pieces.size(), 32, "preview shows the full set")
	check(menu._color_buttons[0].disabled, "color choice disabled in hot-seat")

	menu.set_mode(1)
	eq(GameSettings.mode, GameSettings.Mode.VS_AI, "mode switches to vs computer")
	check(not menu._color_buttons[0].disabled, "color choice enabled vs computer")
	check(not menu._level_buttons[0].disabled, "difficulty enabled vs computer")
	check(menu._rotate_check.disabled, "auto-rotate only applies to hot-seat")

	menu.set_level(2)
	eq(GameSettings.ai_level, 2)
	menu.set_color_choice(1)
	menu.apply_choices()
	eq(GameSettings.human_color, Piece.BLACK, "play as Black")
	menu.set_color_choice(2)
	menu.apply_choices()
	check(GameSettings.human_color == Piece.WHITE or GameSettings.human_color == Piece.BLACK, "random resolves")

	menu.set_preset(MaterialPresets.Preset.MARBLE)
	eq(GameSettings.material_preset, int(MaterialPresets.Preset.MARBLE), "preset selected")
	eq(menu._preview_pieces.size(), 32, "preview rebuilt")
	var first := menu._preview_pieces[0] as Piece3D
	var mi := first.get_child(0) as MeshInstance3D
	eq((mi.get_surface_override_material(0) as StandardMaterial3D).albedo_color,
			MaterialPresets.piece_material(MaterialPresets.Preset.MARBLE, first.piece & 24).albedo_color,
			"preview pieces show the new preset")

	menu.get_parent().remove_child(menu)
	menu.free()
	if backup != "":
		var f := FileAccess.open(GameSettings.SETTINGS_FILE, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	_reset_settings()
