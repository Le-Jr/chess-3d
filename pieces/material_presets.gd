class_name MaterialPresets
extends RefCounted
## Material looks for the pieces and the board. Pick one from the main menu.

enum Preset { CLASSIC_WOOD, MARBLE, STYLIZED_FLAT, ANTIQUE_METAL, CARVED_STONE }

const NAMES := ["Classic wood", "Marble", "Stylized flat", "Antique metal", "Carved stone"]

static var _grain_albedo: Texture2D
static var _grain_normal: Texture2D


static func preset_count() -> int:
	return NAMES.size()


## Material for the pieces of `color` (Piece.WHITE / Piece.BLACK).
static func piece_material(preset: int, color: int) -> StandardMaterial3D:
	var white := color == Piece.WHITE
	var m := StandardMaterial3D.new()
	match preset:
		Preset.ANTIQUE_METAL:
			# Aged gold against dark pewter, like a cast metal set.
			m.albedo_color = Color(0.92, 0.70, 0.34) if white else Color(0.36, 0.38, 0.42)
			m.metallic = 0.72
			m.roughness = 0.36
			m.metallic_specular = 0.6
			_add_grain(m, 2.6, 0.55)
		Preset.CARVED_STONE:
			# Ivory resin against charcoal, hand-finished.
			m.albedo_color = Color(0.90, 0.85, 0.74) if white else Color(0.20, 0.19, 0.185)
			m.roughness = 0.62
			m.metallic = 0.0 if white else 0.25
			m.metallic_specular = 0.45
			_add_grain(m, 3.2, 0.9)
		Preset.MARBLE:
			m.albedo_color = Color(0.93, 0.92, 0.89) if white else Color(0.09, 0.09, 0.11)
			m.roughness = 0.16
			m.metallic_specular = 0.6
			m.clearcoat_enabled = true
			m.clearcoat = 0.4
			m.clearcoat_roughness = 0.1
		Preset.STYLIZED_FLAT:
			m.albedo_color = Color(0.96, 0.94, 0.88) if white else Color(0.20, 0.23, 0.32)
			m.roughness = 1.0
			m.metallic_specular = 0.0
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_:
			m.albedo_color = Color(0.85, 0.68, 0.44) if white else Color(0.23, 0.12, 0.065)
			m.roughness = 0.38
			m.metallic_specular = 0.45
			m.clearcoat_enabled = true
			m.clearcoat = 0.25
			m.clearcoat_roughness = 0.25
	return m


# Cast / carved surface grain: a noise pattern projected onto the mesh
# (triplanar, so the meshes need no UVs) that mottles the color like a patina
# and roughens the surface normal.
static func _add_grain(m: StandardMaterial3D, scale: float, bump: float) -> void:
	if _grain_albedo == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.018
		noise.fractal_octaves = 4
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.50, 0.46, 0.42))
		ramp.set_color(1, Color(1.0, 1.0, 1.0))
		var albedo := NoiseTexture2D.new()
		albedo.width = 256
		albedo.height = 256
		albedo.seamless = true
		albedo.noise = noise
		albedo.color_ramp = ramp
		_grain_albedo = albedo
		var bump_noise := FastNoiseLite.new()
		bump_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		bump_noise.frequency = 0.05
		bump_noise.fractal_octaves = 3
		var normal := NoiseTexture2D.new()
		normal.width = 256
		normal.height = 256
		normal.seamless = true
		normal.as_normal_map = true
		normal.bump_strength = 5.0
		normal.noise = bump_noise
		_grain_normal = normal
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.albedo_texture = _grain_albedo
	m.normal_enabled = true
	m.normal_texture = _grain_normal
	m.normal_scale = bump


## The pad under each piece.
static func felt_material(preset: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 1.0
	m.metallic_specular = 0.0
	match preset:
		Preset.MARBLE:
			m.albedo_color = Color(0.25, 0.05, 0.07)
		Preset.STYLIZED_FLAT:
			m.albedo_color = Color(0.12, 0.13, 0.17)
		Preset.ANTIQUE_METAL:
			m.albedo_color = Color(0.22, 0.04, 0.05)
		Preset.CARVED_STONE:
			m.albedo_color = Color(0.10, 0.09, 0.08)
		_:
			m.albedo_color = Color(0.07, 0.22, 0.12)
	return m


## Dark detail on the pieces of `color` (e.g. inside the bishop's slit).
static func accent_material(preset: int, color: int) -> StandardMaterial3D:
	var m := piece_material(preset, color)
	m.albedo_color = m.albedo_color.darkened(0.72 if color == Piece.WHITE else 0.55)
	if preset == Preset.ANTIQUE_METAL or preset == Preset.CARVED_STONE:
		m.albedo_color = m.albedo_color.darkened(0.6)
		m.metallic = 0.0
	m.roughness = 0.9
	m.clearcoat_enabled = false
	return m


static func board_light(preset: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	match preset:
		Preset.MARBLE:
			m.albedo_color = Color(0.88, 0.87, 0.83)
			m.roughness = 0.12
		Preset.STYLIZED_FLAT:
			m.albedo_color = Color(0.87, 0.89, 0.86)
			m.roughness = 1.0
			m.metallic_specular = 0.0
		Preset.ANTIQUE_METAL:
			m.albedo_color = Color(0.78, 0.70, 0.56)
			m.roughness = 0.22
		Preset.CARVED_STONE:
			m.albedo_color = Color(0.90, 0.89, 0.86)
			m.roughness = 0.10
		_:
			m.albedo_color = Color(0.80, 0.63, 0.42)
			m.roughness = 0.45
	return m


static func board_dark(preset: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	match preset:
		Preset.MARBLE:
			m.albedo_color = Color(0.20, 0.27, 0.25)
			m.roughness = 0.12
		Preset.STYLIZED_FLAT:
			m.albedo_color = Color(0.40, 0.56, 0.62)
			m.roughness = 1.0
			m.metallic_specular = 0.0
		Preset.ANTIQUE_METAL:
			m.albedo_color = Color(0.20, 0.10, 0.07)
			m.roughness = 0.22
		Preset.CARVED_STONE:
			m.albedo_color = Color(0.045, 0.045, 0.05)
			m.roughness = 0.10
		_:
			m.albedo_color = Color(0.40, 0.23, 0.12)
			m.roughness = 0.45
	return m


static func board_frame(preset: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	match preset:
		Preset.MARBLE:
			m.albedo_color = Color(0.10, 0.10, 0.11)
			m.roughness = 0.2
		Preset.STYLIZED_FLAT:
			m.albedo_color = Color(0.17, 0.20, 0.27)
			m.roughness = 1.0
			m.metallic_specular = 0.0
		Preset.ANTIQUE_METAL:
			m.albedo_color = Color(0.13, 0.065, 0.04)
			m.roughness = 0.6
			_add_grain(m, 0.5, 0.12)
		Preset.CARVED_STONE:
			m.albedo_color = Color(0.36, 0.27, 0.20)
			m.roughness = 0.85
			_add_grain(m, 0.6, 1.4)
		_:
			m.albedo_color = Color(0.21, 0.11, 0.06)
			m.roughness = 0.5
	return m


## Color of the a-h / 1-8 labels on the frame.
static func label_color(preset: int) -> Color:
	match preset:
		Preset.MARBLE:
			return Color(0.80, 0.78, 0.72)
		Preset.STYLIZED_FLAT:
			return Color(0.80, 0.86, 0.90)
		Preset.ANTIQUE_METAL:
			return Color(0.85, 0.66, 0.34)
		Preset.CARVED_STONE:
			return Color(0.86, 0.80, 0.70)
	return Color(0.86, 0.72, 0.50)
