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
func _matte(n: Node):
	if n is MeshInstance3D:
		for s in n.mesh.get_surface_count():
			var m: BaseMaterial3D = n.mesh.surface_get_material(s).duplicate()
			m.metallic = 0.0; m.metallic_texture = null; m.roughness = 1.0; m.roughness_texture = null; m.normal_enabled = false
			n.set_surface_override_material(s, m)
	for c in n.get_children(): _matte(c)
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
const ARM_DOWN := 50.0  # T자 기본 자세에서 팔을 내리는 각도. 72°는 손이 허리의 책을 뚫고 58°도 스쳐서 벌림
func pose(sk: Skeleton3D, p: float):
	var lat := (sk.get_bone_global_rest(sk.find_bone("LeftUpLeg")).origin - sk.get_bone_global_rest(sk.find_bone("RightUpLeg")).origin)
	lat.y = 0; lat = lat.normalized()
	var up := Vector3.UP
	var fwd := lat.cross(up)
	var ph := TAU * p
	var unit := sk.get_bone_global_rest(sk.find_bone("Head")).origin.y / 85.0
	for side in 2:
		var S := "Left" if side == 0 else "Right"
		var a := ph + (0.0 if side == 0 else PI)
		var thigh := 26.0 * sin(a)
		var knee := 42.0 * maxf(0.0, -cos(a)) + 4.0
		_rot(sk, S + "UpLeg", lat, thigh - 6.0)
		_rot(sk, S + "Leg", lat, knee)
		_rot(sk, S + "Foot", lat, -0.6 * (thigh - 6.0 + knee) - 8.0 * maxf(0.0, sin(a - 0.6)))
		var arm := -20.0 * sin(a)
		_rot(sk, S + "Arm", lat, arm + 4.0, Quaternion(fwd, deg_to_rad(-ARM_DOWN * (1.0 if side == 0 else -1.0))))
		_rot(sk, S + "ForeArm", lat, -14.0 - 8.0 * maxf(0.0, -sin(a)))
	var twist := 5.0 * sin(ph)
	var hb := sk.find_bone("Hips")
	_rot(sk, "Hips", up, twist, Quaternion(fwd, deg_to_rad(2.0 * cos(ph))))
	sk.set_bone_pose_position(hb, sk.get_bone_rest(hb).origin + up * (-1.6 * unit * (0.5 + 0.5 * cos(2.0 * ph))))
	_rot(sk, "Spine02", lat, 3.0)
	_rot(sk, "Spine", up, -twist * 1.4)
	_rot(sk, "Head", up, twist * 0.4, Quaternion(lat, deg_to_rad(-2.0 + 1.5 * cos(2.0 * ph))) * Quaternion(fwd, deg_to_rad(-2.0 * cos(ph))))
func _ready():
	for a in OS.get_cmdline_user_args(): mode = a
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.96,0.96,0.97)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color.WHITE; env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,25,0); sun.light_energy = 0.45; add_child(sun)
	var angles := [-90.0, -30.0]
	if OS.get_environment("FRONT") != "": angles = [0.0, 180.0]  # 정면·뒷면으로 보기
	var sks := []; var aps := []
	for k in 2:
		var doc := GLTFDocument.new(); var st := GLTFState.new()
		doc.append_from_file(FILE, st)
		var n := doc.generate_scene(st); _matte(n)
		if mode != "nofix": _fix_legs(n, _find(n, "Skeleton3D"))
		var pivot := Node3D.new(); pivot.position = Vector3((k-0.5)*1.0, 0, 0); pivot.rotation_degrees.y = angles[k]
		pivot.add_child(n); add_child(pivot)
		var ap: AnimationPlayer = _find(n, "AnimationPlayer"); aps.append(ap)
		var sk: Skeleton3D = _find(n, "Skeleton3D"); sks.append(sk)
		if k == 0:
			for nm in ["Hips","Head","headfront","LeftUpLeg","RightUpLeg","LeftArm","RightArm","LeftHand","RightHand","LeftFoot","RightFoot"]:
				print(nm, " ", sk.get_bone_global_rest(sk.find_bone(nm)).origin.snapped(Vector3.ONE*0.1))
			print("skel basis ", sk.global_transform.basis.get_scale(), " anim ", ap.get_animation_list())
	var cam := Camera3D.new(); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = 1.25
	cam.position = Vector3(0,0.52,6); add_child(cam)
	var an: String = aps[0].get_animation_list()[0]
	var L: float = aps[0].get_animation(an).length
	var frames := N if mode in ["custom", "nofix", "dbg"] else 50
	for f in frames:
		for k in 2:
			if mode == "custom" or mode == "nofix" or mode == "dbg":
				aps[k].stop(); sks[k].reset_bone_poses(); pose(sks[k], float(f) / N)
			elif mode == "rest":
				aps[k].stop(); sks[k].reset_bone_poses()
			else:
				aps[k].play(an); aps[k].seek(L * f / 50.0, true); aps[k].pause()
		await get_tree().create_timer(0.05).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://gif/%s%02d.png" % [mode, f])
		if mode == "rest": break
	get_tree().quit()
