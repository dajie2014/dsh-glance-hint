#!/bin/bash
# 看门人 —— 不露面，只干一件事：**DSH 在的时候，让阿达也在**。
#
# 为什么需要它（他 2026-10-11 定的两条）：
#   · 「我关掉 DSH 的时候，GHS 也关掉了」→ 阿达在 DSH 关掉时**真的退出**，桌面上一点不剩
#   · 「开的时候也把它一道开下来」      → 可 DSH 启动时不会通知谁，得有个东西把阿达叫出来
#
#   一个进程不可能既"退干净"、又"自己知道 DSH 回来了" —— 这两件事只能分给两个角色：
#   **阿达负责"关"，这个看门人负责"开"。**
#
# 它没有窗口、不进 Dock，就每 5 秒看一眼 DSH 的端口。
#
# 三条规矩（照他的使用习惯定的）：
#   ① DSH 不在          → 什么都不做，等着
#   ② DSH 在、阿达不在   → 把阿达叫出来
#   ③ 他右键"退出阿达"   → **不要**马上再叫一个（阿达退出时会留个记号文件），
#                          等 DSH 下次重新打开，才算新回合
#
# 由 launchd 登录项托管（`com.jieda.glancehint.frame`，KeepAlive=true）：崩了会被自动重起。
# ⚠️ 它必须住在「文稿」外面（TCC 不让登录项读文稿，见 install.sh 抬头）—— install.sh 会把它
#    和 app 一起装到 ~/Library/Application Support/GlanceHint/。

set -uo pipefail

LIB="${HOME}/Library/Application Support/GlanceHint"
APP="${GHS_APP:-${HOME}/Applications/Ada.app}"
BIN="${APP}/Contents/MacOS/GlanceHintFrame"
PORT="${GHS_DSH_PORT:-19387}"
FLAG="${LIB}/user-quit"
LOG="${GHS_KEEPER_LOG:-${LIB}/keeper.log}"   # 自测时可以指到别处（Application Support 从沙箱里写不了）

mkdir -p "${LIB}"
log() { printf '[%s] %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "${LOG}"; }

# 探 DSH 的端口：连的是本地回环，端口关着会**立刻**被拒，不花时间
dsh_up() { (exec 3<>/dev/tcp/127.0.0.1/"${PORT}") 2>/dev/null; }

log "看门人起来了（DSH 端口 ${PORT}，阿达在 ${BIN}）"

# 阿达还没装出来时就等着，别退出（退出会被 launchd 立刻重起，刷日志）
while [ ! -x "${BIN}" ]; do
  log "还没装出阿达（${BIN}），等 60 秒再看"
  sleep 60
done

while true; do
  if dsh_up; then
    if [ -f "${FLAG}" ]; then
      sleep 5
      continue                       # 规矩③：他自己收的，别烦他
    fi
    if pgrep -x GlanceHintFrame >/dev/null 2>&1; then
      sleep 5
      continue                       # 阿达已经在跑（也许是他自己双击开的）
    fi
    log "DSH 在，把阿达叫出来"
    "${BIN}"                           # 前台跑，一直到阿达退出为止
    if dsh_up; then
      log "阿达退出了，DSH 还在 —— 他要是自己收的（留了记号）下轮就不叫，不然 5 秒后会再叫一个"
    else
      log "DSH 关掉了，阿达跟着收工"
    fi
  else
    rm -f "${FLAG}"                    # 规矩③：DSH 没了 ⇒ 记号作废，下次开 DSH 是新回合
  fi
  sleep 5
done
