local _, ns = ...

local L = {
  TITLE = "OxQueue",
  SUBTITLE = "Spell queue tuner",
  LIGHT = "Light",
  DARK = "Dark",

  START = "Start recording",
  STOP = "Stop",
  STATUS_OFF = "Not recording. Press start, then fight as usual.",
  STATUS_WAITING = "Recording. Waiting for combat...",
  STATUS_LIVE = "Recording in combat",
  STATUS_PAUSED = "Recording",
  GCDS = "%d GCDs",
  COMBAT_TIME = "%s of combat",

  RECOMMENDED = "Recommended",
  NOW = "Now %d ms",
  DELTA = "%+d ms",
  BY_PRESSES = "Set by your press rhythm",
  BY_PING = "Set by your ping",
  ALREADY = "You're already at the recommended window",
  NEED_DATA = "Collecting",
  NEED_UNIT = "/ 30 GCDs",
  NO_TIMING = "Presses seen, but GCD timing can't be read",
  DIAG = "Presses: %d during GCD · %d after · %d unreadable",
  NEED_DATA_HINT = "Fight a target dummy or a few pulls. The chart fills in as you press.",

  CHART_TITLE = "When your last press lands",
  CHART_HINT = "Lead time before the GCD ends. Left of a line gets queued.",
  MARK_NOW = "now",
  MARK_REC = "rec.",
  MARK_PING = "ping",

  INSIGHT = "At %d ms, %d%% of your GCDs queue in time. At %d ms: %d%%.",
  INSIGHT_SAME = "%d%% of your GCDs queue in time at %d ms.",
  LATE_WARN = "%d%% of GCDs you pressed too late for any window to help.",
  EARLY_WARN = "%d%% of GCDs your last press came over 400 ms early; no window reaches that.",

  TILE_PING = "Ping",
  TILE_PING_SUB = "p90 %d ms",
  TILE_RHYTHM = "Press rhythm",
  TILE_RHYTHM_SUB = "between presses",
  TILE_RATE = "Presses",
  TILE_RATE_SUB = "per second",
  TILE_LATE = "Too late",
  TILE_LATE_SUB = "no window helps",

  APPLY = "Apply %d ms",
  APPLY_NONE = "Apply",
  APPLY_PENDING = "Applies after combat",
  APPLIED_BTN = "Applied",
  REVERT = "Revert to %d ms",
  RESET = "Reset data",
  RESET_CONFIRM = "Click again to reset",

  APPLY_AFTER_COMBAT = "In combat; the new window applies when combat ends.",
  APPLIED = "SpellQueueWindow set to %d ms.",
  RESET_DONE = "Data for this spec cleared.",
  NEED_DATA_CHAT = "Not enough data yet. Open /oxq to see progress.",
  NEED_SPEC = "Choose a specialization before applying a window.",

  LOADED = "%s loaded. Type /oxq to open the panel.",
  QQ_CHAT = "Feedback QQ group: |cffffd100%s|r (click it in the /oxq panel to copy)",
  QQ_LABEL = "QQ group",
  QQ_COPY = "Click to copy",
  QQ_COPIED = "Copied!",
  QQ_SELECTED = "Selected, press Ctrl+C",
  QQ_COPIED_CHAT = "Copied QQ group number: %s",
}

if GetLocale() == "zhCN" or GetLocale() == "zhTW" then
  L.SUBTITLE = "施法队列窗口调校"
  L.LIGHT, L.DARK = "亮色", "深色"
  L.START = "开始记录"
  L.STOP = "停止"
  L.STATUS_OFF = "未在记录。点开始，然后照常战斗。"
  L.STATUS_WAITING = "记录中，等待进入战斗…"
  L.STATUS_LIVE = "战斗中记录"
  L.STATUS_PAUSED = "记录中"
  L.GCDS = "%d 个公共冷却"
  L.COMBAT_TIME = "战斗 %s"
  L.RECOMMENDED = "推荐值"
  L.NOW = "当前 %d ms"
  L.BY_PRESSES = "由你的按键节奏决定"
  L.BY_PING = "由你的延迟决定"
  L.ALREADY = "已经是推荐值"
  L.NEED_DATA = "采集中"
  L.NEED_UNIT = "/ 30 个公共冷却"
  L.NO_TIMING = "已记录按键，但读不到公共冷却时间"
  L.DIAG = "按键：公共冷却中 %d · 冷却后 %d · 读不到 %d"
  L.NEED_DATA_HINT = "打木桩或打几波怪，图表会随按键逐渐填满。"
  L.CHART_TITLE = "最后一次按键落在哪里"
  L.CHART_HINT = "距公共冷却结束的提前量。线左侧的按键会进队列。"
  L.MARK_NOW, L.MARK_REC, L.MARK_PING = "当前", "推荐", "延迟"
  L.INSIGHT = "%d ms 时 %d%% 的公共冷却能及时排队；%d ms 时为 %d%%。"
  L.INSIGHT_SAME = "%d%% 的公共冷却能在 %d ms 内及时排队。"
  L.LATE_WARN = "%d%% 的公共冷却你按得太晚，调窗口帮不上。"
  L.EARLY_WARN = "%d%% 的公共冷却最后一次按键早于 400 ms，任何窗口都够不着。"
  L.TILE_PING, L.TILE_PING_SUB = "延迟", "p90 %d ms"
  L.TILE_RHYTHM, L.TILE_RHYTHM_SUB = "按键节奏", "两次按键间隔"
  L.TILE_RATE, L.TILE_RATE_SUB = "按键", "每秒"
  L.TILE_LATE, L.TILE_LATE_SUB = "按晚了", "调窗口无效"
  L.APPLY = "应用 %d ms"
  L.APPLY_NONE = "应用"
  L.APPLY_PENDING = "脱战后生效"
  L.APPLIED_BTN = "已应用"
  L.REVERT = "恢复 %d ms"
  L.RESET = "清空数据"
  L.RESET_CONFIRM = "再点一次确认"
  L.APPLY_AFTER_COMBAT = "战斗中，新窗口将在脱战后生效。"
  L.APPLIED = "SpellQueueWindow 已设为 %d ms。"
  L.RESET_DONE = "已清空本专精的数据。"
  L.NEED_DATA_CHAT = "数据还不够，输入 /oxq 查看进度。"
  L.NEED_SPEC = "请先选择专精，再应用延迟容限。"
  L.LOADED = "%s 已载入。输入 /oxq 打开窗口"
  L.QQ_CHAT = "交流反馈 QQ 群：|cffffd100%s|r（/oxq 窗口里可点击复制）"
  L.QQ_LABEL = "推荐 QQ 群"
  L.QQ_COPY = "点击复制"
  L.QQ_COPIED = "已复制！"
  L.QQ_SELECTED = "已选中，按 Ctrl+C 复制"
  L.QQ_COPIED_CHAT = "已复制 QQ 群号：%s"
end

ns.L = L
