#!/bin/bash
# 每天翻一遍日志，看看这个小东西有没有「瞎报」「漏报」「卡死」。
#
# 为什么要有它 —— 他 2026-10-11 那句话：「它的作用对于 Operator 来讲比好玩更重要」。
# 所以定下的次序是 **可信度 > 反应速度 > 花样**，而**误报最伤**：错一次他就不信它了。
# 这个脚本只负责把「可信度」里**能自动查的那部分**查出来：
#
#   能自动查：卡死、断线、日志报错、状态抖（来回乱切）
#   没法自动查：某一格演得对不对 —— 那得他自己看，我看不了他的屏幕
#
# 用法：
#   ./check-health.sh            人看的（全部结论）
#   ./check-health.sh --quiet    定时任务用：没异常就一声不出，有异常才打印

set -uo pipefail
LIB="${HOME}/Library/Application Support/GlanceHint"
QUIET=""
[ "${1:-}" = "--quiet" ] && QUIET=1

OK=(); BAD=(); NOTE=()
say() { [ -n "${QUIET}" ] || printf '%s\n' "$*"; }

# ── ① 三个进程都活着吗 ──────────────────────────────────────────
if pgrep -x GlanceHintFrame >/dev/null 2>&1; then OK+=("小窗在跑")
else BAD+=("小窗没在跑"); fi

if pgrep -f 'bash.*keeper.sh' >/dev/null 2>&1; then OK+=("看门人在跑")
else BAD+=("看门人没在跑 —— 开机它就不会自己出来"); fi

WATCH_PID=""
if [ -f "${LIB}/watch.pid" ]; then
  WATCH_PID="$(tr -d '[:space:]' < "${LIB}/watch.pid" 2>/dev/null || true)"
fi
if [ -n "${WATCH_PID}" ] && kill -0 "${WATCH_PID}" 2>/dev/null; then OK+=("看门狗在跑（pid ${WATCH_PID}）")
else BAD+=("看门狗没在跑 —— 状态不会更新了"); fi

# ── ② 心跳新鲜吗（状态文件多久没更新） ──────────────────────────
if [ -f "${LIB}/state.json" ]; then
  read -r AGE STATE NAME < <(python3 - "${LIB}/state.json" <<'PY'
import json, sys, time
try:
    d = json.load(open(sys.argv[1]))
    print(int(time.time() - d.get("at", 0) / 1000), d.get("state", "?"), d.get("name", "?"))
except Exception:
    print(-1, "?", "?")
PY
)
  if [ "${AGE}" -lt 0 ]; then BAD+=("状态文件读不动（坏了？）")
  elif [ "${AGE}" -lt 120 ]; then OK+=("心跳 ${AGE} 秒前（当前：${STATE} ${NAME}）")
  else BAD+=("心跳停在 ${AGE} 秒前 —— 可能断了"); fi
else
  BAD+=("没有状态文件")
fi

# ── ③ 日志里有没有报错 ──────────────────────────────────────────
ERRS=0
for f in frame.log watch.log keeper.log; do
  if [ -f "${LIB}/${f}" ]; then
    n=$(grep -c -E "失败|错误|出错|起不来|Error|error" "${LIB}/${f}" 2>/dev/null || true)
    ERRS=$(( ERRS + ${n:-0} ))
  fi
done
if [ "${ERRS}" -eq 0 ]; then OK+=("日志里没有报错")
else NOTE+=("日志里出现 ${ERRS} 行「失败/错误」—— 值得翻一眼"); fi

# ── ④ 状态抖不抖（相邻两次切换挨得太近 = 来回乱跳） ──────────────
if [ -f "${LIB}/watch.log" ]; then
  read -r TOTAL JITTER < <(python3 - "${LIB}/watch.log" <<'PY'
import re, sys
rows = []
for line in open(sys.argv[1], errors="ignore"):
    m = re.match(r"\[(\d\d):(\d\d):(\d\d)\] → 状态 (\d)", line)
    if m:
        h, mi, s, st = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
        rows.append((h * 3600 + mi * 60 + s, st))
rows = rows[-400:]                      # 只看最近 400 次
jit = sum(1 for a, b in zip(rows, rows[1:]) if b[0] - a[0] <= 3)   # 3 秒内又切了一次
print(len(rows), jit)
PY
)
  RATIO=$(( JITTER * 100 / (TOTAL > 0 ? TOTAL : 1) ))
  # 样本太少（刚重启、用得不多的日子）不算异常，直接跳过 —— 别瞎喊
  if [ "${TOTAL}" -ge 50 ]; then
    if [ "${RATIO}" -lt 25 ]; then
      OK+=("状态切换 ${TOTAL} 次，其中挨得近的 ${JITTER} 次（${RATIO}%）—— 不抖")
    else
      NOTE+=("状态切换 ${TOTAL} 次里有 ${JITTER} 次挨得极近（${RATIO}%）—— 有点抖，翻日志看看是不是误报")
    fi
  fi
fi

# ── ⑤ 结论 ─────────────────────────────────────────────────────
if [ -n "${QUIET}" ] && [ "${#BAD[@]}" -eq 0 ] && [ "${#NOTE[@]}" -eq 0 ]; then
  exit 0                                # 一切正常：一声不出
fi

echo "揽示健康检查 · $(date '+%m-%d %H:%M')"
echo
# ⚠️ bash 3.2 里 "${ARR[@]}" 碰到空数组会报 unbound variable（配上 set -u 直接退出），
#    所以每个都要先看长度。
if [ "${#OK[@]}" -gt 0 ]; then for x in "${OK[@]}"; do echo "  ✓ ${x}"; done; fi
if [ "${#NOTE[@]}" -gt 0 ]; then for x in "${NOTE[@]}"; do echo "  · ${x}"; done; fi
if [ "${#BAD[@]}" -gt 0 ]; then for x in "${BAD[@]}"; do echo "  ✗ ${x}"; done; fi
echo
if [ "${#BAD[@]}" -eq 0 ] && [ "${#NOTE[@]}" -eq 0 ]; then
  echo "结论：一切正常。"
elif [ "${#BAD[@]}" -eq 0 ]; then
  echo "结论：能跑，但有上面几条值得翻一眼。"
else
  echo "结论：有东西没在跑，看看要不要重启它。"
  exit 1
fi
