// 37FRHG 화면 조작 도우미(손쉬운 사용 API). build_mac.sh 가 swiftc 로 Contents/MacOS/frhgax 로 만들어 넣는다.
// 앱(37FRHG)이 자식 프로세스로 부르므로 손쉬운 사용 권한은 37FRHG 에 붙는다(처음엔 시스템이 허용 창을 띄움).
// 결과는 표준 출력에 JSON 한 줄. 종료 코드: 0 성공·못 찾음 모두, 2 권한 없음, 1 그 밖의 오류.
//
//   frhgax music-play <덤프 파일> <기다릴 초> <곡 길이 m:ss> <트랙 번호> <앨범 곡 수> <곡 이름>
//     음악 앱에 열린 앨범 페이지에서 그 곡 줄을 찾아 누른다. 곡 줄은 곡 길이(m:ss) 글자로 먼저 찾고(한국 페이지는
//     곡 이름이 검색 결과의 영어 이름과 다를 수 있어서), 없으면 곡 이름으로. 줄 안의 '재생'·'Play' 버튼이 있으면
//     누르고(AXPress), 없으면 줄 가운데를 두 번 누른다(마우스 이벤트, 음악 앱을 앞으로 가져옴). 앨범 곡이 하나면
//     페이지의 재생 버튼을 눌러도 된다. 찾은 화면 구조를 덤프 파일에 남긴다(고칠 때 씀).
import ApplicationServices
import Cocoa

func out(_ obj: [String: Any], _ code: Int32 = 0) -> Never {
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    exit(code)
}

struct Node {
    let el: AXUIElement
    let parent: Int
    let depth: Int
    let role: String
    let text: String   // 제목·설명·값을 이은 것
    let frame: CGRect
}

func attr(_ e: AXUIElement, _ a: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
}

func frame(_ e: AXUIElement) -> CGRect {
    var p = CGPoint.zero
    var s = CGSize.zero
    if let v = attr(e, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    if let v = attr(e, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &s) }
    return CGRect(origin: p, size: s)
}

func walk(_ root: AXUIElement, limit: Int = 9000) -> [Node] {
    var nodes: [Node] = []
    var queue: [(AXUIElement, Int, Int)] = [(root, -1, 0)]
    var i = 0
    while i < queue.count && nodes.count < limit {
        let (e, parent, depth) = queue[i]
        i += 1
        let role = attr(e, kAXRoleAttribute) as? String ?? ""
        var parts: [String] = []
        for a in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
            if let s = attr(e, a) as? String, !s.isEmpty { parts.append(s) }
        }
        nodes.append(Node(el: e, parent: parent, depth: depth, role: role, text: parts.joined(separator: " | "), frame: frame(e)))
        let me = nodes.count - 1
        if depth < 60, let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] {
            for k in kids { queue.append((k, me, depth + 1)) }
        }
    }
    return nodes
}

func dump(_ nodes: [Node], _ path: String) {
    var s = ""
    for n in nodes {
        s += String(repeating: " ", count: min(n.depth, 40)) + n.role + " [" + n.text.prefix(80) + "] "
        s += "\(Int(n.frame.minX)),\(Int(n.frame.minY)) \(Int(n.frame.width))x\(Int(n.frame.height))\n"
    }
    try? s.write(toFile: path, atomically: true, encoding: .utf8)
}

func isPlay(_ n: Node) -> Bool {
    let t = n.text.lowercased()
    return n.role == "AXButton" && (t.contains("재생") || t.hasPrefix("play") || t.contains(" play"))
        && !t.contains("다음") && !t.contains("셔플") && !t.contains("shuffle") && !t.contains("next")
}

// 그 노드를 품은 '줄': 위로 올라가며 AXRow 를 찾고, 없으면 폭이 넓고(목록 줄) 높이가 낮은 첫 조상.
func rowOf(_ nodes: [Node], _ idx: Int) -> Int {
    var i = nodes[idx].parent
    var wide = -1
    while i >= 0 {
        let n = nodes[i]
        if n.role == "AXRow" { return i }
        if wide < 0 && n.frame.width > 300 && n.frame.height > 20 && n.frame.height < 90 { wide = i }
        i = nodes[i].parent
    }
    return wide
}

func inside(_ nodes: [Node], _ root: Int, _ idx: Int) -> Bool {
    var i = idx
    while i >= 0 {
        if i == root { return true }
        i = nodes[i].parent
    }
    return false
}

func doubleClick(_ p: CGPoint) {
    let src = CGEventSource(stateID: .hidSystemState)
    for n in 1...2 {
        for t in [CGEventType.leftMouseDown, .leftMouseUp] {
            let e = CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!
            e.setIntegerValueField(.mouseEventClickState, value: Int64(n))
            e.post(tap: .cghidEventTap)
            usleep(15000)
        }
        usleep(60000)
    }
}

let args = CommandLine.arguments
guard args.count >= 2 else { out(["error": "usage"], 1) }
let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
guard AXIsProcessTrustedWithOptions(opts) else { out(["error": "denied"], 2) }

if args[1] == "music-play" {
    guard args.count >= 8 else { out(["error": "usage"], 1) }
    let dumpPath = args[2]
    let wait = Double(args[3]) ?? 8
    let dur = args[4]
    let trackNo = args[5]
    let count = Int(args[6]) ?? 0
    let title = args[7...].joined(separator: " ")
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else {
        out(["result": "no-app"])
    }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    let t0 = Date()
    var nodes: [Node] = []
    while Date().timeIntervalSince(t0) < wait {
        let win = (attr(ax, kAXFocusedWindowAttribute) ?? attr(ax, kAXMainWindowAttribute)).map { $0 as! AXUIElement }
        if let w = win {
            nodes = walk(w)
            // 1) 곡 길이 글자 → 2) 곡 이름 글자로 곡 줄 찾기
            var hit = -1
            for (i, n) in nodes.enumerated() where n.role == "AXStaticText" && n.text == dur { hit = i; break }
            if hit < 0 {
                for (i, n) in nodes.enumerated() where n.role == "AXStaticText" && !title.isEmpty && n.text.hasPrefix(title) { hit = i; break }
            }
            if hit >= 0 {
                let row = rowOf(nodes, hit)
                if row >= 0 {
                    if let b = nodes.indices.first(where: { inside(nodes, row, $0) && isPlay(nodes[$0]) }) {
                        let err = AXUIElementPerformAction(nodes[b].el, kAXPressAction as CFString)
                        dump(nodes, dumpPath)
                        out(["result": "row-button", "ax": err.rawValue, "row": nodes[row].text, "secs": Date().timeIntervalSince(t0)])
                    }
                    app.activate()
                    usleep(250000)
                    let f = nodes[row].frame
                    doubleClick(CGPoint(x: f.midX, y: f.midY))
                    dump(nodes, dumpPath)
                    out(["result": "row-double-click", "row": nodes[row].text, "track": trackNo, "secs": Date().timeIntervalSince(t0)])
                }
            }
            // 곡이 하나뿐인 앨범(싱글)은 페이지의 재생 버튼으로 충분하다.
            if count == 1, let b = nodes.firstIndex(where: isPlay) {
                let err = AXUIElementPerformAction(nodes[b].el, kAXPressAction as CFString)
                dump(nodes, dumpPath)
                out(["result": "page-button", "ax": err.rawValue, "secs": Date().timeIntervalSince(t0)])
            }
        }
        usleep(500000)
    }
    dump(nodes, dumpPath)
    out(["result": "not-found", "nodes": nodes.count])
}
out(["error": "usage"], 1)
