extends Node
## Claude API 키. 저장소·파일에 두지 않고 맥 키체인(로그인 키체인, 일반 암호 항목)에 둔다.
## 37RHHG 는 user://claude_key.txt(다른 사용자도 읽을 수 있는 권한)에 두었다.
## - 읽기: `security find-generic-password -w` (출력으로만 받는다).
## - 쓰기: `security -i` 에 표준 입력으로 명령을 넘긴다. 명령줄 인자로 넘기면 그동안 ps 에 키가 보이기 때문.
##   항목을 만든 프로그램(/usr/bin/security)이 접근 목록에 들어가서 다시 읽을 때 키체인 창이 뜨지 않는다.
## - 넣기 전에 GET /v1/models(무료)로 키가 맞는지 본다.
## - 37RHHG 에 저장된 키가 있고 여기 키가 없으면 처음 한 번 가져올지 묻는다.
## 키 내용은 print·로그에 절대 남기지 않는다.

signal saved(ok: bool, msg: String)   # set_key 결과(말풍선에 띄울 말)

const SEC := "/usr/bin/security"
const ACCOUNT := "claude"
const API_VERSION := "2026-10-21"
const MODELS_URL := "https://api.anthropic.com/v1/models?limit=1"
const OLD_KEY := "Library/Application Support/Godot/app_userdata/37RHHG/claude_key.txt"
const PREFS := "user://prefs.cfg"

var service := "37FRHG Claude API"     # 확인용으로 FRHG_KEY_SERVICE 를 주면 다른 항목을 쓴다
var key := ""
var busy := false
var http: HTTPRequest


func _ready() -> void:
	var sv := OS.get_environment("FRHG_KEY_SERVICE")
	if sv != "":
		service = sv
	http = HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	key = _read()


func has_key() -> bool:
	return key != ""


static func looks_like_key(k: String) -> bool:
	if not k.begins_with("sk-ant-") or k.length() < 20 or k.length() > 400:
		return false
	for c in k:
		if not (c in "-_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")):
			return false
	return true


func _read() -> String:
	var out := []
	var code := OS.execute(SEC, ["find-generic-password", "-s", service, "-a", ACCOUNT, "-w"], out, false)
	if code != 0 or out.is_empty():
		return ""
	var k := String(out[0]).strip_edges()
	return k if looks_like_key(k) else ""


func _write(k: String) -> bool:
	if not looks_like_key(k):
		return false
	var p := OS.execute_with_pipe(SEC, ["-i"], false)
	if p.is_empty():
		return false
	var io: FileAccess = p.stdio
	io.store_string('add-generic-password -U -s "%s" -a "%s" -w "%s"\n' % [service, ACCOUNT, k])
	io.flush()
	io.close()
	var t := 0
	while OS.is_process_running(p.pid) and t < 3000:
		OS.delay_msec(20)
		t += 20
	if OS.is_process_running(p.pid):
		OS.kill(p.pid)
	return _read() == k


# 키체인 항목을 지운다(확인용 정리).
func delete_key() -> void:
	OS.execute(SEC, ["delete-generic-password", "-s", service, "-a", ACCOUNT], [], false)
	key = ""


# 키가 맞는지 보고(무료 호출) 키체인에 넣는다. 결과는 saved 신호로.
func set_key(k: String) -> void:
	k = k.strip_edges()
	if busy:
		return
	if not looks_like_key(k):
		saved.emit(false, "Claude API 키 모양이 아니에요. sk-ant- 로 시작하는 키를 붙여 넣어 주세요.")
		return
	busy = true
	var res := await _check(k)
	busy = false
	if res == 401 or res == 403:
		saved.emit(false, "키가 맞지 않아요. 다시 확인해 주세요.")
		return
	if not _write(k):
		saved.emit(false, "키체인에 넣지 못했어요.")
		return
	key = k
	if res == 200:
		saved.emit(true, "키를 넣었어요. 이제 말을 걸 수 있어요!")
	else:
		saved.emit(true, "키를 넣었어요. 다만 지금은 맞는 키인지 확인하지 못했어요.")


# HTTP 상태 코드(연결 실패면 0).
func _check(k: String) -> int:
	var err := http.request(MODELS_URL, PackedStringArray(["x-api-key: " + k, "anthropic-version: " + API_VERSION]))
	if err != OK:
		return 0
	var r: Array = await http.request_completed
	return int(r[1]) if r[0] == HTTPRequest.RESULT_SUCCESS else 0


# 여기 키가 없고 37RHHG 키 파일이 있으면 처음 한 번만 가져올지 묻는다.
func offer_import() -> void:
	if has_key():
		return
	var path := OS.get_environment("HOME").path_join(OLD_KEY)
	if not FileAccess.file_exists(path):
		return
	var cfg := ConfigFile.new()
	cfg.load(PREFS)
	if cfg.get_value("key", "import_asked", false):
		return
	cfg.set_value("key", "import_asked", true)
	cfg.save(PREFS)
	DisplayServer.dialog_show("37FRHG", "37RHHG 에 저장된 Claude API 키가 있어요. 이 앱에서도 쓸까요?\n(이 앱은 키를 맥 키체인에 넣어요.)",
		PackedStringArray(["가져오기", "아니요"]), func(i: int):
			if i == 0:
				set_key(FileAccess.get_file_as_string(path)))
