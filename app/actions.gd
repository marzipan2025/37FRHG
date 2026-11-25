extends Node
## 개구리가 맥에서 하는 일(Claude 도구). talk.gd 가 TOOLS 를 Claude 에 보내고, Claude 가 고른 도구를
## run(이름, 입력)으로 실행해 결과 글을 Claude 에 돌려준다(Claude 가 결과를 보고 말로 대답한다).
## 새 도구는 TOOLS 에 정의를 넣고 run() 에 갈래를 더하면 된다.
## 되돌리기 어려운 일(문자 보내기 등)은 나중에 "사용자 확인" 단계를 거치게 할 것(지금 도구는 모두 바로 해도 되는 것).

signal timer_fired(message: String)    # 타이머 시간이 됨(main 이 말풍선으로 알림)

const TIMERS := "user://timers.json"
const UA := "37FRHG/1.0 (macOS desktop pet)"
# 날씨: Open-Meteo(키 없음). 37RHHG 집 네트워크에서 api.open-meteo.com 이 안 된 적이 있어 met.no 로 돌아간다.
const GEO_IP := "https://get.geojs.io/v1/ip/geo.json"
const GEOCODE := "https://geocoding-api.open-meteo.com/v1/search?count=1&language=ko&name="
const FORECAST := "https://api.open-meteo.com/v1/forecast?latitude=%f&longitude=%f&timezone=auto&forecast_days=2&current=temperature_2m,apparent_temperature,weather_code,precipitation,wind_speed_10m,relative_humidity_2m&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
const METNO := "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=%.4f&lon=%.4f"

const TOOLS := [
	{"name": "get_weather",
		"description": "지금 날씨와 오늘·내일 예보(기온, 하늘, 비 올 확률)를 가져온다. 사용자가 장소를 말하지 않았으면 모두 비워 두면 사용자의 대략적인 위치(인터넷 주소)로 찾는다. 장소를 말했으면 place 와 함께 네가 아는 그곳의 대략적인 위도·경도(lat, lon)를 꼭 넣어라(지명 검색이 한국 지명에 약하다).",
		"input_schema": {"type": "object", "properties": {
			"place": {"type": "string", "description": "도시나 동네 이름(예: 부산 해운대). 없으면 비워 둔다."},
			"lat": {"type": "number", "description": "place 의 위도(예: 35.16)."},
			"lon": {"type": "number", "description": "place 의 경도(예: 129.16)."}}}},
	{"name": "open_app",
		"description": "맥 앱을 이름으로 연다(예: Safari, Notes, Calendar, Music, Finder, Figma).",
		"input_schema": {"type": "object", "properties": {
			"name": {"type": "string", "description": "앱 이름(영문 이름이 확실하다)."}}, "required": ["name"]}},
	{"name": "list_open_apps",
		"description": "지금 맥에서 열려 있는(Dock 에 떠 있는) 앱의 개수와 이름, 맨 앞에 있는(지금 쓰고 있는) 앱, 화면에 보이는 순서, 숨겨 둔 앱을 알아본다. '지금 뭐 쓰고 있어?', '맨 앞 앱이 뭐야?'에도 쓴다. 이 개구리 앱(37FRHG)은 뺀다.",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "open_url",
		"description": "웹 주소(http/https)를 기본 브라우저로 연다. 검색으로 찾은 페이지나 검색 결과 페이지를 사용자에게 보여 줄 때 쓴다.",
		"input_schema": {"type": "object", "properties": {
			"url": {"type": "string"}}, "required": ["url"]}},
	{"name": "set_timer",
		"description": "타이머를 건다. 시간이 되면 개구리가 말풍선으로 알리고, action 을 주면 그때 그 일도 한다(앱 열기·웹 주소 열기). minutes(몇 분 뒤) 또는 at(오늘/내일 HH:MM) 중 하나를 준다.",
		"input_schema": {"type": "object", "properties": {
			"minutes": {"type": "number", "description": "몇 분 뒤(소수 가능, 예: 0.5 는 30초)."},
			"at": {"type": "string", "description": "24시간제 HH:MM. 지난 시각이면 내일."},
			"message": {"type": "string", "description": "시간이 되면 할 말(짧게)."},
			"action": {"type": "string", "enum": ["none", "open_app", "open_url"]},
			"target": {"type": "string", "description": "action 의 대상(앱 이름이나 웹 주소)."}},
			"required": ["message"]}},
	{"name": "list_timers",
		"description": "걸어 둔 타이머 목록(번호, 남은 시간, 할 말, 할 일).",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "cancel_timer",
		"description": "타이머를 끈다. id 는 list_timers 의 번호. all 이 true 면 모두.",
		"input_schema": {"type": "object", "properties": {
			"id": {"type": "integer"}, "all": {"type": "boolean"}}}},
]

var http: HTTPRequest
var mail: Node                         # 메일 읽기(mail.gd)
var calendar: Node                     # 캘린더 일정(calendar.gd)
var music: Node                        # 음악 앱(music.gd)
var turn := 0                          # 사용자 말 수(talk.gd 가 올림). 캘린더 바꾸기·지우기 확인에 쓴다
var notify: Node                       # 알림 센터 알림 읽기(notify.gd)
var timers: Array = []                 # {id, at(유닉스 초), message, action, target}
var next_id := 1
var here := {}                         # IP 로 찾은 위치 {lat, lon, name, t}
var tick := 0.0


func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	mail = load("res://mail.gd").new()
	add_child(mail)
	calendar = load("res://calendar.gd").new()
	add_child(calendar)
	music = load("res://music.gd").new()
	add_child(music)
	notify = load("res://notify.gd").new()
	notify.mail = mail
	add_child(notify)
	if FileAccess.file_exists(TIMERS):
		var d = JSON.parse_string(FileAccess.get_file_as_string(TIMERS))
		if d is Dictionary:
			timers = d.get("timers", [])
			next_id = int(d.get("next_id", 1))


func _save_timers() -> void:
	var f := FileAccess.open(TIMERS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"timers": timers, "next_id": next_id}))


# 1초마다 시간이 된 타이머를 알린다. 앱이 꺼져 있던 사이 지난 것은 켤 때 "놓쳤다"고 알린다.
func _process(dt: float) -> void:
	tick += dt
	if tick < 1.0:
		return
	tick = 0.0
	var now := Time.get_unix_time_from_system()
	for t in timers.duplicate():
		if float(t.at) <= now:
			timers.erase(t)
			_save_timers()
			var late := now - float(t.at) > 120.0
			var msg := String(t.message)
			if late:
				msg = "(놓친 타이머) " + msg
			else:
				_do(String(t.get("action", "none")), String(t.get("target", "")))
			timer_fired.emit(msg)


# Claude 에 보내는 도구 정의 전부(여기 것 + 메일).
func tools() -> Array:
	return TOOLS + mail.TOOLS + calendar.TOOLS + notify.TOOLS + music.TOOLS


# 도구 실행. {"text": 결과 글, "error": bool}
func run(tool: String, input: Dictionary) -> Dictionary:
	if tool.ends_with("_mail"):
		return await mail.run(tool, input)
	if calendar.has(tool):
		return await calendar.run(tool, input)
	if music.has(tool):
		return await music.run(tool, input)
	if tool == "list_notifications":
		return await notify.run(tool, input)
	match tool:
		"get_weather":
			return await _weather(String(input.get("place", "")).strip_edges(), input.get("lat"), input.get("lon"))
		"open_app":
			return _open_app(String(input.get("name", "")))
		"open_url":
			return _open_url(String(input.get("url", "")))
		"list_open_apps":
			return await _open_apps()
		"set_timer":
			return _set_timer(input)
		"list_timers":
			return {"text": _list(), "error": false}
		"cancel_timer":
			return _cancel(input)
	return {"text": "모르는 도구: " + tool, "error": true}


func _do(action: String, target: String) -> Dictionary:
	if action == "open_app":
		return _open_app(target)
	if action == "open_url":
		return _open_url(target)
	return {"text": "", "error": false}


func _open_app(app_name: String) -> Dictionary:
	app_name = app_name.strip_edges()
	if app_name == "" or app_name.contains("/"):
		return {"text": "앱 이름이 비었거나 이상해요.", "error": true}
	# 셸을 거치지 않게(OS.execute 에 출력 배열을 주면 셸 명령 줄이 되어 이름 속 $(…) 가 실행될 수 있다).
	var code: int = mail.run_cmd("/usr/bin/open", PackedStringArray(["-a", app_name]))[0]
	if code != 0:
		return {"text": "'%s' 앱을 찾지 못했어요." % app_name, "error": true}
	return {"text": "'%s' 앱을 열었어요." % app_name, "error": false}


# 열린 앱(2026-11-24): lsappinfo(권한 필요 없음). `list` 에서 type="Foreground"(Dock 에 뜨는 보통 앱)만 고르고,
# `visibleProcessList`(앞에서 뒤 순서, 숨긴 앱은 빠짐)로 순서·맨 앞·숨김을 정한다. 이 앱(37FRHG)은 뺀다.
func _open_apps() -> Dictionary:
	var r: Array = await mail._run("/usr/bin/lsappinfo", PackedStringArray(["list"]))
	if int(r[0]) != 0:
		return {"text": "열린 앱을 알아보지 못했어요.", "error": true}
	var apps := {}        # ASN → 이름
	var order := []       # list 순서(대략 연 순서)
	var name := ""
	var asn := ""
	for line in String(r[1]).split("\n"):
		var t := line.strip_edges()
		var q1 := t.find(") \"")
		if q1 > 0 and t.left(q1).is_valid_int():
			var q2 := t.find("\" ASN:", q1 + 3)
			if q2 > 0:
				name = t.substr(q1 + 3, q2 - q1 - 3)
				asn = t.substr(q2 + 6).get_slice(":", 0)
			continue
		if asn != "" and t.contains("type=\"Foreground\""):
			if name != "37FRHG":
				apps[asn] = name
				order.append(asn)
			asn = ""
	var fr: Array = await mail._run("/usr/bin/lsappinfo", PackedStringArray(["front"]))
	var front_asn := String(fr[1]).strip_edges().trim_prefix("ASN:").trim_suffix(":")
	var v: Array = await mail._run("/usr/bin/lsappinfo", PackedStringArray(["visibleProcessList"]))
	var shown := []
	for part in String(v[1]).split("ASN:"):
		var id := "ASN:" + part.get_slice("-\"", 0).strip_edges()
		var a2 := id.substr(4)
		if apps.has(a2) and not (a2 in shown):
			shown.append(a2)
	if apps.is_empty():
		return {"text": "열린 앱이 없어요(개구리 앱 빼고).", "error": false}
	var names := PackedStringArray()
	for a in shown:
		names.append(apps[a])
	var hidden := PackedStringArray()
	for a in order:
		if not (a in shown):
			hidden.append(apps[a])
	var txt := "열린 앱 %d개(이 개구리 앱 빼고)." % apps.size()
	# 맨 앞: lsappinfo front(키보드를 받는 앱). 개구리(입력칸)가 맨 앞이면 그 바로 뒤의 보이는 앱.
	var front := String(apps.get(front_asn, ""))
	if front == "" and not names.is_empty():
		front = names[0] + "(개구리 입력칸 바로 뒤)"
	if front != "":
		txt += " 맨 앞(지금 쓰는 앱): %s." % front
	if not names.is_empty():
		txt += " 보이는 순서(앞→뒤): %s." % ", ".join(names)
	if not hidden.is_empty():
		txt += " 숨겨 두었거나 창이 없는 앱: %s." % ", ".join(hidden)
	return {"text": txt, "error": false}


func _open_url(url: String) -> Dictionary:
	url = url.strip_edges()
	if not (url.begins_with("http://") or url.begins_with("https://")):
		return {"text": "http/https 주소만 열 수 있어요.", "error": true}
	OS.shell_open(url)
	return {"text": "%s 를 열었어요." % url, "error": false}


func _set_timer(input: Dictionary) -> Dictionary:
	var now := Time.get_unix_time_from_system()
	var at := -1.0
	if input.has("minutes") and float(input.minutes) > 0.0:
		at = now + float(input.minutes) * 60.0
	elif String(input.get("at", "")).contains(":"):
		var hm := String(input.at).split(":")
		var d := Time.get_datetime_dict_from_system()
		d.hour = int(hm[0])
		d.minute = int(hm[1])
		d.second = 0
		# get_unix_time_from_datetime_dict 는 UTC 로 보므로 지역 시간 차이를 뺀다.
		at = Time.get_unix_time_from_datetime_dict(d) - Time.get_time_zone_from_system().bias * 60.0
		if at <= now:
			at += 86400.0
	if at < 0.0:
		return {"text": "minutes 나 at 중 하나가 필요해요.", "error": true}
	var action := String(input.get("action", "none"))
	var target := String(input.get("target", ""))
	if action == "open_url" and not (target.begins_with("http://") or target.begins_with("https://")):
		return {"text": "웹 주소는 http/https 만 돼요.", "error": true}
	if action == "open_app" and (target.strip_edges() == "" or target.contains("/")):
		return {"text": "열 앱 이름이 필요해요.", "error": true}
	var t := {"id": next_id, "at": at, "message": String(input.get("message", "시간 됐어요!")),
		"action": action, "target": target}
	next_id += 1
	timers.append(t)
	_save_timers()
	return {"text": "타이머 %d번을 %s 에 걸었어요(%s 뒤).%s" % [t.id, _clock(at), _left(at - now),
		"" if action == "none" else " 그때 %s: %s" % [action, target]], "error": false}


func _list() -> String:
	if timers.is_empty():
		return "걸어 둔 타이머가 없어요."
	var now := Time.get_unix_time_from_system()
	var lines := PackedStringArray()
	for t in timers:
		lines.append("%d번: %s(%s 뒤) \"%s\"%s" % [int(t.id), _clock(float(t.at)), _left(float(t.at) - now),
			t.message, "" if t.action == "none" else " → %s %s" % [t.action, t.target]])
	return "\n".join(lines)


func _cancel(input: Dictionary) -> Dictionary:
	if bool(input.get("all", false)):
		var n := timers.size()
		timers.clear()
		_save_timers()
		return {"text": "타이머 %d개를 모두 껐어요." % n, "error": false}
	var id := int(input.get("id", -1))
	for t in timers:
		if int(t.id) == id:
			timers.erase(t)
			_save_timers()
			return {"text": "타이머 %d번을 껐어요." % id, "error": false}
	return {"text": "%d번 타이머가 없어요." % id, "error": true}


func _clock(unix: float) -> String:
	var bias: int = int(Time.get_time_zone_from_system().bias) * 60
	var d := Time.get_datetime_dict_from_unix_time(int(unix) + bias)
	return "%02d:%02d" % [int(d.hour), int(d.minute)]


func _left(sec: float) -> String:
	var m := int(round(sec / 60.0))
	if sec < 90.0:
		return "%d초" % int(round(sec))
	if m < 60:
		return "%d분" % m
	return "%d시간 %d분" % [m / 60, m % 60]


# ---------------------------------------------------------------- 날씨

func _fetch(url: String) -> Variant:
	if http.request(url, PackedStringArray(["User-Agent: " + UA, "Accept: application/json"])) != OK:
		return null
	var r: Array = await http.request_completed
	if r[0] != HTTPRequest.RESULT_SUCCESS or int(r[1]) != 200:
		print("weather get failed ", r[0], " ", r[1], " ", url.left(60))
		return null
	return JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())


func _weather(place: String, plat: Variant, plon: Variant) -> Dictionary:
	var lat := 0.0
	var lon := 0.0
	var where := ""
	if (plat is float or plat is int) and (plon is float or plon is int) and absf(plat) <= 90.0 and absf(plon) <= 180.0:
		# Claude 가 준 좌표(지명 검색보다 낫다: "부산"을 찾으면 충북의 산 이름이 먼저 나왔다)
		lat = float(plat)
		lon = float(plon)
		where = place if place != "" else "%.2f, %.2f" % [lat, lon]
	elif place != "":
		var g = await _fetch(GEOCODE.replace("count=1", "count=10") + place.uri_encode())
		if not (g is Dictionary) or g.get("results", []).is_empty():
			return {"text": "'%s' 를 찾지 못했어요. 위도·경도를 넣어 다시 불러 주세요." % place, "error": true}
		# 산(MT)·공원(PRK) 말고 도시·마을을, 그중 행정 중심·인구 많은 곳을 고른다.
		var best: Dictionary = {}
		var best_score := -1.0
		for p in g.results:
			var fc := String(p.get("feature_code", ""))
			var score := float(p.get("population", 0) if p.get("population") != null else 0)
			if fc.begins_with("PPLC") or fc.begins_with("PPLA"):
				score += 1e8
			elif not fc.begins_with("PPL") and not fc.begins_with("ADM"):
				score -= 1e9
			if score > best_score:
				best_score = score
				best = p
		lat = float(best.latitude)
		lon = float(best.longitude)
		where = "%s(%s)" % [best.get("name", place), best.get("admin1", best.get("country", ""))]
	else:
		if here.is_empty() or Time.get_unix_time_from_system() - float(here.t) > 3600.0:
			var g = await _fetch(GEO_IP)
			if not (g is Dictionary) or not g.has("latitude"):
				return {"text": "지금 위치를 알 수 없어요. 장소를 말해 달라고 하세요.", "error": true}
			here = {"lat": float(g.latitude), "lon": float(g.longitude),
				"name": "%s %s" % [g.get("city", ""), g.get("region", "")], "t": Time.get_unix_time_from_system()}
		lat = here.lat
		lon = here.lon
		where = "%s 근처(인터넷 주소로 짐작한 위치)" % String(here.name).strip_edges()
	var f = await _fetch(FORECAST % [lat, lon])
	if f is Dictionary and f.has("current"):
		var c: Dictionary = f.current
		var dl: Dictionary = f.get("daily", {})
		var s := "%s 지금: %s, %.0f°C(체감 %.0f°C), 습도 %d%%, 바람 %.0fkm/h, 강수 %.1fmm." % [where,
			_wmo(int(c.weather_code)), c.temperature_2m, c.apparent_temperature, int(c.relative_humidity_2m),
			c.wind_speed_10m, c.precipitation]
		for i in mini(2, dl.get("time", []).size()):
			s += " %s: %s, %.0f~%.0f°C, 비 올 확률 %d%%." % ["오늘" if i == 0 else "내일",
				_wmo(int(dl.weather_code[i])), dl.temperature_2m_min[i], dl.temperature_2m_max[i],
				int(dl.precipitation_probability_max[i]) if dl.precipitation_probability_max[i] != null else 0]
		return {"text": s, "error": false}
	# Open-Meteo 가 안 되면 met.no(지금 값만)
	var m = await _fetch(METNO % [lat, lon])
	if m is Dictionary and m.has("properties"):
		var ts: Array = m.properties.timeseries
		if not ts.is_empty():
			var det: Dictionary = ts[0].data.instant.details
			var nxt: Dictionary = ts[0].data.get("next_1_hours", ts[0].data.get("next_6_hours", {}))
			var sym := String(nxt.get("summary", {}).get("symbol_code", ""))
			return {"text": "%s 지금: %.0f°C, 습도 %d%%, 바람 %.0fm/s, 하늘 %s(met.no 기호), 1시간 강수 %.1fmm." % [where,
				det.get("air_temperature", 0.0), int(det.get("relative_humidity", 0)), det.get("wind_speed", 0.0),
				sym, float(nxt.get("details", {}).get("precipitation_amount", 0.0))], "error": false}
	return {"text": "날씨 정보를 가져오지 못했어요.", "error": true}


func _wmo(c: int) -> String:
	if c == 0: return "맑음"
	if c <= 2: return "구름 조금"
	if c == 3: return "흐림"
	if c <= 48: return "안개"
	if c <= 57: return "이슬비"
	if c <= 67: return "비"
	if c <= 77: return "눈"
	if c <= 82: return "소나기"
	if c <= 86: return "눈보라"
	return "뇌우"
