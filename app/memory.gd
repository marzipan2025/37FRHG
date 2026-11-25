extends Node
## 사용자에 대한 기억(2026-11-24). 이 맥에만 저장하고(user://memory.json), 말할 때마다 시스템 프롬프트에 붙인다.
## - 넣기: 사용자가 따로 시키지 않아도 Claude 가 대화 중 오래 두고 쓸 만한 사실을 들으면 remember 도구로 조용히 적는다.
##   잊어 달라고 하면 forget. 비밀번호·카드·계좌·주민번호 같은 것은 적지 않는다(프롬프트 + 여기서 한 번 더 거름).
## - 정리: 한 달(TIDY_DAYS)마다, 또는 글자 수가 MAX_CHARS 를 넘으면 Claude 에 한 번 보내 중복을 합치고
##   지난 일을 빼서 짧은 사실 목록으로 다시 쓴다. 대답이 끝난 뒤 한가할 때 한다(대답이 늦어지지 않게).
##   정리 전 내용은 user://memory.bak.json 에 남긴다.
## 내용은 print·로그에 남기지 않는다(개수·글자 수만).
## 개구리 자신(2026-11-25 사용자: "이름을 정해 줬는데 기억 못 함"): 처음엔 사용자에 대한 사실만 적게 해서, 사용자가 정해 준
## 개구리 이름이 적히지 않고 최근 12마디 대화 기록에서 밀려나 잊혔다. 이제 remember(about "self")로 이름·별명·말투 같은
## 개구리 자신에 대한 것도 적고(항목 "w": "self"), 프롬프트에 따로 보이며, 한 달 정리에서는 건드리지 않는다.

const PATH := "user://memory.json"
const BAK := "user://memory.bak.json"
const ITEM_CHARS := 200        # 한 줄 최대(120 이면 계정 설명 같은 긴 사실이 중간에서 잘렸다, 2026-11-25)
const MAX_CHARS := 2000        # 이보다 길어지면 한 달이 안 됐어도 정리
const TIDY_DAYS := 30
const TIDY_LINES := 25         # 정리 뒤 최대 줄 수
const TIDY_MODEL := "claude-haiku-5-5"
const URL := "https://api.anthropic.com/v1/messages"
const API_VERSION := "2026-10-21"

const TOOLS := [
	{"name": "remember",
		"description": "오래 두고 쓸 만한 사실을 이 맥에 적어 둔다. about 'self' 는 사용자가 너(개구리)에게 정해 준 것(너의 이름·별명, 말투, 성격, 사용자와의 약속 같은 것)으로, 사용자가 정해 주면 반드시 부른다. about 'user'(기본)는 사용자에 대한 사실로, 사용자가 시키지 않아도, 대화에서 이름·호칭, 가족·반려동물, 사는 곳·일하는 곳, 하는 일, 좋아하는 것·싫어하는 것, 습관, 생일·기념일 같은 것을 새로 알게 되면 부른다. 이미 기억하는 것, 잠깐의 일(오늘 기분, 지금 하려는 일), 비밀번호·카드·계좌·주민번호·API 키 같은 민감한 정보는 적지 않는다. 이전 기억이 바뀌었으면 replace 에 그 기억의 일부를 넣는다.",
		"input_schema": {"type": "object", "properties": {
			"fact": {"type": "string", "description": "짧은 한 문장, 사용자 기준(예: '이름은 병수, 병수님이라고 불러 주길 원함')."},
			"replace": {"type": "string", "description": "바뀐 이전 기억의 일부 글자(없으면 비움)."},
			"about": {"type": "string", "enum": ["user", "self"], "description": "user: 사용자에 대한 것(기본), self: 너(개구리)에 대해 사용자가 정해 준 것."}},
			"required": ["fact"]}},
	{"name": "forget",
		"description": "사용자가 잊어 달라고 한 기억을 지운다. what 에 그 기억의 일부 글자, 모두 잊어 달라면 'all'.",
		"input_schema": {"type": "object", "properties": {
			"what": {"type": "string"}}, "required": ["what"]}},
]

var keystore: Node
var http: HTTPRequest
var data := {"items": [], "tidied": ""}
var tidying := false


func setup(ks: Node) -> void:
	keystore = ks
	http = HTTPRequest.new()
	http.timeout = 60.0
	add_child(http)
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			data.merge(d, true)
	if String(data.tidied) == "":
		data.tidied = Time.get_date_string_from_system()
		_save()


func _save(path := PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func _chars() -> int:
	var n := 0
	for it in data.items:
		n += String(it.t).length()
	return n


# 시스템 프롬프트에 붙일 글(없으면 빈 글).
func prompt() -> String:
	if data.items.is_empty():
		return ""
	var me := PackedStringArray()
	var lines := PackedStringArray()
	for it in data.items:
		(me if it.get("w", "") == "self" else lines).append("- " + String(it.t))
	var out := ""
	if not me.is_empty():
		out += "너(개구리) 자신에 대해 사용자가 정해 준 것(이름·별명·말투 등, 이것을 따른다):\n" + "\n".join(me) + "\n"
	if not lines.is_empty():
		out += "사용자에 대해 기억하는 것(이 맥에 저장한 메모, 지난 대화에서 들은 것이라 바뀌었을 수 있다):\n" + "\n".join(lines) + "\n"
	return out


static func _sensitive(t: String) -> bool:
	var low := t.to_lower()
	for w in ["비밀번호", "패스워드", "password", "카드번호", "계좌", "주민번호", "주민등록", "여권번호", "sk-ant", "api 키", "api key", "인증번호", "otp"]:
		if low.contains(w):
			return true
	# 숫자가 10개 넘게 이어지면(카드·계좌·주민번호 모양) 거름. 전화번호(11자리)도 여기서 걸린다.
	var run := 0
	for c in t:
		if c >= "0" and c <= "9":
			run += 1
			if run >= 10:
				return true
		elif c != "-" and c != " ":
			run = 0
	return false


func run(tool: String, inp: Dictionary) -> Dictionary:
	if tool == "remember":
		var fact := String(inp.get("fact", "")).strip_edges().replace("\n", " ")
		var rep := String(inp.get("replace", "")).strip_edges()
		if fact == "":
			return {"text": "적을 내용이 비었어요.", "error": true}
		if _sensitive(fact):
			return {"text": "민감한 정보라 적지 않았어요.", "error": true}
		fact = fact.left(ITEM_CHARS)
		var w := "self" if String(inp.get("about", "")) == "self" else ""
		var today := Time.get_date_string_from_system()
		var item := {"t": fact, "d": today}
		if w != "":
			item["w"] = w
		if rep != "":
			for i in data.items.size():
				if String(data.items[i].get("w", "")) == w and String(data.items[i].t).contains(rep):
					data.items[i] = item
					_save()
					return {"text": "기억을 고쳤어요.", "error": false}
		for it in data.items:
			if String(it.t) == fact:
				return {"text": "이미 기억하고 있어요.", "error": false}
		data.items.append(item)
		_save()
		return {"text": "기억했어요.", "error": false}
	if tool == "forget":
		var what := String(inp.get("what", "")).strip_edges()
		if what == "":
			return {"text": "무엇을 잊을지 비었어요.", "error": true}
		var before: int = data.items.size()
		if what.to_lower() == "all" or what == "전부" or what == "모두":
			data.items = []
		else:
			data.items = data.items.filter(func(it): return not String(it.t).contains(what))
		_save()
		var n: int = before - data.items.size()
		return {"text": "%d개를 잊었어요." % n if n > 0 else "그런 기억은 없어요.", "error": n == 0}
	return {"text": "모르는 도구: " + tool, "error": true}


func _days_since(day: String) -> int:
	var a := Time.get_unix_time_from_datetime_string(day + "T00:00:00")
	var b := Time.get_unix_time_from_datetime_string(Time.get_date_string_from_system() + "T00:00:00")
	return int((b - a) / 86400.0)


func tidy_due() -> bool:
	if data.items.size() < 2:
		return false
	return _chars() > MAX_CHARS or _days_since(String(data.tidied)) >= TIDY_DAYS


# 한 달마다(또는 너무 길면) 정리. talk.gd 가 대답을 마친 뒤 부른다. force 면 때가 아니어도(확인용).
func tidy(force := false) -> void:
	if tidying or (not force and not tidy_due()) or data.items.is_empty():
		return
	if keystore == null or not keystore.has_key():
		return
	tidying = true
	var lines := PackedStringArray()
	for it in data.items:
		if it.get("w", "") != "self":   # 개구리 자신에 대한 것은 정리하지 않는다
			lines.append("- (%s) %s" % [it.get("d", "?"), it.t])
	if lines.size() < 2:
		tidying = false
		return
	var ask := ("아래는 한 사람에 대해 지난 대화에서 적어 둔 메모다(괄호는 적은 날짜). 오늘은 %s. 다음처럼 정리해라:\n"
		+ "- 같은 뜻은 하나로 합치고, 바뀐 것은 최근 것만 남긴다.\n"
		+ "- 이미 지난 일·한때의 일(지난 약속, 그때의 기분 등)은 뺀다. 오래 쓸 사실만.\n"
		+ "- 한 줄에 한 사실, 짧게(40자 안팎), 최대 %d줄. 새 사실을 지어내지 않는다.\n"
		+ "- 결과는 JSON 문자열 배열 하나만 출력한다(설명 없이).\n\n%s") % [Time.get_date_string_from_system(), TIDY_LINES, "\n".join(lines)]
	var body := {"model": TIDY_MODEL, "max_tokens": 3000, "output_config": {"effort": "low"},
		"messages": [{"role": "user", "content": ask}]}
	var headers := PackedStringArray(["content-type: application/json", "x-api-key: " + keystore.key,
		"anthropic-version: " + API_VERSION])
	if http.request(URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		tidying = false
		return
	var r: Array = await http.request_completed
	tidying = false
	if r[0] != HTTPRequest.RESULT_SUCCESS or int(r[1]) != 200:
		print("memory: 정리 실패 code ", r[1])
		return
	var d = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	if not (d is Dictionary):
		return
	var txt := ""
	for c in d.get("content", []):
		if c is Dictionary and c.get("type", "") == "text":
			txt += String(c.text)
	var a := txt.find("[")
	var b := txt.rfind("]")
	var arr = JSON.parse_string(txt.substr(a, b - a + 1)) if a >= 0 and b > a else null
	if not (arr is Array) or arr.is_empty():
		print("memory: 정리 결과를 못 읽음")
		return
	var before: int = data.items.size()
	var before_chars := _chars()
	_save(BAK)
	var today := Time.get_date_string_from_system()
	var items: Array = data.items.filter(func(it): return it.get("w", "") == "self")
	var keep: int = items.size()
	for s in arr:
		var t := String(s).strip_edges().left(ITEM_CHARS)
		if t != "" and not _sensitive(t):
			items.append({"t": t, "d": today})
	data.items = items.slice(0, keep + TIDY_LINES)
	data.tidied = today
	_save()
	print("memory: 정리 %d줄 %d자 → %d줄 %d자" % [before, before_chars, data.items.size(), _chars()])
