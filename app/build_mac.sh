#!/bin/zsh
# 메뉴바 개구리 마법사 앱을 build/37FRHG.app 으로 내보낸다.
# Dock 아이콘 숨김(LSUIElement)은 export_presets.cfg 의 additional_plist_content 로 들어간다.
set -e
cd "$(dirname "$0")"
OUT=../build/37FRHG.app
rm -rf "$OUT"
mkdir -p ../build
godot --headless --path . --import >/dev/null 2>&1 || true
godot --headless --path . --export-release "macOS" "$OUT" 2>&1 | grep -E "ERROR" && exit 1 || true
[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$OUT/Contents/Info.plist")" = "true" ] || { echo "LSUIElement 누락"; exit 1; }
# 말풍선 그림(app/bubble, Godot 임포트 제외)과 카카오 빅 산스(저장소에 안 넣음)를 Resources 에 넣는다.
# 글꼴은 FRHG_FONT=<ttf 경로> → ~/Library/Fonts → 37RHHG 설치본 순서로 찾고, 없으면 말풍선이 시스템 글꼴로 빠진다.
mkdir -p "$OUT/Contents/Resources/bubble"
cp bubble/bubblefrog.png bubble/froginput.png "$OUT/Contents/Resources/bubble/"
FONT="${FRHG_FONT:-}"
for f in "$HOME/Library/Fonts/KakaoBigSans-Regular.ttf" /Applications/37RHHG.app/Contents/Resources/fonts/KakaoBigSans-Regular.ttf; do
  [ -z "$FONT" ] && [ -f "$f" ] && FONT="$f"
done
if [ -n "$FONT" ]; then
  mkdir -p "$OUT/Contents/Resources/fonts"
  cp "$FONT" "$OUT/Contents/Resources/fonts/KakaoBigSans-Regular.ttf"
else
  echo "카카오 빅 산스 없음: 말풍선은 시스템 글꼴"
fi
# Apple Development 인증서가 있으면 그걸로 서명한다(없으면 임시 서명).
ID=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | awk '{print $2}')
codesign --force --deep -s "${ID:--}" "$OUT"
echo "서명: ${ID:-임시}"
codesign -v "$OUT"
echo "완료: $OUT"
