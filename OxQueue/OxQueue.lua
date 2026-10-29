local ADDON, ns = ...
local A, L = ns.Analyzer, ns.L

local GCD_SPELL = 61304
local MAX_CYCLES, MAX_INTERVALS, MAX_LATENCY = 1500, 3000, 360
local LATENCY_EVERY = 10   -- GetNetStats refreshes roughly every 30s; 10s is plenty
local SPAM_GAP = 0.5       -- presses further apart than this are not "spamming"
local LATE_WINDOW = 1.0    -- a press this long after the lock ended is idle, not late
local SAME_LOCK = 0.05     -- lock-end jitter (haste changes, rounding) treated as the same cycle
local DUPLICATE = 0.01     -- two hooks reporting one press
local VERSION = "1.0.1"
ns.QQ_GROUP = "233489177"   -- same group as ExecutionerWatch

local DEFAULTS = { coverage = 0.95, margin = 20, combatOnly = true, recording = false,
  theme = "light", profiles = {} }

local db, profile, profileKey
local current            -- open cycle: { endT, minLead, maxLead }
local lastLock           -- latest lock end that was still running when sampled
local frameLock          -- lock end sampled last frame, i.e. before this frame's presses
local pressedLock        -- lock end of the last cycle that got a press while locked
local lastPress
local combatStart        -- set only while recording
-- Our own combat flag: PLAYER_REGEN_DISABLED fires just before InCombatLockdown() turns
-- true, so asking InCombatLockdown() inside that handler says "not in combat".
local inCombat = false
local hooks = { api = 0, buttons = 0 }
local seen = {}          -- signal name -> count this session, for /oxq status
local debugUntil
local pendingApply = {}   -- spec key -> window waiting for combat to end

local function secret(v) return issecretvalue and issecretvalue(v) end

local function print_(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff8f84f5OxQueue|r " .. msg) end
ns.Print = print_
ns.print = print_

local function getCVar(k) return (C_CVar and C_CVar.GetCVar or GetCVar)(k) end
local function setCVar(k, v) return (C_CVar and C_CVar.SetCVar or SetCVar)(k, v) end

local function push(list, v, cap)
  list[#list + 1] = v
  if #list > cap then table.remove(list, 1) end
end

local function specKey()
  local getSpec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
  local idx = getSpec and getSpec()
  local id = idx and GetSpecializationInfo(idx)
  return tostring(id or "none")
end

local function loadProfile()
  local key = specKey()
  db.profiles[key] = db.profiles[key] or { cycles = {}, intervals = {}, presses = 0, combatTime = 0 }
  profile, profileKey = db.profiles[key], key
  if key == "none" then return end

  local getDefault = C_CVar and C_CVar.GetCVarDefault or GetCVarDefault
  local defaultWindow = tonumber(getDefault and getDefault("SpellQueueWindow")) or 400
  if profile.window == nil then
    -- Only the active spec can inherit the old global setting during migration.
    profile.window = not db.windowPerSpec and tonumber(getCVar("SpellQueueWindow")) or defaultWindow
  end
  if not db.windowPerSpec and profile.previousWindow == nil then
    profile.previousWindow = db.previousWindow
  end
  db.previousWindow = nil
  db.windowPerSpec = true
end

local function restoreWindow()
  if not profile or profileKey == "none" then return end
  if InCombatLockdown() then
    pendingApply[profileKey] = profile.window
  else
    if tonumber(getCVar("SpellQueueWindow")) ~= profile.window then
      setCVar("SpellQueueWindow", profile.window)
    end
    pendingApply[profileKey] = nil
  end
end

-- When the client will next accept a non-queued cast: end of GCD or of the current cast.
-- Returns nil if Blizzard hides the value (secret) so we skip rather than record garbage.
local function lockEnd()
  local e = 0
  local cd = C_Spell.GetSpellCooldown(GCD_SPELL)
  if cd then
    if secret(cd.startTime) or secret(cd.duration) then return nil end
    if cd.duration > 0 then e = cd.startTime + cd.duration end
  end
  local _, _, _, _, castEndMs = UnitCastingInfo("player")
  if castEndMs then
    if secret(castEndMs) then return nil end
    e = math.max(e, castEndMs / 1000)
  end
  return e
end

local function closeCycle()
  if current then
    push(profile.cycles, { lead = math.floor(current.minLead * 1000 + 0.5),
      first = math.floor(current.maxLead * 1000 + 0.5) }, MAX_CYCLES)
    pressedLock = current.endT
  end
  current = nil
end

local function sampleLock()
  frameLock = lockEnd()
  if frameLock and frameLock > GetTime() then lastLock = frameLock end
end

local function isRecording()
  return db and db.recording and (not db.combatOnly or inCombat or InCombatLockdown()
    or UnitAffectingCombat("player"))
end

local function onPress(src)
  seen[src] = (seen[src] or 0) + 1
  if debugUntil and GetTime() < debugUntil then
    print_(string.format("%.3f %s%s", GetTime(), src, inCombat and " (combat)" or ""))
  end
  if not profile or not isRecording() then return end
  local t = GetTime()
  if lastPress and t - lastPress < DUPLICATE then return end

  profile.presses = profile.presses + 1
  if lastPress and t - lastPress < SPAM_GAP then
    push(profile.intervals, math.floor((t - lastPress) * 1000 + 0.5), MAX_INTERVALS)
  end
  lastPress = t

  -- Hooks run after the press was handled, so a press that started a new GCD would
  -- read that GCD. Last frame's snapshot is the lock the press actually ran into.
  local e = frameLock
  if not e then
    seen["no GCD timing"] = (seen["no GCD timing"] or 0) + 1
    return
  end
  local stage = e > t and "during GCD" or "after GCD"
  seen[stage] = (seen[stage] or 0) + 1

  if e > t then
    if current and math.abs(current.endT - e) > SAME_LOCK then closeCycle() end
    current = current or { endT = e, minLead = e - t, maxLead = e - t }
    current.minLead = math.min(current.minLead, e - t)
    current.maxLead = math.max(current.maxLead, e - t)
  else
    closeCycle()
    -- A lock just ended that you never pressed during: the queue window could not have helped.
    if lastLock and t >= lastLock and t - lastLock < LATE_WINDOW
        and not (pressedLock and math.abs(pressedLock - lastLock) <= SAME_LOCK) then
      push(profile.cycles, { late = math.floor((t - lastLock) * 1000 + 0.5) }, MAX_CYCLES)
      pressedLock = lastLock
    end
  end
end

-- The per-frame GCD sample is the only recurring cost (two cheap API calls). It runs
-- whenever recording is on rather than tracking combat, so event order can't break it.
local sampler = CreateFrame("Frame")
local function updateSampler()
  local on = db and db.recording
  sampler:SetScript("OnUpdate", on and sampleLock or nil)
  if not on then frameLock, lastLock = nil, nil end
end

local function sampleLatency()
  local _, _, _, world = GetNetStats()
  if world and world > 0 then push(db.latency, world, MAX_LATENCY) end
end

-- Recording time counts only combat spent recording.
local function startClock() if isRecording() then combatStart = combatStart or GetTime() end end
local function stopClock()
  if combatStart then profile.combatTime = profile.combatTime + (GetTime() - combatStart) end
  combatStart = nil
end

---------------------------------------------------------------- API used by UI.lua

function ns.Recommend()
  return A.Recommend(
    { cycles = profile.cycles, intervals = profile.intervals, latency = db.latency },
    { coverage = db.coverage, margin = db.margin })
end

function ns.CurrentWindow() return tonumber(getCVar("SpellQueueWindow")) end
function ns.PreviousWindow() return profile.previousWindow end
function ns.PendingApply() return pendingApply[profileKey] end
function ns.DB() return db end
function ns.IsRecording() return db.recording end
function ns.InRecordedCombat() return combatStart ~= nil end

function ns.Stats()
  local time = profile.combatTime + (combatStart and GetTime() - combatStart or 0)
  return { presses = profile.presses, combatTime = time,
    pps = time > 0 and profile.presses / time or nil, hooks = hooks, seen = seen,
    noTiming = seen["no GCD timing"] or 0, duringGCD = seen["during GCD"] or 0,
    afterGCD = seen["after GCD"] or 0 }
end

function ns.SetRecording(on)
  if on == db.recording then return end
  if not on then closeCycle(); stopClock() end
  db.recording = on
  if on then startClock() end
  lastPress = nil
  updateSampler()
  if ns.UI then ns.UI.Refresh() end
end

function ns.Apply(value)
  if profileKey == "none" then return print_(L.NEED_SPEC) end
  value = math.max(0, math.min(A.MAX_WINDOW, math.floor(value)))
  local now = pendingApply[profileKey] or ns.CurrentWindow()
  if now and now ~= value then profile.previousWindow = now end
  profile.window = value
  restoreWindow()
  if InCombatLockdown() then
    print_(L.APPLY_AFTER_COMBAT)
  else
    print_(string.format(L.APPLIED, value))
  end
  if ns.UI then ns.UI.Refresh() end
end

function ns.Reset()
  profile.cycles, profile.intervals = {}, {}
  profile.presses, profile.combatTime = 0, 0
  current, lastPress = nil, nil
  combatStart = nil
  startClock()
  if ns.UI then ns.UI.Refresh() end
end

---------------------------------------------------------------- chat report

local function fmt(v) return v and string.format("%d ms", v + 0.5) or "?" end

local function report()
  local r, st = ns.Recommend(), ns.Stats()
  print_(string.format("watching %d API hooks, %d bound buttons; recording %s",
    hooks.api, hooks.buttons, tostring(db.recording)))
  local names = {}
  for name in pairs(seen) do names[#names + 1] = name end
  table.sort(names)
  for i, name in ipairs(names) do names[i] = name .. " " .. seen[name] end
  print_("signals this session: " .. (#names > 0 and table.concat(names, ", ") or "none"))
  print_(string.format("current SpellQueueWindow: %s", fmt(ns.CurrentWindow())))
  print_(string.format("ping (world) p50 %s / p90 %s, %d samples", fmt(r.latP50), fmt(r.latP90), #db.latency))
  print_(string.format("presses: %.2f/s in combat, spam cadence %s, %d GCD/cast cycles (%d with no early press)",
    st.pps or 0, fmt(r.cadence), r.cycles, r.lateCycles))
  if r.humanLimited then
    print_(string.format("%.0f%% of cycles you first pressed later than your ping (no window fixes that)",
      r.humanLimited * 100))
  end
  if r.value then
    print_(string.format("recommended: %d ms (press term %s, network floor %s)", r.value, fmt(r.cover), fmt(r.floor)))
  else
    print_(string.format("need 30+ cycles with an early press (have %d).", r.cycles - r.lateCycles))
  end
end

---------------------------------------------------------------- hooks

-- Presses are observed with post-hooks only. Never take keyboard focus: a keyboard-enabled
-- frame that fails to propagate (SetPropagateKeyboardInput is restricted) eats every key.
local hookedButtons = {}

-- Which of these a keypress passes through depends on the client version and the bar
-- addon, so hook all of them; presses in the same frame are counted once.
for _, name in ipairs({ "ActionButtonDown", "MultiActionButtonDown", "UseAction",
    "CastSpellByName", "CastSpellByID" }) do
  if type(_G[name]) == "function" then
    hooksecurefunc(name, function() onPress(name) end)
    hooks.api = hooks.api + 1
  end
end

-- Bar addons (Bartender, ElvUI, Dominos) bind keys as "CLICK <Button>:<mouse button>".
local function onButtonClick(_, _, down)
  if down ~= false then onPress("button click") end  -- key-down only; the matching key-up would double count
end

local needRehook
local function hookClickBindings()
  if InCombatLockdown() then needRehook = true; return end
  needRehook = nil
  for i = 1, GetNumBindings() do
    local command, _, key1 = GetBinding(i)
    local name = key1 and command and command:match("^CLICK ([^:]+):")
    local btn = name and _G[name]
    if btn and not hookedButtons[btn] and btn.HookScript then
      btn:HookScript("OnClick", onButtonClick)
      hookedButtons[btn] = true
      hooks.buttons = hooks.buttons + 1
    end
  end
end

---------------------------------------------------------------- events

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("UPDATE_BINDINGS")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    OxQueueDB = OxQueueDB or {}
    db = OxQueueDB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    db.latency = db.latency or {}
  elseif event == "PLAYER_LOGIN" then
    inCombat = InCombatLockdown() or UnitAffectingCombat("player") or false  -- /reload mid-fight
    loadProfile()
    restoreWindow()
    hookClickBindings()
    sampleLatency()
    C_Timer.NewTicker(LATENCY_EVERY, sampleLatency)
    updateSampler()
    startClock()
    print_(string.format(L.LOADED, VERSION))
    print_(string.format(L.QQ_CHAT, ns.QQ_GROUP))
  elseif event == "PLAYER_REGEN_DISABLED" then
    inCombat = true
    updateSampler()
    startClock()
  elseif event == "PLAYER_REGEN_ENABLED" then
    inCombat = false
    closeCycle()
    stopClock()
    lastPress = nil
    updateSampler()
    if needRehook then hookClickBindings() end
    if pendingApply[profileKey] ~= nil then
      local value = pendingApply[profileKey]
      restoreWindow()
      print_(string.format(L.APPLIED, value))
    end
    if ns.UI then ns.UI.Refresh() end
  elseif event == "UNIT_SPELLCAST_SENT" then
    -- Not a press (rejected presses never send), only proof that casting is happening.
    seen["cast sent (event)"] = (seen["cast sent (event)"] or 0) + 1
  elseif event == "UPDATE_BINDINGS" then
    if profile then hookClickBindings() end
  elseif event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 == "player" then
    if specKey() == profileKey then return end
    closeCycle()
    stopClock()
    lastPress, frameLock, lastLock, pressedLock = nil, nil, nil, nil
    loadProfile()
    restoreWindow()
    startClock()
    if ns.UI then ns.UI.Refresh() end
  end
end)

function OxQueue_Toggle() if ns.UI then ns.UI.Toggle() end end

SLASH_OXQUEUE1, SLASH_OXQUEUE2, SLASH_OXQUEUE3 = "/oxq", "/sqw", "/yanchi"
SlashCmdList.OXQUEUE = function(msg)
  local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  if cmd == "" then
    OxQueue_Toggle()
  elseif cmd == "status" then
    report()
  elseif cmd == "start" or cmd == "stop" then
    ns.SetRecording(cmd == "start")
  elseif cmd == "apply" then
    local v = tonumber(arg) or ns.Recommend().value
    if not v then return print_(L.NEED_DATA_CHAT) end
    ns.Apply(v)
  elseif cmd == "reset" then
    ns.Reset()
    print_(L.RESET_DONE)
  elseif cmd == "margin" and tonumber(arg) then
    db.margin = tonumber(arg)
    print_(string.format("latency margin = %d ms", db.margin))
  elseif cmd == "coverage" and tonumber(arg) then
    db.coverage = math.max(0.5, math.min(1, tonumber(arg) / 100))
    print_(string.format("press coverage = %.0f%%", db.coverage * 100))
  elseif cmd == "debug" then
    debugUntil = GetTime() + 30
    print_("printing every press signal for 30s; press a few abilities, in and out of combat.")
  elseif cmd == "anytime" then
    db.combatOnly = not db.combatOnly
    updateSampler()
    print_("record out of combat too: " .. tostring(not db.combatOnly))
  elseif cmd == "motion" then
    db.reduceMotion = not db.reduceMotion
    print_("panel animations: " .. (db.reduceMotion and "off" or "on"))
  else
    print_("/oxq (panel) | status | start | stop | apply [ms] | reset | margin <ms> | coverage <50-100> | anytime | motion | debug")
  end
end
