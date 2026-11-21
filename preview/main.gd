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
func pose(sk: Skeleton3D, p: float, w := 1.0, run := 0.0, t := 0.0, j := 0.0, leap := 0.0, greet := 0.0, wave := 0.0, look := 0.0, cock := 0.0):
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
		_rot(sk, S + "Arm", up, 0.0, q_arm)
		_rot(sk, S + "ForeArm", up, 0.0, q_fore)
	var hb := sk.find_bone("Hips")
	_rot(sk, "Hips", up, twist * sin(a0), Quaternion(fwd, deg_to_rad(2.0 * w * cos(a0))))
	var drop := bob * (0.5 + 0.5 * cos(2.0 * a0)) + 6.0 * j
	sk.set_bone_pose_position(hb, sk.get_bone_rest(hb).origin + up * (-drop * unit))
	_rot(sk, "Spine02", lat, lean + 1.2 * breath * idle - 6.0 * j + 10.0 * leap)
	_rot(sk, "Spine", up, -twist * 1.4 * sin(a0))
	var nod := (-2.0 + 1.5 * cos(2.0 * a0)) * w - lean * 0.5 + 1.0 * breath * idle
	var tilt := -2.0 * w * cos(a0) + 2.5 * sin(t * TAU * 0.13) * idle + cock
	tilt = lerpf(tilt, GREET_TILT, greet)
	var turn := twist * 0.4 * sin(a0) + clampf(look, -LOOK_MAX, LOOK_MAX)
	_rot(sk, "Head", up, turn, Quaternion(lat, deg_to_rad(nod)) * Quaternion(fwd, deg_to_rad(tilt)))
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
	var sks := []; var aps := []; var pivots := []; var matss := []; var ls := []
	for k in 2:
		var doc := GLTFDocument.new(); var st := GLTFState.new()
		doc.append_from_file(FILE, st)
		var n := doc.generate_scene(st); var mats := []; _matte(n, mats); matss.append(mats)
		if mode != "nofix": _fix_legs(n, _find(n, "Skeleton3D"))
		var pivot := Node3D.new(); pivot.position = Vector3((k-0.5)*(0.42 if mode in ["blink", "mouth"] else 0.5 if mode == "potion" else (0.7 if OS.get_environment("ZOOM") != "" else 1.0)), 0, 0); pivot.rotation_degrees.y = angles[k]
		pivot.add_child(n); add_child(pivot); pivots.append(pivot)
		var ap: AnimationPlayer = _find(n, "AnimationPlayer"); aps.append(ap)
		var sk: Skeleton3D = _find(n, "Skeleton3D"); sks.append(sk)
		ls.append(_head_l(sk, _find(n, "MeshInstance3D")))
		if k == 0:
			for nm in ["Hips","Head","headfront","LeftUpLeg","RightUpLeg","LeftArm","RightArm","LeftHand","RightHand","LeftFoot","RightFoot"]:
				print(nm, " ", sk.get_bone_global_rest(sk.find_bone(nm)).origin.snapped(Vector3.ONE*0.1))
			print("skel basis ", sk.global_transform.basis.get_scale(), " anim ", ap.get_animation_list())
	var cam := Camera3D.new(); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = 1.25
	cam.position = Vector3(0,0.52,6); add_child(cam)
	if mode in ["jump", "leap"]: cam.size = 1.8; cam.position.y = 0.78  # 뛰어오른 높이까지 보이게
	if mode in ["blink", "mouth"]: cam.size = 0.42; cam.position.y = 0.66
	if mode == "potion": cam.size = 0.5; cam.position.y = 0.36  # 허리 유리병 크게
	if OS.get_environment("ZOOM") != "": cam.size = 0.62; cam.position = Vector3(-0.25, 0.62, 6)  # 든 손을 크게  # 머리만 크게
	var frames_look := 0
	var an: String = aps[0].get_animation_list()[0]
	var L: float = aps[0].get_animation(an).length
	if mode == "look": frames_look = 60
	if mode in ["tint", "potion"]: frames_look = 24
	var frames := frames_look if mode in ["look", "tint", "potion"] else N if mode in ["custom", "nofix", "dbg", "run", "jump", "leap", "blink", "greet", "mouth"] else 50
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
		if mode == "rest": break
	get_tree().quit()
