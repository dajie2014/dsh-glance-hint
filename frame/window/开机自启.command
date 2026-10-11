#!/bin/bash
# 双击这个文件 —— 以后**开机（登录）阿达就自己出来**。
#
# 装的是什么：一个「登录项」，开机时系统直接把「应用程序」里的阿达拉起来。
# ⚠️ 跑的是**装到 ~/Applications 的那一份**，不是工作区里这份 —— 原因见 install.sh 抬头。
# 它是用户级设置，不需要管理员密码，随时可以反悔（双击旁边那个「取消开机自启」）。
#
# 装完当场就会试一次；阿达已经在屏幕上就不会重复放第二个。

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.jieda.glancehint.frame"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
APP="${HOME}/Applications/Ada.app"
BIN="${APP}/Contents/MacOS/GlanceHintFrame"
KEEPER="${HOME}/Library/Application Support/GlanceHint/keeper.sh"

# ★ 装到「文稿」外面 —— 这是关键一步。
#   开机登录项（launchd）读不了「文稿」里的东西（系统直接拒，报 Operation not permitted），
#   就地跑的话开机根本起不来。细节见 install.sh 抬头。
#
#   ⚠️ 这里**不能**要求"先编译"：发给别人的包里没有源码、也没有 Xcode，
#      编译这一步得由 install.sh 自己决定（它优先用发布包里预编译的那份 dist/Ada.app）。
echo "先装一份到「应用程序」里…"
"${HERE}/install.sh" || {
  echo "装不上。如果你是开发者，先跑一次 ./frame/window/build.sh；"
  echo "如果是下载来的包，那这个包不完整，重新下一次。"
  read -r -p "按回车关掉这个窗口"
  exit 1
}

mkdir -p "${HOME}/Library/LaunchAgents"

cat > "${PLIST}" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${LABEL}</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>${KEEPER}</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<!-- ★ 登录项跑的是**看门人**，不是阿达本身：
	     阿达的规矩是"DSH 关了就退干净"，而 DSH 开的时候又没人通知谁，
	     所以得有个不露面的角色替他把阿达叫出来（它每 5 秒看一眼 DSH 的端口）。
	     KeepAlive：看门人万一崩了，launchd 会自动把它拉起来。 -->
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>${HOME}/Library/Application Support/GlanceHint/autostart.log</string>
	<key>StandardErrorPath</key>
	<string>${HOME}/Library/Application Support/GlanceHint/autostart.log</string>
</dict>
</plist>
PLISTEOF

# 先卸掉旧的（如果装过），再装上 —— 重复双击不会叠出两份。
#
# ⚠️ 中间那个等待是必须的：bootout 会顺手把**正在跑的阿达**也收掉，
#    而 launchd 清理要一点时间；紧接着 bootstrap 会报
#    `Bootstrap failed: 5: Input/output error`，服务就没了（2026-10-11 实际踩到）。
launchctl bootout "gui/${UID}/${LABEL}" 2>/dev/null || true
for _ in 1 2 3 4 5; do
  launchctl print "gui/${UID}/${LABEL}" >/dev/null 2>&1 || break
  sleep 1
done
if ! launchctl bootstrap "gui/${UID}" "${PLIST}" 2>/dev/null; then
  sleep 2
  launchctl bootstrap "gui/${UID}" "${PLIST}" || {
    echo "登记没成 —— 打开「活动监视器」看一眼，或者把 ${PLIST} 删掉重来。"
    read -r -p "按回车关掉这个窗口"
    exit 1
  }
fi

echo
echo "装好了：开机登录后阿达会自己出来。"
echo "设置文件：${PLIST}"
echo "阿达：${APP}"
echo "看门人：${KEEPER}（DSH 一开就把阿达叫出来）"
echo "想反悔：双击「取消开机自启.command」。"
echo
read -r -p "按回车关掉这个窗口"
