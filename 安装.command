#!/bin/bash
# 双击这个文件 —— 把阿达装上。**第一次用就点它，别的都不用管。**
#
# 它会依次做四件事：
#   ① 把阿达放进「应用程序」里
#   ② 建好两个文件夹：换小人用的「角色」、放问候录音用的「voice」
#   ③ 装一个登录项：以后开机它自己出来（关掉 DSH 它也自己收工）
#   ④ 当场把它叫出来，你马上能看到
#
# 卸载：双击 frame/window/取消开机自启.command，再把「应用程序」里的 Ada.app 拖到废纸篓。

set -uo pipefail
cd "$(dirname "$0")" || exit 1

# ★ 从 GitHub 拿下来的文件**没有可执行位**（走 API/网页下载都一样）。
#   所以自己先把这一堆脚本补上 +x，不然下面 ./frame/window/install.sh 调不动。
chmod +x ./frame/window/*.sh ./frame/window/*.command ./frame/*.sh 2>/dev/null || true

cat <<'BANNER'

  ╭──────────────────────────────────────────╮
  │  阿达 —— 桌角上的小人                     │
  │  你干活的时候，它在旁边演给你看           │
  ╰──────────────────────────────────────────╯

BANNER

if [ ! -x "./frame/window/install.sh" ]; then
  echo "这个包好像不完整（找不到 frame/window/install.sh）。"
  echo "请把整个文件夹一起解压/下载，别只拿单个文件。"
  read -r -p "按回车关掉"
  exit 1
fi

echo "① 装到「应用程序」…"
if ! ./frame/window/install.sh; then
  echo
  echo "装不上了，先看上面那行报错。"
  read -r -p "按回车关掉这个窗口"
  exit 1
fi

echo
echo "② 装开机自启…"
./frame/window/开机自启.command < /dev/null

echo
echo "③ 把它叫出来…"
open "${HOME}/Applications/Ada.app" 2>/dev/null || true

cat <<'TAIL'

──────────────────────────────────────────────
装好了。阿达这会儿应该已经在屏幕右下角了。

想换成你自己的小人：把你的七张图丢进
    ~/Library/Application Support/GlanceHint/roles/default/
（名字就用 01.png … 07.png；缺哪张，那张就退回 face.png）

想让它用你的声音打招呼：双击 frame/window/导入问候语.command，
把录音拖进去，再双击一次本文件。

细节都在 README.md 里。
──────────────────────────────────────────────

TAIL
read -r -p "按回车关掉这个窗口"
