extends RefCounted
## Writes the procedural chess set to a glTF binary (.glb): one object per
## piece, laid out in a row, with materials named "body", "felt" and
## "accent" so the surfaces keep their roles when the file is loaded back
## through PieceSet.from_glb().

const NAMES := ["", "Pawn", "Knight", "Bishop", "Rook", "Queen", "King"]


static func export_glb(path: String, segments: int = 32) -> Error:
	var root := Node3D.new()
	root.name = "Pieces"
	var materials := {}
	for surface_name: String in [ProceduralPieceFactory.SURFACE_BODY,
			ProceduralPieceFactory.SURFACE_FELT, ProceduralPieceFactory.SURFACE_ACCENT]:
		var m := StandardMaterial3D.new()
		m.resource_name = surface_name
		materials[surface_name] = m
	materials[ProceduralPieceFactory.SURFACE_BODY].albedo_color = Color(0.85, 0.80, 0.70)
	materials[ProceduralPieceFactory.SURFACE_FELT].albedo_color = Color(0.07, 0.22, 0.12)
	materials[ProceduralPieceFactory.SURFACE_ACCENT].albedo_color = Color(0.10, 0.09, 0.08)

	for type in range(Piece.PAWN, Piece.KING + 1):
		# Duplicate so the cached mesh shared with the game is left alone.
		var mesh: ArrayMesh = ProceduralPieceFactory.build_mesh(type, segments).duplicate()
		for s in mesh.get_surface_count():
			mesh.surface_set_material(s, materials[mesh.surface_get_name(s)])
		var mi := MeshInstance3D.new()
		mi.name = NAMES[type]
		mi.mesh = mesh
		mi.position = Vector3((type - 3.5) * 1.0, 0.0, 0.0)
		root.add_child(mi)
		mi.owner = root

	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	var document := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var err := document.append_from_scene(root, gltf_state)
	if err == OK:
		err = document.write_to_filesystem(gltf_state, path)
	root.free()
	return err
