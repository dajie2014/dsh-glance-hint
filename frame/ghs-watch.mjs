#!/usr/bin/env node
// GHS 状态看门狗 —— 连**正在运行的** DSH，算出七种状态，**写成一个状态文件**。
//
// 它和浮窗是两家：看门狗死了，浮窗只是不动；浮窗崩了，DSH 一点不受影响。
// 这正是 GHS 规格里「彩蛋层与主干业务强制隔离」的意思。
//
// ★ 2026-10-11 第二版：**同时盯多个会话**。
//   他要的是「我换到哪个对话，它就演哪里」，所以不能只订启动时那一个。
//   做法：把最近用过的几个会话**全部订阅**（同一个 WebSocket 上开多条流），
//   **哪个会话有动静，状态就从哪里来** —— 不靠定时轮询，事件自己会送上门；
//   只在"有事件到达"时顺手补订一次新会话（带节流），免得新建的对话漏掉。
//
// 为什么不去写 DSH 插件：那要动 profile、要 pnpm install（本项目已知会把 node_modules 删空）、要重启。
// DSH 自己的本地接口就够用：
//   session/list    → 有哪些会话、哪个在跑
//   session/follow  → 那个会话的事件流（turn/start、tool/call、tool/result、turn/end…）
// 认证与线上协议复用 qq-bridge 已经趟平的客户端，细节见 `qq-bridge/docs/连接正在运行的DSH.md`。
//
// 用法：
//   node ghs-watch.mjs                 盯最近用的几个会话，哪个动就演哪个
//   node ghs-watch.mjs --raw           连原始事件数据一起打印（校映射时用）
//   node ghs-watch.mjs --session <id>  只盯指定的那一个
//
// 环境变量：
//   GHS_STATE_FILE     状态文件写哪（默认 ~/Library/Application Support/GlanceHint/state.json）
//   GHS_HEARTBEAT_MS   心跳间隔，默认 20000 —— 让浮窗能分辨"停住了"和"看门狗死了"
//   GHS_MAX_SESSIONS   同时盯几个会话，默认 6
//   GHS_REFRESH_MS     补订新会话的最小间隔，默认 10000

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { DSHClient } from "../../qq-bridge/qq/dsh-client.mjs";

const args = process.argv.slice(2);
const RAW = args.includes("--raw");
const sidIdx = args.indexOf("--session");
const WANT = sidIdx >= 0 ? args[sidIdx + 1] : null;

const STATE_NAME = {
  1: "在写",
  2: "在想",
  3: "摔了",
  4: "停了",
  5: "等你",
  6: "成一半",
  7: "全成了",
};

const STATE_FILE =
  process.env.GHS_STATE_FILE ??
  path.join(os.homedir(), "Library", "Application Support", "GlanceHint", "state.json");
const HEARTBEAT_MS = Number(process.env.GHS_HEARTBEAT_MS ?? 20000);
const MAX_SESSIONS = Number(process.env.GHS_MAX_SESSIONS ?? 12);
const REFRESH_MS = Number(process.env.GHS_REFRESH_MS ?? 10000);
const SCAN_MS = Number(process.env.GHS_SCAN_MS ?? 15000);

/** 看门狗自己的 pid 文件 —— 浮窗靠它判断"要不要再起一个"。
 *
 *  ★ 为什么不用 `pgrep -f ghs-watch.mjs`：那个办法是**按命令行里有没有这个字样**找进程的，
 *    于是任何提到过这个名字的命令（包括我调试时敲的那条 shell）都会被当成看门狗 —— 2026-10-11 实际被骗过一次。
 *    pid 文件没有这个歧义。 */
const PID_FILE =
  process.env.GHS_PID_FILE ?? path.join(path.dirname(STATE_FILE), "watch.pid");

const stamp = () => new Date().toTimeString().slice(0, 8);
const log = (...a) => console.log(`[${stamp()}]`, ...a);
const short = (v) => String(v ?? "").replace(/^session-/, "").slice(0, 8);

function writePid() {
  try {
    fs.mkdirSync(path.dirname(PID_FILE), { recursive: true });
    fs.writeFileSync(PID_FILE, String(process.pid) + "\n");
  } catch (e) {
    log(`pid 文件写不进去：${e.message}`);
  }
}

function clearPid() {
  try { fs.unlinkSync(PID_FILE); } catch { /* 已经没了就算了 */ }
}

const client = new DSHClient({ onLog: (m) => log("连接｜", m) });

/** 当前状态。sessionId 记的是"最后有动静的那个会话"。 */
let current = { state: 0, why: "", since: 0, sessionId: null, seq: 0 };
/** 已订阅的会话：sessionId → 取消函数 */
const followed = new Map();
let lastRefresh = 0;

/** 子任务会话（origin === 'subagent'）的 id —— 「成一半」靠它们的起落 */
const subagentSessions = new Set();
/** 主机事件流（`$events`）已经搬走多少条 */
let hostSeen = 0;
/** 「等你」当前挂在哪个 eventId 上（同一个请求只演一次） */
let pendingAsk = null;

/**
 * ★ 回馈词 —— 他 2026-10-11 亲口定的：
 *   「你做到一半的事情说**搞好了**，全部做完的时候**做完了**，碰到阻碍一定要加**踩坑**这两个字，
 *     高危动作允许……你自己定」
 *
 * 这就是「暗号通路」的真身，而且比隐形暗号好：**他本人看得见**，程序也**精确匹配**，不需要任何模型。
 *
 * ⚠️ 程序认的是**加粗**形式（`**做完了**`），理由有两个：
 *   ① 我平时聊天提到这几个字（比如正在讨论这套规矩）不会误触发；
 *   ② 界面上他看到的还是"做完了"三个字，看不出多了什么标记。
 */
const MARKERS = [
  { pattern: "**做完了**", state: 7, why: "回馈词：做完了" },
  { pattern: "**搞好了**", state: 6, why: "回馈词：搞好了" },
  { pattern: "**踩坑**", state: 3, why: "回馈词：踩坑" },
  { pattern: "**允许**", state: 5, why: "回馈词：等你允许" },
];

/** 这一轮我在回复里说过的最后那个词 —— 轮次结束时要听它的，别一律盖上"全成了" */
let lastMarker = null;

/**
 * 从一条助手消息里找回馈词。
 *
 * ★ 两处刻意收窄：
 *   ① **只扫正文（type: "text"）、不扫思考（type: "reasoning"）** —— 思考里我天天提这几个字；
 *   ② 一条消息里出现好几个，**以最后出现的为准**（那才是最新的状态）。
 */
function findMarker(message) {
  const parts = (message?.content ?? [])
    .filter((c) => c?.type === "text")
    .map((c) => c.text ?? "");
  if (!parts.length) return null;
  const text = parts.join("\n");
  let best = null;
  for (const m of MARKERS) {
    const at = text.lastIndexOf(m.pattern);
    if (at < 0) continue;
    if (!best || at > best.at) best = { at, state: m.state, why: m.why };
  }
  return best ? { state: best.state, why: best.why } : null;
}

function write() {
  const payload = {
    state: current.state,
    name: STATE_NAME[current.state] ?? "?",
    why: current.why,
    since: current.since,
    at: Date.now(),
    sessionId: current.sessionId,
    seq: current.seq,
  };
  fs.mkdirSync(path.dirname(STATE_FILE), { recursive: true });
  fs.writeFileSync(STATE_FILE, JSON.stringify(payload, null, 2) + "\n");
}

function publish(state, why, sessionId, seq) {
  if (state === current.state && sessionId === current.sessionId) return; // 没变化就不刷
  const since = state === current.state ? current.since : Date.now();
  current = { state, why, since, sessionId, seq: seq ?? current.seq };
  try {
    write();
    log(`→ 状态 ${state} ${STATE_NAME[state]}（${why}）　来自 ${short(sessionId)}…　已写入`);
  } catch (e) {
    log(`状态文件写不进去：${e.message}`);
  }
}

function heartbeat() {
  if (!current.state) return;
  try {
    write();
  } catch {
    /* 心跳失败不吵人 */
  }
}

/**
 * 事件 → 状态。返回 null 表示"这个事件不动状态"。
 *
 * ★ 2026-10-11 校准：`tool/result` **刻意不切状态**。
 *   实测发现一轮里是"调工具 → 工具返回 → 又调工具"连着走，
 *   若每完成一个工具就演一次「成一半」，会从有趣变成骚扰。
 *   「成一半」留给真正的阶段性节点（子任务 / 批处理收尾），等实测碰到再补。
 */
function mapEvent(ev) {
  const d = ev.data ?? {};
  switch (ev.type) {
    case "turn/start":
      lastMarker = null; // 新的一轮，上一轮说过的词作废
      return { state: 2, why: "开新一轮" };
    case "assistant/message": {
      // ★ 暗号路：我在回复里说的那几个词。跟 DSH 事件那条路并行，谁后到谁赢。
      const m = findMarker(d.message);
      if (!m) return null;
      lastMarker = m;
      return m;
    }
    case "tool/call":
      return { state: 1, why: `调工具 ${d.name ?? "?"}` };
    case "turn/end": {
      const k = d.reason?.kind;
      if (k === "completed") {
        // 这一轮我说过回馈词（踩坑 / 搞好了 / 允许），就听它的；
        // 没说才按"整轮完成"演 7 —— 否则一句"踩坑"刚演出来就被盖掉了。
        return lastMarker ?? { state: 7, why: "整轮完成" };
      }
      if (k === "aborted") return { state: 4, why: `被停（${d.reason?.reason?.kind ?? "?"}）` };
      return { state: 3, why: `非正常结束（${k ?? "?"}）` };
    }
    default:
      return null;
  }
}

/**
 * ★ 主机事件流（`$events`）→ 状态。**「等你」就藏在这里。**
 *
 * 2026-10-11 实测：这条流推的是**主机事件**，会话流里一个字都看不到。两种形状：
 *   { type:'waterfall', event:'user-questions/request', agentId, request:{…} }   ← 要你选
 *   { type:'emit',      event:'api-session/status', args:[sessionId, running] }  ← 谁在跑
 * 回答完/请求没了，会来一条 { type:'cancel', eventId } 把它收掉。
 *
 * ⚠️ 我们**只旁观**：收到什么都不返回 —— 这正是"仅仅观察、不影响流程"的写法。
 *    waterfall 那条流本来是"要监听者投票"的，我们弃权，DSH 照常等你。
 */
function drainHostEvents() {
  while (hostSeen < client.events.length) {
    try {
      handleHostEvent(client.events[hostSeen++]);
    } catch (e) {
      log(`主机事件看不懂，跳过一条：${e.message}`);
    }
  }
}

function handleHostEvent(v) {
  if (!v || typeof v !== "object") return;

  // ① 「等你」—— 有个东西卡住，等你点头
  if (v.type === "waterfall") {
    if (v.event === "user-questions/request") {
      pendingAsk = v.eventId ?? null;
      publish(5, "有个问题等你选", v.agentId ?? current.sessionId, 0);
    } else if (v.event === "approval/request") {
      pendingAsk = v.eventId ?? null;
      publish(5, "等你点一下允许", v.agentId ?? current.sessionId, 0);
    }
    return;
  }

  // ② 你回完了 / 那个请求撤了 —— 别一直杵在"等你"
  if (v.type === "cancel") {
    if (current.state === 5 && (pendingAsk === null || v.eventId === pendingAsk)) {
      pendingAsk = null;
      publish(2, "你回完了，继续", current.sessionId, 0);
    }
    return;
  }

  if (v.type !== "emit") return;
  const first = (v.args ?? [])[0];

  // ③ 记下新出现的子任务会话（它们订不了流，但这里看得见）
  if (v.event === "api-session/added" && first?.origin === "subagent") {
    subagentSessions.add(first.sessionId);
    return;
  }

  if (v.event === "api-session/status") {
    const [sid, running] = v.args ?? [];

    // ④ 实时雷达：谁开始跑就**当场**订上它的流。
    //    15 秒一次的扫描太慢 —— 你按一下停止，那一轮一秒钟就结束了，等扫描到早就没了。
    if (running) {
      if (!followed.has(sid) && !subagentSessions.has(sid)) {
        followOne(sid);
        log(`发现 ${short(sid)}… 开始跑了，立刻订上它的流（现在盯 ${followed.size} 个）`);
      }
      return;
    }

    // ⑤ 「成一半」—— 派出去的小弟干完了
    if (subagentSessions.has(sid)) {
      subagentSessions.delete(sid); // 一个子任务只演一次
      publish(6, "派出去的小弟干完了", current.sessionId, 0);
    }
  }
}

function onFrame(sid, frame) {
  if (frame.type === "snapshot") {
    if (RAW) log(`会话 ${short(sid)}… 开局快照 ${frame.records?.length ?? 0} 条`);
    return;
  }
  if (frame.type === "assistant-stream") return; // 太密，一律不看
  if (frame.type !== "event") return;

  const ev = frame.event;
  const m = mapEvent(ev);
  if (m) publish(m.state, m.why, sid, ev.seq);
  else if (RAW) log(`会话 ${short(sid)}… 事件 ${ev.type}（不动状态）`);
  if (RAW) log(`　　${JSON.stringify(ev.data)?.slice(0, 300) ?? ""}`);

  // 有动静就顺手补订一次（带节流）——新建的对话、久未用的对话都能被收进来
  void refreshFollow();
}

function followOne(sid) {
  const cancel = client.follow(
    sid,
    (frame) => onFrame(sid, frame),
    () => {
      followed.delete(sid);
      log(`会话 ${short(sid)}… 的流结束了（现在盯 ${followed.size} 个）`);
    },
  );
  followed.set(sid, cancel);
}

/** 把"最近用过的几个会话"补进订阅集合。 */
async function refreshFollow() {
  const now = Date.now();
  if (now - lastRefresh < REFRESH_MS) return;
  lastRefresh = now;

  let items = [];
  try {
    items = await client.listSessions();
  } catch (e) {
    log("列会话失败：", e.message);
    return;
  }
  // ⚠️ 必须滤掉子任务会话：它们是子智能体开的，follow 会立刻以
  //    「subagent Sessions require their durable parent address」结束（实测）。
  //    本机 304 个会话里 244 个是这种，不过滤的话订阅集合几乎全是死的。
  const plain = items.filter((s) => !s.origin);
  // ★ 正在跑的排最前面：它**一定**会出状态，漏了就是白跑一趟；其余的按"最近用过"排。
  plain.sort((a, b) => {
    const running = Number(b.running ?? false) - Number(a.running ?? false);
    if (running !== 0) return running;
    return (b.updatedAt ?? 0) - (a.updatedAt ?? 0);
  });
  const want = plain.slice(0, MAX_SESSIONS);
  let added = 0;
  for (const s of want) {
    if (followed.has(s.sessionId)) continue;
    followOne(s.sessionId);
    added++;
  }
  if (added) {
    log(`新盯上 ${added} 个会话（共 ${followed.size} 个）：${want.map((s) => short(s.sessionId)).join(" ")}`);
  }
}

async function main() {
  writePid();
  await client.connect();

  if (WANT) {
    followOne(WANT);
    current.sessionId = WANT;
    log(`只盯你指定的会话 ${short(WANT)}…`);
  } else {
    await refreshFollow();
    if (!followed.size) throw new Error("没有可盯的会话");
    current.sessionId = [...followed.keys()][0]; // 挂在最近用过的那个上
  }

  log(`状态文件：${STATE_FILE}`);
  publish(2, "刚起来，待命", current.sessionId, 0);
  setInterval(heartbeat, HEARTBEAT_MS).unref?.();
  // ★ 主机事件流攒在 client.events 里，得有人搬。
  //   为什么这么快（300 毫秒）："等你"要**当场**演出来 —— 你正等着呢，
  //   等两秒才看见小人举手，那就没意义了。搬的是内存里的数组，几乎不花钱。
  setInterval(drainHostEvents, 300).unref?.();

  // 低频补订（默认 15 秒一次，GHS_SCAN_MS 可调）。
  // 为什么非要有这个定时器：如果他切到一个**很久没用的对话**，那个会话不在订阅集合里，
  // 它也就没有事件来触发补订（鸡生蛋）。低频扫一遍列表，把"最近用过的"重新排一次，
  // 他那边一开口就能被接上。代价是每 15 秒一次本地 HTTP 调用，很轻。
  if (!WANT) setInterval(() => void refreshFollow(), SCAN_MS).unref?.();
}

process.on("exit", clearPid);
for (const sig of ["SIGINT", "SIGTERM", "SIGHUP"]) {
  process.on(sig, () => { clearPid(); process.exit(0); });
}

main().catch((e) => {
  console.error("起不来：", e.message);
  process.exit(1);
});
