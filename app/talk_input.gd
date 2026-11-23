extends Node
## 말 거는 입력칸. 37RHHG 처럼 캐릭터 발치에 뜨는 따로 된 창(테두리 없음·투명·항상 위)이고,
## 그림은 bubble/froginput.png(936×295, 그림자 포함), 그 안 연보라 네모에 LineEdit 를 얹는다.
## 키보드를 받아야 하므로 말풍선 창과 달리 포커스를 받는다(unfocusable·mouse_passthrough 끔).
## Enter → submitted(글), Esc 나 아무것도 안 친 채 IDLE_CLOSE 초 → 닫힘. 글을 치기 시작하면 Esc·Enter 전까지 안 닫힌다.
## 키 넣기(key_mode): 글자를 ●로 가리고, 키를 복사하러 다른 창에 다녀올 수 있게 시간·포커스로 닫지 않는다(Esc·Enter 만).

signal submitted(text: String, key_mode: bool)
signal closed

const IMG_W := 936.0
const IMG_H := 295.0
# 글 자리(그림 픽셀). 연보라 네모는 x 104~832·y 66~186, 왼쪽 아래 물약 병(~x 120)·오른쪽 잉크병(~x 810)을 피한다.
const TEXT_L := 132.0
const TEXT_R := 800.0
const TEXT_CY := 126.0         # 네모 세로 가운데
# LineEdit 는 글꼴 높이(아래 여백 큰 카카오 빅 산스)를 가운데에 두므로 한글 글자가 아래로 처진다 → 이만큼(글자 크기 대비) 올린다.
const TEXT_NUDGE := -0.375
const BODY_TOP := 36.0         # 그림의 불투명한 몸통(그 아래는 그림자)
const BODY_BOTTOM := 216.0

const WIDTH := 208.0           # 화면 폭(pt, 그림자 포함). 처음 260 의 80%(2026-11-23)
const FONT_SIZE := 10            # 처음 13 의 80%
const TEXT_COL := Color(0.30, 0.12, 0.52)          # 진한 보라(2026-11-23 사용자 요청)
const HINT_COL := Color(0.30, 0.12, 0.52, 0.40)
const SEL_COL := Color(0.55, 0.40, 0.85, 0.35)
const HINT := "개구리에게 말 걸기…"
const KEY_HINT := "Claude 키를 붙여 넣고 Enter"
const MAX_LEN := 300
const IDLE_CLOSE := 5.0        # 아무것도 안 친 채 이만큼 지나면 닫힘
const GAP := 14.0              # 발과 입력칸 몸통 사이(pt). 처음 2 에서 12pt 더 내림
const FADE := 0.12

var win: Window
var art: TextureRect
var edit: LineEdit
var s := WIDTH / IMG_W
var size_pt := Vector2.ZERO
var screen_scale := 1.0
var open := false
var idle := 0.0
var alpha := 0.0
var key_mode := false


func setup(scale: float, font: Font) -> void:
	screen_scale = scale
	var img := _load_image()
	if img == null:
		push_warning("입력칸 그림 없음: 입력칸은 꺼짐")
		return
	img.generate_mipmaps()
	size_pt = Vector2(WIDTH, IMG_H * s)

	win = Window.new()
	win.borderless = true
	win.transparent = true
	win.transparent_bg = true
	win.always_on_top = true
	win.unresizable = true
	win.visible = false
	win.content_scale_factor = screen_scale
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	win.size = Vector2i(ceili(size_pt.x * screen_scale), ceili(size_pt.y * screen_scale))
	win.focus_exited.connect(_on_focus_out)
	win.close_requested.connect(close)
	add_child(win)

	art = TextureRect.new()
	art.texture = ImageTexture.create_from_image(img)
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.size = size_pt
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.add_child(art)

	edit = LineEdit.new()
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "focus", "read_only"]:
		edit.add_theme_stylebox_override(st, empty)
	edit.add_theme_font_override("font", font)
	edit.add_theme_font_size_override("font_size", FONT_SIZE)
	edit.add_theme_color_override("font_color", TEXT_COL)
	edit.add_theme_color_override("caret_color", TEXT_COL)
	edit.add_theme_color_override("font_placeholder_color", HINT_COL)
	edit.add_theme_color_override("selection_color", SEL_COL)
	edit.add_theme_color_override("font_selected_color", TEXT_COL)
	edit.add_theme_constant_override("caret_width", 1)
	edit.placeholder_text = HINT
	edit.max_length = MAX_LEN
	edit.context_menu_enabled = false
	edit.caret_blink = true
	var h := font.get_height(FONT_SIZE) + 6.0
	edit.position = Vector2(TEXT_L * s, TEXT_CY * s - h * 0.5 + TEXT_NUDGE * FONT_SIZE)
	edit.size = Vector2((TEXT_R - TEXT_L) * s, h)
	edit.text_submitted.connect(_on_submit)
	edit.text_changed.connect(func(_t): idle = 0.0)
	edit.gui_input.connect(_on_key)
	win.add_child(edit)


func _load_image() -> Image:
	for p in [OS.get_executable_path().get_base_dir().path_join("../Resources/bubble/froginput.png"),
			ProjectSettings.globalize_path("res://bubble/froginput.png")]:
		if FileAccess.file_exists(p):
			var img := Image.load_from_file(p)
			if img:
				img.convert(Image.FORMAT_RGBA8)
				return img
	return null


func show_input(feet: Vector2, head: Vector2, usable: Rect2, for_key := false) -> void:
	if win == null:
		return
	key_mode = for_key
	edit.secret = for_key
	edit.placeholder_text = KEY_HINT if for_key else HINT
	edit.max_length = 400 if for_key else MAX_LEN
	edit.text = ""
	idle = 0.0
	open = true
	if not win.visible:
		alpha = 0.0
	follow(feet, head, usable, 0.0)
	win.visible = true
	DisplayServer.window_move_to_foreground(win.get_window_id())
	win.grab_focus()
	edit.grab_focus()


func close() -> void:
	if not open:
		return
	open = false
	edit.release_focus()
	closed.emit()


func is_open() -> bool:
	return open


func _on_submit(t: String) -> void:
	t = t.strip_edges()
	edit.text = ""   # 키가 창에 남지 않게
	close()
	if t != "":
		submitted.emit(t, key_mode)


func _on_key(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		edit.accept_event()
		edit.text = ""
		close()


# 다른 데를 눌러 포커스를 잃으면, 아무것도 안 쳤을 때만 닫는다(치던 글은 남김).
func _on_focus_out() -> void:
	if open and not key_mode and edit.text == "" and not edit.has_ime_text():
		close()


# feet: 발 가운데, head: 머리끝 가운데(화면 픽셀). 발 아래에 두고, 자리가 없으면 머리 위로.
func follow(feet: Vector2, head: Vector2, usable: Rect2, dt: float) -> void:
	if win == null or not win.visible:
		return
	if open and not key_mode and edit.text == "" and not edit.has_ime_text():
		idle += dt
		if idle >= IDLE_CLOSE:
			close()
	alpha = move_toward(alpha, 1.0 if open else 0.0, dt / FADE if dt > 0.0 else 0.0)
	if not open and alpha <= 0.0:
		win.visible = false
		return
	art.modulate.a = alpha
	edit.modulate.a = alpha
	var wpx := Vector2(win.size)
	var k := s * screen_scale
	var pos := Vector2(feet.x - wpx.x * 0.5, feet.y + GAP * screen_scale - BODY_TOP * k)
	if pos.y + BODY_BOTTOM * k > usable.end.y:
		pos.y = head.y - GAP * screen_scale - BODY_BOTTOM * k
	pos.x = clampf(pos.x, usable.position.x, usable.end.x - wpx.x)
	pos.y = clampf(pos.y, usable.position.y - BODY_TOP * k, usable.end.y - BODY_BOTTOM * k)
	win.position = Vector2i(roundi(pos.x), roundi(pos.y))


# 확인용: 지금 입력칸 창 그림을 PNG 로 남긴다.
func dump(path: String) -> void:
	if win and win.visible:
		win.get_texture().get_image().save_png(path)
		print("input at ", win.position, " size ", win.size)
