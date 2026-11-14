extends SceneTree
## Exports the procedural chess set to a .glb with one object per piece
## (Pawn, Knight, Bishop, Rook, Queen, King), ready to refine in Blender or
## any other DCC tool and to load back as a PieceSet.
##
##   godot --headless --path . -s tools/export_pieces_glb.gd -- [out.glb] [segments]
##
## Defaults: piece_sets/procedural_export.glb, 32 segments.

const PieceExporter := preload("res://tools/piece_exporter.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "res://piece_sets/procedural_export.glb"
	var segments := int(args[1]) if args.size() > 1 else 32
	var err := PieceExporter.export_glb(out, segments)
	if err == OK:
		print("Exported the procedural set to %s" % ProjectSettings.globalize_path(out))
	else:
		push_error("Export failed: %s" % error_string(err))
	quit(0 if err == OK else 1)
