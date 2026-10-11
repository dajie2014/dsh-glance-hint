#!/bin/bash
# 双击这个文件就行 —— 阿达出来。
# 这个终端窗口可以直接关掉，阿达不会跟着走。
cd "$(dirname "$0")" || exit 1

BIN="build/GlanceHintFrame.app/Contents/MacOS/GlanceHintFrame"

# 什么时候要先编译一遍：
#   ① 还没编译过；
#   ② 程序或打包脚本改过；
#   ③ **assets/ 里的素材比编译产物新** —— 他出了新图丢进 assets/states/，
#      双击一下就该看到新的，不该还要记得"再跑一次 build.sh"。
need_build() {
  [ -x "${BIN}" ] || return 0
  [ main.swift -nt "${BIN}" ] && return 0
  [ build.sh -nt "${BIN}" ] && return 0
  [ -n "$(find ../../assets -newer "${BIN}" -print -quit 2>/dev/null)" ] && return 0
  return 1
}

if need_build; then
  echo "先编译一下（几秒）…"
  ./build.sh || { echo; echo "编译没成功，先看上面的报错。"; read -r -p "按回车关掉这个窗口"; exit 1; }
fi

# 双击的意思就是"我要它出来"，所以先把旧的收掉再放一个 ——
# 不然用 open 只会把旧进程叫到前面来，看到的还是上一次的画面（2026-10-11 被这个骗过）。
pkill -x GlanceHintFrame 2>/dev/null && sleep 1

./start.sh --open
