extends Node
## 개구리와 말하기(Claude API, Haiku). 입력칸에서 보낸 말에 대답한다. 37RHHG talk.gd 를 줄여 새로 씀:
## - 대화는 Messages API 의 user/assistant 차례로 그대로 보낸다(최근 KEEP_TURNS 마디). 나중에 도구 결과를
##   돌려주는 반복(메일 읽기 등)을 붙이기 쉽게.
## - 대화 기록·하루 호출 수는 user://talk.json. 키는 keystore(키체인)에서 받고 어디에도 찍지 않는다.
## - 아직 도구가 없다(앱 켜기·타이머·메일·문자는 다음 단계).

signal answered(text: String)          # 말풍선에 띄울 말(대답 또는 실패 까닭)

const MODEL := "claude-haiku-5-5"
const URL := "https://api.anthropic.com/v1/messages"
const API_VERSION := "2026-10-21"      # 이 버전에서는 temperature 같은 샘플링 값을 보내면 400
const EFFORT := "low"                  # 짧은 대화라 생각은 조금만(비용·속도)
const MAX_TOKENS := 2000               # 생각하는 몫까지 포함한 상한. 말 길이는 프롬프트로 정한다
const DAY_CALLS := 300                 # 하루 호출 상한
const KEEP_TURNS := 12                 # 같이 보내는 최근 말 수(사용자·개구리 합쳐서)
const MAX_CHARS := 60                  # 대답 길이(글자, 프롬프트로). 말풍선은 6줄(약 90자)까지라 여유를 둠
const STATE := "user://talk.json"

var keystore: Node
var http: HTTPRequest
var busy := false
var state := {"turns": [], "day": "", "calls": 0}


func setup(ks: Node) -> void:
	keystore = ks
	http = HTTPRequest.new()
	http.timeout = 30.0
	add_child(http)
	if FileAccess.file_exists(STATE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(STATE))
		if d is Dictionary:
			state.merge(d, true)


func is_busy() -> bool:
	return busy


func _save() -> void:
	var f := FileAccess.open(STATE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(state))


func _today() -> void:
	var day := Time.get_date_string_from_system()
	if state.day != day:
		state.day = day
		state.calls = 0


func _system() -> String:
	var now := Time.get_datetime_dict_from_system()
	var wd: String = ["일", "월", "화", "수", "목", "금", "토"][int(now.weekday)]
	return ("너는 사용자의 맥 화면 위를 걸어 다니는 작은 개구리 마법사다. 보라색 고깔모자와 로브를 입고, "
		+ "허리에 마법책과 물약 병을 차고 있다. 사용자의 다정한 조수다.\n"
		+ "말하는 법:\n"
		+ "- 한국어 존댓말로, 밝고 따뜻하게. 말풍선이 작으니 반드시 짧게: 한두 문장, %d자 이내(띄어쓰기 포함). 자기소개도 짧게. 묻지 않은 설명은 덧붙이지 않는다. 목록·마크다운·이모지는 쓰지 않는다.\n" % MAX_CHARS
		+ "- 모르는 사실(뉴스, 날씨, 시세 등)은 지어내지 말고 모른다고 한다. 너는 검색을 할 수 없다.\n"
		+ "- 너는 아직 맥을 직접 다루지 못한다(앱 켜기, 타이머, 메일 읽기, 문자 보내기는 곧 배울 예정). "
		+ "그런 부탁을 받으면 한 것처럼 꾸미지 말고, 아직은 못 한다고 솔직히 말한다.\n"
		+ "지금: %d년 %d월 %d일 %s요일 %02d:%02d.") % [int(now.year), int(now.month), int(now.day), wd,
			int(now.hour), int(now.minute)]


# 사용자의 말에 대답한다. 결과는 answered 신호로(실패해도 까닭을 말로).
func reply(text: String) -> void:
	text = text.strip_edges()
	if text == "" or busy:
		return
	_today()
	if int(state.calls) >= DAY_CALLS:
		answered.emit("오늘은 이야기를 너무 많이 했어요. 내일 또 이야기해요!")
		return
	if keystore == null or not keystore.has_key():
		answered.emit("먼저 Claude API 키를 넣어 주세요.")
		return
	var msgs: Array = []
	for t in state.turns:
		msgs.append({"role": "user" if t.r == "u" else "assistant", "content": String(t.t)})
	msgs.append({"role": "user", "content": text})
	# API 는 user 로 시작해야 한다(오래된 기록이 잘려 assistant 로 시작하면 뺀다).
	while msgs.size() > 1 and msgs[0].role != "user":
		msgs.pop_front()
	var body := {
		"model": MODEL,
		"max_tokens": MAX_TOKENS,
		"system": _system(),
		"messages": msgs,
		"output_config": {"effort": EFFORT},
	}
	var headers := PackedStringArray(["content-type: application/json", "x-api-key: " + keystore.key,
		"anthropic-version: " + API_VERSION])
	if http.request(URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		answered.emit("지금은 연결이 안 돼요. 조금 뒤에 다시 말 걸어 주세요.")
		return
	busy = true
	state.calls = int(state.calls) + 1
	_save()
	var r: Array = await http.request_completed
	busy = false
	var code: int = r[1]
	var raw := (r[3] as PackedByteArray).get_string_from_utf8()
	if r[0] != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("claude 실패 result ", r[0], " code ", code, " ", raw.left(200))
		answered.emit(_fail_line(code, raw))
		return
	var d = JSON.parse_string(raw)
	var out := ""
	if d is Dictionary:
		if d.get("stop_reason", "") == "refusal":
			answered.emit("음… 그건 제가 대답하기 어려워요.")
			return
		for c in d.get("content", []):
			if c is Dictionary and c.get("type", "") == "text":
				out += String(c.get("text", ""))
	out = out.strip_edges().replace("\n", " ")
	if out == "":
		answered.emit("음… 뭐라고 해야 할지 모르겠어요.")
		return
	_push("u", text)
	_push("m", out)
	_save()
	answered.emit(out)


func _push(r: String, t: String) -> void:
	state.turns.append({"r": r, "t": t})
	while state.turns.size() > KEEP_TURNS:
		state.turns.pop_front()


func _fail_line(code: int, raw: String) -> String:
	var m := raw.to_lower()
	if m.contains("credit balance") or m.contains("billing"):
		return "Claude 크레딧이 바닥났어요. 충전해 주세요."
	if code == 401 or code == 403:
		return "키가 맞지 않아요. 메뉴에서 Claude 키를 다시 넣어 주세요."
	if code == 429 or code == 529 or code >= 500:
		return "지금 Claude 가 붐벼요. 조금 뒤에 다시 말 걸어 주세요."
	return "지금은 연결이 안 돼요. 조금 뒤에 다시 말 걸어 주세요."
