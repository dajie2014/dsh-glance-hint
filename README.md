# 览示 · Glance-Hint

> 桌角一个小人。你干活的时候，它把正在发生的事演给你看。

## 它是什么

**中文**

览示（Glance-Hint）
这是一个只作观测的小东西。
它栖身在任务的洪流之中，收集来自工作台现场的各类信号。
它不会执行写入，不会介入流程，更不会代替宿主做出任何决定。
它唯一的职责，收集现场正在上演的一切，将发生的事件转译为动画与声响，呈现在操作者的眼前。
它构成一层可移除的中间夹层，横亘在人与引擎之间。
你可以选择让它守候在工作流一旁静静观看，也能够在任意时刻，撤去这一重观测。

**English**

Glance-Hint
This is an observing-only bystander.
It dwells amid the flow of tasks, collecting signals from the running workbench.
It shall never write, never intervene, never make decisions on behalf of the host.
Its sole duty is to gather what unfolds on-site, then translate those happenings into animation and
sound, and present them before the operator's eyes.
It forms a removable intermediate layer between human and engine.
You may choose to keep it watching beside your workflow, or lift away this layer of observation at
any time.

## 它长什么样

![七种状态](assets/preview.jpg)

桌角一扇小窗，永远在最上层，别的程序盖不住它。七种状态各演各的：

| 编号 | 状态 | 演什么 |
|---|---|---|
| 01 | 在写 | 伏在案上，沙沙地写 |
| 02 | 在想 | 坐正，安静地想 |
| 03 | 摔了 | 歪倒，头上一滴汗 |
| 04 | 停了 | 睡着了，冒 Z |
| 05 | 等你 | 凑近你，旁边一个问号 |
| 06 | 成一半 | 挂一个对勾 |
| 07 | 全成了 | 冒星星，脸都亮了 |

动起来的时候，每一格的动作、声音都不一样。

## 装它

1. 把这个仓库下下来（或者取 Releases 里的压缩包），**整个文件夹都要**，别只拿一个文件
2. **双击根目录的 `安装.command`**
3. 就这样 —— 屏幕右下角会出现它，以后开机也自己出来

要求 macOS 13 或更新。它不装进任何东西里、也不改你的任何设置 —— 它只是坐在旁边看。

**关了 DSH，它自己收工**；重新打开 DSH，它自己回来。你不用管。

### 系统说它「来路不明」怎么办

macOS 对从网上下载的、没签名的程序会拦一下（它没有 Apple 的签名，这很正常）。两条路：

**推荐 —— 用 git 拿它**（这样系统不会给它打那个标记）：

```sh
git clone https://github.com/dajie2014/dsh-glance-hint.git
cd dsh-glance-hint
./安装.command
```

**或者 —— 下载压缩包解压后**，先在这个文件夹里跑一句，再去双击 `安装.command`：

```sh
xattr -dr com.apple.quarantine .
```

这一句只是去掉「从网上来的」那个标记，不改任何别的东西。

## 换成你自己的小人

把它自己的图换掉就行。把七张图丢进这里：

```
~/Library/Application Support/GlanceHint/roles/default/
```

名字用 `01.png` … `07.png`（编号就是上面那张表的状态号），另外放一张 `face.png` 当兜底 ——
**哪一格缺图，那一格就退回 `face.png`**。丢完双击一次 `安装.command`，脸就换了。

> 想同时留着几套？再建一个文件夹（比如 `roles/我的另一套/`），
> 然后 `GHS_ROLE=我的另一套 ./frame/window/install.sh` 切过去。

## 换成你自己的声音

把它打招呼那句话换成你自己的录音：

1. 双击 `frame/window/导入问候语.command` —— 会打开一个文件夹
2. 把你的录音拖进去（**wav / mp3 / m4a / aiff 都行**，文件名不用改）
3. 再双击一次 `安装.command`

不放音频也没关系：**它会静音打招呼**（照样挥手、照样冒气泡，只是不说话）。

## 换成你自己的音效

想做整套主题皮肤的，声音也能换。放进这里：

```
~/Library/Application Support/GlanceHint/sounds/
```

| 文件名 | 用在哪 | 要不要循环 |
|---|---|---|
| `writing.*` | 01 在写 | 要（一直响着） |
| `fall.*` | 03 摔了 | 不要 |
| `small.*` | 06 成一半 | 不要 |
| `big.*` | 07 全成了 | 不要 |

有哪个用哪个，**没有的那几格照旧用内置的合成音** —— 可以混着来。放完双击一次 `安装.command`。

## 它怎么工作

它只是**坐在旁边看**：读正在运行的 DSH 本机事件流，把里面的事翻译成七种状态，写进一个小文件；
桌角那扇小窗读那个文件，演出来。

- **不写入**：它不碰 DSH 的任何东西，不改写、不介入、不替谁做决定。
- **随时可撤**：双击 `frame/window/取消开机自启.command`，再把「应用程序」里的
  `Ada.app` 拖进废纸篓 —— 它就彻底不在了，什么痕迹都不留。

## 目录里都有什么

```
安装.command               ← 第一次用就双击它
dist/Ada.app               预编译好的小窗（你不用自己编译）
frame/ghs-watch.mjs        在旁边看的那只眼睛（只读）
frame/keeper.sh            不露面的看门人：DSH 一开就把它叫出来
frame/window/              小窗本体、打包脚本、各个入口
assets/roles/default/      默认角色（中性小人）
assets/runtime/            小窗里那个网页（想改动作、文字就改它）
tools/                     造图、打包的脚本（想自己改默认角色就看看这儿）
```
