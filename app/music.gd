extends Node
## 음악(Claude 도구, actions.gd 가 run() 에서 넘겨줌, 2026-11-25 사용자 요청: "음악 앱을 켜서 어떤 노래를 틀어 달라").
## 맥 기본 '음악' 앱만 다룬다(이 맥에 다른 음악 앱 없음).
## - 보관함: AppleScript 로 곡(곡 이름, 가수로 거름)·재생목록을 찾아 바로 재생. 재생·일시정지·다음·이전·멈춤·볼륨, 지금 곡.
## - 보관함에 없는 곡: 음악 앱 스크립트는 Apple Music 카탈로그를 찾거나 틀지 못한다. 그래서 애플 공개 검색
##   (itunes.apple.com/search, 키 없음. 한국 스토어는 결과 0건이라 미국 → 일본 순)으로 곡을 찾아 음악 앱에
##   music://music.apple.com/kr/album/<앨범>?i=<곡> 페이지를 열고, 화면 도우미(native/ax.swift → frhgax)가 그 곡 줄을
##   찾아 누른다(줄 안 재생 버튼, 없으면 줄을 두 번 클릭). 곡 줄은 곡 길이(m:ss) 글자로 찾는다: 한국 페이지의 곡 이름이
##   검색 결과(영어 이름)와 다를 수 있어서. 그 뒤 지금 곡을 읽어 맞는지 본다. 안 되면 "페이지를 열어 뒀으니 재생만 눌러 달라".
##   화면 도우미는 손쉬운 사용 권한이 37FRHG 에 있어야 한다. 찾은 화면 구조는 user://music_ax.txt (고칠 때 씀).
## 확인: open -n -a /Applications/37FRHG.app --args -- --music-tool play_music '{"title":"밤편지","artist":"아이유"}'
##   → user://music_tool.txt

const Mail := preload("res://mail.gd")   # run_cmd(인자를 셸 없이 그대로 넘김)

const TOOLS := [
	{"name": "play_music",
		"description": "맥 '음악' 앱에서 노래나 재생목록을 튼다. 먼저 사용자의 음악 보관함에서 찾고, 없으면 Apple Music 에서 그 곡을 찾아 곡 페이지를 열고 재생 버튼을 누른다(몇 초 걸림, 안 되면 페이지만 열림). 사용자가 '아이유 밤편지 틀어 줘'처럼 곡을 틀어 달라고 하면 title 과 artist 를 나눠 넣는다. 재생목록 이름을 말하면 playlist.",
		"input_schema": {"type": "object", "properties": {
			"title": {"type": "string", "description": "곡 이름(원래 표기 그대로, 예: 밤편지)."},
			"artist": {"type": "string", "description": "가수 이름(알면). 예: 아이유"},
			"playlist": {"type": "string", "description": "보관함 재생목록 이름(재생목록을 틀 때만)."}}}},
	{"name": "music_control",
		"description": "음악 앱 재생 조작: resume(다시 재생), pause(일시정지), next(다음 곡), previous(이전 곡), stop(멈춤). volume(0~100)을 주면 음악 앱 볼륨도 바꾼다.",
		"input_schema": {"type": "object", "properties": {
			"action": {"type": "string", "enum": ["resume", "pause", "next", "previous", "stop", "none"]},
			"volume": {"type": "integer", "description": "0~100. 볼륨만 바꿀 때는 action none."}}, "required": ["action"]}},
	{"name": "now_playing",
		"description": "음악 앱에서 지금 나오는 곡(이름·가수·앨범, 재생 중인지)을 알아본다.",
		"input_schema": {"type": "object", "properties": {}}},
]

const NO_AUTO := "음악 앱을 제어할 권한이 없어요. 시스템 설정 > 개인정보 보호 및 보안 > 자동화에서 37FRHG 의 '음악'을 켜 달라고 하세요."
const NO_AX := "곡 페이지는 열었지만 버튼을 누를 권한이 없어요. 시스템 설정 > 개인정보 보호 및 보안 > 기기 제어 및 데이터 접근(예전 이름 손쉬운 사용)에서 37FRHG 를 켜 주면 다음부터 제가 눌러요. 지금은 재생 버튼만 눌러 주세요."

const LIB := """on run argv
	set t to item 1 of argv
	set a to item 2 of argv
	tell application "Music"
		set pick to missing value
		if t is not "" then
			repeat with x in (search library playlist 1 for t only songs)
				if a is "" or (artist of x) contains a then
					set pick to contents of x
					exit repeat
				end if
			end repeat
		end if
		if pick is missing value and a is not "" then
			repeat with x in (search library playlist 1 for a only songs)
				if t is "" or (name of x) contains t then
					set pick to contents of x
					exit repeat
				end if
			end repeat
		end if
		if pick is missing value then return "NONE"
		play pick
		return "TRACK" & tab & (name of pick) & tab & (artist of pick)
	end tell
end run"""

const PLAYLIST := """on run argv
	set q to item 1 of argv
	tell application "Music"
		set ps to (every user playlist whose name contains q)
		if (count of ps) is 0 then return "NONE"
		play item 1 of ps
		return "PLAYLIST" & tab & (name of item 1 of ps)
	end tell
end run"""

const CONTROL := """on run argv
	set act to item 1 of argv
	set vol to item 2 of argv
	tell application "Music"
		if act is "pause" then
			pause
		else if act is "resume" then
			play
		else if act is "next" then
			next track
		else if act is "previous" then
			previous track
		else if act is "stop" then
			stop
		end if
		if vol is not "" then set sound volume to (vol as integer)
		return (player state as text) & tab & (sound volume as text)
	end tell
end run"""

const NOW := """if application "Music" is not running then return "OFF"
tell application "Music"
	if player state is stopped then return "STOPPED"
	set t to current track
	return (player state as text) & tab & (name of t) & tab & (artist of t) & tab & (album of t)
end tell"""

var http: HTTPRequest


func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	var args := OS.get_cmdline_user_args()
	var t := args.find("--music-tool")
	if t < 0 or t + 1 >= args.size():
		return
	var inp = JSON.parse_string(args[t + 2]) if t + 2 < args.size() else {}
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = await run(args[t + 1], inp if inp is Dictionary else {})
	var f := FileAccess.open("user://music_tool.txt", FileAccess.WRITE)
	f.store_string("%d ms error=%s\n%s" % [Time.get_ticks_msec() - t0, res.error, res.text])
	f.close()
	get_tree().quit()


func has(tool: String) -> bool:
	return tool in ["play_music", "music_control", "now_playing"]


func run(tool: String, input: Dictionary) -> Dictionary:
	match tool:
		"play_music":
			return await _play(String(input.get("title", "")).strip_edges(), String(input.get("artist", "")).strip_edges(),
				String(input.get("playlist", "")).strip_edges())
		"music_control":
			var vol := ""
			if input.get("volume") != null:
				vol = str(clampi(int(input.get("volume")), 0, 100))
			var act := String(input.get("action", "none"))
			var r := await _osa(CONTROL, [act, vol])
			if not r.ok:
				return _fail(r.out)
			var f := String(r.out).split("\t")
			return {"text": "음악 앱: %s%s." % [_state(f[0]), (", 볼륨 " + f[1]) if vol != "" and f.size() > 1 else ""], "error": false}
		"now_playing":
			return await _now()
	return {"text": "모르는 도구: " + tool, "error": true}


func _play(title: String, artist: String, playlist: String) -> Dictionary:
	if playlist != "":
		var p := await _osa(PLAYLIST, [playlist])
		if not p.ok:
			return _fail(p.out)
		if String(p.out).begins_with("PLAYLIST"):
			return {"text": "보관함 재생목록 '%s'을(를) 틀었어요." % String(p.out).split("\t")[1], "error": false}
		if title == "" and artist == "":
			return {"text": "보관함에서 '%s' 재생목록을 찾지 못했어요." % playlist, "error": true}
	if title == "" and artist == "":
		return {"text": "무엇을 틀지 곡 이름이나 가수를 알려 주세요.", "error": true}
	var r := await _osa(LIB, [title, artist])
	if not r.ok:
		return _fail(r.out)
	if String(r.out).begins_with("TRACK"):
		var f := String(r.out).split("\t")
		return {"text": "보관함에서 '%s'(%s)을(를) 틀었어요." % [f[1], f[2] if f.size() > 2 else ""], "error": false}
	return await _catalog(title, artist)


# 보관함에 없는 곡: 공개 검색 → 곡 페이지 열기 → 화면 도우미로 누르기 → 맞는 곡이 나오는지 확인.
func _catalog(title: String, artist: String) -> Dictionary:
	var term := (title + " " + artist).strip_edges()
	var hit: Dictionary = {}
	for country in ["US", "JP"]:
		var d = await _fetch("https://itunes.apple.com/search?term=%s&country=%s&entity=song&limit=8" % [term.uri_encode(), country])
		if d is Dictionary and int(d.get("resultCount", 0)) > 0:
			hit = d.results[0]
			break
	if hit.is_empty():
		return {"text": "보관함에도 Apple Music 검색에도 '%s'이(가) 없어요." % term, "error": true}
	var name := String(hit.get("trackName", title))
	var who := String(hit.get("artistName", artist))
	var url := "music://music.apple.com/kr/album/%d?i=%d" % [int(hit.get("collectionId", 0)), int(hit.get("trackId", 0))]
	var o: Array = await _run("/usr/bin/open", PackedStringArray([url]))
	if int(o[0]) != 0:
		return {"text": "음악 앱에서 곡 페이지를 열지 못했어요.", "error": true}
	var ms := int(hit.get("trackTimeMillis", 0))
	var dur := "%d:%02d" % [ms / 60000, (ms / 1000) % 60]
	var dump := ProjectSettings.globalize_path("user://music_ax.txt")
	var a: Array = await _run(_helper(), PackedStringArray(["music-play", dump, "10", dur,
		str(int(hit.get("trackNumber", 0))), str(int(hit.get("trackCount", 0))), name]))
	print("music ax ", a[0], " ", String(a[1]).strip_edges().left(200))
	if int(a[0]) == 2:
		return {"text": NO_AX + " (곡: %s - %s)" % [who, name], "error": true}
	var res = JSON.parse_string(String(a[1]).strip_edges())
	var how := String(res.get("result", "")) if res is Dictionary else ""
	if how == "" or how == "not-found" or how == "no-app":
		return {"text": "음악 앱에 '%s'(%s) 곡 페이지를 열어 뒀어요. 재생 버튼을 찾지 못했으니 눌러 주세요." % [name, who], "error": true}
	# 눌렀으면 지금 곡을 읽어 확인한다(곡 이름이 한국어로 다를 수 있어 길이·상태도 본다).
	await get_tree().create_timer(1.5).timeout
	var now := await _osa(NOW, [])
	var f := String(now.out).split("\t")
	if now.ok and f.size() >= 2 and f[0] == "playing":
		return {"text": "Apple Music 에서 '%s'(%s)을(를) 틀었어요(보관함에는 없는 곡). 지금 나오는 곡: %s - %s." % [name, who, f[2] if f.size() > 2 else "", f[1]], "error": false}
	return {"text": "음악 앱에 '%s'(%s) 곡 페이지를 열고 눌러 봤는데 재생이 확인되지 않아요. 재생 버튼을 눌러 주세요." % [name, who], "error": true}


func _now() -> Dictionary:
	var r := await _osa(NOW, [])
	if not r.ok:
		return _fail(r.out)
	var out := String(r.out)
	if out == "OFF":
		return {"text": "음악 앱이 꺼져 있어요.", "error": false}
	if out == "STOPPED":
		return {"text": "음악 앱에서 아무것도 나오지 않아요.", "error": false}
	var f := out.split("\t")
	return {"text": "%s: %s - %s (앨범 %s)" % [_state(f[0]), f[2] if f.size() > 2 else "", f[1] if f.size() > 1 else "",
		f[3] if f.size() > 3 else ""], "error": false}


func _state(s: String) -> String:
	return {"playing": "재생 중", "paused": "일시정지", "stopped": "멈춤"}.get(s, s)


func _fail(out: String) -> Dictionary:
	if out.contains("-1743") or out.to_lower().contains("not authorized") or out.contains("허용되지"):
		return {"text": NO_AUTO, "error": true}
	if out.contains("-1712") or out.to_lower().contains("timed out"):
		return {"text": "음악 앱이 대답하지 않아요(시간 초과).", "error": true}
	return {"text": "음악 앱을 다루지 못했어요.", "error": true}


func _helper() -> String:
	var p := OS.get_executable_path().get_base_dir().path_join("frhgax")
	if FileAccess.file_exists(p):
		return p
	return ProjectSettings.globalize_path("res://").path_join("../build/frhgax").simplify_path()


func _osa(script: String, args: Array) -> Dictionary:
	var argv := PackedStringArray(["-e", script])
	for a in args:
		argv.append(str(a))
	var r: Array = await _run("/usr/bin/osascript", argv)
	var text := String(r[1]).strip_edges()
	if int(r[0]) != 0:
		print("music osascript 실패 ", r[0], " ", text.left(200))
	return {"ok": int(r[0]) == 0, "out": text}


# 스레드에서 실행하고 기다린다(개구리가 멈추지 않게). [종료 코드, 글]
func _run(path: String, args: PackedStringArray) -> Array:
	var th := Thread.new()
	th.start(func() -> Array: return Mail.run_cmd(path, args))
	while th.is_alive():
		await get_tree().process_frame
	return th.wait_to_finish()


func _fetch(url: String) -> Variant:
	if http.request(url) != OK:
		return null
	var r: Array = await http.request_completed
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		return null
	return JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
