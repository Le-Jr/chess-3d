extends SceneTree
## Renders a scene for a moment and saves a PNG - a quick way to check the
## look without opening the editor. Needs a real window (not --headless).
##
##   godot --path . -s tools/screenshot.gd -- <scene.tscn> <out.png> [key=value ...]
##
## Optional key=value arguments:
##   moves=e2e4,e7e5      UCI moves to play first (scene needs debug_play_moves)
##   preset=1             MaterialPresets preset index
##   call=method_name     method to call on the scene before capturing
##   select=e2            square to select (scene needs debug_select)
##   fen=...              position to start from (use _ for spaces)
##   frames=40            frames to wait before capturing
##   view=yaw,pitch,dist  camera view (scene needs a camera_rig)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -s tools/screenshot.gd -- <scene.tscn> <out.png> [key=value ...]")
		quit(1)
		return
	var options := {}
	for i in range(2, args.size()):
		var kv := args[i].split("=", true, 1)
		options[kv[0]] = kv[1] if kv.size() > 1 else ""

	if options.has("preset"):
		GameSettings.material_preset = int(options["preset"])

	var packed: PackedScene = load(args[0])
	if packed == null:
		push_error("cannot load scene " + args[0])
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	if options.has("fen") and scene.has_method("new_game"):
		scene.call("new_game", options["fen"].replace("_", " "))
	if options.has("moves") and scene.has_method("debug_play_moves"):
		scene.call("debug_play_moves", options["moves"])
	if options.has("call") and scene.has_method(options["call"]):
		scene.call(options["call"])

	if options.has("select") and scene.has_method("debug_select"):
		scene.call("debug_select", options["select"])
	if options.has("view") and "camera_rig" in scene:
		var v: PackedStringArray = options["view"].split(",")
		scene.camera_rig.set_view(float(v[0]), float(v[1]), float(v[2]))

	for i in int(options.get("frames", "40")):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var err := image.save_png(args[1])
	print("saved %s (%dx%d): %s" % [args[1], image.get_width(), image.get_height(), error_string(err)])
	quit(0 if err == OK else 1)
