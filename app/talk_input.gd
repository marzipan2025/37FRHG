extends Node
## 말 거는 입력칸. 37RHHG 처럼 캐릭터 발치에 뜨는 따로 된 창(테두리 없음·투명·항상 위)이고,
## 그림은 bubble/froginput.png(936×295, 그림자 포함), 그 안 연보라 네모에 글칸을 얹는다.
## 여러 줄(2026-11-25 사용자 요청): 폭은 그대로, 글이 길면 줄을 바꾸고 창이 아래로 늘어난다(MAX_LINES 줄까지, 그 뒤는 칸 안에서
## 위로 밀림). 그림은 가운데 띠(BAND_TOP~BAND_BOT)만 세로로 늘이고 아래 조각(물약 병·잉크병)은 아래에 붙인다. 오른쪽 깃펜은
## 위 테두리 모서리까지 걸쳐 있어서, 그 자리(x XR~, y ~YB)를 왼쪽 끝을 좌우로 뒤집은 깨끗한 테두리로 바꾸고 깃펜만 떼어
## (색으로 찾고 넓힘, _feather_mask) 잉크병과 같이 아래로 옮겨 얹는다(_compose).
## 키 넣기는 글자를 가려야 해서 한 줄 LineEdit(edit) 그대로, 말 걸기는 여러 줄 TextEdit(memo).
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
# 여러 줄로 늘이기(그림 픽셀, 잰 값): 왼쪽 별 장식은 y 87 까지, 반짝이 점은 y 106, 물약 병 코르크는 y 120 부터.
const BAND_TOP := 90.0
const BAND_BOT := 100.0
const XR := 820                # 이 x 부터 오른쪽 끝은 깃펜 자리라 왼쪽 끝을 뒤집어 깨끗한 테두리로(위 YB 행까지)
const YB := 115                # 이 행부터 아래(잉크병·깃펜 아래쪽)는 원래 그림 그대로
const MIRROR := 936            # 좌우 대칭 축: 몸통이 x 49~887 → x ↔ 936 - x
const MAX_LINES := 4
const MEMO_NUDGE := 0.0        # 글칸 세로 보정(pt). 그림으로 재서 맞춘다
# 사진 붙여넣기(2026-11-25 사용자 요청): ⌘V 때 클립보드에 그림이 있으면 받아 두고(긴 변 IMG_MAX 로 줄임)
# 글칸 오른쪽 끝에 작은 그림(THUMB)을 보인다. 보낼 때 main.gd 가 take_image() 로 가져가 talk.gd 에 넘긴다.
# 글 없이 그림만 보내도 된다. 글이 빈 채 지우기(⌫)를 누르면 그림을 뺀다.
const IMG_MAX := 1024
const THUMB := Vector2(30.0, 22.0)   # pt

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
var edit: LineEdit             # 키 넣기(한 줄, 가림)
var memo: TextEdit             # 말 걸기(여러 줄)
var src: Image                 # 원본 그림
var clean: Image               # 깃펜 자리를 깨끗한 테두리로 바꾼 그림
var feather: Image             # 떼어 낸 깃펜(위 YB 행, 나머지 투명)
var grow := 0                  # 지금 늘인 높이(그림 픽셀)
var lines := 1
var line_h := 0.0              # 글 한 줄 높이(pt)
var pending_img: Image = null  # 붙여 넣은 그림(보내기 전)
var thumb: TextureRect
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
	src = img
	_prepare_art()
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
	art.texture = ImageTexture.create_from_image(_compose(0))
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

	memo = TextEdit.new()
	for st in ["normal", "focus", "read_only"]:
		memo.add_theme_stylebox_override(st, empty)
	memo.add_theme_font_override("font", font)
	memo.add_theme_font_size_override("font_size", FONT_SIZE)
	memo.add_theme_color_override("font_color", TEXT_COL)
	memo.add_theme_color_override("caret_color", TEXT_COL)
	memo.add_theme_color_override("font_placeholder_color", HINT_COL)
	memo.add_theme_color_override("selection_color", SEL_COL)
	memo.add_theme_color_override("font_selected_color", TEXT_COL)
	memo.add_theme_constant_override("caret_width", 1)
	# 줄 간격: 말풍선(bubble.gd LEADING)처럼 글꼴 높이+4pt 의 절반만 띄운다(카카오 빅 산스는 글꼴 높이가 커서 그대로면 성김).
	var fh := font.get_height(FONT_SIZE)
	memo.add_theme_constant_override("line_spacing", roundi(FONT_SIZE + (fh + 4.0 - FONT_SIZE) * 0.5 - fh))
	memo.placeholder_text = HINT
	memo.context_menu_enabled = false
	memo.caret_blink = true
	# 줄바꿈은 TextEdit 에 맡긴다(한글은 낱말 가운데서도 끊긴다. 띄어쓰기 단위로 직접 나누던 것은 2026-11-25 사용자 요청으로 뺌).
	memo.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	memo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 스크롤 막대는 보이지 않게(4줄 넘으면 칸 안에서 밀리기만). 막대 폭만큼 글 자리가 줄지 않게 모양을 비운다.
	for sb in [memo.get_v_scroll_bar(), memo.get_h_scroll_bar()]:
		for st in ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed"]:
			sb.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		sb.modulate.a = 0.0
	memo.text_changed.connect(_on_memo_changed)
	memo.gui_input.connect(_on_memo_key)
	win.add_child(memo)
	line_h = memo.get_line_height()
	thumb = TextureRect.new()
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.visible = false
	win.add_child(thumb)
	_layout()


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
	edit.secret = true
	edit.placeholder_text = KEY_HINT
	edit.max_length = 400
	edit.text = ""
	edit.visible = for_key
	memo.visible = not for_key
	memo.text = ""
	set_image(null)
	_set_lines(1)
	idle = 0.0
	open = true
	if not win.visible:
		alpha = 0.0
	follow(feet, head, usable, 0.0)
	win.visible = true
	DisplayServer.window_move_to_foreground(win.get_window_id())
	win.grab_focus()
	if for_key:
		edit.grab_focus()
	else:
		memo.grab_focus()


func close() -> void:
	if not open:
		return
	open = false
	edit.release_focus()
	memo.release_focus()
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
	if open and not key_mode and memo.text == "" and pending_img == null and not memo.has_ime_text():
		close()


# feet: 발 가운데, head: 머리끝 가운데(화면 픽셀). 발 아래에 두고, 자리가 없으면 머리 위로.
func follow(feet: Vector2, head: Vector2, usable: Rect2, dt: float) -> void:
	if win == null or not win.visible:
		return
	if open and not key_mode and memo.text == "" and pending_img == null and not memo.has_ime_text():
		idle += dt
		if idle >= IDLE_CLOSE:
			close()
	alpha = move_toward(alpha, 1.0 if open else 0.0, dt / FADE if dt > 0.0 else 0.0)
	if not open and alpha <= 0.0:
		win.visible = false
		return
	art.modulate.a = alpha
	edit.modulate.a = alpha
	memo.modulate.a = alpha
	thumb.modulate.a = alpha
	var wpx := Vector2(win.size)
	var k := s * screen_scale
	var bottom := BODY_BOTTOM + grow   # 늘어난 몸통 아래 끝
	# 발 아래에서는 위 끝을 두고 아래로 늘어난다. 아래 자리가 없어 머리 위로 가면 아래 끝을 두고 위로 늘어난다.
	var pos := Vector2(feet.x - wpx.x * 0.5, feet.y + GAP * screen_scale - BODY_TOP * k)
	if pos.y + bottom * k > usable.end.y:
		pos.y = head.y - GAP * screen_scale - bottom * k
	pos.x = clampf(pos.x, usable.position.x, usable.end.x - wpx.x)
	pos.y = clampf(pos.y, usable.position.y - BODY_TOP * k, usable.end.y - bottom * k)
	win.position = Vector2i(roundi(pos.x), roundi(pos.y))


func _on_memo_changed() -> void:
	idle = 0.0
	if memo.text.length() > MAX_LEN:
		memo.text = memo.text.left(MAX_LEN)
		memo.set_caret_line(memo.get_line_count() - 1)
		memo.set_caret_column(memo.get_line(memo.get_line_count() - 1).length())
	_set_lines(memo.get_total_visible_line_count())
	# 4줄을 넘으면 칸 크기가 정해진 뒤 커서 줄이 보이게 민다(안 하면 마지막 줄이 칸 밑에 숨었다).
	memo.call_deferred("adjust_viewport_to_caret")


# Enter 는 보내기(Shift+Enter 는 줄바꿈). 한글 조합 중이면 입력기가 먼저 글자를 확정하게 둔다.
func _on_memo_key(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	if e.keycode == KEY_ESCAPE:
		memo.accept_event()
		memo.text = ""
		set_image(null)
		close()
	elif (e.keycode == KEY_V or e.physical_keycode == KEY_V) and (e.meta_pressed or e.ctrl_pressed) and DisplayServer.clipboard_has_image():
		# 그림 붙여넣기(글은 TextEdit 가 원래대로 붙인다). 한글 입력 중에도 V 키 자리로 본다.
		memo.accept_event()
		var img := DisplayServer.clipboard_get_image()
		if img != null and not img.is_empty():
			set_image(img)
			idle = 0.0
	elif e.keycode == KEY_BACKSPACE and memo.text == "" and pending_img != null:
		memo.accept_event()
		set_image(null)
	elif (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER) and e.shift_pressed:
		memo.accept_event()   # 줄바꿈 글자는 받지 않는다(한 문단으로 보냄)
	elif (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER) and not memo.has_ime_text():
		memo.accept_event()
		var t := memo.text.replace("\n", " ").strip_edges()
		memo.text = ""
		close()
		if t != "" or pending_img != null:
			submitted.emit(t, false)


# 붙여 넣은 그림을 정한다(null 이면 뺌). 긴 변을 IMG_MAX 로 줄여 둔다.
func set_image(img: Image) -> void:
	if img != null:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
		var k := float(IMG_MAX) / maxf(img.get_width(), img.get_height())
		if k < 1.0:
			img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		var t := img.duplicate()
		t.generate_mipmaps()
		thumb.texture = ImageTexture.create_from_image(t)
	pending_img = img
	if thumb:
		thumb.visible = img != null
	if memo:
		_layout()


# 보낼 그림을 가져간다(가져가면 비움).
func take_image() -> Image:
	var img := pending_img
	set_image(null)
	return img


# 확인용(main.gd INPUT_TEXT): 지금 글칸에 글을 넣는다.
func insert_text(t: String) -> void:
	if key_mode:
		edit.insert_text_at_caret(t)
	else:
		memo.insert_text_at_caret(t)
		_on_memo_changed()


func _set_lines(n: int) -> void:
	n = clampi(n, 1, MAX_LINES)
	if n == lines and win.size.y > 0:
		return
	lines = n
	grow = roundi((n - 1) * line_h / s)
	art.texture = ImageTexture.create_from_image(_compose(grow))
	_layout()


# 창·그림·글칸 크기와 자리(pt). 첫 줄 가운데는 늘 연보라 네모의 원래 가운데(TEXT_CY), 늘어난 만큼 아래로.
func _layout() -> void:
	size_pt = Vector2(WIDTH, (IMG_H + grow) * s)
	art.size = size_pt
	win.size = Vector2i(ceili(size_pt.x * screen_scale), ceili(size_pt.y * screen_scale))
	var top := TEXT_CY * s - line_h * 0.5 + MEMO_NUDGE
	memo.position = Vector2(TEXT_L * s, top)
	var w := (TEXT_R - TEXT_L) * s
	if pending_img != null:
		# 그림은 글칸 오른쪽 끝, 첫 줄 높이 가운데. 그만큼 글 폭을 줄인다.
		w -= THUMB.x + 4.0
		thumb.position = Vector2(TEXT_R * s - THUMB.x, TEXT_CY * s - THUMB.y * 0.5)
		thumb.size = THUMB
	memo.size = Vector2(w, line_h * lines + 1.0)


# 깨끗한 테두리(clean)와 떼어 낸 깃펜(feather)을 만든다(처음 한 번).
func _prepare_art() -> void:
	clean = src.duplicate()
	for y in YB:
		for x in range(XR, int(IMG_W)):
			var mx := MIRROR - x
			clean.set_pixel(x, y, src.get_pixel(mx, y) if mx >= 0 else Color(0, 0, 0, 0))
	var m := _feather_mask()
	feather = Image.create(int(IMG_W), YB, false, Image.FORMAT_RGBA8)
	for y in YB:
		for x in range(XR, int(IMG_W)):
			if m.get_pixel(x, y).r > 0.5:
				feather.set_pixel(x, y, src.get_pixel(x, y))


# 깃펜 점: 연보라(색상 0.62~0.82, 채도 > 0.22, 명도 > 0.42) 점을 찾아 닫기(가운데 깃대 메움)·넓히기(진한 테두리선 포함).
func _feather_mask() -> Image:
	var w := int(IMG_W)
	var a := Image.create(w, YB, false, Image.FORMAT_L8)
	for y in range(20, YB):
		for x in range(840, w):
			var c := src.get_pixel(x, y)
			if c.a > 0.5 and c.h > 0.62 and c.h < 0.82 and c.s > 0.22 and c.v > 0.42:
				a.set_pixel(x, y, Color.WHITE)
	a = _morph(a, 4, true)
	a = _morph(a, 4, false)
	a = _morph(a, 3, true)
	# 아래 YB 행에 닿은 깃펜은 원래 그림(아래 조각)과 이어진다.
	return a


# 네모 커널 넓히기(grow)·줄이기.
func _morph(img: Image, r: int, grow_it: bool) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_L8)
	for y in h:
		for x in range(XR, w):
			var hit := not grow_it
			for dy in range(-r, r + 1):
				var yy := y + dy
				if yy < 0 or yy >= h:
					if not grow_it and yy < h:
						pass
					continue
				for dx in range(-r, r + 1):
					var xx := clampi(x + dx, 0, w - 1)
					var on := img.get_pixel(xx, yy).r > 0.5
					if grow_it and on:
						hit = true
						break
					if not grow_it and not on:
						hit = false
						break
				if hit == grow_it:
					break
			if hit:
				out.set_pixel(x, y, Color.WHITE)
	return out


# 늘인 그림: 위 조각 · 늘인 띠 · 아래 조각(아래에 붙임) + 깃펜(아래로 같이 옮김).
func _compose(d: int) -> Image:
	var w := int(IMG_W)
	var h := int(IMG_H) + d
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bt := int(BAND_TOP)
	var bb := int(BAND_BOT)
	out.blit_rect(clean, Rect2i(0, 0, w, bt), Vector2i.ZERO)
	var band := clean.get_region(Rect2i(0, bt, w, bb - bt))
	band.resize(w, bb - bt + d, Image.INTERPOLATE_BILINEAR)
	out.blit_rect(band, Rect2i(0, 0, w, bb - bt + d), Vector2i(0, bt))
	out.blit_rect(clean, Rect2i(0, bb, w, int(IMG_H) - bb), Vector2i(0, bb + d))
	out.blend_rect(feather, Rect2i(0, 0, w, YB), Vector2i(0, d))
	out.generate_mipmaps()
	return out


# 확인용: 지금 입력칸 창 그림을 PNG 로 남긴다.
func dump(path: String) -> void:
	if win and win.visible:
		win.get_texture().get_image().save_png(path)
		print("input at ", win.position, " size ", win.size, " lines ", lines, " line_h ", line_h, " caret ", memo.get_caret_line(), ":", memo.get_caret_column(), " text [", memo.text, "] ime ", memo.has_ime_text(),
			" font_h ", memo.get_theme_font("font").get_height(FONT_SIZE), " spacing ", memo.get_theme_constant("line_spacing"), " memo ", memo.position, memo.size)
