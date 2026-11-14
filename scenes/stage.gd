class_name Stage
extends RefCounted
## The shared look of every 3D scene: sky, ambient light, SSAO, glow, a key
## light with soft shadows, a fill light, and the table under the board.

## Adds the environment, lights and table to `parent`.
static func build(parent: Node) -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.16, 0.20, 0.28)
	sky_material.sky_horizon_color = Color(0.46, 0.47, 0.50)
	sky_material.ground_horizon_color = Color(0.30, 0.30, 0.32)
	sky_material.ground_bottom_color = Color(0.07, 0.07, 0.08)
	sky_material.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 0.7
	env.ssao_intensity = 1.8
	env.ssao_power = 1.4
	# Subtle glow: only the emissive square highlights are bright enough to bloom.
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Phones and tablets: drop the screen-space effects and use cheaper shadows.
	var mobile := OS.has_feature("mobile") or OS.has_feature("web")
	if mobile:
		env.ssao_enabled = false
		env.glow_enabled = false

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	parent.add_child(world_env)

	# Key light with soft shadows. The biases are tuned for pieces ~1 unit
	# tall: low enough that shadows start right at the base (no "floating").
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.6
	sun.shadow_blur = 2.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 32.0
	if mobile:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.shadow_blur = 1.0
	parent.add_child(sun)

	# Cool fill from the opposite side so the shadowed faces keep their shape.
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-35.0, 140.0, 0.0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.75, 0.84, 1.0)
	fill.shadow_enabled = false
	parent.add_child(fill)

	# Table under the board.
	var table_mesh := PlaneMesh.new()
	table_mesh.size = Vector2(80.0, 80.0)
	var table_material := StandardMaterial3D.new()
	table_material.albedo_color = Color(0.11, 0.11, 0.12)
	table_material.roughness = 0.85
	var table := MeshInstance3D.new()
	table.name = "Table"
	table.mesh = table_mesh
	table.material_override = table_material
	table.position.y = -Board3D.FRAME_DROP
	parent.add_child(table)
