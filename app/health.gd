extends Node
## 인터넷·Claude 를 쓸 수 있는지 지켜본다(2026-11-26 사용자 요청: 못 쓰면 뒤 유리병 액체를 검게).
## main.gd 가 `down()` 을 보고 셰이더 back_dark 를 켠다.
##
## 못 쓰는 경우:
##   - 키가 없음(keystore.has_key() 거짓).
##   - 확인 요청 실패: GET /v1/models?limit=1(무료)을 OK_EVERY 초마다(못 쓰는 동안은 BAD_EVERY 초마다).
##     연결 실패(인터넷 끊김·DNS)·401/403(키)·5xx/529(Claude 장애)면 못 씀, 200·429 면 씀.
##   - 말하기(talk.gd) 결과: 크레딧 바닥·키 거절은 다음에 말하기가 성공하거나 키를 새로 넣을 때까지(확인 요청은
##     크레딧과 상관없이 200 이라 이것으로는 못 안다). 붐빔·연결 실패는 TALK_HOLD 초 동안만(그 뒤엔 확인 요청에 맡김).

signal changed(down: bool, why: String)

const URL := "https://api.anthropic.com/v1/models?limit=1"
var url := URL
const API_VERSION := "2026-10-21"
const OK_EVERY := 60.0
const BAD_EVERY := 15.0
const TALK_HOLD := 180.0

var keystore: Node
var http: HTTPRequest
var probe_bad := ""                    # 확인 요청이 못 쓴다고 본 까닭("" 이면 씀)
var talk_bad := ""                     # 말하기가 실패한 까닭
var talk_sticky := false               # talk_bad 가 크레딧·키 문제라 시간이 지나도 안 풀리는지
var talk_until := 0.0                  # 붐빔·연결 실패면 이 시각(초)까지
var wait := 3.0                        # 다음 확인까지(시작 3초 뒤 처음 확인)
var busy := false
var last_down := false
var last_why := ""


func _ready() -> void:
	# 확인용: FRHG_HEALTH_URL 로 확인 주소를 바꾼다(예 https://127.0.0.1:9 → 연결 안 됨).
	if OS.get_environment("FRHG_HEALTH_URL") != "":
		url = OS.get_environment("FRHG_HEALTH_URL")
	http = HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	if keystore != null:
		keystore.saved.connect(func(_ok, _msg): _clear_talk(); wait = 0.5)


func down() -> bool:
	return why() != ""


# 못 쓰는 까닭(쓸 수 있으면 "").
func why() -> String:
	if keystore != null and not keystore.has_key():
		return "키 없음"
	if talk_bad != "" and (talk_sticky or Time.get_ticks_msec() / 1000.0 < talk_until):
		return talk_bad
	return probe_bad


func _process(dt: float) -> void:
	_emit()
	if busy:
		return
	wait -= dt
	if wait > 0.0:
		return
	_probe()


func _emit() -> void:
	var w := why()
	if (w != "") != last_down or w != last_why:
		last_down = w != ""
		last_why = w
		print("health ", "못 씀: " + w if last_down else "씀")
		changed.emit(last_down, w)


func _probe() -> void:
	if keystore == null or not keystore.has_key():
		wait = BAD_EVERY
		return
	busy = true
	var code := 0
	if http.request(url, PackedStringArray(["x-api-key: " + keystore.key, "anthropic-version: " + API_VERSION])) == OK:
		var r: Array = await http.request_completed
		code = int(r[1]) if r[0] == HTTPRequest.RESULT_SUCCESS else 0
	busy = false
	probe_bad = _code_why(code)
	wait = BAD_EVERY if probe_bad != "" else OK_EVERY


static func _code_why(code: int) -> String:
	if code == 200 or code == 429:
		return ""
	if code == 0:
		return "연결 안 됨"
	if code == 401 or code == 403:
		return "키 거절"
	if code >= 500:
		return "Claude 장애(%d)" % code
	return "응답 %d" % code


# talk.gd 가 호출마다 알려 준다. ok 면 code 는 무시.
func talk_result(ok: bool, code: int, raw: String) -> void:
	if ok:
		_clear_talk()
		if probe_bad != "":
			probe_bad = ""             # 방금 말이 됐으니 연결은 된다
			wait = OK_EVERY
		return
	var m := raw.to_lower()
	if m.contains("credit balance") or m.contains("billing"):
		talk_bad = "크레딧 없음"
		talk_sticky = true
	elif code == 401 or code == 403:
		talk_bad = "키 거절"
		talk_sticky = true
	else:
		var w := _code_why(code)
		if w == "":                    # 429(잠깐 너무 잦음)는 못 쓰는 것으로 보지 않는다
			return
		talk_bad = w
		talk_sticky = false
		talk_until = Time.get_ticks_msec() / 1000.0 + TALK_HOLD
		wait = minf(wait, 1.0)         # 바로 한 번 확인해 본다


func _clear_talk() -> void:
	talk_bad = ""
	talk_sticky = false
