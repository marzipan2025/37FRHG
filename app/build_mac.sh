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
# Apple Development 인증서가 있으면 그걸로 서명한다(없으면 임시 서명).
ID=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | awk '{print $2}')
codesign --force --deep -s "${ID:--}" "$OUT"
echo "서명: ${ID:-임시}"
codesign -v "$OUT"
echo "완료: $OUT"
