extends Node
## 개구리와 말하기(Claude API, Haiku). 입력칸에서 보낸 말에 대답한다. 37RHHG talk.gd 를 줄여 새로 씀:
## - 대화는 Messages API 의 user/assistant 차례로 보낸다(최근 KEEP_TURNS 마디, 글만 남김).
## - 도구 반복: Claude 가 도구를 고르면(stop_reason tool_use) actions.gd 로 실행하고 결과(tool_result)를 붙여
##   다시 부른다. 글로 대답할 때까지 MAX_STEPS 번. 37RHHG 는 도구를 실행만 하고 결과를 돌려주지 않았다.
##   반복 중의 assistant 내용(생각 블록 포함)은 받은 그대로 다시 보낸다(Haiku 5.5 는 생각 블록을 바꾸면 안 됨).
## - 대화 기록·하루 호출 수는 user://talk.json. 키는 keystore(키체인)에서 받고 어디에도 찍지 않는다.

signal answered(text: String)          # 말풍선에 띄울 말(대답 또는 실패 까닭)

const MODELS := {"haiku": "claude-haiku-5-5", "sonnet": "claude-sonnet-5-5"}   # 고를 수 있는 것은 이 둘뿐
const MODEL_NAME := {"haiku": "Haiku", "sonnet": "Sonnet"}
# 말 모델 바꾸기: 입력칸에 "소넷으로 바꿔 줘" 같은 말을 하면 Claude 가 이 도구를 부른다(talk.gd 가 직접 처리).
# 바꾸면 그 대답부터 새 모델로 말한다(반복 안에서 모델이 바뀌면 앞 모델의 생각 블록은 API 가 알아서 버린다).
# Sonnet 이면 옷 색이 바뀐다(main.gd _tint_step, 37RHHG 머리카락처럼).
const MODEL_TOOL := {"name": "set_model",
	"description": "사용자가 말하는 AI 모델을 바꿔 달라고 할 때 부른다. 고를 수 있는 것은 haiku(빠르고 싸다, 기본)와 sonnet(더 똑똑하지만 비용이 약 20배)뿐이다. 다른 모델(Opus 등)을 원하면 부르지 말고 Haiku·Sonnet 만 된다고 말한다.",
	"input_schema": {"type": "object", "properties": {
		"model": {"type": "string", "enum": ["haiku", "sonnet"]}}, "required": ["model"]}}
const URL := "https://api.anthropic.com/v1/messages"
const API_VERSION := "2026-10-21"      # 이 버전에서는 temperature 같은 샘플링 값을 보내면 400
const EFFORT := "low"                  # 짧은 대화라 생각은 조금만(비용·속도)
const MAX_TOKENS := 2000               # 생각하는 몫까지 포함한 상한. 말 길이는 프롬프트로 정한다
const DAY_CALLS := 300                 # 하루 호출 상한
const KEEP_TURNS := 12                 # 같이 보내는 최근 말 수(사용자·개구리 합쳐서)
const MAX_CHARS := 60                  # 대답 길이(글자, 프롬프트로). 말풍선은 6줄(약 90자)까지라 여유를 둠
const STATE := "user://talk.json"
const MAX_STEPS := 5                   # 한 번 말할 때 API 를 부르는 최대 횟수(도구 반복)

var keystore: Node
var actions: Node
var http: HTTPRequest
var busy := false
var state := {"turns": [], "day": "", "calls": 0, "model": "haiku"}


func setup(ks: Node, acts: Node) -> void:
	keystore = ks
	actions = acts
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
	return ("너는 사용자의 맥 화면 위를 걸어 다니는 작은 개구리 마법사다. 지금 너를 움직이는 AI 모델은 Claude %s 다(Haiku·Sonnet 중 set_model 로 바꿀 수 있다). " % MODEL_NAME[_model_key()] + " 보라색 고깔모자와 로브를 입고, "
		+ "허리에 마법책과 물약 병을 차고 있다. 사용자의 다정한 조수다.\n"
		+ "말하는 법:\n"
		+ "- 한국어 존댓말로, 밝고 따뜻하게. 말풍선이 작으니 반드시 짧게: 한두 문장, %d자 이내(띄어쓰기 포함). 자기소개도 짧게. 묻지 않은 설명은 덧붙이지 않는다. 목록·마크다운·이모지는 쓰지 않는다.\n" % MAX_CHARS
		+ "- 날씨는 get_weather 로 알아보고 말한다. 그 밖에 모르는 사실(뉴스, 시세 등)은 지어내지 말고 모른다고 한다. 너는 검색을 할 수 없다.\n"
		+ "- 앱 열기·웹 주소 열기·타이머는 도구로 한다. 부탁받은 일만 하고, 도구 결과를 보고 된 것만 됐다고 말한다. "
		+ "대화 기록의 [앱 기록: …] 은 앱이 붙인 것으로, 그때 실제로 실행한 도구다. 너는 그 표시를 쓰지 않는다. "
		+ "메일 읽기·문자 보내기는 아직 못 한다(곧 배울 예정). 못 하는 일은 한 것처럼 꾸미지 말고 솔직히 말한다.\n"
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
		var c := String(t.t)
		# 지난 대답 때 실행한 도구를 같이 보여 준다. 없으면 Claude 가 "도구 없이 한 척했다"고 사과했다.
		if t.has("k"):
			c += "\n[앱 기록: 이 대답 때 실행한 도구 — %s]" % t.k
		msgs.append({"role": "user" if t.r == "u" else "assistant", "content": c})
	msgs.append({"role": "user", "content": text})
	# API 는 user 로 시작해야 한다(오래된 기록이 잘려 assistant 로 시작하면 뺀다).
	while msgs.size() > 1 and msgs[0].role != "user":
		msgs.pop_front()
	busy = true
	var out := ""
	var done := PackedStringArray()    # 실행한 도구 요약(기록용)
	for step in MAX_STEPS:
		var res: Dictionary = await _call(msgs)
		if res.has("fail"):
			busy = false
			answered.emit(res.fail)
			return
		var d: Dictionary = res.data
		print("claude ", d.get("model", "?"), " stop ", d.get("stop_reason", "?"))
		if d.get("stop_reason", "") == "refusal":
			busy = false
			answered.emit("음… 그건 제가 대답하기 어려워요.")
			return
		out = ""
		var uses: Array = []
		for c in d.get("content", []):
			if c is Dictionary and c.get("type", "") == "text":
				out += String(c.get("text", ""))
			elif c is Dictionary and c.get("type", "") == "tool_use":
				uses.append(c)
		if uses.is_empty() or d.get("stop_reason", "") != "tool_use":
			break
		# 도구를 실행하고 결과를 한 user 메시지에 모아 다시 부른다.
		msgs.append({"role": "assistant", "content": d.content})
		var results: Array = []
		for u in uses:
			var inp: Dictionary = u.get("input", {}) if u.get("input") is Dictionary else {}
			var r: Dictionary = _set_model(inp) if u.name == "set_model" else await actions.run(String(u.name), inp)
			print("tool ", u.name, " ", JSON.stringify(u.get("input", {})), " -> ", String(r.text).left(160))
			done.append("%s %s → %s" % [u.name, JSON.stringify(u.get("input", {})), String(r.text).left(80)])
			results.append({"type": "tool_result", "tool_use_id": u.id, "content": String(r.text), "is_error": bool(r.error)})
		msgs.append({"role": "user", "content": results})
		if step == MAX_STEPS - 1:
			out = "음… 생각이 길어졌어요. 다시 한 번 말해 주세요."
	busy = false
	out = out.strip_edges().replace("\n", " ")
	if out == "":
		answered.emit("음… 뭐라고 해야 할지 모르겠어요.")
		return
	_push("u", text)
	_push("m", out)
	if not done.is_empty():
		state.turns[-1]["k"] = "; ".join(done)
	_save()
	answered.emit(out)


# API 한 번. {"data": 응답} 또는 {"fail": 말로 된 까닭}
func _call(msgs: Array) -> Dictionary:
	_today()
	if int(state.calls) >= DAY_CALLS:
		return {"fail": "오늘은 이야기를 너무 많이 했어요. 내일 또 이야기해요!"}
	var model: String = MODELS[_model_key()]
	var body := {
		"model": model,
		"max_tokens": MAX_TOKENS,
		"system": _system(),
		"messages": msgs,
		"tools": actions.TOOLS + [MODEL_TOOL],
		"output_config": {"effort": EFFORT},
	}
	var headers := PackedStringArray(["content-type: application/json", "x-api-key: " + keystore.key,
		"anthropic-version: " + API_VERSION])
	if _model_key() == "sonnet":
		# Sonnet 5.5 는 안전 분류기가 거절할 수 있다 → 서버가 알맞은 모델로 대신 답하게(기본 대체).
		body["fallbacks"] = "default"
		headers.append("anthropic-beta: server-side-fallback-2026-07-01")
	if http.request(URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		return {"fail": "지금은 연결이 안 돼요. 조금 뒤에 다시 말 걸어 주세요."}
	state.calls = int(state.calls) + 1
	_save()
	var r: Array = await http.request_completed
	var code: int = r[1]
	var raw := (r[3] as PackedByteArray).get_string_from_utf8()
	if r[0] != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("claude 실패 result ", r[0], " code ", code, " ", raw.left(300))
		return {"fail": _fail_line(code, raw)}
	var d = JSON.parse_string(raw)
	if not (d is Dictionary):
		return {"fail": "음… 대답을 알아듣지 못했어요."}
	return {"data": d}


func sonnet() -> bool:
	return _model_key() == "sonnet"


func _model_key() -> String:
	var m := String(state.get("model", "haiku"))
	return m if MODELS.has(m) else "haiku"


func _set_model(inp: Dictionary) -> Dictionary:
	var m := String(inp.get("model", "")).to_lower()
	if not MODELS.has(m):
		return {"text": "Haiku 와 Sonnet 만 고를 수 있어요.", "error": true}
	if m == _model_key():
		return {"text": "이미 %s 예요." % MODEL_NAME[m], "error": false}
	state.model = m
	_save()
	return {"text": "이제 %s 로 대답해요.%s" % [MODEL_NAME[m],
		" Sonnet 은 Haiku 보다 비용이 약 20배예요." if m == "sonnet" else ""], "error": false}


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
