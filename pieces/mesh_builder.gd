class_name MeshBuilder
extends RefCounted
## Small triangle-soup builder used by ProceduralPieceFactory and Board3D.
##
## Geometry is accumulated as plain (vertex, normal) triangles, which makes it
## easy to transform, merge and clip, and is then pushed through SurfaceTool
## (which welds identical vertices) when committed to an ArrayMesh.
## All `add_*` helpers fix the triangle winding themselves, so callers never
## have to think about clockwise vs. counter-clockwise.

var verts := PackedVector3Array()
var norms := PackedVector3Array()


func is_empty() -> bool:
	return verts.is_empty()


func triangle_count() -> int:
	@warning_ignore("integer_division")
	return verts.size() / 3


# ------------------------------------------------------------- primitives ---

## Triangle with per-vertex (smooth) normals.
func add_tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var face := (c - a).cross(b - a)  # front-face normal for Godot's clockwise winding
	if face.length_squared() < 1e-14:
		return
	if face.dot(na + nb + nc) < 0.0:
		verts.append(a); verts.append(c); verts.append(b)
		norms.append(na); norms.append(nc); norms.append(nb)
	else:
		verts.append(a); verts.append(b); verts.append(c)
		norms.append(na); norms.append(nb); norms.append(nc)


## Flat-shaded triangle facing roughly toward `outward`.
func add_flat_tri(a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	if n.dot(outward) < 0.0:
		n = -n
	add_tri(a, b, c, n, n, n)


## Flat-shaded quad (corners in perimeter order) facing toward `outward`.
func add_flat_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	add_flat_tri(a, b, c, outward)
	add_flat_tri(a, c, d, outward)


## Quad with per-vertex normals (corners in perimeter order).
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	add_tri(a, b, c, na, nb, nc)
	add_tri(a, c, d, na, nc, nd)


# ------------------------------------------------------------------ lathe ---

## Revolves a 2D profile around the Y axis. Each profile point is
## (radius, height), listed from the bottom of the shape to the top along its
## outside. Normals are smoothed along the profile, except at corners sharper
## than `crease_deg`, which stay crisp.
func add_lathe(profile: PackedVector2Array, segments: int, crease_deg: float = 40.0) -> void:
	var count := profile.size()
	if count < 2:
		return

	# Outward normal of each profile segment, in (radius, height) space.
	var seg_n := PackedVector2Array()
	seg_n.resize(count - 1)
	for i in count - 1:
		var d := profile[i + 1] - profile[i]
		seg_n[i] = Vector2(d.y, -d.x).normalized() if d.length_squared() > 1e-12 else Vector2.ZERO

	var crease_cos := cos(deg_to_rad(crease_deg))
	for i in count - 1:
		var n := seg_n[i]
		if n == Vector2.ZERO:
			continue
		var n_start := n
		var n_end := n
		if i > 0 and seg_n[i - 1] != Vector2.ZERO and seg_n[i - 1].dot(n) >= crease_cos:
			n_start = (seg_n[i - 1] + n).normalized()
		if i < count - 2 and seg_n[i + 1] != Vector2.ZERO and seg_n[i + 1].dot(n) >= crease_cos:
			n_end = (seg_n[i + 1] + n).normalized()

		var p0 := profile[i]
		var p1 := profile[i + 1]
		for j in segments:
			var a0 := TAU * j / segments
			var a1 := TAU * (j + 1) / segments
			var c0 := cos(a0)
			var s0 := sin(a0)
			var c1 := cos(a1)
			var s1 := sin(a1)
			add_quad(
				Vector3(p0.x * c0, p0.y, p0.x * s0),
				Vector3(p0.x * c1, p0.y, p0.x * s1),
				Vector3(p1.x * c1, p1.y, p1.x * s1),
				Vector3(p1.x * c0, p1.y, p1.x * s0),
				Vector3(n_start.x * c0, n_start.y, n_start.x * s0),
				Vector3(n_start.x * c1, n_start.y, n_start.x * s1),
				Vector3(n_end.x * c1, n_end.y, n_end.x * s1),
				Vector3(n_end.x * c0, n_end.y, n_end.x * s0))


## UV-sphere-ish ball built as a lathe.
func add_ball(center: Vector3, radius: float, segments: int, rings: int = 6) -> void:
	var profile := PackedVector2Array()
	for i in rings + 1:
		var t := -PI / 2.0 + PI * i / rings
		profile.append(Vector2(maxf(0.0, cos(t)) * radius, sin(t) * radius))
	var ball := MeshBuilder.new()
	ball.add_lathe(profile, segments, 180.0)
	ball.transform(Transform3D(Basis.IDENTITY, center))
	append(ball)


# ------------------------------------------------------------------ boxes ---

## Flat-shaded box. `basis` rotates it around its center.
func add_box(center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var h := size * 0.5
	for axis in 3:
		for sign_dir: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sign_dir
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = 1.0
			var c := n * h
			var du := u * h
			var dv := v * h
			add_flat_quad(
				center + basis * (c - du - dv),
				center + basis * (c + du - dv),
				center + basis * (c + du + dv),
				center + basis * (c - du + dv),
				basis * n)


## A block bent along an arc around the Y axis (e.g. one rook merlon):
## radii r_in..r_out, heights y0..y1, angles a0..a1 (radians).
func add_arc_block(r_in: float, r_out: float, y0: float, y1: float,
		a0: float, a1: float, steps: int = 3) -> void:
	for k in steps:
		var t0 := lerpf(a0, a1, float(k) / steps)
		var t1 := lerpf(a0, a1, float(k + 1) / steps)
		var d0 := Vector3(cos(t0), 0.0, sin(t0))
		var d1 := Vector3(cos(t1), 0.0, sin(t1))
		var up0 := Vector3(0.0, y0, 0.0)
		var up1 := Vector3(0.0, y1, 0.0)
		# Outer and inner walls (smooth around the arc).
		add_quad(d0 * r_out + up0, d1 * r_out + up0, d1 * r_out + up1, d0 * r_out + up1, d0, d1, d1, d0)
		add_quad(d0 * r_in + up0, d1 * r_in + up0, d1 * r_in + up1, d0 * r_in + up1, -d0, -d1, -d1, -d0)
		# Top and bottom.
		add_flat_quad(d0 * r_in + up1, d1 * r_in + up1, d1 * r_out + up1, d0 * r_out + up1, Vector3.UP)
		add_flat_quad(d0 * r_in + up0, d1 * r_in + up0, d1 * r_out + up0, d0 * r_out + up0, Vector3.DOWN)
	# End caps.
	for end: float in [a0, a1]:
		var d := Vector3(cos(end), 0.0, sin(end))
		var tangent := Vector3(-sin(end), 0.0, cos(end)) * (-1.0 if end == a0 else 1.0)
		add_flat_quad(
			d * r_in + Vector3(0.0, y0, 0.0), d * r_out + Vector3(0.0, y0, 0.0),
			d * r_out + Vector3(0.0, y1, 0.0), d * r_in + Vector3(0.0, y1, 0.0), tangent)


# -------------------------------------------------------------- extrusion ---

## Extrudes a 2D outline (in the XY plane) symmetrically along Z, with a
## chamfer of width `bevel` around both faces. Used for the knight's head.
func add_beveled_extrusion(outline: PackedVector2Array, depth: float, bevel: float,
		smooth_deg: float = 50.0) -> void:
	var pts := outline.duplicate()
	if Geometry2D.is_polygon_clockwise(pts):
		pts.reverse()
	var n := pts.size()
	if n < 3:
		return

	# Outward normal of each edge i -> i+1 (outline is counter-clockwise).
	var edge_n := PackedVector2Array()
	edge_n.resize(n)
	for i in n:
		var d := (pts[(i + 1) % n] - pts[i]).normalized()
		edge_n[i] = Vector2(d.y, -d.x)

	# Inset outline for the chamfered faces (miter offset, length-clamped).
	var inset := PackedVector2Array()
	inset.resize(n)
	var smooth_cos := cos(deg_to_rad(smooth_deg))
	var vert_n := PackedVector2Array()  # averaged normal per vertex
	vert_n.resize(n)
	var is_smooth := PackedByteArray()
	is_smooth.resize(n)
	for i in n:
		var n_prev := edge_n[(i - 1 + n) % n]
		var n_next := edge_n[i]
		var avg := (n_prev + n_next).normalized()
		if avg == Vector2.ZERO:
			avg = n_next
		var miter := 1.0 / maxf(0.5, avg.dot(n_next))
		inset[i] = pts[i] - avg * bevel * minf(miter, 2.0)
		vert_n[i] = avg
		is_smooth[i] = 1 if n_prev.dot(n_next) >= smooth_cos else 0

	var half := depth * 0.5
	var wall := half - bevel

	# Front and back faces.
	var tri_idx := Geometry2D.triangulate_polygon(inset)
	for side: float in [1.0, -1.0]:
		var face_n := Vector3(0.0, 0.0, side)
		for t in range(0, tri_idx.size(), 3):
			var a := inset[tri_idx[t]]
			var b := inset[tri_idx[t + 1]]
			var c := inset[tri_idx[t + 2]]
			add_flat_tri(Vector3(a.x, a.y, half * side), Vector3(b.x, b.y, half * side),
					Vector3(c.x, c.y, half * side), face_n)

	for i in n:
		var j := (i + 1) % n
		var en := edge_n[i]
		var ni := vert_n[i] if is_smooth[i] else en
		var nj := vert_n[j] if is_smooth[j] else en
		var ni3 := Vector3(ni.x, ni.y, 0.0)
		var nj3 := Vector3(nj.x, nj.y, 0.0)
		# Side wall.
		add_quad(
			Vector3(pts[i].x, pts[i].y, wall), Vector3(pts[j].x, pts[j].y, wall),
			Vector3(pts[j].x, pts[j].y, -wall), Vector3(pts[i].x, pts[i].y, -wall),
			ni3, nj3, nj3, ni3)
		# Chamfers.
		for side: float in [1.0, -1.0]:
			var bi := (ni3 + Vector3(0.0, 0.0, side)).normalized()
			var bj := (nj3 + Vector3(0.0, 0.0, side)).normalized()
			add_quad(
				Vector3(pts[i].x, pts[i].y, wall * side), Vector3(pts[j].x, pts[j].y, wall * side),
				Vector3(inset[j].x, inset[j].y, half * side), Vector3(inset[i].x, inset[i].y, half * side),
				bi, bj, bj, bi)


# ------------------------------------------------------- whole-mesh edits ---

func transform(xf: Transform3D) -> void:
	var normal_basis := xf.basis.inverse().transposed()
	for i in verts.size():
		verts[i] = xf * verts[i]
		norms[i] = (normal_basis * norms[i]).normalized()


func append(other: MeshBuilder) -> void:
	verts.append_array(other.verts)
	norms.append_array(other.norms)


## Cuts away everything inside the convex region bounded by `planes` (a point
## is inside when it is behind every plane). Triangles crossing the boundary
## are split exactly. The cut is left open - put darker geometry behind it.
func cut_convex(planes: Array[Plane]) -> void:
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	for t in range(0, verts.size(), 3):
		var poly_v: Array[Vector3] = [verts[t], verts[t + 1], verts[t + 2]]
		var poly_n: Array[Vector3] = [norms[t], norms[t + 1], norms[t + 2]]
		for plane in planes:
			if poly_v.size() < 3:
				break
			var front_v: Array[Vector3] = []
			var front_n: Array[Vector3] = []
			var back_v: Array[Vector3] = []
			var back_n: Array[Vector3] = []
			var count := poly_v.size()
			for i in count:
				var a := poly_v[i]
				var b := poly_v[(i + 1) % count]
				var da := plane.distance_to(a)
				var db := plane.distance_to(b)
				if da >= 0.0:
					front_v.append(a); front_n.append(poly_n[i])
				else:
					back_v.append(a); back_n.append(poly_n[i])
				if (da >= 0.0) != (db >= 0.0):
					var w := da / (da - db)
					var p := a.lerp(b, w)
					var pn := poly_n[i].lerp(poly_n[(i + 1) % count], w).normalized()
					front_v.append(p); front_n.append(pn)
					back_v.append(p); back_n.append(pn)
			# Whatever is in front of this plane is outside the region: keep it.
			for k in range(1, front_v.size() - 1):
				out_v.append(front_v[0]); out_v.append(front_v[k]); out_v.append(front_v[k + 1])
				out_n.append(front_n[0]); out_n.append(front_n[k]); out_n.append(front_n[k + 1])
			poly_v = back_v
			poly_n = back_n
		# What is left in poly_v is inside all planes and is discarded.
	verts = out_v
	norms = out_n


# ----------------------------------------------------------------- output ---

## Appends the geometry to `mesh` as a new named surface (via SurfaceTool).
func commit(mesh: ArrayMesh, surface_name: String) -> void:
	if verts.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in verts.size():
		st.set_normal(norms[i])
		st.add_vertex(verts[i])
	st.index()
	st.commit(mesh)
	mesh.surface_set_name(mesh.get_surface_count() - 1, surface_name)
