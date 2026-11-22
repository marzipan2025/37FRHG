extends Node
# 메뉴바 "업데이트 확인…": GitHub 최신 릴리스(marzipan2025/37FRHG)의 태그를 이 앱 버전과 비교해
# macOS 대화상자로 알린다. 새 버전이면 [업데이트]를 누를 때 zip(37FRHG-v<버전>.zip)을 받아,
# 이 앱이 끝나길 기다린 작은 셸이 번들을 바꾸고 다시 띄운다(37RHHG 도우미 Updater 와 같은 흐름을 GDScript 로).
# GitHub API 를 키 없이 부르므로 저장소가 공개여야 한다(비공개면 404 → "확인하지 못했어요").

const REPO := "marzipan2025/37FRHG"
const API := "https://api.github.com/repos/%s/releases/latest" % REPO

var http: HTTPRequest
var busy := false
var zip_url := ""
var new_version := ""


func _ready() -> void:
	http = HTTPRequest.new()
	http.max_redirects = 8
	add_child(http)


# 이 앱 버전: 내보낸 앱의 Info.plist(CFBundleShortVersionString). 개발 실행이면 "".
func app_version() -> String:
	var plist := _bundle_path().path_join("Contents/Info.plist")
	if not FileAccess.file_exists(plist):
		return ""
	var s := FileAccess.get_file_as_string(plist)
	var re := RegEx.create_from_string("<key>CFBundleShortVersionString</key>\\s*<string>([^<]+)</string>")
	var m := re.search(s)
	return m.get_string(1) if m else ""


# .../37FRHG.app (실행 파일은 .../37FRHG.app/Contents/MacOS/37FRHG)
func _bundle_path() -> String:
	var exe := OS.get_executable_path()
	if not exe.contains(".app/Contents/MacOS/"):
		return ""
	return exe.get_base_dir().get_base_dir().get_base_dir()


func check(manual: bool) -> void:
	if busy:
		return
	busy = true
	var err := http.request(API, PackedStringArray(["User-Agent: 37FRHG", "Accept: application/vnd.github+json"]))
	if err != OK:
		busy = false
		_alert("업데이트를 확인하지 못했어요.")
		return
	var res: Array = await http.request_completed
	busy = false
	var code: int = res[1]
	if res[0] != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("update check failed ", res[0], " ", code)
		_alert("업데이트를 확인하지 못했어요.")
		return
	var j = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(j) != TYPE_DICTIONARY:
		_alert("업데이트를 확인하지 못했어요.")
		return
	new_version = String(j.get("tag_name", "")).trim_prefix("v")
	zip_url = ""
	for a in j.get("assets", []):
		if String(a.get("name", "")).ends_with(".zip"):
			zip_url = String(a.get("browser_download_url", ""))
	var cur := app_version()
	print("update check: latest ", new_version, " this ", cur)
	if cur != "" and _newer(new_version, cur) and zip_url != "":
		DisplayServer.dialog_show("37FRHG", "새 버전 v%s이 있어요(지금 v%s). 지금 업데이트할까요?" % [new_version, cur],
			PackedStringArray(["업데이트", "나중에"]), _on_answer)
	elif manual:
		_alert("이게 최신이에요(v%s)." % (cur if cur != "" else new_version))


func _on_answer(i: int) -> void:
	if i == 0:
		_install()


func _newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false


func _install() -> void:
	var app := _bundle_path()
	if app == "":
		_alert("개발 실행에서는 업데이트할 수 없어요.")
		return
	var zip := OS.get_user_data_dir().path_join("update.zip")
	http.download_file = zip
	var err := http.request(zip_url, PackedStringArray(["User-Agent: 37FRHG"]))
	if err != OK:
		http.download_file = ""
		_alert("업데이트를 받지 못했어요.")
		return
	var res: Array = await http.request_completed
	http.download_file = ""
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_alert("업데이트를 받지 못했어요.")
		return
	# 이 앱이 끝나면 풀어서(격리 표시 지움) 번들을 바꾸고 다시 띄운다.
	var sh := "while kill -0 %d 2>/dev/null; do sleep 0.3; done; T=$(mktemp -d); " % OS.get_process_id() \
		+ "/usr/bin/ditto -x -k \"$0\" \"$T\" && /usr/bin/xattr -dr com.apple.quarantine \"$T\"; " \
		+ "NEW=$(ls -d \"$T\"/*.app | head -1); " \
		+ "if [ -d \"$NEW\" ]; then /bin/rm -rf \"$1\" && /bin/mv \"$NEW\" \"$1\"; fi; /bin/rm -rf \"$T\" \"$0\"; /usr/bin/open \"$1\""
	OS.create_process("/bin/sh", PackedStringArray(["-c", sh, zip, app]))
	get_tree().quit()


func _alert(msg: String) -> void:
	DisplayServer.dialog_show("37FRHG", msg, PackedStringArray(["확인"]), func(_i: int): pass)
