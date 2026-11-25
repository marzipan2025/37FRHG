extends Node3D
## 화면 위를 돌아다니는 개구리 마법사(37FRHG).
## 37RHHG 의 창·이동·조작·혼자 돌아다니기·조명·인사·두리번·깜빡임을 가져오고,
## 말 걸기(AI)·말풍선 도우미·그림 버튼 메뉴·화면 보고 길 고르기·발자국은 뺐다(AI 는 나중에 붙일 예정).
## 작은 투명 창 하나에 캐릭터를 그리고, 걸을 때는 창 자체를 움직인다.
## 길이 단위는 pt(포인트). 실제 픽셀 = pt * px_scale.

const WIN_W := 180.0
const WIN_H := 210.0
const FEET_Y := 192.0         # 창 안에서 발이 닿는 높이
const CHAR_H := 120.0         # 37RHHG 소녀의 화면 키. 개구리는 frog.SIZE 배(150pt)
const MODEL_H := 1.7          # 37RHHG 소녀의 모델 키(월드 단위). 개구리 모델은 frog.SCALE 로 키워 맞춘다
const CAM_PITCH := 10.0       # 살짝 위에서 내려다보는 각도

const WALK_SPEED := 80.0      # pt/s
const RUN_SPEED := 210.0
const ACCEL := 700.0
const WALK_STRIDE := 48.0     # 한 주기(두 걸음)에 나아가는 거리
const RUN_STRIDE := 76.0
const JUMP_H := 44.0          # 개구리는 창 안에 들게 _jump_h() 로 줄인다
const JUMP_TIME := 0.56

# 클릭을 받는 영역(창 안 pt). 나머지 투명한 곳은 클릭이 아래로 통과한다.
const HIT_RECT := Rect2(36, 20, 108, 178)

var px_scale := 1.0            # 창 크기용 배율 = screen_scale * zoom
var screen_scale := 1.0        # 화면 자체 배율(pt → 화면 픽셀)
const BASE_ZOOM := 160.0 / CHAR_H
var zoom := BASE_ZOOM           # z 를 누르고 있는 동안만 2배(두 발을 기준으로 위로 커진다)
const ZOOM_MAX := 2.0
const ZOOM_FREQ := 16.0
const ZOOM_DAMP := 0.55
var zoom_k := 1.0
var zoom_v := 0.0

# 가만히 서 있을 때는 프레임을 낮춰 CPU 를 아낀다. 움직이면 바로 60.
const FPS_ACTIVE := 60
const FPS_IDLE := 24
const FPS_CALM := 0.6
var calm_t := 0.0

var win_pos := Vector2.ZERO    # 창 왼쪽 위, 화면 픽셀
var move_dir := Vector2.DOWN
var last_axis := 0             # 마지막으로 누른 방향키 축(0 좌우, 1 위아래)
var speed := 0.0
var anim_speed := 0.0          # 실제로 움직인 속도(벽에 막히면 줄어듦)
var yaw := 0.0
var target_yaw := 0.0
var phase := 0.0
var clock := 0.0
var jump_u := -1.0
var dragging := false
var drag_mouse := Vector2.ZERO
var drag_win := Vector2.ZERO
const CLICK_SLOP := 4.0        # 이만큼(pt) 넘게 끌었으면 클릭이 아니다

# 서 있을 때 머리를 좌우로 돌려 두리번거린다(±LOOK_MAX 도).
const LOOK_MAX := 30.0
var look := 0.0
var look_target := 0.0
var look_timer := 1.0

# 인사: 정면을 보고 서 있을 때 40~90초마다. 자세는 frog.gd(팔꿈치를 굽혀 흔들고 손바닥이 앞).
const GREET_EVERY := Vector2(40.0, 90.0)
const GREET_WAVES := 2.5
const GREET_UP := 0.35
const GREET_HOLD := 1.25
const GREET_DOWN := 0.4
const GREET_EYES := 0.3        # 인사할 때 눈을 감을 확률
var greet_t := -1.0
var greet := 0.0
var greet_wave := 0.0
var greet_eyes := false
var greet_next := 25.0

# 소품 들어 보이기(frog.gd PROPS): "book" 왼쪽 허리 책을 톡톡 만지고 집어 정면으로 내밀었다가 돌려놓기(4.2초),
# "vial" 앞 유리병 하나를 꺼내 어깨 높이로 들어 흔들어 보이고 다시 걸기(4.0초).
# 아직 켜는 곳이 없다(AI 붙일 때 쓸 예정). _start_prop(이름) 을 부르면 정면을 보고 한다. 확인은 -- --props(서 있으면 8초마다 번갈아).
var prop_act := ""
var prop_t := -1.0
var prop_test := false
var prop_test_next := 2.0
var prop_test_i := 0
# 책 읽기(⑫, 2026-11-24): 긴 기다림에만 쓴다(사용자: "긴 검색 로딩에 제한적으로"). 말 걸고 대답이 READ_WAIT 초 넘게
# 안 오면(도구를 쓰는 긴 대답) 서 있을 때 책을 꺼내 펼쳐 페이지를 넘기고, 대답이 오면 그 장을 다 넘긴 뒤 닫아 넣는다.
const READ_WAIT := 2.0
var wait_t := 0.0

# 혼자 돌아다니기(메뉴바 "걷기"): 걷기 2~6초(25%는 달리기)와 쉬기 1.5~5초를 랜덤하게. 수직·수평으로만.
var wander := false
var w_walking := false
var w_timer := 0.0
var w_dir := Vector2.RIGHT
var w_run := false
var w_stuck := 0.0

var model: Node3D
var shadow: MeshInstance3D
var skel: Skeleton3D
var bones := {}
var lat := Vector3.RIGHT       # 캐릭터의 왼쪽 방향(골격 공간)
var fwd := Vector3.BACK        # 캐릭터의 앞 방향
var k := MODEL_H / CHAR_H      # pt → 월드 단위
var frog: RefCounted           # frog/frog.gd
var face_mat: ShaderMaterial

# 마우스를 광원으로: 빛이 마우스 쪽에서 오고, 가까울수록 음영이 짙다.
const LIGHT_DEPTH := 140.0
const LIGHT_NEAR := 120.0
const LIGHT_FAR := 900.0
const LIGHT_PEAK := 1.15
const SUN_FAR := 0.06
const SUN_NEAR := 0.30
const AMB_TINT := Color(1.0, 0.90, 0.93)
const SUN_TINT := Color(1.0, 0.97, 0.96)
const SHADOW_COL := Color(0.24, 0.16, 0.36, 0.30)   # 발밑 그림자(어두운 보라)
const SHADOW_SHIFT := 0.16
var sun: DirectionalLight3D
var env: Environment
var light_dir := Vector3(0.3, 0.6, 0.74)
var light_near := 0.0
# macOS 는 창을 메뉴바 위로 못 올린다. 화면 위쪽에서는 창을 멈추고 캐릭터를 창 안에서 올려 그린다.
var lift := 0.0
var cam: Camera3D
var cam_base := Vector3.ZERO
var cam_lift_dir := Vector3.UP

# 깜빡임: 서 있을 때 3.5~8초마다, 걸을 때 3배 드물게. 점프·달리기 때 가끔 눈을 감는다.
const RUN_EYES := 0.25
const JUMP_EYES := 0.25
# 평소 입 벌리기(37RHHG 와 같은 식, 2026-11-23): 서 있거나 걸을 때 20~50초마다 0.6~1.4초(37RHHG 16~40초의 80% 빈도),
# 달리는 동안 3~8초마다 35% 확률로 0.5~1.3초, 점프 때 30% 확률로 그 점프 동안, 인사하는 동안. 벌린 정도 0.6.
# 37RHHG 는 0/0.6 으로 바로 바꾸지만 개구리는 메시 턱이 움직여 MOUTH_EASE 초에 걸쳐 여닫는다.
const RUN_MOUTH := 0.35
const JUMP_MOUTH := 0.3
const IDLE_MOUTH := Vector2(20.0, 50.0)
const MOUTH_OPEN := 0.6
const MOUTH_EASE := 0.12
var face_act := 0
var eyes_left := 0.0
var eyes_next := 3.0
var mouth_left := 0.0          # 평소 벌린 입이 남은 시간
var mouth_next := 20.0
var mouth_now := 0.0           # 평소 입 벌린 정도(말할 때는 _chat_step 이 대신 정함)
var blink_next := 2.0
var blink_left := 0.0

# 메뉴바
var popup_menu := RID()
var indicator := -1
var walk_item := -1
var updater: Node
var bubble: Node
var talk_input: Node   # 말 거는 입력칸(talk_input.gd)
var keystore: Node     # Claude API 키(키체인, keystore.gd)
var talk: Node         # Claude 와 말하기(talk.gd)
const TINT_TIME := 0.6           # 옷 색이 다 바뀌는 데 걸리는 시간(초)
var tint_now := -1.0             # 0 보라(Haiku) ~ 1 검정·터키색(Sonnet). -1 은 아직 안 정함(처음엔 바로 맞춘다)
var potion_on := false           # 물약 색을 바꿨는지(아니면 원래 그라데이션). set_potion() 으로 바꾼다
var potion_want := Color(0.98, 0.80, 0.16)  # 바꿀 물약 색
var potion_now := -1.0           # 물약 색 바꾼 정도 0~1(셰이더 bloom). -1 은 처음(바로 맞춤)
var potion_col := Color(0.98, 0.80, 0.16)   # 지금 셰이더에 넣은 물약 색(bloom_to). 다른 색으로 바꿀 때 이 색에서 옮겨 간다
# 모자: set_hat(false) 면 꼭대기부터 반짝이며 녹아 사라지고 set_hat(true) 면 아래부터 다시 생긴다(2026-11-24).
# 물약 색처럼 다른 기능이 상태 표시로 쓸 것이라 저장하지 않는다. 셰이더 hat_off(0 모자 ~ 1 없음).
const HAT_TIME := 0.77         # 처음 1.1초의 70%(2026-11-24 사용자 요청)
const HAT_HEAD := 0.78           # 모자가 없을 때 정수리 높이(모자 끝까지 키 대비)
var hat_on := true
var hat_now := 0.0
var actions: Node      # 개구리가 맥에서 하는 일(Claude 도구, actions.gd)
# 캐릭터 창에서 받은 키만 눌림으로 친다(물리 키 → true). Input.is_physical_key_pressed 는 창과 상관없는 전역이라,
# 입력칸에서 한글을 치면 입력기가 W(ㅈ)·S(ㄴ) 같은 키의 뗌을 먹어 "계속 눌림"으로 남았다 → 입력칸을 닫으면
# 캐릭터가 화면 위로 끝까지 걸어가 멈추고 키도 안 먹었다(2026-11-23). 창이 포커스를 잃거나 입력칸을 열면 비운다.
var held := {}
# 말하는 입(촉새처럼 빠르게 재잘대는 느낌, 2026-11-23 사용자 요청): 대답 글자를 따라 입을 여닫는다.
# 글자 하나 CHAT_SYL 초(그 안에서 빠르게 열었다 닫음, 여는 정도는 글자마다 조금씩 다르게), 띄어쓰기는 짧게 다물고,
# 쉼표·마침표·물음표 등은 조금 길게 다문다. 글이 길면 CHAT_MAX 초까지만.
const CHAT_SYL := Vector2(0.156, 0.216)  # 처음 0.075~0.11 은 너무 빨랐고, 0.13~0.18 에서 20% 더 느리게
const CHAT_OPEN := Vector2(0.65, 1.0)    # 처음 0.35~0.9 는 덜 벌어져 보였음
const CHAT_SPACE := 0.084
const CHAT_PUNCT := 0.36
const CHAT_MAX := 8.0
const DEMO_LINE := "안녕하세요! 저는 맥 화면 위를 걸어 다니는 개구리 마법사예요. 오늘 날씨가 참 좋네요."
var mouth_demo := false       # 확인용 -- --mouth: 위 문장을 되풀이해서 말하는 입
var chat: Array = []          # [시작, 끝, 여는 정도] 목록(clock 기준). 여는 정도 0 은 다문 입
var click_wait := -1.0  # 클릭 뒤 두 번째 클릭을 기다리는 남은 시간. 0 아래로 가면 한 번 클릭
# 두 번째 클릭을 기다리는 시간: 맥 설정(손쉬운 사용 > 포인터 제어 > 이중 클릭 속도, defaults 의 doubleClickThreshold)을 읽는다.
# 처음엔 0.28초로 고정이라, 설정이 0.8초인 맥에서 천천히 두 번 누르면 한 번 클릭 둘(걷기 켜고 끄기)이 됐다(2026-11-25).
const DOUBLE_CLICK_DEFAULT := 0.5
var double_click := DOUBLE_CLICK_DEFAULT
var swallow_release := false   # 누를 때 이미 두 번 클릭으로 처리했으면 그 뗌은 넘긴다

var snapshot := false
var demo := false
var demo_keys: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	snapshot = "--snapshot" in args
	demo = "--demo" in args
	prop_test = "--props" in args
	mouth_demo = "--mouth" in args
	_build_scene()
	if snapshot:
		_take_snapshots()
		return
	_setup_window()
	double_click = _system_double_click()
	get_window().focus_exited.connect(func(): held.clear())
	updater = load("res://updater.gd").new()
	add_child(updater)
	keystore = load("res://keystore.gd").new()
	add_child(keystore)
	keystore.saved.connect(func(_ok, msg): bubble.say(msg))
	_setup_menu()
	bubble = load("res://bubble.gd").new()
	add_child(bubble)
	bubble.setup(screen_scale)
	talk_input = load("res://talk_input.gd").new()
	add_child(talk_input)
	talk_input.setup(screen_scale, bubble.font)
	talk_input.submitted.connect(_on_talk)
	actions = load("res://actions.gd").new()
	add_child(actions)
	actions.timer_fired.connect(func(msg): bubble.say(msg, 10.0))
	talk = load("res://talk.gd").new()
	add_child(talk)
	talk.setup(keystore, actions)
	talk.hat_get = func() -> bool: return hat_on
	talk.hat_set = set_hat
	talk.updater = updater
	talk.body_state = _body_state
	talk.answered.connect(_on_answer)
	# 확인용: -- --ask "문장" 이면 2초 뒤 그 말을 보내고 대답을 찍는다(BUBBLE_DUMP 면 대답 뒤 말풍선 그림).
	var ai := args.find("--ask")
	if ai >= 0 and ai + 1 < args.size():
		get_tree().create_timer(2.0).timeout.connect(_on_talk.bind(args[ai + 1], false))
	if not snapshot and not demo:
		get_tree().create_timer(1.5).timeout.connect(keystore.offer_import)
	if "--wander" in args:
		_set_wander(true)
	# 확인용: -- --say "문장" 이면 1초 뒤 말풍선을 띄운다(아직 말하게 하는 곳은 없다. AI 붙일 때 씀).
	var si := args.find("--say")
	if si >= 0 and si + 1 < args.size():
		get_tree().create_timer(1.0).timeout.connect(bubble.say.bind(args[si + 1], 600.0))
		var dump := OS.get_environment("BUBBLE_DUMP")
		if dump != "":
			get_tree().create_timer(2.0).timeout.connect(func(): bubble.dump(dump))
	# 확인용: FROG_DUMP=경로면 2초 뒤 캐릭터 창 그림을 PNG 로 남긴다.
	var fdump := OS.get_environment("FROG_DUMP")
	if fdump != "":
		get_tree().create_timer(2.0).timeout.connect(func(): get_viewport().get_texture().get_image().save_png(fdump))
	# 확인용: -- --potion "#RRGGBB" 면 1초 뒤 물약 색을 바꾼다(아직 이 표시를 쓰는 기능은 없다).
	var pi_ := args.find("--potion")
	if pi_ >= 0 and pi_ + 1 < args.size():
		get_tree().create_timer(1.0).timeout.connect(set_potion.bind(Color.html(args[pi_ + 1])))
	# 확인용: -- --memory-tidy 면 2초 뒤 기억 정리를 바로 한다(한 달이 안 됐어도).
	if "--memory-tidy" in args:
		get_tree().create_timer(2.0).timeout.connect(func(): talk.memory.tidy(true))
	# 확인용: -- --read [초] 면 1초 뒤 책 읽기를 시작해 그 초(기본 8) 뒤 끝낸다.
	var ri := args.find("--read")
	if ri >= 0:
		var secs := float(args[ri + 1]) if ri + 1 < args.size() and args[ri + 1].is_valid_float() else 8.0
		get_tree().create_timer(1.0).timeout.connect(func(): _start_prop("read"))
		get_tree().create_timer(1.0 + secs).timeout.connect(func(): if prop_act == "read": prop_t = frog.read_end(prop_t))
	# 확인용: -- --hat 이면 3초마다 모자를 없앴다 다시 씌운다.
	if "--hat" in args:
		var ht := Timer.new()
		ht.wait_time = 3.0
		ht.autostart = true
		ht.timeout.connect(func(): set_hat(not hat_on))
		add_child(ht)
	# 확인용: -- --input 이면 1초 뒤 입력칸을 연다(INPUT_TEXT 를 넣어 둠, INPUT_KEY=1 이면 키 넣기 모양). INPUT_DUMP=경로면 2초 뒤 그림을 남긴다.
	if "--input" in args:
		get_tree().create_timer(1.0).timeout.connect(func():
			talk_input.show_input(_feet(), _head_top(), _usable(), OS.get_environment("INPUT_KEY") == "1")
			talk_input.insert_text(OS.get_environment("INPUT_TEXT")))
		var idump := OS.get_environment("INPUT_DUMP")
		if idump != "":
			get_tree().create_timer(2.0).timeout.connect(func(): talk_input.dump(idump))


func _exit_tree() -> void:
	# 메뉴바 아이콘과 메뉴를 직접 풀어 준다. 그냥 두면 엔진이 꺼진 뒤 macOS 가 풀다가 충돌한다(37RHHG 에서 겪음).
	if indicator >= 0:
		DisplayServer.status_indicator_set_menu(indicator, RID())
		DisplayServer.delete_status_indicator(indicator)
		indicator = -1
	if popup_menu.is_valid():
		NativeMenu.free_menu(popup_menu)
		popup_menu = RID()


# ---------------------------------------------------------------- 장면

func _build_scene() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_energy = 0.45
	add_child(sun)

	model = Node3D.new()
	add_child(model)
	frog = load("res://frog/frog.gd").new()
	var r: Dictionary = frog.build(model)
	skel = r["skel"]
	face_mat = r["mat"]
	_cache_bones()

	shadow = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.75, 0.75)
	shadow.mesh = quad
	shadow.rotation_degrees.x = -90
	shadow.position.y = 0.003
	var grad := Gradient.new()
	grad.set_color(0, SHADOW_COL)
	grad.set_color(1, Color(SHADOW_COL, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_texture = tex
	shadow.material_override = sm
	add_child(shadow)

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = WIN_H * k
	var p := deg_to_rad(CAM_PITCH)
	var cam_fwd := Vector3(0, -sin(p), -cos(p))
	var cam_up := Vector3(0, cos(p), -sin(p))
	var target := cam_up * ((FEET_Y - WIN_H * 0.5) * k)
	cam.position = target - cam_fwd * 20.0
	cam_base = cam.position
	cam_lift_dir = cam_up
	add_child(cam)
	cam.look_at(target, Vector3.UP)


func _cache_bones() -> void:
	for b in skel.get_bone_count():
		bones[skel.get_bone_name(b)] = b
	var l := skel.get_bone_global_rest(bones["LeftUpLeg"]).origin
	var r := skel.get_bone_global_rest(bones["RightUpLeg"]).origin
	lat = l - r
	lat.y = 0
	lat = lat.normalized()
	fwd = lat.cross(Vector3.UP)


# 화면에 보이는 키(pt)
func _char_h() -> float:
	return CHAR_H * frog.SIZE


# 점프 높이(pt). 창(WIN_H)은 37RHHG 그대로라 큰 개구리가 높이 뛰면 모자 끝이 잘려서 줄인다.
func _jump_h() -> float:
	return minf(JUMP_H, FEET_Y - _char_h() - 2.0)


# v: 캐릭터 가슴에서 마우스까지(pt, 화면 좌표라 y 는 아래가 +). blend 1 이면 바로 적용.
func _light_set(v: Vector2, blend: float) -> void:
	var d := v.length()
	# 마우스가 아래에 있어도 빛이 턱 밑에서 올라오면 무서워 보여서 아래쪽은 덜 반영한다.
	var want := Vector3(v.x, -v.y if v.y < 0.0 else -v.y * 0.35, maxf(LIGHT_DEPTH, d * 0.45)).normalized()
	light_dir = light_dir.lerp(want, blend).normalized()
	light_near = lerpf(light_near, 1.0 - smoothstep(LIGHT_NEAR, LIGHT_FAR, d), blend)
	var lw := cam.global_basis * light_dir
	sun.look_at_from_position(Vector3.ZERO, -lw, Vector3.UP if absf(lw.y) < 0.98 else Vector3.RIGHT)
	sun.light_energy = lerpf(SUN_FAR, SUN_NEAR, light_near)
	sun.light_color = SUN_TINT
	env.ambient_light_energy = LIGHT_PEAK - sun.light_energy
	env.ambient_light_color = Color.WHITE.lerp(AMB_TINT, light_near)
	var off := Vector2(-lw.x, -lw.z) / maxf(lw.y, 0.45) * SHADOW_SHIFT * lerpf(0.3, 1.0, light_near)
	shadow.position.x = off.x
	shadow.position.z = off.y


func _light_step(dt: float) -> void:
	var chest := _feet() - Vector2(0, lift + _char_h() * 0.5 * px_scale)
	_light_set((Vector2(DisplayServer.mouse_get_position()) - chest) / px_scale, 1.0 - exp(-8.0 * dt))


# ---------------------------------------------------------------- 창과 메뉴

func _setup_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	screen_scale = DisplayServer.screen_get_scale(screen)
	px_scale = screen_scale * zoom
	_apply_size()
	_reset_position()


func _apply_size() -> void:
	get_window().size = Vector2i(roundi(WIN_W * px_scale), roundi(WIN_H * px_scale))
	_apply_hit()


func _apply_hit() -> void:
	var a := HIT_RECT.position * px_scale - Vector2(0, lift)
	var b := HIT_RECT.end * px_scale - Vector2(0, lift)
	a.y = maxf(a.y, 0.0)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]))


# 창을 win_pos 에 둔다. 메뉴바 위로 올라가야 하면 창은 맨 위에 두고 모자란 만큼 캐릭터를 올려 그린다.
func _place() -> void:
	var top := _usable().position.y
	var y := maxf(win_pos.y, top)
	var l := minf(y - win_pos.y, (FEET_Y - _char_h()) * px_scale)
	DisplayServer.window_set_position(Vector2i(roundi(win_pos.x), roundi(y)))
	if absf(l - lift) > 0.01:
		lift = l
		_apply_hit()
	if cam:
		cam.position = cam_base - cam_lift_dir * (lift / px_scale * k)


func _zoom_step(dt: float) -> void:
	# 입력칸에 글을 치는 동안은 z 가 글자라 확대하지 않는다(키 상태는 창과 상관없이 전역이라 직접 막는다).
	var target := ZOOM_MAX if held.has(KEY_Z) and not _typing() else 1.0
	if zoom_k == target and zoom_v == 0.0:
		return
	var n := 4
	var h := minf(dt, 0.05) / n
	for i in n:
		zoom_v += (ZOOM_FREQ * ZOOM_FREQ * (target - zoom_k) - 2.0 * ZOOM_DAMP * ZOOM_FREQ * zoom_v) * h
		zoom_k += zoom_v * h
	if absf(target - zoom_k) < 0.002 and absf(zoom_v) < 0.02:
		zoom_k = target
		zoom_v = 0.0
	_set_zoom(BASE_ZOOM * maxf(zoom_k, 0.5))


func _set_zoom(z: float) -> void:
	if z == zoom:
		return
	var feet := _feet()
	zoom = z
	px_scale = screen_scale * zoom
	_apply_size()
	win_pos = feet - Vector2(WIN_W * 0.5, FEET_Y) * px_scale
	_place()


func _reset_position() -> void:
	var r := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	win_pos = Vector2(r.position.x + r.size.x * 0.5 - WIN_W * px_scale * 0.5,
		r.end.y - FEET_Y * px_scale - 8.0 * px_scale)
	# 확인용: FROG_X=0~1 이면 발 가운데를 화면 폭의 그 비율 자리에(0 왼쪽 끝, 1 오른쪽 끝, 창이 화면 밖으로 나가도 됨).
	var fx := OS.get_environment("FROG_X")
	if fx != "":
		win_pos.x = r.position.x + r.size.x * float(fx) - WIN_W * px_scale * 0.5
	_place()


# 메뉴바 메뉴: 걷기/멈추기 토글(지금이 아닌 쪽을 보여 줌), 업데이트 확인, 종료.
func _setup_menu() -> void:
	var menu := NativeMenu.create_menu()
	popup_menu = menu
	walk_item = NativeMenu.add_item(menu, "", func(_tag): _set_wander(not wander))
	NativeMenu.add_item(menu, "말 걸기…", func(_tag): _open_input())
	NativeMenu.add_item(menu, "Claude 키 넣기…", func(_tag): _ask_key())
	NativeMenu.add_separator(menu)
	NativeMenu.add_item(menu, "업데이트 확인…", func(_tag): updater.check(true))
	NativeMenu.add_separator(menu)
	NativeMenu.add_item(menu, "종료", func(_tag): get_tree().quit())
	_menu_check()
	indicator = DisplayServer.create_status_indicator(_menu_icon(), "37FRHG", func(_b, _p): pass)
	DisplayServer.status_indicator_set_menu(indicator, menu)


func _menu_check() -> void:
	if popup_menu.is_valid() and walk_item >= 0:
		NativeMenu.set_item_text(popup_menu, walk_item, "멈추기" if wander else "걷기")


func _set_wander(on: bool) -> void:
	wander = on
	w_walking = false
	w_timer = 0.4
	_menu_check()


# 캐릭터를 클릭하면(끌지 않고 뗌) 걷기를 켜고 끈다: 돌아다니던 중이면 돌아서서 정면을 보고 멈추고,
# 멈춰 있으면 다시 돌아다닌다. 키보드 조작을 받도록 창에 포커스도 준다.
func _on_click() -> void:
	if wander:
		_set_wander(false)
		target_yaw = 0.0
	else:
		_set_wander(true)
	DisplayServer.window_move_to_foreground()
	get_window().grab_focus()


# 말 모델이 Sonnet 이면 옷 색을 바꾼다(셰이더 tint: 보라 → 검정, 금색 장식 → 터키색). 37RHHG 머리카락 색과 같은 자리.
func _tint_step(dt: float) -> void:
	var want := 1.0 if talk != null and talk.sonnet() else 0.0
	if tint_now == want:
		return
	tint_now = want if tint_now < 0.0 else move_toward(tint_now, want, dt / TINT_TIME)
	for m in frog.mats:
		m.set_shader_parameter("tint", smoothstep(0.0, 1.0, tint_now))


# 허리 유리병 물약 색: 앱의 다른 기능이 지금 상태를 알리는 표시로 쓴다(입력칸·Claude 로 바꾸지 않음, 사용자 결정).
# set_potion(색) 으로 켜고 set_potion(null) 로 원래 색. 저장하지 않는다(상태를 보여 주는 것이라 켤 때마다 정함).
func set_potion(col: Variant) -> void:
	potion_on = col is Color
	if potion_on:
		potion_want = col


# 셰이더 bloom·bloom_to 를 TINT_TIME 에 걸쳐 바꾼다. 켜져 있을 때 다른 색을 고르면 지금 색에서 새 색으로 옮겨 간다.
# 손에 든 병·병 속 공도 같은 재질이라 같이 바뀐다.
func _potion_step(dt: float) -> void:
	var want := 1.0 if potion_on else 0.0
	var col := potion_want
	if potion_now == want and (want == 0.0 or potion_col == col):
		return
	if potion_now < 0.0:
		potion_now = want
		potion_col = col
	else:
		if potion_now <= 0.0:
			potion_col = col           # 꺼져 있다 켜면 새 색으로 바로(원래 색에서 번져 나옴)
		potion_now = move_toward(potion_now, want, dt / TINT_TIME)
		if want > 0.0:
			potion_col = potion_col.lerp(col, minf(1.0, dt / TINT_TIME * 3.0))
			if absf(potion_col.r - col.r) + absf(potion_col.g - col.g) + absf(potion_col.b - col.b) < 0.01:
				potion_col = col
	for m in frog.mats:
		m.set_shader_parameter("bloom", smoothstep(0.0, 1.0, potion_now))
		m.set_shader_parameter("bloom_to", potion_col)


# 말할 때 Claude 에게 알려 주는 지금 몸 상태(talk.gd 시스템 프롬프트 '지금 상태').
func _body_state() -> String:
	var doing := "서 있다"
	if prop_act == "read":
		doing = "책을 꺼내 읽고 있다(대답을 기다리는 동안)"
	elif anim_speed > 2.0:
		doing = "걷고 있다"
	var mode := "혼자 돌아다니기 켬" if wander else "혼자 돌아다니기 끔(멈춰 있음)"
	return "%s, %s" % [doing, mode]


func set_hat(on: bool) -> void:
	hat_on = on


func _hat_step(dt: float) -> void:
	var want := 0.0 if hat_on else 1.0
	if hat_now == want:
		return
	hat_now = move_toward(hat_now, want, dt / HAT_TIME)
	for m in frog.mats:
		m.set_shader_parameter("hat_off", hat_now)


func _typing() -> bool:
	return talk_input != null and talk_input.is_open()


# 말 걸기: 발치에 입력칸을 연다(캐릭터 더블클릭, 캐릭터에 포커스가 있을 때 Enter, 메뉴바 "말 걸기…").
func _open_input() -> void:
	if talk_input == null or snapshot:
		return
	held.clear()
	click_wait = -1.0
	if not keystore.has_key():
		bubble.say("먼저 Claude API 키를 넣어 주세요.")
		_ask_key()
		return
	talk_input.show_input(_feet(), _head_top(), _usable())


# 메뉴바 "Claude 키 넣기…": 입력칸을 키 넣기로 연다(글자 가림).
func _ask_key() -> void:
	if talk_input == null or snapshot:
		return
	held.clear()
	click_wait = -1.0
	talk_input.show_input(_feet(), _head_top(), _usable(), true)


# 입력칸에서 Enter 로 보낸 글. 키 넣기면 키체인으로(키는 로그에 찍지 않는다).
# 말은 talk.gd 가 Claude(Haiku)에 보내고, 기다리는 동안 머리 위에 "…"를 띄운다.
func _on_talk(text: String, key_mode: bool) -> void:
	if key_mode:
		keystore.set_key(text)
		return
	if talk.is_busy():
		return
	bubble.say("…", 40.0)
	talk.reply(text)


# 글자를 따라 입 여닫기 순서를 만든다([시작, 끝, 여는 정도], clock 기준). _chat_step 이 재생한다.
func _chatter(text: String) -> void:
	chat.clear()
	var t := clock
	for ch in text:
		if t - clock > CHAT_MAX:
			break
		var d := 0.0
		var amt := 0.0
		if ch == " " or ch == "\n":
			d = CHAT_SPACE
		elif ch in ",.!?…~;:":
			d = CHAT_PUNCT
		else:
			d = randf_range(CHAT_SYL.x, CHAT_SYL.y)
			amt = randf_range(CHAT_OPEN.x, CHAT_OPEN.y)
		chat.append([t, t + d, amt])
		t += d


# 지금 글자 칸 안에서 사인 한 번(빠르게 열었다 닫음). 다 말하면 다문다.
func _chat_step() -> void:
	if face_mat == null:
		return
	if mouth_demo and (chat.is_empty() or clock > chat[-1][1] + 0.6):
		_chatter(DEMO_LINE)
	while not chat.is_empty() and clock > chat[0][1]:
		chat.pop_front()
	var m := mouth_now
	if not chat.is_empty() and clock >= chat[0][0]:
		var c: Array = chat[0]
		m = c[2] * sin(PI * clampf((clock - c[0]) / (c[1] - c[0]), 0.0, 1.0))
	elif not chat.is_empty():
		m = 0.0
	face_mat.set_shader_parameter("mouth", m)


# 대답을 머리 위에 띄운다. 길수록 조금 더 오래(5~12초).
func _on_answer(text: String) -> void:
	print("frog: ", text)
	_chatter(text)
	bubble.say(text, clampf(4.0 + text.length() * 0.09, 5.0, 12.0))
	var dump := OS.get_environment("BUBBLE_DUMP")
	if dump != "":
		get_tree().create_timer(0.6).timeout.connect(func(): bubble.dump(dump))


func _menu_icon() -> Texture2D:
	# 보라 고깔모자를 쓴 초록 개구리 얼굴(튀어나온 두 눈)
	var n := 36
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var skin := Color(0.46, 0.72, 0.25)
	var hat := Color(0.33, 0.22, 0.55)
	var band := Color(0.85, 0.62, 0.22)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var c := Color(0, 0, 0, 0)
			# 얼굴(넓적한 타원)
			var face := Vector2((p.x - 18) / 13.0, (p.y - 26) / 8.5).length()
			c = c.blend(Color(skin, clampf((1.0 - face) * 9.0, 0, 1)))
			# 눈(흰자 + 눈동자)
			for e in [Vector2(11.5, 19), Vector2(24.5, 19)]:
				var de := p.distance_to(e)
				c = c.blend(Color(skin, clampf(4.6 - de, 0, 1)))
				c = c.blend(Color(Color(0.98, 0.97, 0.92), clampf(3.4 - de, 0, 1)))
				c = c.blend(Color(Color(0.12, 0.08, 0.06), clampf(1.8 - p.distance_to(e + Vector2(0.4, 0.4)), 0, 1)))
			# 모자: 챙(납작한 타원)과 고깔(삼각형)
			var brim := Vector2((p.x - 18) / 15.0, (p.y - 14) / 2.3).length()
			c = c.blend(Color(hat, clampf((1.0 - brim) * 6.0, 0, 1)))
			var cone_w := (p.y - 1.0) / 13.0 * 7.5
			if p.y > 1.0 and p.y < 14.0:
				c = c.blend(Color(hat, clampf(cone_w - absf(p.x - 18.0 - (14.0 - p.y) * 0.25), 0, 1)))
			if p.y > 11.0 and p.y < 13.0:
				c = c.blend(Color(band, clampf(cone_w - absf(p.x - 18.0), 0, 1)))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- 혼자 돌아다니기

func _usable() -> Rect2:
	return Rect2(DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()))


func _feet() -> Vector2:
	return win_pos + Vector2(WIN_W * 0.5, FEET_Y) * px_scale


# 머리(모자) 끝 가운데, 화면 픽셀. 점프하면 같이 올라간다. 모자가 사라지면 정수리로 내려온다.
func _head_top() -> Vector2:
	var h := _char_h() * lerpf(1.0, HAT_HEAD, smoothstep(0.0, 1.0, hat_now))
	return _feet() - Vector2(0, (h + model.position.y / k) * px_scale)


func _pick_dir() -> Vector2:
	# 수직·수평으로만 움직인다. 대체로 옆으로, 가끔 위아래로. 화면 가장자리 가까우면 안쪽으로.
	var r := _usable()
	var rel := (_feet() - r.position) / r.size
	if randf() < 0.25:
		var sy := 1.0 if randf() < 0.5 else -1.0
		if rel.y < 0.35:
			sy = 1.0
		elif rel.y > 0.85:
			sy = -1.0
		return Vector2(0, sy)
	var sx := -1.0 if randf() < 0.5 else 1.0
	if rel.x < 0.2:
		sx = 1.0
	elif rel.x > 0.8:
		sx = -1.0
	return Vector2(sx, 0)


func _wander_step(dt: float) -> void:
	w_timer -= dt
	if w_timer > 0.0:
		return
	if w_walking and randf() < 0.7:
		# 쉬기. 반쯤은 이쪽을 바라본다.
		w_walking = false
		w_timer = randf_range(1.5, 5.0)
		if randf() < 0.5:
			target_yaw = 0.0
	else:
		w_walking = true
		w_timer = randf_range(2.0, 6.0)
		w_run = randf() < 0.25
		w_dir = _pick_dir()


# ---------------------------------------------------------------- 입력과 이동

# 맥의 이중 클릭 간격(초). 못 읽으면 기본값. 너무 짧거나 길면 0.2~0.8 로.
func _system_double_click() -> float:
	var r: Array = preload("res://mail.gd").run_cmd("/usr/bin/defaults", PackedStringArray(["read", "-g", "com.apple.mouse.doubleClickThreshold"]))
	var v := String(r[1]).strip_edges()
	if int(r[0]) == 0 and v.is_valid_float():
		return clampf(float(v), 0.2, 0.8)
	return DOUBLE_CLICK_DEFAULT


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and get_window().has_focus() and not _typing():
			held[event.physical_keycode] = true
		elif not event.pressed:
			held.erase(event.physical_keycode)
	if event is InputEventKey and event.pressed and not event.echo:
		# 방향키를 둘 같이 누르면 사선 대신 나중에 누른 축으로만 간다.
		if event.physical_keycode in [KEY_LEFT, KEY_RIGHT, KEY_A, KEY_D]:
			last_axis = 0
		elif event.physical_keycode in [KEY_UP, KEY_DOWN, KEY_W, KEY_S]:
			last_axis = 1
		if event.physical_keycode == KEY_SPACE and jump_u < 0.0 and not _typing():
			jump_u = 0.0
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not _typing():
			_open_input()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# 맥이 두 번 클릭이라고 알려 주면(시스템 간격) 누르는 순간 바로 말 걸기.
		if event.pressed and event.double_click and click_wait >= 0.0:
			click_wait = -1.0
			swallow_release = true
			_open_input()
		elif not event.pressed and swallow_release:
			swallow_release = false
		elif not event.pressed and dragging:
			var moved := (Vector2(DisplayServer.mouse_get_position()) - drag_mouse).length()
			if moved < CLICK_SLOP * screen_scale:
				# 두 번 누르면 말 걸기, 한 번이면(double_click 초 기다린 뒤) 걷기 켜고 끄기.
				if click_wait >= 0.0:
					click_wait = -1.0
					_open_input()
				else:
					click_wait = double_click
		dragging = event.pressed
		drag_mouse = Vector2(DisplayServer.mouse_get_position())
		drag_win = win_pos
	elif event is InputEventMouseMotion:
		# 버튼을 뗀 이벤트를 놓쳐도 끌기가 남지 않도록 실제 버튼 상태를 본다.
		dragging = dragging and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		if dragging:
			win_pos = drag_win + Vector2(DisplayServer.mouse_get_position()) - drag_mouse
			_place()


func _key(a: Key, b: Key) -> float:
	return 1.0 if held.has(a) or held.has(b) or a in demo_keys else 0.0


# 확인용 자동 조작: 실행 인자 -- --demo
const DEMO := [
	[2.5, [KEY_RIGHT]], [1.5, [KEY_RIGHT, KEY_SHIFT]], [0.4, []], [0.8, [KEY_SPACE]],
	[2.5, [KEY_LEFT]], [1.5, [KEY_UP]], [1.5, [KEY_DOWN, KEY_SHIFT]], [1.0, []],
]


func _demo_step() -> void:
	var total := 0.0
	for s in DEMO:
		total += s[0]
	var tt := fmod(clock, total)
	for s in DEMO:
		if tt < s[0]:
			var was_space := KEY_SPACE in demo_keys
			demo_keys = s[1]
			if KEY_SPACE in demo_keys and not was_space and jump_u < 0.0:
				jump_u = 0.0
			return
		tt -= s[0]


func _process(dt: float) -> void:
	if snapshot:
		return
	clock += dt
	if dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		dragging = false
	if demo:
		_demo_step()
	if click_wait >= 0.0:
		click_wait -= dt
		if click_wait < 0.0:
			_on_click()
	_zoom_step(dt)
	var d := Vector2(_key(KEY_RIGHT, KEY_D) - _key(KEY_LEFT, KEY_A),
		_key(KEY_DOWN, KEY_S) - _key(KEY_UP, KEY_W))
	var shift: bool = held.has(KEY_SHIFT) or KEY_SHIFT in demo_keys
	# 입력칸에 글을 치는 동안은 키가 캐릭터를 움직이지 않고, 돌아다니지도 않고 정면을 본다(37RHHG 처럼).
	if _typing():
		d = Vector2.ZERO
		target_yaw = 0.0
	if d == Vector2.ZERO and not dragging and wander and greet_t < 0.0 and prop_t < 0.0 and not _typing():
		_wander_step(dt)
		if w_walking:
			d = w_dir
			shift = w_run
	if d.x != 0.0 and d.y != 0.0:
		if last_axis == 0:
			d.y = 0.0
		else:
			d.x = 0.0
	var target_speed := 0.0
	if d != Vector2.ZERO and not dragging:
		move_dir = d.normalized()
		# 옆으로 걸을 때 70도 정도만 돌린다(37RHHG 그대로. 얼굴이 조금 보이게).
		target_yaw = atan2(move_dir.x, move_dir.y + 0.35 * absf(move_dir.x))
		target_speed = RUN_SPEED if shift else WALK_SPEED
	speed = move_toward(speed, target_speed, ACCEL * dt)

	var before := win_pos
	win_pos += move_dir * speed * px_scale * dt
	var r := _usable()
	win_pos.x = clampf(win_pos.x, r.position.x - HIT_RECT.position.x * px_scale, r.end.x - HIT_RECT.end.x * px_scale)
	# 머리끝이 화면 위(메뉴바 바로 아래)에 닿을 때까지 올라가게 한다.
	win_pos.y = clampf(win_pos.y, r.position.y - (FEET_Y - _char_h()) * px_scale, r.end.y - FEET_Y * px_scale - 4.0 * px_scale)
	if win_pos != before:
		_place()
	var moved := (win_pos - before).length() / px_scale / maxf(dt, 0.0001)
	anim_speed = lerpf(anim_speed, moved if not dragging else 0.0, 1.0 - exp(-15.0 * dt))

	# 화면 가장자리에 막히면 되돌아가거나 직각으로 꺾는다.
	if wander and w_walking and speed > 30.0 and moved < speed * 0.3:
		w_stuck += dt
		if w_stuck > 0.25:
			w_stuck = 0.0
			w_dir = -w_dir if randf() < 0.5 else _pick_dir()
			if w_dir.dot(move_dir) > 0.5:
				w_dir = -w_dir
	else:
		w_stuck = 0.0

	yaw = lerp_angle(yaw, target_yaw, 1.0 - exp(-10.0 * dt))
	model.rotation.y = yaw

	var j := 0.0
	if jump_u >= 0.0:
		jump_u += dt / JUMP_TIME
		if jump_u >= 1.0:
			jump_u = -1.0
		else:
			j = sin(PI * jump_u)
	var u := maxf(jump_u, 0.0)
	model.position.y = _jump_h() * k * 4.0 * u * (1.0 - u)
	shadow.scale = Vector3.ONE * (1.0 - 0.4 * j)

	var w := clampf(anim_speed / WALK_SPEED, 0.0, 1.0) * (1.0 - j)
	var run := clampf((anim_speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)
	if jump_u < 0.0:
		phase = fposmod(phase + anim_speed / lerpf(WALK_STRIDE, RUN_STRIDE, run) * dt, 1.0)

	# 두리번거리기: 몇 초마다 새 방향을 고르고 천천히 돌린다. 걸을 때는 앞을 본다.
	look_timer -= dt
	if look_timer <= 0.0:
		look_timer = randf_range(1.2, 3.5)
		look_target = 0.0 if randf() < 0.35 else randf_range(-LOOK_MAX, LOOK_MAX)
	look = lerpf(look, look_target * (1.0 - w) * (1.0 - greet) * (0.0 if _typing() else 1.0), 1.0 - exp(-4.0 * dt))
	_greet_step(dt, d != Vector2.ZERO or w > 0.05)
	_read_step(dt, d != Vector2.ZERO or w > 0.05)
	_prop_step(dt, d != Vector2.ZERO or w > 0.05)
	_light_step(dt)
	_tint_step(dt)
	_potion_step(dt)
	_hat_step(dt)
	bubble.follow(_head_top(), _usable(), dt)
	talk_input.follow(_feet(), _head_top(), _usable(), dt)
	_face_step(dt, 2 if jump_u >= 0.0 else (1 if run > 0.5 else 0), w < 0.15)
	_pose(w, run, phase, clock, j)
	_fps_step(dt, w)


# ---------------------------------------------------------------- 인사

func _start_greet() -> void:
	greet_t = 0.0
	greet_eyes = randf() < GREET_EYES
	greet_next = randf_range(GREET_EVERY.x, GREET_EVERY.y)


func _greet_step(dt: float, moving: bool) -> void:
	var front := absf(angle_difference(yaw, 0.0)) < 0.12 and absf(angle_difference(target_yaw, 0.0)) < 0.01
	var still := not moving and not dragging and jump_u < 0.0 and anim_speed < 5.0
	if greet_t < 0.0:
		if still and front:
			greet_next -= dt
			if greet_next <= 0.0:
				_start_greet()
	else:
		if not still and greet_t < GREET_UP + GREET_HOLD:
			# 움직이면 흔들기를 그만두고 내린다.
			greet_t = maxf(GREET_UP + GREET_HOLD, GREET_UP + GREET_HOLD + GREET_DOWN * (1.0 - greet))
		greet_t += dt
		if greet_t >= GREET_UP + GREET_HOLD + GREET_DOWN:
			greet_t = -1.0
	if greet_t < 0.0:
		greet = 0.0
		greet_wave = 0.0
		return
	if greet_t < GREET_UP:
		greet = smoothstep(0.0, GREET_UP, greet_t)
	elif greet_t < GREET_UP + GREET_HOLD:
		greet = 1.0
	else:
		greet = 1.0 - smoothstep(GREET_UP + GREET_HOLD, GREET_UP + GREET_HOLD + GREET_DOWN, greet_t)
	var u := clampf((greet_t - GREET_UP) / GREET_HOLD, 0.0, 1.0)
	greet_wave = sin(TAU * GREET_WAVES * u) * sin(PI * u) ** 0.3 if u > 0.0 and u < 1.0 else 0.0


# ---------------------------------------------------------------- 소품 들어 보이기

func _start_prop(name: String) -> void:
	if prop_t >= 0.0 or greet_t >= 0.0 or jump_u >= 0.0:
		return
	if name == "read":
		frog.read_begin()
	target_yaw = 0.0
	prop_act = name
	prop_t = 0.0


# 대답을 오래 기다리면 책 읽기를 시작하고, 기다림이 끝나면 끝낸다.
func _read_step(dt: float, moving: bool) -> void:
	var waiting: bool = talk != null and talk.is_busy()
	wait_t = wait_t + dt if waiting else 0.0
	if waiting and wait_t > READ_WAIT and prop_t < 0.0 and not moving and not dragging and greet_t < 0.0 and jump_u < 0.0:
		_start_prop("read")
	if not waiting and prop_act == "read" and prop_t >= 0.0:
		prop_t = frog.read_end(prop_t)


func _prop_step(dt: float, moving: bool) -> void:
	if prop_test and prop_t < 0.0 and greet_t < 0.0 and not moving and not dragging and jump_u < 0.0:
		prop_test_next -= dt
		if prop_test_next <= 0.0:
			prop_test_next = 8.0
			_start_prop(["book", "vial"][prop_test_i % 2])
			prop_test_i += 1
	if prop_t < 0.0:
		return
	if moving or dragging or jump_u >= 0.0:
		# 움직이면 손을 거두거나(만지기까지) 소품을 돌려놓는 데로 건너뛴다.
		prop_t = frog.prop_cancel(prop_act, prop_t)
	prop_t += dt
	if prop_t >= frog.prop_len(prop_act):
		prop_t = -1.0
		prop_act = ""


# ---------------------------------------------------------------- 표정(눈만. 입 벌리기는 없음)

func _face_step(dt: float, act: int, idle: bool) -> void:
	eyes_left -= dt
	mouth_left -= dt
	blink_left -= dt
	if act == 0:
		blink_next -= dt / (1.0 if idle else 3.0)
		if blink_next <= 0.0:
			blink_left = randf_range(0.06, 0.09)
			blink_next = blink_left + (0.14 if randf() < 0.1 else randf_range(3.5, 8.0))
	else:
		blink_left = 0.0
		blink_next = randf_range(0.8, 2.0)
	if act != face_act:
		if face_act == 2:
			eyes_left = 0.0
			mouth_left = 0.0
		face_act = act
		if act == 2:
			if randf() < JUMP_EYES:
				eyes_left = JUMP_TIME
			if randf() < JUMP_MOUTH:
				mouth_left = JUMP_TIME
		elif act == 0:
			eyes_left = 0.0
			mouth_left = 0.0
			mouth_next = randf_range(IDLE_MOUTH.x, IDLE_MOUTH.y)
	if act == 0:
		mouth_next -= dt
		if mouth_next <= 0.0:
			mouth_next = randf_range(IDLE_MOUTH.x, IDLE_MOUTH.y)
			mouth_left = randf_range(0.6, 1.4)
	if act == 1:
		eyes_next -= dt
		mouth_next -= dt
		if eyes_next <= 0.0:
			eyes_next = randf_range(3.0, 8.0)
			if randf() < RUN_EYES:
				eyes_left = randf_range(0.5, 1.3)
		if mouth_next <= 0.0:
			mouth_next = randf_range(3.0, 8.0)
			if randf() < RUN_MOUTH:
				mouth_left = randf_range(0.5, 1.3)
	var want := MOUTH_OPEN if (mouth_left > 0.0 or greet > 0.2) else 0.0
	mouth_now = move_toward(mouth_now, want, dt * MOUTH_OPEN / MOUTH_EASE)
	var closed := eyes_left > 0.0 or blink_left > 0.0 or (greet > 0.2 and greet_eyes)
	if face_mat:
		face_mat.set_shader_parameter("blink", 1.0 if closed else 0.0)
		_chat_step()


# ---------------------------------------------------------------- 동작

func _pose(w: float, run: float, ph: float, t: float, j: float) -> void:
	frog.pose(skel, ph, w, run, t, j, 0.0, greet, greet_wave, look, prop_act, prop_t)
	_face_update()


func _face_update() -> void:
	# 셰이더가 쓰는 머리 좌표계: 원점은 머리 뼈, 축은 캐릭터의 왼쪽·위·앞.
	if face_mat == null:
		return
	var hi: int = bones["Head"]
	var gp := skel.get_bone_global_pose(hi)
	var rot := gp.basis.orthonormalized() * skel.get_bone_global_rest(hi).basis.orthonormalized().inverse()
	var sk := skel.global_transform
	var b := sk.basis.orthonormalized() * rot
	var frame := Transform3D(Basis(b * lat, b * Vector3.UP, b * fwd), sk * gp.origin)
	face_mat.set_shader_parameter("head_inv", Projection(frame.affine_inverse()))


func _fps_step(dt: float, w: float) -> void:
	var active := w > 0.02 or anim_speed > 2.0 or jump_u >= 0.0 or dragging or zoom_v != 0.0 \
		or zoom_k != 1.0 or greet_t >= 0.0 or prop_t >= 0.0 or absf(angle_difference(yaw, target_yaw)) > 0.01 \
		or not chat.is_empty() or mouth_demo
	calm_t = 0.0 if active else calm_t + dt
	var want := FPS_IDLE if calm_t > FPS_CALM else FPS_ACTIVE
	if Engine.max_fps != want:
		Engine.max_fps = want


# ---------------------------------------------------------------- 확인용 스냅샷

# godot --path app -- --snapshot : 자세 몇 개를 app/snap/*.png 로 저장하고 끝낸다.
func _take_snapshots() -> void:
	var sc := float(OS.get_environment("SNAP_SCALE")) if OS.get_environment("SNAP_SCALE") != "" else 2.0
	get_window().size = Vector2i(roundi(WIN_W * sc), roundi(WIN_H * sc))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://snap"))
	# [이름, 몸 방향, 걷기, 달리기, 걸음 주기, 점프, 인사(손 흔들기), 눈 감음, 소품(이름), 소품 동작 초(없으면 -1)]
	var shots := [
		["idle_front", 0.0, 0.0, 0.0, 0.0, 0.0, null, 0.0, "", -1.0],
		["walk_side", PI * 0.5, 1.0, 0.0, 0.0, 0.0, null, 0.0, "", -1.0],
		["run_side", PI * 0.5, 1.0, 1.0, 0.25, 0.0, null, 0.0, "", -1.0],
		["walk_back", PI, 1.0, 0.0, 0.0, 0.0, null, 0.0, "", -1.0],
		["jump_front", -0.4, 0.0, 0.0, 0.0, 1.0, null, 0.0, "", -1.0],
		["greet", 0.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, "", -1.0],
		["blink", 0.0, 0.0, 0.0, 0.0, 0.0, null, 1.0, "", -1.0],
		["book_touch", 0.0, 0.0, 0.0, 0.0, 0.0, null, 0.0, "book", 0.8],
		["book_hold", 0.0, 0.0, 0.0, 0.0, 0.0, null, 0.0, "book", 2.4],
		["vial_touch", 0.0, 0.0, 0.0, 0.0, 0.0, null, 0.0, "vial", 0.7],
		["vial_hold", 0.0, 0.0, 0.0, 0.0, 0.0, null, 0.0, "vial", 2.3],
	]
	if OS.get_environment("HAT") != "":
		for m in frog.mats:
			m.set_shader_parameter("hat_off", float(OS.get_environment("HAT")))
			m.set_shader_parameter("hat_debug", OS.get_environment("HAT_DEBUG") == "1")
	if OS.get_environment("MOUTH") != "":
		face_mat.set_shader_parameter("mouth", float(OS.get_environment("MOUTH")))
		face_mat.set_shader_parameter("mouth_debug", OS.get_environment("MOUTH_DEBUG") == "1")
	var pc := OS.get_environment("POTION_COLOR")
	if pc != "":
		for m in frog.mats:
			m.set_shader_parameter("bloom", 1.0)
			m.set_shader_parameter("bloom_to", Color.html(pc))
			m.set_shader_parameter("bloom_debug", OS.get_environment("POTION_DEBUG") == "1")
	# READ 가 있으면 책 읽기 확인용: 정면·3/4 로 꺼내기 → 펼치기 → 넘기기(u) 몇 순간. READ=시각들(쉼표)이면 그 시각만 정면.
	if OS.get_environment("READ") != "":
		frog.read_begin()
		var times := [1.0, 1.6, 1.95, 2.1, 2.1 + 1.4 * 0.15, 2.1 + 1.4 * 0.4, 2.1 + 1.4 * 0.6, 2.1 + 1.4 * 0.72]
		if OS.get_environment("READ") != "1":
			times = Array(OS.get_environment("READ").split(",")).map(func(x): return float(x))
		var yaw := float(OS.get_environment("READ_YAW")) if OS.get_environment("READ_YAW") != "" else 0.0
		if OS.get_environment("READ_STOP") != "":
			frog.read_stop = float(OS.get_environment("READ_STOP"))
		shots = []
		for i in times.size():
			shots.append(["read_%02d" % i, yaw, 0.0, 0.0, 0.0, 0.0, null, 0.0, "read", times[i]])
	# HAT 이 있으면 모자 확인용으로 서 있는 모습만 정면·3/4·옆·뒤에서
	if OS.get_environment("HAT") != "":
		shots = [["hat_front", 0.0, 0.0, 0.0, 0.0, 0.0, null, 0.0, "", -1.0],
			["hat_34", -0.6, 0.0, 0.0, 0.0, 0.0, null, 0.0, "", -1.0],
			["hat_side", -PI * 0.5, 0.0, 0.0, 0.0, 0.0, null, 0.0, "", -1.0],
			["hat_back", PI * 0.8, 0.0, 0.0, 0.0, 0.0, null, 0.0, "", -1.0],
			["hat_back2", PI, 0.0, 0.0, 0.0, 0.0, null, 0.0, "", -1.0]]
	# MOUTH 가 있으면 입 확인용으로 서 있는 모습만 정면·3/4·옆에서
	if OS.get_environment("MOUTH") != "":
		shots = [["mouth_front", 0.0, 0.0, 0.0, 0.0, 0.0, null, 0.0, "", -1.0],
			["mouth_34", -0.6, 0.0, 0.0, 0.0, 0.0, null, 0.0, "", -1.0],
			["mouth_side", -PI * 0.5, 0.0, 0.0, 0.0, 0.0, null, 0.0, "", -1.0]]
	for s in shots:
		model.rotation.y = s[1]
		model.position.y = _jump_h() * k * s[5]
		greet = 0.0 if s[6] == null else 1.0
		greet_wave = 0.0 if s[6] == null else s[6]
		face_mat.set_shader_parameter("blink", s[7])
		prop_act = s[8]
		prop_t = s[9]
		_pose(s[2], s[3], s[4], 0.0, s[5])
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://snap/%s.png" % s[0])
	get_tree().quit()
