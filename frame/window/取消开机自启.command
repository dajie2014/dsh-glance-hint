#!/bin/bash
# 双击这个文件 —— 取消「开机自动出来」。
#
# 只是把那个登录项去掉。屏幕上的阿达不受影响（要收工用右键 → 退出阿达）。

set -euo pipefail

LABEL="com.jieda.glancehint.frame"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

launchctl bootout "gui/${UID}/${LABEL}" 2>/dev/null || true
rm -f "${PLIST}"

echo "取消了：以后开机不会自己出来。"
echo "（屏幕上这个阿达还在 —— 不想要就右键它 → 退出阿达。）"
echo
read -r -p "按回车关掉这个窗口"
