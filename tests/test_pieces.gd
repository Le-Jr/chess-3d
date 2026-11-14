extends "res://tests/test_case.gd"
## Procedural piece meshes, PieceSet, and the board's coordinate / picking math.

const TYPES := [Piece.PAWN, Piece.KNIGHT, Piece.BISHOP, Piece.ROOK, Piece.QUEEN, Piece.KING]


func test_every_piece_builds_a_sane_mesh() -> void:
	for type: int in TYPES:
		var mesh := ProceduralPieceFactory.build_mesh(type)
		var label := mesh.resource_name
		check(mesh.get_surface_count() >= 2, label + " has body and felt surfaces")
		eq(mesh.surface_get_name(0), ProceduralPieceFactory.SURFACE_BODY, label + " surface 0")
		eq(mesh.surface_get_name(1), ProceduralPieceFactory.SURFACE_FELT, label + " surface 1")

		var aabb := mesh.get_aabb()
		check(absf(aabb.position.y) < 0.001, label + " stands on y = 0")
		check(absf(aabb.end.y - PieceProfiles.height(type)) < 0.02,
				"%s height %.3f matches PieceProfiles.height %.3f" % [label, aabb.end.y, PieceProfiles.height(type)])
		check(aabb.size.x <= 0.75 and aabb.size.z <= 0.75, label + " fits inside a square")
		check(absf(aabb.get_center().z) < 0.01, label + " is centered front-to-back")

		var triangles := 0
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			@warning_ignore("integer_division")
			triangles += indices.size() / 3
			var bad_normals := 0
			for n in normals:
				if absf(n.length() - 1.0) > 0.01:
					bad_normals += 1
			eq(bad_normals, 0, "%s surface %d normals are unit length" % [label, s])
		check(triangles > 100 and triangles < 6000, "%s triangle budget (%d)" % [label, triangles])


func test_bishop_has_slit_accent() -> void:
	var mesh := ProceduralPieceFactory.build_mesh(Piece.BISHOP)
	eq(mesh.get_surface_count(), 3, "bishop has an accent surface")
	eq(mesh.surface_get_name(2), ProceduralPieceFactory.SURFACE_ACCENT)


func test_meshes_are_cached() -> void:
	check(ProceduralPieceFactory.build_mesh(Piece.ROOK) == ProceduralPieceFactory.build_mesh(Piece.ROOK),
			"same mesh instance returned")


func test_lathe_faces_outward() -> void:
	# For a closed surface, sum(face normal . vertex position) is positive
	# when the triangles face outward (clockwise winding in Godot).
	var mb := MeshBuilder.new()
	mb.add_lathe(PieceProfiles.pawn(), 16)
	var outward := 0
	var agree := 0
	for t in range(0, mb.verts.size(), 3):
		var a := mb.verts[t]
		var b := mb.verts[t + 1]
		var c := mb.verts[t + 2]
		var face := (c - a).cross(b - a)
		var radial := Vector3(a.x + b.x + c.x, 0.0, a.z + b.z + c.z)
		if absf(face.y) < face.length() * 0.9 and face.dot(radial) > 0.0:
			outward += 1
		if face.dot(mb.norms[t] + mb.norms[t + 1] + mb.norms[t + 2]) > 0.0:
			agree += 1
	eq(agree, mb.triangle_count(), "winding agrees with the vertex normals")
	check(outward > mb.triangle_count() / 2, "side faces point away from the axis")


func test_cut_convex_removes_geometry() -> void:
	var mb := MeshBuilder.new()
	mb.add_box(Vector3.ZERO, Vector3.ONE)
	eq(mb.triangle_count(), 12, "box has 12 triangles")
	# Remove everything with x > 0.25: the +X face disappears, 4 faces are trimmed.
	var planes: Array[Plane] = [Plane(Vector3.LEFT, -0.25)]
	mb.cut_convex(planes)
	var max_x := -INF
	for v in mb.verts:
		max_x = maxf(max_x, v.x)
	check(absf(max_x - 0.25) < 0.0001, "nothing left beyond the cut plane (max x = %.3f)" % max_x)
	check(mb.triangle_count() >= 10, "the rest of the box survives")


func test_piece_set_instantiates_all_pieces() -> void:
	var piece_set := PieceSet.procedural()
	for color: int in [Piece.WHITE, Piece.BLACK]:
		for type: int in TYPES:
			var node := piece_set.instantiate(color | type)
			check(node is MeshInstance3D, "procedural piece is a MeshInstance3D")
			var mi := node as MeshInstance3D
			var expected: Material = piece_set.white_material if color == Piece.WHITE else piece_set.black_material
			check(mi.get_surface_override_material(0) == expected, "body uses the color's material")
			check(mi.get_surface_override_material(1) == piece_set.felt_material, "felt material applied")
			node.free()


func test_piece_set_uses_custom_mesh() -> void:
	var piece_set := PieceSet.procedural()
	var box := BoxMesh.new()
	piece_set.set_source(Piece.ROOK, box)
	var node := piece_set.instantiate(Piece.WHITE | Piece.ROOK) as MeshInstance3D
	check(node.mesh == box, "custom mesh is used for the rook")
	node.free()
	var pawn := piece_set.instantiate(Piece.WHITE | Piece.PAWN) as MeshInstance3D
	check(pawn.mesh == ProceduralPieceFactory.build_mesh(Piece.PAWN), "other slots stay procedural")
	pawn.free()


func test_square_mapping_round_trip() -> void:
	for rank in 8:
		for file in 8:
			var s := Board.sq(file, rank)
			eq(Board3D.local_to_square(Board3D.square_to_local(s)), s, Board.sq_name(s))
	eq(Board3D.square_to_local(Board.A1), Vector3(-3.5, 0.0, 3.5), "a1 is near-left for White")
	eq(Board3D.square_to_local(Board.H8), Vector3(3.5, 0.0, -3.5), "h8 is far-right")
	eq(Board3D.local_to_square(Vector3(4.2, 0.0, 0.0)), -1, "off the board")
	eq(Board3D.local_to_square(Vector3(0.0, 0.0, -4.01)), -1, "off the board")


func test_picking() -> void:
	var view := Board3D.new()
	var board := Board.new()
	var e4 := Board3D.square_to_local(Board.sq_from_name("e4"))
	eq(view.pick_square_ray(e4 + Vector3(0.1, 10.0, 0.1), Vector3.DOWN, board),
			Board.sq_from_name("e4"), "straight down onto an empty square")
	eq(view.pick_square_ray(Vector3(10.0, 10.0, 0.0), Vector3.DOWN, board), -1, "miss")
	eq(view.pick_square_ray(Vector3(0.0, 5.0, 0.0), Vector3.UP, board), -1, "ray pointing away")

	# A slanted ray that passes through the white king's head but would land
	# on the board two squares behind it must still pick the king.
	var e1 := Board3D.square_to_local(Board.E1)
	var head := e1 + Vector3(0.0, 1.1, 0.0)
	var dir := Vector3(0.0, -0.55, -1.0).normalized()
	var origin := head - dir * 8.0
	eq(view.pick_square_ray(origin, dir, board), Board.E1, "ray through the king's head picks e1")
	check(view.pick_square_ray(origin, dir, null) != Board.E1, "without pieces the same ray lands elsewhere")
	view.free()
