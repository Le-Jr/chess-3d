class_name Effects
extends RefCounted
## One-shot visual effects, all built in code: the debris, dust and shockwave
## of a capture, and the flash of a promotion. Each effect frees itself.

const COLOR_IMPACT := Color(1.0, 0.82, 0.50)
const COLOR_PROMOTION := Color(1.0, 0.86, 0.35)

static var _dust_texture: Texture2D
static var _ring_mesh: Mesh
static var _shard_mesh: Mesh


## A piece breaking under a blow travelling along `dir`: chips of the piece's
## own material fly off, dust puffs up and a ring spreads over the square.
## `at` is the piece's place on the board, in `parent`'s space.
static func shatter(parent: Node3D, at: Vector3, dir: Vector3, material: Material, height: float) -> void:
	var holder := Node3D.new()
	holder.name = "CaptureFx"
	holder.position = at
	parent.add_child(holder)

	var shards := CPUParticles3D.new()
	shards.mesh = _get_shard_mesh()
	shards.material_override = material
	shards.position.y = height * 0.45
	shards.amount = 26
	shards.lifetime = 0.75
	shards.one_shot = true
	shards.explosiveness = 1.0
	shards.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	shards.emission_sphere_radius = 0.16
	shards.direction = (dir + Vector3.UP * 0.9).normalized()
	shards.spread = 62.0
	shards.initial_velocity_min = 1.6
	shards.initial_velocity_max = 4.2
	shards.gravity = Vector3(0.0, -11.0, 0.0)
	shards.angular_velocity_min = -540.0
	shards.angular_velocity_max = 540.0
	shards.angle_max = 360.0
	shards.particle_flag_rotate_y = true
	shards.scale_amount_min = 0.45
	shards.scale_amount_max = 1.35
	shards.scale_amount_curve = _fade_curve(1.0, 0.0)
	shards.emitting = true
	holder.add_child(shards)

	var dust := CPUParticles3D.new()
	var puff := QuadMesh.new()
	puff.size = Vector2(0.42, 0.42)
	dust.mesh = puff
	dust.material_override = _dust_material()
	dust.position.y = 0.12
	dust.amount = 10
	dust.lifetime = 0.6
	dust.one_shot = true
	dust.explosiveness = 0.92
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 0.2
	dust.direction = Vector3.UP
	dust.spread = 80.0
	dust.initial_velocity_min = 0.4
	dust.initial_velocity_max = 1.3
	dust.gravity = Vector3(0.0, 0.5, 0.0)
	dust.damping_min = 1.5
	dust.damping_max = 2.5
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.5
	dust.scale_amount_curve = _fade_curve(0.45, 1.6)
	dust.color_ramp = _alpha_ramp(Color(0.52, 0.47, 0.41, 0.30))
	dust.emitting = true
	holder.add_child(dust)

	_add_ring(holder, COLOR_IMPACT, 0.35, 1.25, 0.34)
	_free_later(holder, 1.2)


## A ring of light and rising sparks on a square (a pawn promoting).
static func flash(parent: Node3D, at: Vector3, color: Color = COLOR_PROMOTION) -> void:
	var holder := Node3D.new()
	holder.name = "FlashFx"
	holder.position = at
	parent.add_child(holder)
	_add_ring(holder, color, 0.3, 1.15, 0.5)

	var sparks := CPUParticles3D.new()
	var spark := QuadMesh.new()
	spark.size = Vector2(0.09, 0.09)
	sparks.mesh = spark
	sparks.material_override = _dust_material(true)
	sparks.position.y = 0.1
	sparks.amount = 28
	sparks.lifetime = 0.9
	sparks.one_shot = true
	sparks.explosiveness = 0.75
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	sparks.emission_ring_axis = Vector3.UP
	sparks.emission_ring_radius = 0.32
	sparks.emission_ring_inner_radius = 0.22
	sparks.emission_ring_height = 0.05
	sparks.direction = Vector3.UP
	sparks.spread = 12.0
	sparks.initial_velocity_min = 1.0
	sparks.initial_velocity_max = 2.4
	sparks.gravity = Vector3(0.0, -0.6, 0.0)
	sparks.scale_amount_curve = _fade_curve(1.0, 0.0)
	sparks.color_ramp = _alpha_ramp(Color(color.r, color.g, color.b, 1.0))
	sparks.emitting = true
	holder.add_child(sparks)
	_free_later(holder, 1.3)


# A glowing ring on the board growing from `from_scale` to `to_scale`.
static func _add_ring(holder: Node3D, color: Color, from_scale: float, to_scale: float, time: float) -> void:
	if _ring_mesh == null:
		var torus := TorusMesh.new()
		torus.inner_radius = 0.40
		torus.outer_radius = 0.48
		torus.rings = 40
		torus.ring_segments = 6
		_ring_mesh = torus
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.2
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.012
	ring.scale = Vector3(from_scale, 0.2, from_scale)
	holder.add_child(ring)
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3(to_scale, 0.2, to_scale), time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, time)
	tween.parallel().tween_property(material, "emission_energy_multiplier", 0.0, time)


static func _free_later(node: Node, seconds: float) -> void:
	var tween := node.create_tween()
	tween.tween_interval(seconds)
	tween.tween_callback(node.queue_free)


static func _get_shard_mesh() -> Mesh:
	if _shard_mesh == null:
		# A small irregular chip: a squashed, low-poly ball.
		var chip := SphereMesh.new()
		chip.radius = 0.058
		chip.height = 0.075
		chip.radial_segments = 5
		chip.rings = 2
		_shard_mesh = chip
	return _shard_mesh


# Soft round billboard for dust (alpha blended) or sparks (additive).
static func _dust_material(additive: bool = false) -> StandardMaterial3D:
	if _dust_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 64
		texture.height = 64
		_dust_texture = texture
	var m := StandardMaterial3D.new()
	m.albedo_texture = _dust_texture
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


static func _fade_curve(from: float, to: float) -> Curve:
	var curve := Curve.new()
	curve.max_value = maxf(maxf(from, to), 1.0)
	curve.add_point(Vector2(0.0, from))
	curve.add_point(Vector2(1.0, to))
	return curve


static func _alpha_ramp(color: Color) -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	return ramp
