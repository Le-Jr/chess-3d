class_name PieceSet
extends Resource
## A set of chess piece models plus their materials.
##
## Each piece slot takes a Mesh or a PackedScene (e.g. a node from an imported
## .glb). Empty slots fall back to the procedural mesh, so the default set is
## simply a PieceSet with nothing assigned. Models should stand on y = 0,
## centered on the origin, facing +Z, and fit a 1 x 1 square (use
## `model_scale` / `model_rotation_degrees` to adapt external models).

## Path that selects the built-in medieval set (see `load_from`).
const BUILTIN_MEDIEVAL := "builtin:medieval"

@export var display_name: String = "Procedural"
## Which built-in look fills the empty slots: 0 = classic turned pieces,
## 1 = sculpted medieval figures (ProceduralPieceFactory.STYLE_*).
@export_enum("Classic", "Medieval") var procedural_style: int = 0

@export_group("Models (Mesh or PackedScene; empty = procedural)")
@export var pawn: Resource
@export var knight: Resource
@export var bishop: Resource
@export var rook: Resource
@export var queen: Resource
@export var king: Resource

@export_group("Materials")
## When true, the materials below replace whatever the models came with.
## Turn it off to keep the materials baked into an external model.
@export var apply_materials: bool = true
@export var white_material: Material
@export var black_material: Material
@export var white_accent_material: Material
@export var black_accent_material: Material
@export var felt_material: Material

@export_group("Model adjustment")
@export var model_scale: float = 1.0
@export var model_rotation_degrees: float = 0.0


## The default procedural set with one of the MaterialPresets applied.
static func procedural(preset: int = MaterialPresets.Preset.CLASSIC_WOOD) -> PieceSet:
	var piece_set := PieceSet.new()
	piece_set.display_name = "Procedural"
	piece_set.use_preset(preset)
	return piece_set


## The built-in sculpted medieval set.
static func medieval(preset: int = MaterialPresets.Preset.ANTIQUE_METAL) -> PieceSet:
	var piece_set := PieceSet.new()
	piece_set.display_name = "Medieval"
	piece_set.procedural_style = ProceduralPieceFactory.STYLE_MEDIEVAL
	piece_set.use_preset(preset)
	return piece_set


## Fills the material slots from a MaterialPresets preset.
func use_preset(preset: int) -> void:
	white_material = MaterialPresets.piece_material(preset, Piece.WHITE)
	black_material = MaterialPresets.piece_material(preset, Piece.BLACK)
	white_accent_material = MaterialPresets.accent_material(preset, Piece.WHITE)
	black_accent_material = MaterialPresets.accent_material(preset, Piece.BLACK)
	felt_material = MaterialPresets.felt_material(preset)


## The Mesh / PackedScene assigned to a piece type, or null.
func source_for(type: int) -> Resource:
	match type:
		Piece.PAWN: return pawn
		Piece.KNIGHT: return knight
		Piece.BISHOP: return bishop
		Piece.ROOK: return rook
		Piece.QUEEN: return queen
		Piece.KING: return king
	return null


func set_source(type: int, source: Resource) -> void:
	match type:
		Piece.PAWN: pawn = source
		Piece.KNIGHT: knight = source
		Piece.BISHOP: bishop = source
		Piece.ROOK: rook = source
		Piece.QUEEN: queen = source
		Piece.KING: king = source


## Creates the visual for `piece` (color | type): a Node3D standing on y = 0.
func instantiate(piece: int) -> Node3D:
	var type := Piece.type_of(piece)
	var source := source_for(type)
	var node: Node3D
	if source is PackedScene:
		# Keep the model's own transform intact by adjusting a holder instead.
		var model := (source as PackedScene).instantiate() as Node3D
		if model != null:
			node = Node3D.new()
			node.add_child(model)
	if node == null:
		var mi := MeshInstance3D.new()
		mi.mesh = (source as Mesh) if source is Mesh else ProceduralPieceFactory.build_mesh(
				type, ProceduralPieceFactory.DEFAULT_SEGMENTS, procedural_style)
		node = mi

	node.scale = Vector3.ONE * model_scale
	node.rotation_degrees.y = model_rotation_degrees
	if apply_materials:
		_apply_materials(node, Piece.color_of(piece))
	return node


func _apply_materials(node: Node, color: int) -> void:
	var white := color == Piece.WHITE
	var body: Material = white_material if white else black_material
	var accent: Material = white_accent_material if white else black_accent_material
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			# Surfaces (or their materials) named "felt" / "accent" get the
			# matching material; everything else is the piece body.
			var surface_name := ""
			if mi.mesh is ArrayMesh:
				surface_name = (mi.mesh as ArrayMesh).surface_get_name(i)
			if surface_name == "" and mi.mesh.surface_get_material(i) != null:
				surface_name = mi.mesh.surface_get_material(i).resource_name
			surface_name = surface_name.to_lower()
			var material := body
			if surface_name.begins_with(ProceduralPieceFactory.SURFACE_FELT) and felt_material != null:
				material = felt_material
			elif surface_name.begins_with(ProceduralPieceFactory.SURFACE_ACCENT) and accent != null:
				material = accent
			if material != null:
				mi.set_surface_override_material(i, material)
	for child in node.get_children():
		_apply_materials(child, color)


# ---------------------------------------------------------------- loading ---

## Loads a piece set from a PieceSet resource (.tres / .res) or straight from
## a glTF file (.glb / .gltf). Returns null if it can't be loaded.
static func load_from(path: String) -> PieceSet:
	if path == BUILTIN_MEDIEVAL:
		return medieval()
	var ext := path.get_extension().to_lower()
	if ext == "glb" or ext == "gltf":
		return from_glb(path)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PieceSet


## Builds a PieceSet from a glTF file containing one object per piece, named
## Pawn, Knight, Bishop, Rook, Queen and King (case-insensitive; suffixes such
## as "Pawn.001" are fine). Pieces missing from the file stay procedural.
## Works for imported res:// files and for any .glb on disk (user://, absolute
## paths), which is loaded at runtime.
static func from_glb(path: String) -> PieceSet:
	var scene_root: Node = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			scene_root = packed.instantiate()
	if scene_root == null and FileAccess.file_exists(path):
		var document := GLTFDocument.new()
		var gltf_state := GLTFState.new()
		if document.append_from_file(path, gltf_state) == OK:
			scene_root = document.generate_scene(gltf_state)
	if scene_root == null:
		return null

	var piece_set := PieceSet.new()
	piece_set.display_name = path.get_file().get_basename().capitalize()
	var names := ["", "pawn", "knight", "bishop", "rook", "queen", "king"]
	var found := 0
	for type in range(Piece.PAWN, Piece.KING + 1):
		var node := _find_node_named(scene_root, names[type])
		if node != null:
			piece_set.set_source(type, _to_source(node))
			found += 1
	scene_root.free()
	return piece_set if found > 0 else null


# First Node3D (breadth-first) whose name contains `key`.
static func _find_node_named(root: Node, key: String) -> Node3D:
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node is Node3D and node != root and String(node.name).to_lower().contains(key):
			return node as Node3D
		queue.append_array(node.get_children())
	return null


# A plain mesh when the node is a simple untransformed MeshInstance3D,
# otherwise the node's subtree packed as a scene (moved to the origin).
static func _to_source(node: Node3D) -> Resource:
	if node is MeshInstance3D and node.get_child_count() == 0 \
			and node.transform.basis.is_equal_approx(Basis.IDENTITY):
		return (node as MeshInstance3D).mesh
	var copy := node.duplicate() as Node3D
	copy.position = Vector3.ZERO
	_set_owner_recursive(copy, copy)
	var packed := PackedScene.new()
	packed.pack(copy)
	copy.free()
	return packed


static func _set_owner_recursive(node: Node, new_owner: Node) -> void:
	for child in node.get_children():
		child.owner = new_owner
		_set_owner_recursive(child, new_owner)
