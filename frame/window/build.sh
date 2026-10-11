#!/bin/bash
# 把浮窗编译并打包成一个能双击的 .app。
#
#   ./build.sh          编译 → 出 build/GlanceHintFrame.app
#   ./build.sh run      编译完顺手跑起来
#
# 产物是自包含的：页面和图片都拷进 .app 里，拿走这个 app 就能单独用。
# ★ 代价是：**换了页面或换了图，要重跑一次 build.sh**（几秒的事）。

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
DEMO="${ROOT}/assets/runtime/glance-hint-demo.html"
STAGE="${ROOT}/assets/runtime/ada-stage.html"
REF="${ROOT}/assets/ref/ada-ref-02-anime-clean.png"
STATES="${ROOT}/assets/states"
OUT="${HERE}/build"
APP="${OUT}/GlanceHintFrame.app"
BIN="${APP}/Contents/MacOS/GlanceHintFrame"
RES="${APP}/Contents/Resources"

[ -f "${DEMO}" ]  || { echo "找不到演示页：${DEMO}"; exit 1; }
[ -f "${STAGE}" ] || { echo "找不到舞台页：${STAGE}"; exit 1; }
[ -f "${REF}" ]   || { echo "找不到定妆图（缺图时页面没得退回）：${REF}"; exit 1; }

echo "── 1/4 清理"
rm -rf "${APP}"
mkdir -p "$(dirname "${BIN}")" "${RES}/runtime" "${RES}/ref" "${RES}/states"

echo "── 2/4 编译"
mkdir -p "${OUT}/mcache"
# -module-cache-path 指到工作区里：默认那个系统 clang 缓存目录在沙箱下写不了
swiftc -O -swift-version 5 \
  -target arm64-apple-macosx13.0 \
  -module-cache-path "${OUT}/mcache" \
  "${HERE}/main.swift" \
  -o "${BIN}" \
  -framework Cocoa -framework WebKit

echo "── 3/4 拷页面和图片"
# 拷进去的页面各自写死成小窗样子。为什么不在运行时用 ?embed=1 传参：
# file:// 带查询串在 WKWebView 上不稳，写死最省心。

# 演示页（备选）：embed —— 只留阿达，标题按钮音量条全撤。
/usr/bin/python3 - "${DEMO}" "${RES}/runtime/glance-hint-demo.html" embed \
  '<html lang="zh-CN">' <<'PY'
import sys
src, dst, cls, anchor = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(src, encoding="utf-8").read()
assert s.count(anchor) == 1, f"{dst}：锚点出现 {s.count(anchor)} 次"
open(dst, "w", encoding="utf-8").write(
    s.replace(anchor, f'<html lang="zh-CN" class="{cls}">'))
PY

# ★ 七格舞台页：浮窗现在演的就是这一页。把 FORCE_COMPACT 从 false 改成 true。
/usr/bin/python3 - "${STAGE}" "${RES}/runtime/ada-stage.html" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()
old = "var FORCE_COMPACT = false;"
assert s.count(old) == 1, f"舞台页：锚点出现 {s.count(old)} 次"
open(dst, "w", encoding="utf-8").write(
    s.replace(old, "var FORCE_COMPACT = true;"))
PY

# ★ 图片要按**原样的相对层级**放：页面里写的是 ../ref/ 和 ../states/，
#   所以得放成 Resources/ref/、Resources/states/ —— 跟页面所在的 runtime/ 平级。
#   放错层级不会报错，只会让页面 404 退回定妆图（看着像"图没生效"，很难查）。
cp "${REF}" "${RES}/ref/face.png"     # 名字用中性的 face.png（发布版里它会换成默认角色的脸）
# 问候音：他那句克隆声（1.94 秒）。页面里写的是 ../welcome.wav ⇒ 要落在 Resources 根上，
# 不能塞进 runtime/。alt/ 里那份旧台词（"…想干吗"）**不拷**，免得混进包里。
if [ -f "${ROOT}/assets/welcome.wav" ]; then
  cp "${ROOT}/assets/welcome.wav" "${RES}/"
else
  echo "    ⚠️ 没有 assets/welcome.wav：启动问候会没声音（画面照常）"
fi
# 七格图：有几张带几张；一张都没有也照常能跑（页面自己退回定妆图）
shopt -s nullglob
for f in "${STATES}"/*.png; do cp "${f}" "${RES}/states/"; done
shopt -u nullglob

# 浮窗照这一行去找页面（相对 Resources 的路径）
printf '%s\n' "runtime/ada-stage.html" > "${RES}/page-path.txt"
echo "    演的是：$(cat "${RES}/page-path.txt")"
echo "    七格图：$(ls "${RES}/states" | wc -l | tr -d ' ') 张（0 张就退回定妆图）"
echo "    问候音：$( [ -f "${RES}/welcome.wav" ] && echo "有" || echo "没有" )"

echo "── 3.5/4 记下 node 和看门狗在哪"
# 浮窗要靠这两个路径把看门狗拉起来。记绝对路径，因为 app 会被双击、没有工作目录可言。
NODE_BIN="${GHS_NODE:-${HOME}/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/node/bin/node}"
if [ ! -x "${NODE_BIN}" ]; then
  NODE_BIN="$(command -v node || true)"
fi
printf '%s\n' "${NODE_BIN}" > "${RES}/node-path.txt"
printf '%s\n' "$(cd "${HERE}/.." && pwd)/ghs-watch.mjs" > "${RES}/watch-path.txt"
echo "    node: ${NODE_BIN}"
echo "    看门狗: $(cat "${RES}/watch-path.txt")"

echo "── 4/4 写 Info.plist"
cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>            <string>GlanceHintFrame</string>
	<key>CFBundleDisplayName</key>     <string>阿达</string>
	<key>CFBundleIdentifier</key>      <string>com.jieda.glancehint.frame</string>
	<key>CFBundleExecutable</key>      <string>GlanceHintFrame</string>
	<key>CFBundlePackageType</key>     <string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1.0</string>
	<key>CFBundleVersion</key>         <string>1</string>
	<key>LSMinimumSystemVersion</key>  <string>13.0</string>
	<key>NSHighResolutionCapable</key> <true/>
	<key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

echo "好了：${APP}"

if [ "${1:-}" = "run" ]; then
  echo "── 跑起来"
  exec "${BIN}"
fi
