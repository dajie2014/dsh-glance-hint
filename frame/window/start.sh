#!/bin/bash
# 把阿达放出来 —— 一条命令，两件事：
#   ① 看门狗（没有的话）先起来，它负责"我现在在干嘛"；
#   ② 浮窗起来，它负责"把这件事演出来"。
#
#   ./start.sh              正常放出来（占着这个终端）
#   ./start.sh --open       放出来但不占终端（双击「阿达」用的就是它）
#   ./start.sh --dry        只看它打算干什么，不真起
#
# 想收工：关浮窗（右键 → 退出阿达），再 `pkill -f ghs-watch.mjs`。

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WATCH="${HERE}/../ghs-watch.mjs"
# ★ 放出来的**不是** build/ 里那份，而是装到「文稿」外面的一份（~/Applications/Ada.app）——
#   原因见 install.sh 抬头那段：开机自启读不了文稿，系统会直接拒。
APP_BUNDLE="${HOME}/Applications/Ada.app"
APP="${APP_BUNDLE}/Contents/MacOS/GlanceHintFrame"
NODE="${HOME}/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/node/bin/node"
LOG="${GHS_WATCH_LOG:-/tmp/ghs-watch.log}"

DRY=""
[ "${1:-}" = "--dry" ] && DRY="1"

if [ -z "${DRY}" ]; then
  # 每次放出来之前先装一份到 ~/Applications（不到 1MB，很快）—— 保证跑起来的是最新的
  "${HERE}/install.sh"
fi

[ -f "${WATCH}" ] || { echo "找不到看门狗：${WATCH}"; exit 1; }
[ -x "${APP}" ]   || { echo "浮窗还没编译，先跑 ./build.sh：${APP}"; exit 1; }

if [ -n "${DRY}" ]; then
  echo "打算：装一份到 ~/Applications/Ada.app"
  echo "打算：node ${WATCH}  → 日志 ${LOG}"
  echo "打算：${APP}"
  exit 0
fi

# ★ 已经在跑就别再起一个。
#   2026-10-11 踩过：中断 shell 时 nohup 起的后台进程不会跟着死，
#   再起一个就叠成两份 —— 别让同一件事有两个进程在干。
#
#   ⚠️ 判活用的是**看门狗自己写的 pid 文件**（信号 0 探一下），不是 `pgrep -f ghs-watch.mjs`：
#   后者按"命令行里有没有这个字样"匹配，任何提到过这个名字的命令都会被它算成看门狗
#   （调试时敲的 shell、tail 日志的命令，全算）—— 2026-10-11 就被这个骗过一轮，以为在跑其实没有。
STATE_FILE="${GHS_STATE_FILE:-${HOME}/Library/Application Support/GlanceHint/state.json}"
PID_FILE="${GHS_PID_FILE:-$(dirname "${STATE_FILE}")/watch.pid}"
# 浮窗和看门狗必须看**同一个**文件 —— 从这里统一发出去，免得两边各用各的默认值
export GHS_STATE_FILE="${STATE_FILE}"

watch_alive() {
  [ -f "${PID_FILE}" ] || return 1
  local p
  p="$(tr -d '[:space:]' < "${PID_FILE}" 2>/dev/null || true)"
  [ -n "${p}" ] || return 1
  kill -0 "${p}" 2>/dev/null
}

if watch_alive; then
  echo "看门狗已经在跑了（pid $(cat "${PID_FILE}")），不重复起"
else
  echo "看门狗起来了，日志：${LOG}"
  nohup "${NODE}" "${WATCH}" >"${LOG}" 2>&1 &
  disown 2>/dev/null || true
  sleep 1
fi

# ★ 同样的道理：阿达已经在屏幕上就别再放一个。双击两下会叠出两个小人，看着像见鬼。
#   这里用 `pgrep -x`（**按进程名精确匹配**），同样不用 -f。
if pgrep -x "GlanceHintFrame" >/dev/null 2>&1; then
  echo "阿达已经在屏幕上了，不重复放"
  exit 0
fi

echo "浮窗起来了"
if [ "${1:-}" = "--open" ]; then
  # --open：交给系统去起。这样浮窗**不拴在这个终端窗口上** —— 双击那个入口用的就是这条，
  # 否则用户一关终端，阿达就跟着没了。
  open "${APP_BUNDLE}"
else
  exec "${APP}"
fi
