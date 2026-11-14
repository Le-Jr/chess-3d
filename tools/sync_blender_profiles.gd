extends SceneTree
## Copies the numbers from pieces/piece_profiles.gd into the generated data
## block of tools/blender_export_pieces.py. Run it after tweaking a profile:
##
##   godot --headless --path . -s tools/sync_blender_profiles.gd

const ProfileData := preload("res://tools/profile_data.gd")


func _initialize() -> void:
	if ProfileData.write_into_blender_script():
		print("Updated the profile data in %s" % ProfileData.BLENDER_SCRIPT)
		quit(0)
	else:
		push_error("Could not find the PROFILE DATA markers in %s" % ProfileData.BLENDER_SCRIPT)
		quit(1)
