extends Node
## 머리 위 말풍선. 37RHHG 처럼 캐릭터 창과 따로 떠 있는 투명 창에 그린다(캐릭터 창은 캐릭터 크기뿐이라).
## 37RHHG 는 네이티브 도우미(bubble.swift)가 그리지만 여기는 그림 한 장과 글자뿐이라 Godot 창 하나로 한다.
## 그림은 bubble/bubblefrog.png(936×633, 그림자 포함). 폭은 고정, 높이는 글 줄 수에 맞춰 가운데 띠만 늘린다(9-slice 의 세로만).
## 글꼴은 카카오 빅 산스 레귤러(저장소에 넣지 않음, 아래 FONT_PATHS 순서로 찾고 없으면 시스템 글꼴),
## 글자 색은 그림의 금색 테두리 선에서 읽는다.
## 좌표: 창은 화면 픽셀, 안쪽 컨트롤은 pt(content_scale_factor = 화면 배율).

const IMG_W := 936.0
const IMG_H := 633.0
const CUT_TOP := 130.0         # 여기까지(별 장식 포함)는 그대로
const CUT_BOTTOM := 415.0      # 여기부터(아래 점·꼬리·그림자)는 그대로. 사이 띠만 세로로 늘인다
# 글이 들어갈 자리(그림 픽셀). 안쪽 금선(x 74·861) 안, 별(위 모서리)·점(아래 모서리)을 피함.
# 좌우는 처음(104·832)보다 4pt 씩 더 띄운다(2026-11-23 사용자 요청).
const SIDE_PAD := 4.0          # pt
const TEXT_L := 104.0 + SIDE_PAD * IMG_W / 260.0
const TEXT_R := 832.0 - SIDE_PAD * IMG_W / 260.0
# 위아래는 네모(몸통 y 35~486, 안쪽 금선 61·460)의 가운데(260.5)를 기준으로 똑같이 띄운다.
# 띠를 늘여도 금선 사이 가운데에 오도록 TEXT_TOP - 61 = 460 - TEXT_BOTTOM.
const TEXT_TOP := 100.0
const TEXT_BOTTOM := 421.0
const TIP := Vector2(468.0, 572.0)   # 꼬리 끝
const GOLD_AT := Vector2i(200, 472)  # 아래 금선 한가운데. 글자 색을 여기서 읽는다

const WIDTH := 260.0           # 화면 폭(pt, 그림자 포함). 글 폭은 약 194pt
const FONT_SIZE := 12          # 처음 14 에서 2pt 줄임(2026-11-23)
const LEADING := 0.5           # 줄 사이(줄 높이 - 글자 크기)를 처음(글꼴 높이 + 4pt)의 이만큼으로
const TEXT_SAT_UP := 0.10      # 글자 색: 금선 색에서 채도 +10%p
const TEXT_VAL_UP := 0.10      # 명도 +10%p
const SPACE_EM := 0.33         # 띄어쓰기 폭(글자 크기 대비)
const MAX_LINES := 6
const GAP := 2.0               # 꼬리 끝과 머리끝 사이(pt)
const SHOW_TIME := 5.0
const FADE := 0.25

const FONT_NAME := "KakaoBigSans-Regular.ttf"

var win: Window
var art: Control
var label: Label
var tex: Texture2D
var font: Font
var gold := Color(0.85, 0.67, 0.45)
var s := WIDTH / IMG_W         # 그림 픽셀 → pt
var size_pt := Vector2.ZERO
var screen_scale := 1.0
var left := 0.0                # 남은 표시 시간(초). 0 이하면 숨김
var alpha := 0.0
var shown := ""
var line_gap := 0.0            # Label 의 line_spacing(pt). 글꼴 높이로 정한다


func setup(scale: float) -> void:
	screen_scale = scale
	var img := _load_image()
	if img == null:
		push_warning("말풍선 그림 없음: 말풍선은 꺼짐")
		return
	gold = img.get_pixelv(GOLD_AT)
	# 글자는 금선보다 명도·채도를 10%p 씩 올려 또렷하게(2026-11-23 사용자 요청)
	gold = Color.from_hsv(gold.h, minf(gold.s + TEXT_SAT_UP, 1.0), minf(gold.v + TEXT_VAL_UP, 1.0))
	img.generate_mipmaps()
	tex = ImageTexture.create_from_image(img)
	font = _load_font()
	# 카카오 빅 산스는 띄어쓰기가 아주 좁아 어절이 붙어 보인다 → 공백을 글자 크기의 SPACE_EM 폭까지 넓힌다.
	var sp := font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var fv := FontVariation.new()
	fv.base_font = font
	fv.set_spacing(TextServer.SPACING_SPACE, maxi(0, roundi(FONT_SIZE * SPACE_EM - sp)))
	font = fv
	var fh := font.get_height(FONT_SIZE)
	line_gap = roundf(FONT_SIZE + (fh + 4.0 - FONT_SIZE) * LEADING - fh)

	win = Window.new()
	win.borderless = true
	win.transparent = true
	win.transparent_bg = true
	win.always_on_top = true
	win.unfocusable = true
	win.mouse_passthrough = true
	win.unresizable = true
	win.visible = false
	win.content_scale_factor = screen_scale
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	add_child(win)

	art = Control.new()
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.draw.connect(_draw_art)
	win.add_child(art)

	label = Label.new()
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", gold)
	label.add_theme_constant_override("line_spacing", int(line_gap))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF   # 줄은 _wrap 이 낱말 단위로 나눈다
	win.add_child(label)


func _load_image() -> Image:
	# 내보낸 앱은 Contents/Resources/bubble, 개발 실행은 app/bubble(.gdignore 라 Godot 가 임포트하지 않음).
	for p in [OS.get_executable_path().get_base_dir().path_join("../Resources/bubble/bubblefrog.png"),
			ProjectSettings.globalize_path("res://bubble/bubblefrog.png")]:
		if FileAccess.file_exists(p):
			var img := Image.load_from_file(p)
			if img:
				img.convert(Image.FORMAT_RGBA8)
				return img
	return null


func _load_font() -> Font:
	var paths := [OS.get_executable_path().get_base_dir().path_join("../Resources/fonts/" + FONT_NAME),
		OS.get_environment("HOME").path_join("Library/Fonts/" + FONT_NAME),
		"/Library/Fonts/" + FONT_NAME,
		"/Applications/37RHHG.app/Contents/Resources/fonts/" + FONT_NAME]
	for p in paths:
		if FileAccess.file_exists(p):
			var f := FontFile.new()
			if f.load_dynamic_font(p) == OK:
				return f
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Kakao Big Sans", "Apple SD Gothic Neo"])
	return sf


# text 를 secs 초 동안 띄운다. 그동안 follow() 로 머리를 따라간다.
func say(text: String, secs := SHOW_TIME) -> void:
	if win == null:
		return
	shown = text
	var lines := _wrap(text)
	label.text = "\n".join(lines)
	var line_h := font.get_height(FONT_SIZE) + line_gap
	var text_h := lines.size() * line_h - line_gap
	# 가운데 띠를 늘려 글 높이를 맞춘다(최소는 그림의 위·아래 조각만 붙인 높이).
	var fixed_text := (CUT_TOP - TEXT_TOP) + (TEXT_BOTTOM - CUT_BOTTOM)   # 띠가 0일 때 글 자리(그림 픽셀)
	var mid := maxf(0.0, text_h / s - fixed_text + 16.0)
	size_pt = Vector2(WIDTH, (CUT_TOP + mid + (IMG_H - CUT_BOTTOM)) * s)
	art.size = size_pt
	art.queue_redraw()
	var top := TEXT_TOP * s
	var bottom := size_pt.y - (IMG_H - TEXT_BOTTOM) * s
	label.position = Vector2(TEXT_L * s, top)
	label.size = Vector2((TEXT_R - TEXT_L) * s, bottom - top)
	win.size = Vector2i(ceili(size_pt.x * screen_scale), ceili(size_pt.y * screen_scale))
	left = secs
	if not win.visible:
		alpha = 0.0
		win.visible = true


func hide_now() -> void:
	left = 0.0


func is_showing() -> bool:
	return win != null and win.visible


# 한국어도 낱말(띄어쓰기) 단위로 줄을 나눈다. 한 낱말이 한 줄보다 길면 글자 단위로 자른다.
func _wrap(text: String) -> PackedStringArray:
	var max_w := (TEXT_R - TEXT_L) * s
	var out := PackedStringArray()
	for para in text.split("\n"):
		var line := ""
		for word in para.split(" ", false):
			var t := word if line == "" else line + " " + word
			if _w(t) <= max_w:
				line = t
				continue
			if line != "":
				out.append(line)
			line = ""
			while _w(word) > max_w:
				var n := word.length()
				while n > 1 and _w(word.substr(0, n)) > max_w:
					n -= 1
				out.append(word.substr(0, n))
				word = word.substr(n)
			line = word
		out.append(line)
	if out.size() > MAX_LINES:
		out = out.slice(0, MAX_LINES)
		out[MAX_LINES - 1] = out[MAX_LINES - 1].left(-1) + "…"
	return out


func _w(t: String) -> float:
	return font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x


# 위 조각 · 늘인 가운데 띠 · 아래 조각. 폭은 그대로 줄인다.
func _draw_art() -> void:
	var mid_h := size_pt.y - (CUT_TOP + IMG_H - CUT_BOTTOM) * s
	art.draw_texture_rect_region(tex, Rect2(0, 0, WIDTH, CUT_TOP * s), Rect2(0, 0, IMG_W, CUT_TOP))
	if mid_h > 0.0:
		# 띠가 원래보다 짧으면 가운데에서 그만큼만 잘라 쓴다(줄여 넣으면 밉맵이 흐려져 옆 그림자에 줄이 생겼다).
		var src_h := minf(CUT_BOTTOM - CUT_TOP, mid_h / s)
		var src_y := (CUT_TOP + CUT_BOTTOM - src_h) * 0.5
		art.draw_texture_rect_region(tex, Rect2(0, CUT_TOP * s, WIDTH, mid_h),
			Rect2(0, src_y, IMG_W, src_h))
	art.draw_texture_rect_region(tex, Rect2(0, CUT_TOP * s + mid_h, WIDTH, (IMG_H - CUT_BOTTOM) * s),
		Rect2(0, CUT_BOTTOM, IMG_W, IMG_H - CUT_BOTTOM))


# head: 머리끝 가운데(화면 픽셀). usable: 화면에서 쓸 수 있는 곳(픽셀).
func follow(head: Vector2, usable: Rect2, dt: float) -> void:
	if win == null or not win.visible:
		return
	left -= dt
	alpha = move_toward(alpha, 1.0 if left > 0.0 else 0.0, dt / FADE)
	if alpha <= 0.0 and left <= 0.0:
		win.visible = false
		shown = ""
		return
	art.modulate.a = alpha
	label.modulate.a = alpha
	var tip := Vector2(TIP.x * s, size_pt.y - (IMG_H - TIP.y) * s) * screen_scale
	var pos := head - Vector2(0, GAP * screen_scale) - tip
	var wpx := Vector2(win.size)
	pos.x = clampf(pos.x, usable.position.x, usable.end.x - wpx.x)
	pos.y = clampf(pos.y, usable.position.y, usable.end.y - wpx.y)
	win.position = Vector2i(roundi(pos.x), roundi(pos.y))


# 확인용: 지금 말풍선 창 그림을 PNG 로 남긴다.
func dump(path: String) -> void:
	if win and win.visible:
		win.get_texture().get_image().save_png(path)
		print("bubble at ", win.position, " size ", win.size)
