extends Node3D
var FILE := ProjectSettings.globalize_path("res://../models/frog_rig.glb")
const N := 24
var mode := "custom"
func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls): return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r: return r
	return null
const FACE := preload("res://frog.gdshader")
func _matte(n: Node, mats: Array):
	# 원래 재질(PBR)은 번들거려서 무광 셰이더로 바꾼다. 눈꺼풀도 이 셰이더가 그린다.
	if n is MeshInstance3D:
		for s in n.mesh.get_surface_count():
			var src: BaseMaterial3D = n.mesh.surface_get_material(s)
			var m := ShaderMaterial.new(); m.shader = FACE
			m.set_shader_parameter("albedo_tex", src.albedo_texture)
			m.set_shader_parameter("albedo_col", src.albedo_color)
			m.set_shader_parameter("debug", OS.get_environment("EYEDBG") != "")
			n.set_surface_override_material(s, m); mats.append(m)
	for c in n.get_children(): _matte(c, mats)
# 머리 좌표: 머리 뼈 원점 + 기본 자세 메시 축. 뼈 기준으로 고정된 변환 L 을 처음에 구해 둔다.
func _head_l(sk: Skeleton3D, mi: MeshInstance3D) -> Transform3D:
	var hr: Transform3D = sk.global_transform * sk.get_bone_global_rest(sk.find_bone("Head"))
	var f0 := Transform3D(mi.global_transform.basis.orthonormalized(), hr.origin)  # mi 는 0.01 배율이라 축 방향만
	return hr.affine_inverse() * f0
func _face(sk: Skeleton3D, l: Transform3D, mats: Array, bl: float, mo := 0.0):
	var h: Transform3D = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")) * l
	var inv := Projection(h.affine_inverse())
	for m in mats:
		m.set_shader_parameter("head_inv", inv); m.set_shader_parameter("blink", bl); m.set_shader_parameter("mouth", mo)
func _rot(sk: Skeleton3D, name: String, axis: Vector3, deg: float, extra := Quaternion.IDENTITY):
	var b := sk.find_bone(name)
	var g := sk.get_bone_global_rest(b).basis.orthonormalized().get_rotation_quaternion()
	var r := Quaternion(axis.normalized(), deg_to_rad(deg)) * extra
	sk.set_bone_pose_rotation(b, sk.get_bone_rest(b).basis.orthonormalized().get_rotation_quaternion() * (g.inverse() * r * g))

# 리깅은 로브 전체를 다리 뼈(허벅지·정강이)에 거의 1.0으로 묶어 놓았고, 고관절(0.336m) 위 허리까지도 0.7~0.9다.
# 그대로 걸으면 로브 자락이 다리에 끌려 통째로 들린다. 불러올 때 다시 정한다(모델 파일은 그대로):
#  - LEG_FULL 아래는 다리를 따르고 LEG_NONE 위는 골반(Hips)으로 옮긴다.
#  - 다리 뼈 선분(허벅지·정강이·발)에서 _leg_r(높이) 넘게 떨어진 점(로브)은 다리를 ROBE_FOLLOW 만큼만 따른다.
#    잰 값(measure.gd): 허벅지 피부 5cm 안·로브 6cm 밖, 종아리(0.12~0.20m) 피부 6cm 안·로브 7cm 밖,
#    신발(0.12m 아래) 9cm 안·로브 단 11cm 밖. 초록 피부는 거리와 상관없이 다리를 그대로 따른다.
#  - 리깅은 종아리·신발 목(0.08~0.24m) 점 상당수를 반대쪽 다리 뼈에도 묶어 놓아서, 다리를 앞으로 내밀면
#    신발 뒤축·종아리가 뒤로 늘어났다. 다리 살로 분류된 점은 자기 다리 사슬 밖(반대쪽 다리·골반 등)의 무게를
#    가장 가까운 자기 다리 뼈로 옮긴다.
# 옆구리 유리병 범위(메시 좌표 m, measure.gd: 왼쪽 허리(-x) 밝은 병 점 + 여유 1cm, 몸 쪽 병은 -0.06 까지 걸침)
const POTION_MIN := Vector3(-0.17, 0.285, 0.015)
const POTION_MAX := Vector3(-0.06, 0.38, 0.12)
const LEG_FULL := 0.285
const LEG_NONE := 0.325
func _leg_r(y: float) -> float:
	return lerpf(lerpf(0.10, 0.066, smoothstep(0.10, 0.13, y)), 0.058, smoothstep(0.18, 0.22, y))
const ROBE_FOLLOW := 0.45
func _seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a; var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)
func _fix_legs(n: Node, sk: Skeleton3D):
	var to_mesh := Transform3D()
	var nd: Node = sk
	while nd != n:
		to_mesh = (nd as Node3D).transform * to_mesh; nd = nd.get_parent()
	var segs := []
	for sd in ["Left", "Right"]:
		var o := []
		for b in [sd + "UpLeg", sd + "Leg", sd + "Foot", sd + "ToeBase"]: o.append(to_mesh * sk.get_bone_global_rest(sk.find_bone(b)).origin)
		segs.append([o[0], o[1]]); segs.append([o[1], o[2]]); segs.append([o[2], o[3]])
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null: continue
		var bind := {}
		for b in mi.skin.get_bind_count(): bind[sk.get_bone_name(mi.skin.get_bind_bone(b))] = b
		var hips: int = bind["Hips"]
		var legs := [int(bind["LeftUpLeg"]), int(bind["RightUpLeg"]), int(bind["LeftLeg"]), int(bind["RightLeg"])]
		var chain := []  # chain[side] = [UpLeg, Leg, Foot, ToeBase] bind 번호, segs 순서와 같음
		for sd in ["Left", "Right"]:
			chain.append([int(bind[sd + "UpLeg"]), int(bind[sd + "Leg"]), int(bind[sd + "Foot"]), int(bind[sd + "ToeBase"])])
		var out := ArrayMesh.new()
		for sf in mi.mesh.get_surface_count():
			var a: Array = mi.mesh.surface_get_arrays(sf)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var bo = a[Mesh.ARRAY_BONES]
			var we: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			var per: int = we.size() / v.size()
			var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
			var img: Image = (mi.mesh.surface_get_material(sf) as BaseMaterial3D).albedo_texture.get_image()
			if img.is_compressed(): img.decompress()
			var isz := img.get_size()
			var dbgc := PackedColorArray(); dbgc.resize(v.size())
			for k in v.size():
				var keep := 1.0 - smoothstep(LEG_FULL, LEG_NONE, v[k].y)
				var dl := 1e9; var near := 0
				for si in segs.size():
					var d := _seg(v[k], segs[si][0], segs[si][1])
					if d < dl: dl = d; near = si
				var col := img.get_pixelv(Vector2i(uv[k] * Vector2(isz)).clamp(Vector2i.ZERO, isz - Vector2i.ONE))
				var skin := col.g > col.r * 1.15 and col.g > col.b * 1.15
				var legness := 1.0 if skin else 1.0 - smoothstep(_leg_r(v[k].y), _leg_r(v[k].y) + 0.012, dl)
				keep *= lerpf(ROBE_FOLLOW, 1.0, legness)
				dbgc[k] = Color(1.0 - legness, legness, 0.0) if v[k].y < LEG_NONE else Color(0.3, 0.3, 0.9)
				if legness > 0.0 and v[k].y < LEG_FULL:
					var own: Array = chain[near / 3]
					var tgt: int = own[near % 3]
					var take := 0.0; var tslot := -1
					for c in per:
						var i := k * per + c
						if not (int(bo[i]) in own) and we[i] > 0.0:
							take += we[i] * legness; we[i] *= 1.0 - legness
						elif int(bo[i]) == tgt: tslot = i
					if take > 0.0:
						if tslot < 0:
							var lo := k * per
							for c in per:
								if we[k * per + c] < we[lo]: lo = k * per + c
							take += we[lo]; bo[lo] = tgt; we[lo] = 0.0; tslot = lo
						we[tslot] += take
				if keep >= 1.0: continue
				var moved := 0.0; var hip_slot := -1
				for c in per:
					var i := k * per + c
					if int(bo[i]) in legs:
						moved += we[i] * (1.0 - keep); we[i] *= keep
					elif int(bo[i]) == hips and we[i] > 0.0:
						hip_slot = i
				if moved <= 0.0: continue
				if hip_slot < 0:
					var lo := k * per
					for c in per:
						if we[k * per + c] < we[lo]: lo = k * per + c
					moved += we[lo]; bo[lo] = hips; we[lo] = 0.0; hip_slot = lo
				we[hip_slot] += moved
			a[Mesh.ARRAY_BONES] = bo; a[Mesh.ARRAY_WEIGHTS] = we
			# 정점 색 파랑 = 0 은 옆구리 유리병 자리(셰이더가 물약 색을 바꿀 때 씀). 로브에도 같은 보라가 있어 자리로 고른다.
			var vc := PackedColorArray(); vc.resize(v.size())
			for k in v.size():
				var p := v[k]
				vc[k] = Color(1, 1, 0) if (p.x > POTION_MIN.x and p.y > POTION_MIN.y and p.z > POTION_MIN.z and p.x < POTION_MAX.x and p.y < POTION_MAX.y and p.z < POTION_MAX.z) else Color(1, 1, 1)
			a[Mesh.ARRAY_COLOR] = vc
			_prop_split(a, img, hips, "book", 0.0)
			_prop_split(a, img, hips, "vial", 0.5)
			if mode == "dbg": a[Mesh.ARRAY_COLOR] = dbgc
			out.add_surface_from_arrays(mi.mesh.surface_get_primitive_type(sf), a)
			var mat: Material = mi.mesh.surface_get_material(sf)
			if mode == "dbg":
				var dm := StandardMaterial3D.new(); dm.vertex_color_use_as_albedo = true; dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat = dm
			out.surface_set_material(sf, mat)
		mi.mesh = out
		if mode == "dbg":
			for c in mi.get_surface_override_material_count(): mi.set_surface_override_material(c, null)
	print("legs fixed")
# 들어 보이는 소품(PROPS): 왼쪽 허리 책(⑩, 왼손)·오른쪽 앞 유리병(⑪, 오른손).
# 소품 점은 정점 색 빨강(책 0, 병 0.5)으로 표시하고 골반(Hips)에만 1.0 으로 묶는다. 셰이더가 book_m·vial_m 으로 손에 옮긴다.
# 소품이 붙어 있던 로브 자리(텍스처에 그늘·끈이 칠해짐)는 정점 색 초록(책 0, 병 0.5)·알파(기본 자세 높이 0.30~0.45 m)로
# 표시해 들고 있는 동안 허리띠 높이는 갈색, 나머지는 로브 보라로 덮는다.
# 메시가 로브와 이어져 있어서, 소품 점과 로브 점이 섞인 삼각형은 소품 점을 복사해 로브 쪽에 남기고 이웃 로브 점 평균으로 모은다.
# 책(캐릭터 왼쪽 = +x, 정면에서 화면 오른쪽, mb2.gd 로 잼): 로브 옆면은 x 0.14 까지, 책은 x 0.135~0.18.
# 범위 안에서 로브 보라(색상 0.60~0.79)가 아닌 점. 책 표지 그늘은 색상 0.80~0.90.
const BOOK_MIN := Vector3(0.112, 0.27, -0.07)
const BOOK_MAX := Vector3(0.19, 0.42, 0.115)
const BOOK_UNDER_X := 0.09
# 앞 유리병(캐릭터 오른쪽 -x, 정면에서 화면 왼쪽, mp2.gd 로 밝은 병 점을 두 덩이로 나눔): 앞·안쪽 병 공 가운데 VIAL_C,
# 뒤·바깥 병 VIAL_C2, 반지름 약 2.7~3cm. 앞 병만 든다. 병 점 = VIAL_R 안이고 뒤 병보다 VIAL_C 에 가까운 점 + 목·코르크
# (VIAL_NECK_R 원기둥, 높이 VIAL_NECK_Y). 두 병이 메시로 붙어 있어서 떼면 서로 맞닿은 쪽이 뚫려 있다 →
# 두 병 안에 조금 작은 공(VIAL_FILL)을 하나씩 넣어 메운다. 원래 병 겉면이 있는 방향은 겉면보다 안쪽(0.85배)까지만 키워 숨기고,
# 뚫린 쪽에서만 보인다. 공은 텍스처 대신 셰이더가 높이별 병 그라데이션(mp3.gd 로 잼)으로 칠한다(텍스처 UV 를 빌리면 섬 경계에서 줄무늬가 생겼음).
const VIAL_C := Vector3(-0.096, 0.328, 0.090)
const VIAL_C2 := Vector3(-0.131, 0.334, 0.055)
const VIAL_R := 0.036
const VIAL_NECK_R := 0.016
const VIAL_NECK_Y := Vector2(0.345, 0.40)
const VIAL_PATCH := Vector3(-0.097, 0.328, 0.071)   # 앞 병 뒤 로브 구멍을 막는 판 가운데(m)
const VIAL_PATCH_R := Vector2(0.028, 0.034)
const VIAL_FILL := Vector2(0.026, 0.027)   # 메우는 공 반지름(앞 병, 뒤 병). 겉면이 있는 방향은 더 작아짐
var prop_c := {}      # 소품 가운데(메시 좌표 m)
var prop_hb := -1     # 골반 bind 번호
func _robe(col: Color) -> bool:
	return col.h > 0.6 and col.h < 0.79 and col.s > 0.12
func _sel_book(p: Vector3, col: Color) -> bool:
	if p.x < BOOK_MIN.x or p.y < BOOK_MIN.y or p.z < BOOK_MIN.z or p.x > BOOK_MAX.x or p.y > BOOK_MAX.y or p.z > BOOK_MAX.z: return false
	return not _robe(col)
func _under_book(p: Vector3) -> bool:
	return p.x >= BOOK_UNDER_X and p.x < BOOK_MIN.x and p.y >= BOOK_MIN.y and p.y <= BOOK_MAX.y and p.z >= BOOK_MIN.z and p.z <= BOOK_MAX.z
func _sel_vial(p: Vector3, col: Color) -> bool:
	if _robe(col) and col.v < 0.45: return false
	if p.distance_to(VIAL_C) >= p.distance_to(VIAL_C2): return false
	var ball := p.distance_to(VIAL_C) < VIAL_R
	var neck := Vector2(p.x - VIAL_C.x, p.z - VIAL_C.z).length() < VIAL_NECK_R and p.y > VIAL_NECK_Y.x and p.y < VIAL_NECK_Y.y
	return ball or neck
func _under_vial(p: Vector3) -> bool:
	return p.distance_to(VIAL_C) < VIAL_R + 0.022 and p.z < VIAL_C.z + 0.01 and p.distance_to(VIAL_C) < p.distance_to(VIAL_C2)
## 로브 구멍을 막는 납작한 타원 판(앞을 봄). 골반에만 묶인다.
func _add_patch(a: Array, c: Vector3, rr: Vector2, hips: int):
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var tan = a[Mesh.ARRAY_TANGENT]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var vc: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var bo = a[Mesh.ARRAY_BONES]
	var we: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var per: int = we.size() / v.size()
	var segs := 24
	var base := v.size()
	for i in segs + 1:
		var p := c if i == 0 else c + Vector3(cos(TAU * (i - 1) / segs) * rr.x, sin(TAU * (i - 1) / segs) * rr.y, 0.0)
		v.append(p); nrm.append(Vector3.BACK); uv.append(Vector2(-2.0, 0.0))
		vc.append(Color(1.0, 1.0, 1.0, clampf((p.y - 0.30) / 0.15, 0.0, 1.0)))
		if tan != null:
			tan.append(1.0); tan.append(0.0); tan.append(0.0); tan.append(1.0)
		for k in per:
			bo.append(hips if k == 0 else 0); we.append(1.0 if k == 0 else 0.0)
	for i in segs:
		idx.append(base); idx.append(base + 1 + i); idx.append(base + 1 + (i + 1) % segs)
	a[Mesh.ARRAY_VERTEX] = v; a[Mesh.ARRAY_NORMAL] = nrm; a[Mesh.ARRAY_TEX_UV] = uv; a[Mesh.ARRAY_COLOR] = vc
	if tan != null: a[Mesh.ARRAY_TANGENT] = tan
	a[Mesh.ARRAY_BONES] = bo; a[Mesh.ARRAY_WEIGHTS] = we; a[Mesh.ARRAY_INDEX] = idx
## 병 안을 메우는 공을 덧붙인다. 점 색 col(빨강이 소품 표시), UV 는 같은 병 점(src) 중 방향이 가장 가까운 것.
func _add_ball(a: Array, c: Vector3, r: float, col: Color, src: PackedVector3Array, hips: int):
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var tan = a[Mesh.ARRAY_TANGENT]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var vc: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var bo = a[Mesh.ARRAY_BONES]
	var we: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var per: int = we.size() / v.size()
	var rings := 12; var segs := 18
	var base := v.size()
	for i in rings + 1:
		var th := PI * float(i) / rings
		for j2 in segs + 1:
			var ph := TAU * float(j2) / segs
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			# 이 방향 가까이(25° 안)에 병 겉면 점이 있으면 그보다 조금 안쪽까지만(겉면 밖으로 튀어나오지 않게), 없으면(뚫린 쪽) r.
			var rr := r
			for q in src.size():
				var o := src[q] - c
				if o.normalized().dot(d) > 0.9: rr = minf(rr, o.length() * 0.85)
			v.append(c + d * rr); nrm.append(d)
			uv.append(Vector2(-1.0, d.y))   # UV x -1 = 메우는 공 표시, y = 병 가운데 기준 높이(-1~1): 셰이더가 병 그라데이션으로 칠함
			vc.append(Color(col.r, col.g, col.b, clampf((c.y + d.y * rr - 0.30) / 0.15, 0.0, 1.0)))
			if tan != null:
				var tg := Vector3.UP.cross(d)
				if tg.length() < 0.01: tg = Vector3.RIGHT
				tg = tg.normalized()
				tan.append(tg.x); tan.append(tg.y); tan.append(tg.z); tan.append(1.0)
			for k in per:
				bo.append(hips if k == 0 else 0); we.append(1.0 if k == 0 else 0.0)
	for i in rings:
		for j2 in segs:
			var a0 := base + i * (segs + 1) + j2
			var b0 := a0 + segs + 1
			idx.append(a0); idx.append(b0); idx.append(a0 + 1)
			idx.append(a0 + 1); idx.append(b0); idx.append(b0 + 1)
	a[Mesh.ARRAY_VERTEX] = v; a[Mesh.ARRAY_NORMAL] = nrm; a[Mesh.ARRAY_TEX_UV] = uv; a[Mesh.ARRAY_COLOR] = vc
	if tan != null: a[Mesh.ARRAY_TANGENT] = tan
	a[Mesh.ARRAY_BONES] = bo; a[Mesh.ARRAY_WEIGHTS] = we; a[Mesh.ARRAY_INDEX] = idx
## 소품 하나를 떼어 낸다. tag: 정점 색 빨강·초록 값(책 0, 병 0.5).
func _prop_split(a: Array, img: Image, hips: int, name: String, tag: float):
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var tan = a[Mesh.ARRAY_TANGENT]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var vc: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var bo = a[Mesh.ARRAY_BONES]
	var we: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var per: int = we.size() / v.size()
	var isz := img.get_size()
	var n0 := v.size()
	var mine := PackedByteArray(); mine.resize(n0)
	# 알파 = 기본 자세 높이(0.30~0.45 m → 0~1). 덮는 자리 경계 삼각형에서도 높이가 맞게 보간되도록 모든 점에 넣는다.
	for k in n0: vc[k].a = clampf((v[k].y - 0.30) / 0.15, 0.0, 1.0)
	var mn := Vector3(9, 9, 9); var mx := -mn
	for k in n0:
		var p := v[k]
		if vc[k].r < 0.9: continue   # 이미 다른 소품
		var col := img.get_pixelv(Vector2i(uv[k] * Vector2(isz)).clamp(Vector2i.ZERO, isz - Vector2i.ONE))
		var sel: bool = _sel_book(p, col) if name == "book" else _sel_vial(p, col)
		if not sel: continue
		mine[k] = 1
		vc[k] = Color(tag, 1.0, vc[k].b)
		mn = mn.min(p); mx = mx.max(p)
		for c in per:
			bo[k * per + c] = hips if c == 0 else 0
			we[k * per + c] = 1.0 if c == 0 else 0.0
	# 소품이 붙어 있던 로브 자리: 진한 점(그늘, 색상 0.79 위·0.04 아래, 또는 아주 어두움). 허리띠 갈색(색상 0.04~0.16)은 그대로.
	for k in n0:
		var p := v[k]
		if mine[k] == 1 or vc[k].r < 0.9: continue
		if not (_under_book(p) if name == "book" else _under_vial(p)): continue
		var col := img.get_pixelv(Vector2i(uv[k] * Vector2(isz)).clamp(Vector2i.ZERO, isz - Vector2i.ONE))
		var belt := col.h > 0.04 and col.h < 0.16 and col.v > 0.18
		var dark := not belt and (col.h > 0.79 or col.h < 0.04 or col.v < 0.2) or (belt and col.v < 0.3)
		if dark or (name == "vial" and not belt):   # 병 뒤 로브는 구멍·그늘투성이라 통째로 덮는다
			vc[k] = Color(vc[k].r, tag, vc[k].b, clampf((p.y - 0.30) / 0.15, 0.0, 1.0))
	prop_c[name] = VIAL_C if name == "vial" else (mn + mx) * 0.5
	prop_hb = hips
	var copy := {}
	var acc := {}
	var mixed := 0
	for t in range(0, idx.size(), 3):
		var i0 := idx[t]; var i1 := idx[t + 1]; var i2 := idx[t + 2]
		var sb := (mine[i0] if i0 < n0 else 0) + (mine[i1] if i1 < n0 else 0) + (mine[i2] if i2 < n0 else 0)
		if sb == 0 or sb == 3: continue
		mixed += 1
		for c in 3:
			var k := idx[t + c]
			if k >= n0 or mine[k] == 0: continue
			if not copy.has(k):
				copy[k] = v.size()
				v.append(v[k]); nrm.append(nrm[k]); uv.append(uv[k])
				vc.append(Color(1.0, tag, vc[k].b, clampf((v[k].y - 0.30) / 0.15, 0.0, 1.0)))
				if tan != null:
					for q in 4: tan.append(tan[k * 4 + q])
				for c2 in per:
					bo.append(bo[k * per + c2]); we.append(we[k * per + c2])
			idx[t + c] = copy[k]
			# 복사한 점은 그 삼각형의 로브 점 쪽으로 모은다(나중에 평균). 소품을 들면 허리에 조각이 남지 않게.
			var ci: int = copy[k]
			if not acc.has(ci): acc[ci] = [Vector3.ZERO, 0]
			for c2 in 3:
				if idx[t + c2] < n0 and mine[idx[t + c2]] == 0:
					acc[ci][0] += v[idx[t + c2]]; acc[ci][1] += 1
	for ci in acc:
		if acc[ci][1] > 0: v[ci] = acc[ci][0] / float(acc[ci][1])
	for i in a.size():
		if a[i] != null and i not in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_INDEX]:
			push_warning("prop split: array %d not copied" % i)
	a[Mesh.ARRAY_VERTEX] = v; a[Mesh.ARRAY_NORMAL] = nrm; a[Mesh.ARRAY_TEX_UV] = uv; a[Mesh.ARRAY_COLOR] = vc
	if tan != null: a[Mesh.ARRAY_TANGENT] = tan
	a[Mesh.ARRAY_BONES] = bo; a[Mesh.ARRAY_WEIGHTS] = we; a[Mesh.ARRAY_INDEX] = idx
	print(name, ": ", mine.count(1), " pts, box ", mn, " ", mx, " mixed tris ", mixed, " copied ", copy.size())
	if name == "vial":
		# 두 병 속을 메우는 공. 앞 병 공은 앞 병과 같이 움직이고(빨강 tag), 뒤 병 공은 허리에 남는다. 둘 다 물약 자리(파랑 0).
		for which in 2:
			var cc: Vector3 = VIAL_C if which == 0 else VIAL_C2
			var oc: Vector3 = VIAL_C2 if which == 0 else VIAL_C
			var src := PackedVector3Array()
			for k in n0:
				var p := v[k]
				if p.distance_to(cc) > VIAL_R or p.distance_to(cc) > p.distance_to(oc): continue
				var col := img.get_pixelv(Vector2i(uv[k] * Vector2(isz)).clamp(Vector2i.ZERO, isz - Vector2i.ONE))
				if col.v > 0.45 and not (col.h > 0.03 and col.h < 0.2): src.append(p)
			_add_ball(a, cc, VIAL_FILL[which], Color(tag if which == 0 else 1.0, 1.0, 0.0), src, hips)
		# 앞 병 뒤 로브도 뚫려 있어서(mp4.gd: 둘레 로브 앞면 z 0.075~0.086 인데 병 뒤는 0.015~0.05 로 움푹) 로브 앞면 바로 안쪽에
		# 납작한 판(VIAL_PATCH)을 댄다. 로브가 있는 곳에서는 로브 뒤에 숨고 구멍으로만 보인다. 셰이더가 로브 보라로 칠함(UV x -2).
		_add_patch(a, Vector3(VIAL_PATCH.x, VIAL_PATCH.y, VIAL_PATCH.z), VIAL_PATCH_R, hips)

const ARM_DOWN := 50.0  # T자 기본 자세에서 팔을 내리는 각도. 72°는 손이 허리의 책을 뚫고 58°도 스쳐서 벌림
# 37RHHG app/main.gd 의 _pose 를 옮긴 것(w 걷기 비중, run 달리기 비중). 다른 점:
#  - 모델이 T자라 위팔을 앞축으로 ARM_DOWN 만큼 내린다.
#  - 팔꿈치 굽힘 축: T자에서 아래팔은 옆을 향하므로 lat 이 아니라 위(UP) 축으로 굽혀야 앞으로 접힌다(lat 은 비틀기).
#  - 달리기 무릎 굽힘 75→RUN_KNEE: 다리가 짧아 뒤로 차올린 발이 로브 단을 뚫었다.
#  - 달리기 때 팔을 RUN_ARM_OUT 더 벌린다: 팔꿈치를 굽혀 뒤로 흔들면 손이 왼쪽 허리 책에 닿았다.
const RUN_KNEE := 52.0
const RUN_ARM_OUT := 10.0
const JUMP_H := 44.0 / 120.0   # 37RHHG 점프 높이를 키 대비로(모델 키 1.0)
const LEAP_H := 58.0 / 120.0
# 인사: 37RHHG 는 팔을 쭉 펴서 들지만 개구리는 팔이 짧아 그러면 가리키는 꼴이라,
# 위팔은 바깥·위로, 아래팔은 세워서 팔꿈치를 축으로 좌우로 흔든다. 고개는 캐릭터 왼쪽으로. 시간은 37RHHG 그대로.
const GREET_TILT := -8.0
const GREET_ARM_DIR := Vector3(0.85, 0.45, 0.2)    # 위팔 (바깥, 위, 앞)
const GREET_FORE_DIR := Vector3(0.5, 0.85, 0.25)   # 아래팔. 더 세우면 안쪽으로 흔들 때 손이 모자 챙 밑 머리에 닿음
const GREET_WAVE := 18.0
const PALM_SIGN := 1.0   # 기본 자세(T자) 손바닥 방향: 아래(1). measure.gd 로 잼: 손 점들이 위아래로 가장 얇고 엄지는 앞쪽
const GREET_WAVES := 2.5
const GREET_UP := 0.35
const GREET_HOLD := 1.25
const GREET_DOWN := 0.4
## greet: 인사 자세 비중(0~1), wave: 손 흔들기(-1~1)
# 두리번(37RHHG): 서 있을 때 1.2~3.5초마다 새 방향(35%는 정면, 아니면 ±LOOK_MAX)을 골라 천천히 돌린다.
# 갸우뚱: 37RHHG 는 서 있을 때 2.5° 살짝 흔들리는 것뿐이라, 눈에 띄는 기울임 cock(도, +면 머리가 캐릭터 오른쪽 = 정면에서 화면 왼쪽으로 기울어짐)을 따로 둔다.
const LOOK_MAX := 30.0
const COCK_MAX := 16.0
## look: 머리 좌우(도, +가 캐릭터 왼쪽), cock: 갸우뚱(도)
# 소품 들어 보이기: 손 뻗기 reach → 만지기 pat → 들기 lift → 들고 있기 hold → 돌려놓기 lift → 손 내리기 reach(초).
# 좌표는 몸 기준 cm (바깥, 위, 앞): 바깥은 소품 쪽 손의 바깥(왼손이면 +x, 오른손이면 -x).
#  touch: 만질 때 손목(IK), pat: 만지기 동안 손목이 떴다 닿는 방향(톡톡), t_hand: 손가락 방향, t_palm: 손바닥 방향, t_hint: 팔꿈치 쪽
#  wrist: 들고 있을 때 손목(IK, 팔이 짧아 위팔 7.8·아래팔 8.9 → 어깨에서 16.5 안쪽), p_hint, hand: 손가락 방향(손바닥은 앞)
#  ofs: 손목 → 소품 가운데, rot: 들고 있을 때 소품 회전(몸 기준), push: 들고 있을 때 손목을 한 번 더 앞으로(cm)
#  spin: 들고 있는 동안 소품을 앞축으로 흔드는 각도(도)·횟수, lean: 들 때 상체 앞으로(도)
#  see: 만질 때 고개 돌림(도, 바깥 쪽)·숙임, show_cock: 들고 있을 때 갸우뚱(+면 바깥 반대쪽으로)
const PROPS := {
	# ⑩ 책(왼손): 두 번 톡톡 만진 뒤 집어 정면으로 내민다. 손은 책 왼쪽 뒤에 숨는다.
	"book": {"side": 0, "reach": 0.5, "pat": 0.7, "pats": 2.0, "lift": 0.7, "hold": 1.3,
		"touch": Vector3(18.3, 44.5, 2.5), "pat_v": Vector3(1.5, 1.2, 0.0), "t_hint": Vector3(1, 0, -0.5),
		"t_hand": Vector3(0.15, -1, 0.2), "t_palm": Vector3(-1, 0, 0),
		"wrist": Vector3(6.5, 46.0, 9.8), "p_hint": Vector3(1, -0.6, 0), "hand": Vector3(0.0, 0.99, -0.14),
		"ofs": Vector3(-4.5, 3.0, 3.2), "tilt": -8.0, "yaw": -90.0, "push": 1.2, "spin": 0.0, "spins": 0.0, "lean": 4.0,
		"see_look": 22.0, "see_nod": 12.0, "see_side": 4.0, "show_cock": -6.0},
	# ⑪ 앞 유리병(오른손): 병목(코르크)을 위에서 집어 꺼내, 어깨 높이로 들어 병이 손 아래로 대롱대롱 매달리게 보이고
	# 좌우로 살랑 흔든 뒤 다시 건다. 손은 손바닥 아래·손가락 앞(병목을 쥠). 뒤 병은 허리에 남는다.
	"vial": {"side": 1, "reach": 0.5, "pat": 0.35, "pats": 1.0, "lift": 0.6, "hold": 1.6,
		"touch": Vector3(11.0, 43.5, 7.5), "pat_v": Vector3(0.0, -0.8, 0.0), "t_hint": Vector3(1, 0, -0.6),
		"t_hand": Vector3(0.0, -1, 0.15), "t_palm": Vector3(0, 0, -1),
		"wrist": Vector3(17.0, 60.0, 11.0), "p_hint": Vector3(1, -1, -0.3), "hand": Vector3(-0.35, 0.1, 0.93),
		"palm": Vector3(0, -1, 0), "f_palm": Vector3(0, -1, 0),
		"ofs": Vector3(0.0, -5.0, 3.0), "tilt": 0.0, "yaw": 0.0, "push": 0.0, "spin": 14.0, "spins": 2.0, "lean": 0.0,
		"see_look": 24.0, "see_nod": 14.0, "see_side": 4.0, "show_cock": 7.0},
}
func prop_len(name: String) -> float:
	var P: Dictionary = PROPS[name]
	return 2.0 * P.reach + P.pat + 2.0 * P.lift + P.hold
## at(초) → r 손 뻗기, pat 만지기(0~1 들림), k 들기, push 들 때 한 번 더 앞으로, spin 흔들기(-1~1)
func _prop_phase(name: String, at: float) -> Dictionary:
	var d := {"r": 0.0, "pat": 0.0, "k": 0.0, "push": 0.0, "spin": 0.0}
	if name == "" or at < 0.0 or at > prop_len(name): return d
	var P: Dictionary = PROPS[name]
	var t1: float = P.reach; var t2: float = t1 + P.pat; var t3: float = t2 + P.lift; var t4: float = t3 + P.hold; var t5: float = t4 + P.lift
	d.r = smoothstep(0.0, t1, at) if at < t5 else 1.0 - smoothstep(t5, t5 + P.reach, at)
	if at > t1 and at < t2: d.pat = pow(sin(PI * P.pats * (at - t1) / P.pat), 2.0)
	d.k = smoothstep(t2, t3, at) if at < t4 else 1.0 - smoothstep(t4, t5, at)
	if at > t3 - 0.15 and at < t4: d.push = sin(PI * clampf((at - t3 + 0.15) / 0.6, 0.0, 1.0))
	if at > t3 and at < t4:
		var u: float = (at - t3) / P.hold
		d.spin = sin(TAU * P.spins * u) * pow(sin(PI * u), 0.5)
	return d
func _seg_q(d0: Vector3, p0: Vector3, d1: Vector3, p1: Vector3) -> Quaternion:
	p0 = (p0 - d0 * d0.dot(p0)).normalized(); p1 = (p1 - d1 * d1.dot(p1)).normalized()
	return Quaternion(Basis(d1, p1, d1.cross(p1)) * Basis(d0, p0, d0.cross(p0)).inverse())
func _ik(s: Vector3, t: Vector3, l1: float, l2: float, hint: Vector3) -> Array:
	var d := t - s
	var L := clampf(d.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	var n := d.normalized()
	var a := (l1 * l1 + L * L - l2 * l2) / (2.0 * L)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var pole := (hint - n * hint.dot(n)).normalized()
	var e := s + n * a + pole * h
	return [(e - s).normalized(), (s + n * L - e).normalized()]
var pr_q := {}       # 소품 팔의 만지기·들기 자세(전역 회전) — _prop_update 가 손 자리를 잴 때 씀
var prop_xf := {"book": Transform3D.IDENTITY, "vial": Transform3D.IDENTITY}   # 셰이더 book_m·vial_m(월드 → 월드)
var prop_away := {"book": 0.0, "vial": 0.0}   # 셰이더 book_away·vial_away: 소품이 허리를 떠난 정도
func _arm_set(sk: Skeleton3D, S: String, qa: Quaternion, qf: Quaternion, qh: Quaternion):
	_rot(sk, S + "Arm", Vector3.UP, 0.0, qa)
	_rot(sk, S + "ForeArm", Vector3.UP, 0.0, qa.inverse() * qf)
	_rot(sk, S + "Hand", Vector3.UP, 0.0, qf.inverse() * qh)
## 소품을 손에 들게 하는 변환. pose 끝에서 부른다(척추까지 다 놓인 뒤). 만지는 자세·드는 자세일 때 손 기준 소품 자리를 재서
## 그 사이로 보간하고 지금 손에 붙인다(집는·놓는 순간 튀지 않게).
func _prop_update(sk: Skeleton3D, mi: MeshInstance3D, name: String, ph: Dictionary, now: Array, body: Array):
	for nm in prop_xf: prop_xf[nm] = Transform3D.IDENTITY; prop_away[nm] = 0.0
	if name == "" or ph.r <= 0.0: return
	prop_away[name] = smoothstep(0.0, 0.2, ph.k)
	if ph.k <= 0.0: return
	var P: Dictionary = PROPS[name]
	var S := "Left" if P.side == 0 else "Right"
	var hb := sk.find_bone("Hips"); var hn := sk.find_bone(S + "Hand")
	var c0: Vector3 = sk.get_bone_global_rest(hb) * mi.skin.get_bind_pose(prop_hb) * (prop_c[name] as Vector3)
	var hips_d := sk.get_bone_global_pose(hb) * sk.get_bone_global_rest(hb).affine_inverse()
	var rest_n := hips_d * Transform3D(Basis(), c0)
	rest_n.basis = rest_n.basis.orthonormalized()
	var chest := (sk.get_bone_global_pose(sk.find_bone("Spine02")).basis * sk.get_bone_global_rest(sk.find_bone("Spine02")).basis.inverse()).orthonormalized()
	_arm_set(sk, S, pr_q.ta, pr_q.tf, pr_q.th)
	var h_t := sk.get_bone_global_pose(hn); h_t.basis = h_t.basis.orthonormalized()
	_arm_set(sk, S, pr_q.pa, pr_q.pf, pr_q.ph)
	var h_p := sk.get_bone_global_pose(hn); h_p.basis = h_p.basis.orthonormalized()
	_arm_set(sk, S, now[0], now[1], now[2])
	var h_n := sk.get_bone_global_pose(hn); h_n.basis = h_n.basis.orthonormalized()
	var out: Vector3 = body[0]; var up: Vector3 = body[1]; var fwd: Vector3 = body[2]
	# spin: 손목을 축으로 앞축 둘레로 흔든다(매달린 병이 대롱대롱).
	var sw := Basis(chest * fwd, deg_to_rad(P.spin * ph.spin))
	var o: Vector3 = h_p.origin + sw * (chest * (out * P.ofs.x + up * P.ofs.y + fwd * P.ofs.z))
	var rot := sw * chest * Basis(Vector3.RIGHT, deg_to_rad(P.tilt)) * Basis(Vector3.UP, deg_to_rad(P.yaw))
	var present := Transform3D(rot, o)
	var g_c := h_t.affine_inverse() * rest_n
	var g_p := h_p.affine_inverse() * present
	var cur := h_n * g_c.interpolate_with(g_p, smoothstep(0.0, 1.0, ph.k))
	var sg := sk.global_transform
	prop_xf[name] = sg * cur * rest_n.affine_inverse() * sg.affine_inverse()

## act: 들어 보이는 소품("book"·"vial", "" 이면 없음), at: 그 동작 시작 뒤 초
func pose(sk: Skeleton3D, p: float, w := 1.0, run := 0.0, t := 0.0, j := 0.0, leap := 0.0, greet := 0.0, wave := 0.0, look := 0.0, cock := 0.0, act := "", at := -1.0, mi: MeshInstance3D = null):
	var bph := _prop_phase(act, at)
	var PP: Dictionary = PROPS[act] if act != "" else {}
	var pr_now := []
	var lat := (sk.get_bone_global_rest(sk.find_bone("LeftUpLeg")).origin - sk.get_bone_global_rest(sk.find_bone("RightUpLeg")).origin)
	lat.y = 0; lat = lat.normalized()
	var up := Vector3.UP
	var fwd := lat.cross(up)
	var a0 := TAU * p
	var idle := 1.0 - w
	var breath := sin(t * TAU * 0.35)
	var unit := sk.get_bone_global_rest(sk.find_bone("Head")).origin.y / 85.0
	var thigh_a := lerpf(26.0, 40.0, run) * w
	var knee_a := lerpf(42.0, RUN_KNEE, run) * w
	var knee_base := lerpf(3.0, lerpf(4.0, 12.0, run), w)
	var arm_a := lerpf(20.0, 36.0, run) * w
	var fore_base := lerpf(-8.0, lerpf(-14.0, -62.0, run), w)
	var lean := lerpf(1.0, lerpf(3.0, 12.0, run), w)
	var twist := lerpf(5.0, 8.0, run) * w
	var bob := lerpf(1.6, 3.5, run) * w
	for side in 2:
		var S := "Left" if side == 0 else "Right"
		var sgn := 1.0 if side == 0 else -1.0
		var a := a0 + (0.0 if side == 0 else PI)
		var lead := side == 0  # 멀리뛰기에서 앞으로 뻗는 다리
		var thigh := thigh_a * sin(a) - 6.0 * w - 40.0 * j + (-48.0 if lead else 34.0) * leap
		var knee := knee_base + knee_a * maxf(0.0, -cos(a)) + 72.0 * j + (18.0 if lead else 70.0) * leap
		_rot(sk, S + "UpLeg", lat, thigh)
		_rot(sk, S + "Leg", lat, knee)
		_rot(sk, S + "Foot", lat, -0.6 * (thigh + knee) - 8.0 * w * maxf(0.0, sin(a - 0.6)) + 18.0 * j)
		var arm := -arm_a * sin(a) + 4.0 * w - 15.0 * j + (25.0 if lead else -70.0) * leap
		var arm_out := (3.0 + 1.5 * breath) * idle + 4.0 * w + RUN_ARM_OUT * run * w + 27.0 * j + 22.0 * leap
		var fore := fore_base - 8.0 * w * maxf(0.0, -sin(a)) - 25.0 * j
		var q_arm := Quaternion(lat, deg_to_rad(arm)) * Quaternion(fwd, deg_to_rad(-(ARM_DOWN - arm_out) * sgn))
		var q_fore := Quaternion(up, deg_to_rad(fore * sgn))
		if side == 1 and greet > 0.0:
			# 위팔·아래팔이 향할 방향을 몸 기준으로 정해 그쪽으로 돌린다. _rot 은 전역 회전이라 아래팔은 q_arm 을 빼 준다.
			var pa := sk.get_bone_global_rest(sk.find_bone("RightArm")).origin
			var pf := sk.get_bone_global_rest(sk.find_bone("RightForeArm")).origin
			var ph := sk.get_bone_global_rest(sk.find_bone("RightHand")).origin
			var e := (-lat * GREET_ARM_DIR.x + up * GREET_ARM_DIR.y + fwd * GREET_ARM_DIR.z).normalized()
			var hd := (-lat * GREET_FORE_DIR.x + up * GREET_FORE_DIR.y + fwd * GREET_FORE_DIR.z).normalized()
			hd = hd.rotated(fwd, deg_to_rad(-GREET_WAVE * wave))
			q_arm = q_arm.slerp(Quaternion((pf - pa).normalized(), e), greet)
			# 아래팔은 방향뿐 아니라 비틀기까지 정한다: 기본 자세(T자)에서 손바닥이 아래(-up)인 것을 앞(fwd)으로.
			var f0 := (ph - pf).normalized()
			var p0 := (-up * PALM_SIGN - f0 * f0.dot(-up * PALM_SIGN)).normalized()
			var p1 := (fwd - hd * hd.dot(fwd)).normalized()
			var qf := Quaternion(Basis(hd, p1, hd.cross(p1)) * Basis(f0, p0, f0.cross(p0)).inverse())
			q_fore = q_fore.slerp(q_arm.inverse() * qf, greet)
		if bph.r > 0.0 and side == PP.side:
			# 소품 쪽 팔: 몸 기준 전역 회전으로 만지기(IK)·들기(IK) 자세를 정하고, 평소 자세 → 만지기 → 들기로 잇는다.
			var out := lat * sgn
			var pa := sk.get_bone_global_rest(sk.find_bone(S + "Arm")).origin
			var pf := sk.get_bone_global_rest(sk.find_bone(S + "ForeArm")).origin
			var phd := sk.get_bone_global_rest(sk.find_bone(S + "Hand")).origin
			var u0 := (pf - pa).normalized(); var f0 := (phd - pf).normalized(); var p0 := -up * PALM_SIGN
			var B := func(v: Vector3) -> Vector3: return out * v.x + up * v.y + fwd * v.z
			var wt: Vector3 = B.call(PP.touch + PP.pat_v * bph.pat)
			var ik := _ik(pa, wt, pa.distance_to(pf), pf.distance_to(phd), B.call(PP.t_hint))
			var tp: Vector3 = B.call(PP.t_palm)
			pr_q.ta = _seg_q(u0, p0, ik[0], tp)
			pr_q.tf = _seg_q(f0, p0, ik[1], tp)
			pr_q.th = _seg_q(f0, p0, (B.call(PP.t_hand) as Vector3).normalized(), tp)
			var wp: Vector3 = B.call(PP.wrist) + fwd * PP.push * bph.push
			var ikp := _ik(pa, wp, pa.distance_to(pf), pf.distance_to(phd), B.call(PP.p_hint))
			var eh := (B.call(PP.hand) as Vector3).normalized()
			# 손바닥(palm)은 기본 앞. 아래팔 손바닥(f_palm)은 기본 -손가락 방향: 손목을 비틀지 않고 손등 쪽으로 젖힌다.
			var hp: Vector3 = B.call(PP.palm) if PP.has("palm") else fwd
			var fp: Vector3 = B.call(PP.f_palm) if PP.has("f_palm") else -eh
			pr_q.pa = _seg_q(u0, p0, ikp[0], fp)
			pr_q.pf = _seg_q(f0, p0, ikp[1], fp)
			pr_q.ph = _seg_q(f0, p0, eh, hp)
			var qf_abs := q_arm * q_fore
			var qa: Quaternion; var qf: Quaternion; var qh: Quaternion
			if bph.k > 0.0:
				var kk := smoothstep(0.0, 1.0, bph.k)
				qa = pr_q.ta.slerp(pr_q.pa, kk); qf = pr_q.tf.slerp(pr_q.pf, kk); qh = pr_q.th.slerp(pr_q.ph, kk)
			else:
				qa = q_arm.slerp(pr_q.ta, bph.r); qf = qf_abs.slerp(pr_q.tf, bph.r); qh = qf_abs.slerp(pr_q.th, bph.r)
			_arm_set(sk, S, qa, qf, qh)
			pr_now = [qa, qf, qh, out]
			continue
		_rot(sk, S + "Arm", up, 0.0, q_arm)
		_rot(sk, S + "ForeArm", up, 0.0, q_fore)
	var hb := sk.find_bone("Hips")
	_rot(sk, "Hips", up, twist * sin(a0), Quaternion(fwd, deg_to_rad(2.0 * w * cos(a0))))
	var drop := bob * (0.5 + 0.5 * cos(2.0 * a0)) + 6.0 * j
	sk.set_bone_pose_position(hb, sk.get_bone_rest(hb).origin + up * (-drop * unit))
	var bsee: float = bph.r * (1.0 - bph.k)   # 소품을 내려다보는 정도
	var pside: float = (1.0 if PP.side == 0 else -1.0) if act != "" else 0.0   # 소품 쪽(캐릭터 왼쪽 +)
	var plean: float = float(PP.lean) * float(bph.k) + 2.0 * float(bph.push) if act != "" else 0.0
	_rot(sk, "Spine02", lat, lean + 1.2 * breath * idle - 6.0 * j + 10.0 * leap + plean,
		Quaternion(fwd, deg_to_rad(-(PP.see_side if act != "" else 0.0) * bsee * pside)))
	_rot(sk, "Spine", up, -twist * 1.4 * sin(a0))
	var nod: float = (-2.0 + 1.5 * cos(2.0 * a0)) * w - lean * 0.5 + 1.0 * breath * idle - 2.0 * float(bph.k)
	if act != "":
		nod += float(PP.see_nod) * bsee
		look += float(PP.see_look) * bsee * pside
		cock += float(PP.show_cock) * float(bph.k) * -pside
	var tilt := -2.0 * w * cos(a0) + 2.5 * sin(t * TAU * 0.13) * idle + cock
	tilt = lerpf(tilt, GREET_TILT, greet)
	var turn := twist * 0.4 * sin(a0) + clampf(look, -LOOK_MAX, LOOK_MAX)
	_rot(sk, "Head", up, turn, Quaternion(lat, deg_to_rad(nod)) * Quaternion(fwd, deg_to_rad(tilt)))
	if mi != null:
		var out_v: Vector3 = pr_now[3] if pr_now.size() > 3 else lat
		_prop_update(sk, mi, act if pr_now.size() > 0 else "", bph, pr_now, [out_v, up, fwd])
func _ready():
	for a in OS.get_cmdline_user_args(): mode = a
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.96,0.96,0.97)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color.WHITE; env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,25,0); sun.light_energy = 0.45; add_child(sun)
	var angles := [-90.0, -30.0]
	if OS.get_environment("FRONT") != "": angles = [0.0, 180.0]  # 정면·뒷면으로 보기
	if mode == "blink": angles = [0.0, -35.0]
	if mode == "mouth": angles = [0.0, -90.0]  # 정면·완전한 옆면
	if mode == "greet": angles = [0.0, -35.0]
	if mode == "look": angles = [0.0, -35.0]
	if mode == "tint": angles = [0.0, 180.0]  # 앞·뒤
	if mode == "potion": angles = [0.0, 90.0]   # 정면·옆(병이 보이는 쪽)
	if mode == "book": angles = [0.0, -60.0]   # 정면·책 쪽 옆
	if mode == "vial": angles = [0.0, 60.0]    # 정면·병 쪽 옆
	if mode == "book" and OS.get_environment("PROP_ZOOM") != "": angles = [-90.0, -150.0]   # 책 옆면·뒤에서
	if mode == "vial" and OS.get_environment("PROP_ZOOM") != "": angles = [0.0, 90.0]   # 병 정면·옆
	var sks := []; var aps := []; var pivots := []; var matss := []; var ls := []; var mis := []
	for k in 2:
		var doc := GLTFDocument.new(); var st := GLTFState.new()
		doc.append_from_file(FILE, st)
		var n := doc.generate_scene(st); var mats := []; _matte(n, mats); matss.append(mats)
		if mode != "nofix": _fix_legs(n, _find(n, "Skeleton3D"))
		var pivot := Node3D.new(); pivot.position = Vector3((k-0.5)*(0.5 if mode in ["book", "vial"] and OS.get_environment("PROP_ZOOM") != "" else 0.42 if mode in ["blink", "mouth"] else 0.5 if mode == "potion" else (0.7 if OS.get_environment("ZOOM") != "" else 1.0)), 0, 0); pivot.rotation_degrees.y = angles[k]
		pivot.add_child(n); add_child(pivot); pivots.append(pivot)
		var ap: AnimationPlayer = _find(n, "AnimationPlayer"); aps.append(ap)
		var sk: Skeleton3D = _find(n, "Skeleton3D"); sks.append(sk)
		ls.append(_head_l(sk, _find(n, "MeshInstance3D"))); mis.append(_find(n, "MeshInstance3D"))
		if k == 0:
			for nm in ["Hips","Head","headfront","LeftUpLeg","RightUpLeg","LeftArm","RightArm","LeftHand","RightHand","LeftFoot","RightFoot"]:
				print(nm, " ", sk.get_bone_global_rest(sk.find_bone(nm)).origin.snapped(Vector3.ONE*0.1))
			print("skel basis ", sk.global_transform.basis.get_scale(), " anim ", ap.get_animation_list())
	var cam := Camera3D.new(); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = 1.25
	cam.position = Vector3(0,0.52,6); add_child(cam)
	if mode in ["jump", "leap"]: cam.size = 1.8; cam.position.y = 0.78  # 뛰어오른 높이까지 보이게
	if mode in ["blink", "mouth"]: cam.size = 0.42; cam.position.y = 0.66
	if mode == "potion": cam.size = 0.5; cam.position.y = 0.36  # 허리 유리병 크게
	if mode in ["book", "vial"] and OS.get_environment("PROP_ZOOM") != "": cam.size = 0.55; cam.position.y = 0.36
	if OS.get_environment("ZOOM") != "": cam.size = 0.62; cam.position = Vector3(-0.25, 0.62, 6)  # 든 손을 크게  # 머리만 크게
	var frames_look := 0
	var an: String = aps[0].get_animation_list()[0]
	var L: float = aps[0].get_animation(an).length
	if mode == "look": frames_look = 60
	if mode in ["tint", "potion"]: frames_look = 24
	if mode in ["book", "vial"]: frames_look = int(ceil(prop_len(mode) * 12.0)) + 1
	var frames := frames_look if mode in ["look", "tint", "potion", "book", "vial"] else N if mode in ["custom", "nofix", "dbg", "run", "jump", "leap", "blink", "greet", "mouth"] else 50
	for f in frames:
		for k in 2:
			if mode in ["custom", "nofix", "dbg", "run"]:
				aps[k].stop(); sks[k].reset_bone_poses(); pose(sks[k], float(f) / N, 1.0, 1.0 if mode == "run" else 0.0)
			elif mode in ["jump", "leap"]:
				# 37RHHG: 제자리 점프 j = sin(πu), 높이 JUMP_H·4u(1-u). 멀리뛰기는 leap 와 LEAP_H. 높이는 키 대비 비율.
				var u := float(f) / (N - 1)
				var air := sin(PI * u)
				aps[k].stop(); sks[k].reset_bone_poses()
				if mode == "jump": pose(sks[k], 0.0, 0.0, 0.0, 0.0, air, 0.0)
				else: pose(sks[k], 0.0, 0.0, 0.0, 0.0, 0.0, air)
				pivots[k].position.y = (JUMP_H if mode == "jump" else LEAP_H) * 4.0 * u * (1.0 - u)
			elif mode == "greet":
				# 37RHHG _greet_step: 드는 0.35초·흔드는 1.25초·내리는 0.4초 = 2초를 12fps 24프레임으로.
				var gt := float(f) / 12.0
				var g := smoothstep(0.0, GREET_UP, gt) if gt < GREET_UP else (1.0 if gt < GREET_UP + GREET_HOLD else 1.0 - smoothstep(GREET_UP + GREET_HOLD, GREET_UP + GREET_HOLD + GREET_DOWN, gt))
				var gu := clampf((gt - GREET_UP) / GREET_HOLD, 0.0, 1.0)
				var wv := sin(TAU * GREET_WAVES * gu) * pow(sin(PI * gu), 0.3) if gu > 0.0 and gu < 1.0 else 0.0
				aps[k].stop(); sks[k].reset_bone_poses(); pose(sks[k], 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, g, wv)
			elif mode in ["book", "vial"]:
				# 12fps. PROP_DEBUG=1 이면 소품 점을 빨강, 붙어 있던 로브 자리를 초록으로. PROP_T=초 면 그 순간 한 장만.
				var bt := float(f) / 12.0
				if OS.get_environment("PROP_T") != "": bt = float(OS.get_environment("PROP_T"))
				aps[k].stop(); sks[k].reset_bone_poses(); pose(sks[k], 0.0, 0.0, 0.0, bt, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, mode, bt, mis[k])
				for m2 in matss[k]:
					m2.set_shader_parameter("book_m", Projection(prop_xf.book)); m2.set_shader_parameter("book_away", prop_away.book)
					m2.set_shader_parameter("vial_m", Projection(prop_xf.vial)); m2.set_shader_parameter("vial_away", prop_away.vial)
					m2.set_shader_parameter("book_debug", OS.get_environment("PROP_DEBUG") != "")
			elif mode == "potion":
				aps[k].stop(); sks[k].reset_bone_poses(); pose(sks[k], 0.0, 0.0)
				var bv := smoothstep(6.0, 18.0, float(f))
				for m2 in matss[k]:
					m2.set_shader_parameter("potion", bv); m2.set_shader_parameter("potion_debug", OS.get_environment("POTION_DEBUG") != "")
			elif mode == "tint":
				# 0~0.5초 보라, 0.5~1.5초 바뀌고, 1.5~2초 파랑. TINT_DEBUG=1 이면 바뀌는 곳을 초록으로.
				aps[k].stop(); sks[k].reset_bone_poses(); pose(sks[k], 0.0, 0.0)
				var tv := smoothstep(6.0, 18.0, float(f))
				for m2 in matss[k]:
					m2.set_shader_parameter("tint", tv); m2.set_shader_parameter("tint_debug", OS.get_environment("TINT_DEBUG") != "")
			elif mode == "look":
				# 5초(12fps 60프레임): 왼쪽 → 오른쪽 → 정면 → 갸우뚱 → 반대로 살짝
				var tt := float(f) / 12.0
				var keys := [[0.0, 0.0, 0.0], [0.6, LOOK_MAX, 0.0], [1.4, LOOK_MAX, 0.0], [2.0, -LOOK_MAX, 0.0], [2.8, -LOOK_MAX, 0.0],
					[3.3, 0.0, 0.0], [3.7, 0.0, COCK_MAX], [4.3, 0.0, COCK_MAX], [4.7, 0.0, -COCK_MAX * 0.6], [5.0, 0.0, -COCK_MAX * 0.6]]
				var lk := 0.0; var ck := 0.0
				for i in keys.size() - 1:
					if tt >= keys[i][0] and tt <= keys[i + 1][0]:
						var e := smoothstep(keys[i][0], keys[i + 1][0], tt)
						lk = lerpf(keys[i][1], keys[i + 1][1], e); ck = lerpf(keys[i][2], keys[i + 1][2], e)
				aps[k].stop(); sks[k].reset_bone_poses(); pose(sks[k], 0.0, 0.0, 0.0, tt, 0.0, 0.0, 0.0, 0.0, lk, ck)
			elif mode == "mouth":
				aps[k].stop(); sks[k].reset_bone_poses(); pose(sks[k], 0.0, 0.0)
				var u := clampf((float(f) / (N - 1) - 0.15) / 0.7, 0.0, 1.0)
				_face(sks[k], ls[k], matss[k], 0.0, clampf(sin(PI * u) * 1.3, 0.0, 1.0))
			elif mode == "blink":
				# 감았다 뜨기를 천천히: 앞 1/4 은 뜬 채, 가운데서 다 감김.
				aps[k].stop(); sks[k].reset_bone_poses(); pose(sks[k], 0.0, 0.0)
				var u := clampf((float(f) / (N - 1) - 0.2) / 0.6, 0.0, 1.0)
				_face(sks[k], ls[k], matss[k], clampf(sin(PI * u) * 1.4, 0.0, 1.0))
			elif mode == "rest":
				aps[k].stop(); sks[k].reset_bone_poses()
			else:
				aps[k].play(an); aps[k].seek(L * f / 50.0, true); aps[k].pause()
		if mode not in ["blink", "mouth"]:
			for k in 2: _face(sks[k], ls[k], matss[k], 0.0)
		await get_tree().create_timer(0.05).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://gif/%s%02d.png" % [mode, f])
		if mode == "rest" or (mode in ["book", "vial"] and OS.get_environment("PROP_T") != ""): break
	get_tree().quit()
