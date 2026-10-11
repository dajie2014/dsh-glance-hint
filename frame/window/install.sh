#!/bin/bash
# 把浮窗和看门狗装到「不受保护」的位置 —— 双击阿达、开机自启，两条路都先走这里。
#
# ★ 为什么不能就地跑（2026-10-11 踩的坑，值得记住）：
#   这个项目在「文稿」里，而**「文稿」是 macOS 保护的目录**。
#   **开机登录项（launchd）去读文稿里的东西会被系统直接拒掉**，报的是
#   `Operation not permitted` —— 而你自己双击完全看不出来（双击那条路有 Finder 给的授权）。
#   ⇒ 所以「开机自启」必须跑在文稿**外面**的一份：
#        app        →  ~/Applications/Ada.app
#        看门狗脚本  →  ~/Library/Application Support/GlanceHint/ghs-watch.mjs
#   工作区里那份 build/ 从此只是**构建产物**，不是要跑的那份。
#
# 装的时候先拷到旁边再整体换过去，避免拷到一半留下半新半旧的 app。

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
LIB="${HOME}/Library/Application Support/GlanceHint"
APP="${HOME}/Applications/Ada.app"
# 用哪一份 app：
#   · 开发本机  → `build/` 里**刚编出来**的那份（改了源码就该跑它）
#   · 发布包    → `dist/` 里**预编译**的那份（别人的机器上没有 Xcode，编不了）
# ⚠️ 判断顺序不能反：早先写成"优先 dist/"，结果本机改了源码也一直装旧的那份，
#    排查了半天"页面改了怎么不生效"。
if [ -x "${HERE}/build/GlanceHintFrame.app/Contents/MacOS/GlanceHintFrame" ]; then
  SRC="${HERE}/build/GlanceHintFrame.app"
elif [ -d "${ROOT}/dist/Ada.app" ]; then
  SRC="${ROOT}/dist/Ada.app"
else
  echo "找不到浮窗：build/ 和 dist/ 里都没有（开发者先跑 ./frame/window/build.sh）"
  exit 1
fi
WATCH_SRC="${HERE}/../ghs-watch.mjs"

[ -x "${SRC}/Contents/MacOS/GlanceHintFrame" ] || { echo "浮窗还没编译：${SRC}（先跑 ./build.sh）"; exit 1; }
[ -f "${WATCH_SRC}" ] || { echo "找不到看门狗：${WATCH_SRC}"; exit 1; }

mkdir -p "${HOME}/Applications" "${LIB}"

rm -rf "${APP}.new"
cp -R "${SRC}" "${APP}.new"
rm -rf "${APP}"
mv "${APP}.new" "${APP}"

cp "${WATCH_SRC}" "${LIB}/ghs-watch.mjs"
# 看门人（负责"DSH 一开就把阿达叫出来"）也得住到文稿外面 —— 它同样由登录项调用
cp "${HERE}/../keeper.sh" "${LIB}/keeper.sh"
chmod +x "${LIB}/keeper.sh"
# ★ 让这份 app 去找**文稿外面**那个看门狗（它自己带的那行路径还指着工作区）
printf '%s\n' "${LIB}/ghs-watch.mjs" > "${APP}/Contents/Resources/watch-path.txt"

# ── 角色（可以换的那一层）──────────────────────────────────────────────
# 角色住在 ~/Library/Application Support/GlanceHint/roles/<名字>/ 里：
#     face.png            那张定妆图（某一格缺图时退回它）
#     01.png … 07.png     七格
# 第一次安装时，从仓库自带的那份搭一个叫 ada 的角色当样板。
# **换角色 = 往那个目录丢图 + 双击一下安装**，程序一个字都不用改 ——
# 这正是"别人拿自己的角色也能用"那条线（见 ROADMAP 定调之二）。
ROLES="${LIB}/roles"
# ⚠️ 别写成 ROLE="${GHS_ROLE:-$(cat ...)}"：第一次装的时候那个文件还不存在，
#    cat 的非零退出码配上 set -e/pipefail 会让整个脚本**悄悄退出**（连一句报错都没有）。
ROLE="${GHS_ROLE:-}"
if [ -z "${ROLE}" ] && [ -f "${LIB}/role.txt" ]; then
  ROLE="$(tr -d '[:space:]' < "${LIB}/role.txt")"
fi
[ -n "${ROLE}" ] || ROLE="default"
ROLE_DIR="${ROLES}/${ROLE}"

if [ ! -d "${ROLE_DIR}" ]; then
  echo "第一次见这个角色，给它搭个目录：${ROLE_DIR}"
  mkdir -p "${ROLE_DIR}"
  SEED="${ROOT}/assets/roles/${ROLE}"
  if [ -d "${SEED}" ]; then
    # 仓库里自带这个角色（比如中性默认角色 default）—— 直接拿来用
    for f in "${SEED}"/*.png; do
      if [ -f "${f}" ]; then cp "${f}" "${ROLE_DIR}/"; fi
    done
    echo "        从仓库自带的「${ROLE}」装了一份"
  else
    # 仓库里没有：那是拿工作区那套图临时搭一个（阿达就是这么来的）
    if [ -f "${ROOT}/assets/ref/ada-ref-02-anime-clean.png" ]; then
      cp "${ROOT}/assets/ref/ada-ref-02-anime-clean.png" "${ROLE_DIR}/face.png"
    fi
    if [ -d "${ROOT}/assets/states" ]; then
      for f in "${ROOT}"/assets/states/*.png; do
        if [ -f "${f}" ]; then cp "${f}" "${ROLE_DIR}/"; fi
      done
    fi
  fi
fi
printf '%s\n' "${ROLE}" > "${LIB}/role.txt"

# 把当前角色的图铺进 app —— 这一步只换图，不碰程序
if [ -f "${ROLE_DIR}/face.png" ]; then
  cp "${ROLE_DIR}/face.png" "${APP}/Contents/Resources/ref/face.png"
fi
rm -f "${APP}"/Contents/Resources/states/*.png
for f in "${ROLE_DIR}"/*.png; do
  if [ -f "${f}" ] && [ "$(basename "${f}")" != "face.png" ]; then
    cp "${f}" "${APP}/Contents/Resources/states/"
  fi
done
# ── 欢迎语音（谁都能换成自己的） ──────────────────────────────────────
# 他的音频放这儿：~/Library/Application Support/GlanceHint/voice/
# 文件名随便（wav / mp3 / m4a / aiff 都认），安装时挑一个拷进 app，页面挨个格式试。
# 没有就**静音打招呼** —— 画面照常挥手、气泡照常弹，只是不说话。
VOICE_DIR="${LIB}/voice"
mkdir -p "${VOICE_DIR}"
PICK=""
for ext in wav mp3 m4a aiff aif; do
  if [ -f "${VOICE_DIR}/welcome.${ext}" ]; then PICK="${VOICE_DIR}/welcome.${ext}"; break; fi
done
if [ -z "${PICK}" ]; then
  # 没按约定命名也行：目录里第一个音频就用它（拖进去就完事，不用改名）
  for f in "${VOICE_DIR}"/*.wav "${VOICE_DIR}"/*.mp3 "${VOICE_DIR}"/*.m4a "${VOICE_DIR}"/*.aiff "${VOICE_DIR}"/*.aif; do
    if [ -f "${f}" ]; then PICK="${f}"; break; fi
  done
fi
# 头一次装：把仓库里那句（他自己录的）搭一份进去当默认
if [ -z "${PICK}" ] && [ -f "${ROOT}/assets/welcome.wav" ]; then
  cp "${ROOT}/assets/welcome.wav" "${VOICE_DIR}/welcome.wav"
  PICK="${VOICE_DIR}/welcome.wav"
  echo "        欢迎语：先把仓库里那句搭了一份（想换就丢进 ${VOICE_DIR}）"
fi
# 清掉上一次的，再把选中的拷进去（保留原扩展名，页面会挨个试）
rm -f "${APP}"/Contents/Resources/welcome.wav "${APP}"/Contents/Resources/welcome.mp3 \
      "${APP}"/Contents/Resources/welcome.m4a "${APP}"/Contents/Resources/welcome.aiff
if [ -n "${PICK}" ]; then
  cp "${PICK}" "${APP}/Contents/Resources/welcome.${PICK##*.}"
  echo "        欢迎语：$(basename "${PICK}")"
else
  echo "        欢迎语：还没有（打招呼会是静音的；放一个音频进 ${VOICE_DIR} 就响）"
fi

# ── 音效（可选：社区想做主题皮肤，就把自己的音效丢这儿） ──────────────
# 放这儿：~/Library/Application Support/GlanceHint/sounds/
#   在写 → writing.*    摔了 → fall.*    成一半 → small.*    全成了 → big.*
#   （扩展名 wav / mp3 / m4a / aiff 都认）
# 有哪个用哪个，没有的那几格**照旧现场合成** —— 两种方式可以混着来。
# ⚠️ 清单为什么写成 .js 而不是 .json：页面是 file:// 打开的，fetch 会被 CORS 挡掉，
#    只能用 <script src> 带进来（这条路不受限制）。
SND_DIR="${LIB}/sounds"
mkdir -p "${SND_DIR}" "${APP}/Contents/Resources/sounds"
rm -f "${APP}"/Contents/Resources/sounds/*
JS="window.GHS_SOUNDS = {"
FIRST=1
MINE=""
for n in 1 3 6 7; do
  case "${n}" in
    1) base="writing" ;;
    3) base="fall" ;;
    6) base="small" ;;
    7) base="big" ;;
  esac
  for ext in wav mp3 m4a aiff aif; do
    if [ -f "${SND_DIR}/${base}.${ext}" ]; then
      cp "${SND_DIR}/${base}.${ext}" "${APP}/Contents/Resources/sounds/"
      if [ "${FIRST}" -eq 0 ]; then JS="${JS},"; fi
      JS="${JS} \"${n}\": \"../sounds/${base}.${ext}\""
      FIRST=0
      MINE="${MINE} ${base}.${ext}"
      break
    fi
  done
done
JS="${JS} };"
printf '%s\n' "${JS}" > "${APP}/Contents/Resources/sounds/list.js"

echo "装好了：${APP}"
echo "        音效：${MINE:-全用现场合成的（想换就丢进 ${SND_DIR}）}"
echo "        当前角色：${ROLE}（图在 ${ROLE_DIR}；换掉里面的图、再双击一次安装就换脸了）"
echo "        欢迎语放在：${VOICE_DIR}"
