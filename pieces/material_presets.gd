class_name MaterialPresets
extends RefCounted
## Material looks for the pieces and the board. Pick one from the main menu.

enum Preset { CLASSIC_WOOD, MARBLE, STYLIZED_FLAT }

const NAMES := ["Classic wood", "Marble", "Stylized flat"]


static func preset_count() -> int:
	return NAMES.size()


## Material for the pieces of `color` (Piece.WHITE / Piece.BLACK).
static func piece_material(preset: int, color: int) -> StandardMaterial3D:
	var white := color == Piece.WHITE
	var m := StandardMaterial3D.new()
	match preset:
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
		_:
			m.albedo_color = Color(0.07, 0.22, 0.12)
	return m


## Dark detail on the pieces of `color` (e.g. inside the bishop's slit).
static func accent_material(preset: int, color: int) -> StandardMaterial3D:
	var m := piece_material(preset, color)
	m.albedo_color = m.albedo_color.darkened(0.72 if color == Piece.WHITE else 0.55)
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
	return Color(0.86, 0.72, 0.50)
