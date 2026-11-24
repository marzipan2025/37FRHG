extends RefCounted
## 펼친 책(2026-11-24, 책 꺼내 페이지 넘기기). 허리 책 메시는 덮인 모양이라 펼칠 수 없어서, 펼치는 동안에는
## 허리 책을 숨기고(셰이더 book_hide) 이 책을 손에 든 자리에 띄운다. 단위는 뼈대 좌표(모델 키 100 의 cm).
## 책 좌표: X = 가로(+X 가 왼쪽 쪽, 등은 X 0), Y = 펼친 면이 보는 쪽(앞표지 밖), Z = 페이지 위쪽.
## 덮였을 때는 오른쪽 반(표지·페이지 묶음)이 왼쪽 반 위에 접혀 있다(φ = π). 펼치면 φ = 0.
## 넘기는 한 장(page)은 등을 축으로 φ 0(오른쪽에 누움) → π(왼쪽에 누움)로 돌고, 끝으로 갈수록 휜다.

const W := 8.5          # 한 면 너비
const H := 10.5         # 높이(등 방향)
const COVER := 0.28     # 표지 두께
const BLOCK := 1.1      # 한쪽 페이지 묶음 두께
const SEGS := 14        # 넘기는 장을 나누는 칸

const COVER_COL := Color(0.30, 0.08, 0.07)
const COVER_EDGE := Color(0.62, 0.45, 0.16)     # 금빛 테두리
const PAGE_COL := Color(0.95, 0.91, 0.80)
const PAGE_SIDE := Color(0.86, 0.80, 0.66)      # 페이지 묶음 옆면
const TEXT_COL := Color(0.55, 0.50, 0.42)

var node: MeshInstance3D
var flip: MeshInstance3D
var mat: StandardMaterial3D


func make(parent: Node3D) -> void:
	mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node = MeshInstance3D.new()
	node.material_override = mat
	node.visible = false
	parent.add_child(node)
	flip = MeshInstance3D.new()
	flip.material_override = mat
	node.add_child(flip)


# 상자 하나(축 맞춤). 면마다 색.
static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, top: Color, side: Color, xf := Transform3D.IDENTITY) -> void:
	var c := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	var faces := [[3, 2, 6, 7, Vector3.UP, top], [0, 4, 5, 1, Vector3.DOWN, top], [0, 1, 2, 3, Vector3.BACK * -1.0, side],
		[4, 7, 6, 5, Vector3.BACK, side], [0, 3, 7, 4, Vector3.LEFT, side], [1, 5, 6, 2, Vector3.RIGHT, side]]
	for f in faces:
		var n: Vector3 = xf.basis * (f[4] as Vector3)
		st.set_color(f[5])
		st.set_normal(n.normalized())
		var p := [xf * (c[f[0]] as Vector3), xf * (c[f[1]] as Vector3), xf * (c[f[2]] as Vector3), xf * (c[f[3]] as Vector3)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(p[i])


# 글줄(페이지 위 얇은 띠): 한 면에 몇 줄
static func _lines(st: SurfaceTool, x0: float, x1: float, y: float, xf: Transform3D) -> void:
	var rows := 9
	for r in rows:
		var z := H * 0.36 - r * H * 0.075
		var len := (x1 - x0) * (0.55 if r == rows - 1 else 1.0)
		_box(st, Vector3(x0, y, z - 0.12), Vector3(x0 + len, y + 0.02, z + 0.12), TEXT_COL, TEXT_COL, xf)


# open: 0 덮임 ~ 1 펼침. 오른쪽 반이 등을 축으로 π → 0 으로 돈다.
func build_static(open: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 왼쪽 반(+X): 표지, 금 테두리, 페이지 묶음, 글줄
	_box(st, Vector3(-0.1, -COVER, -H * 0.5 - 0.25), Vector3(W + 0.25, 0.0, H * 0.5 + 0.25), COVER_COL, COVER_EDGE)
	_box(st, Vector3(0.15, 0.0, -H * 0.5), Vector3(W - 0.1, BLOCK, H * 0.5), PAGE_COL, PAGE_SIDE)
	if open > 0.5:
		_lines(st, 0.9, W - 0.8, BLOCK, Transform3D.IDENTITY)
	# 오른쪽 반: 등(X 0, Y BLOCK 높이 아래)을 축으로 돈 자리. φ = π(1 - open)
	var phi := PI * (1.0 - open)
	# 등 축은 페이지 묶음 윗면 높이(Y BLOCK)의 Z 축: 덮이면 오른쪽 페이지가 왼쪽 페이지 위에 포개진다.
	var rhalf := Transform3D(Basis(), Vector3(0, BLOCK, 0)) * Transform3D(Basis(Vector3.BACK, -phi), Vector3.ZERO) \
		* Transform3D(Basis(), Vector3(0, -BLOCK, 0))
	_box(st, Vector3(-W - 0.25, -COVER, -H * 0.5 - 0.25), Vector3(0.1, 0.0, H * 0.5 + 0.25), COVER_COL, COVER_EDGE, rhalf)
	_box(st, Vector3(-W + 0.1, 0.0, -H * 0.5), Vector3(-0.15, BLOCK, H * 0.5), PAGE_COL, PAGE_SIDE, rhalf)
	if open > 0.5:
		_lines(st, -W + 0.8, -0.9, BLOCK, rhalf)
	# 등(둥근 책등 대신 얇은 판)
	_box(st, Vector3(-0.3, -COVER - 0.15, -H * 0.5 - 0.25), Vector3(0.3, -COVER, H * 0.5 + 0.25), COVER_COL, COVER_COL)
	node.mesh = st.commit()


# 넘기는 한 장: phi 0 ~ π(등 축 둘레 각), bend 끝으로 갈수록 더 도는 양(라디안, +면 끝이 앞서감).
func build_page(phi: float, bend: float, show: bool) -> void:
	flip.visible = show
	if not show:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(PAGE_COL)
	var pts := []
	var p := Vector3(0.0, BLOCK + 0.03, 0.0)
	pts.append(p)
	var seg := (W - 0.25) / SEGS
	for k in SEGS:
		var u := float(k + 0.5) / SEGS
		var a := phi + bend * u * u
		# a = 0 이면 -X(오른쪽)로 누움, π 면 +X(왼쪽)
		p += Vector3(-cos(a), sin(a), 0.0) * seg
		pts.append(p)
	for k in SEGS:
		var a0: Vector3 = pts[k]
		var a1: Vector3 = pts[k + 1]
		var t := (a1 - a0).normalized()
		var n := Vector3(-t.y, t.x, 0.0)
		var q := [a0 + Vector3(0, 0, -H * 0.5 + 0.1), a1 + Vector3(0, 0, -H * 0.5 + 0.1),
			a1 + Vector3(0, 0, H * 0.5 - 0.1), a0 + Vector3(0, 0, H * 0.5 - 0.1)]
		st.set_normal(n)
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(q[i])
	flip.mesh = st.commit()
