from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ADDON = Path(__file__).resolve().parents[1] / "OxQueue"

MOCK = r'''
now = 0; combat = false; gcdStart = 0; gcdDur = 0; latency = 120; specID = 71
messages = {}; cvars = { SpellQueueWindow = "400" }; frames = {}; secretGCD = false
function GetTime() return now end
function issecretvalue(v) return v == "SECRET" end
function InCombatLockdown() return combat end
function UnitAffectingCombat() return combat end
function hooksecurefunc(name, fn)
  local orig = _G[name]
  _G[name] = function(...) orig(...); fn(...) end
end
function ActionButtonDown() UseAction(1) end
function MultiActionButtonDown() end
function UseAction() end
bindings = { { "CLICK BT4Button1:Keybind", "ACTIONBAR", "F" }, { "MOVEFORWARD", "MOVEMENT", "W" } }
function GetNumBindings() return #bindings end
function GetBinding(i) return unpack(bindings[i]) end
function GetNetStats() return 0, 0, latency, latency end
function GetSpecialization() return specID and 1 end
function GetSpecializationInfo() return specID end
function UnitCastingInfo() return nil end
C_Spell = { GetSpellCooldown = function()
  if secretGCD then return { startTime = "SECRET", duration = "SECRET" } end
  return { startTime = gcdStart, duration = gcdDur } end }
C_CVar = { GetCVar = function(k) return cvars[k] end, SetCVar = function(k, v) cvars[k] = tostring(v) end,
  GetCVarDefault = function() return "400" end }
C_Timer = { NewTicker = function() end }
DEFAULT_CHAT_FRAME = { AddMessage = function(_, s) messages[#messages + 1] = s end }
SlashCmdList = {}
STANDARD_TEXT_FONT = "Fonts\FRIZQT__.TTF"
UISpecialFrames = {}
locale = "enUS"
function GetLocale() return locale end
function GetPhysicalScreenSize() return 3840, 2160 end
function tinsert(t, v) t[#t + 1] = v end
timers = {}
C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
C_Timer.NewTicker = function() return { Cancel = function() end } end

-- Generic widget: real behaviour for what tests inspect, no-op for any other
-- WoW method (methods are Capitalized; addon-set fields are lowercase).
local methods = {}
function newObj()
  local o = { scripts = {}, hooks = {}, kb = false, shown = true, text = "" }
  return setmetatable(o, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:match("^[A-Z]") then return function() end end
  end })
end
function methods:SetScript(k, fn) self.scripts[k] = fn end
function methods:HookScript(k, fn) self.hooks[k] = fn end
function methods:Click(down) if self.hooks.OnClick then self.hooks.OnClick(self, "Keybind", down) end end
function methods:EnableKeyboard(v) self.kb = v end
function methods:IsKeyboardEnabled() return self.kb end
function methods:SetPropagateKeyboardInput(v) self.prop = v end
function methods:CreateTexture() return newObj() end
function methods:CreateFontString() return newObj() end
function methods:CreateAnimationGroup() return newObj() end
function methods:CreateAnimation() return newObj() end
function methods:SetText(t) self.text = t end
function methods:GetText() return self.text end
function methods:IsShown() return self.shown end
function methods:Show()
  local was = self.shown; self.shown = true
  if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide()
  local was = self.shown; self.shown = false
  if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function methods:GetEffectiveScale() return 1 end
function methods:GetFrameLevel() return 1 end
function methods:SetHeight(h) self.height = h end
function methods:GetHeight() return self.height or 0 end
function methods:SetAlpha(a) self.alpha = a end
function methods:GetStringWidth() return #(self.text or "") * 6 end
function CreateFrame(_, name)
  local f = newObj()
  frames[#frames + 1] = f
  if name then _G[name] = f end
  return f
end
UIParent = newObj()
function fire(event, ...)
  for _, f in ipairs(frames) do if f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end end
end
function enterCombat() fire("PLAYER_REGEN_DISABLED"); combat = true end
function tick() for _, f in ipairs(frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0) end end end
-- Runs every UI animation to its end (one long frame).
function settle() for _, f in ipairs(frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 1) end end end
function press() ActionButtonDown(1) end
CreateFrame("Button", "BT4Button1")
'''


FILES = ("Locale.lua", "Analyzer.lua", "UI.lua", "OxQueue.lua")


def load(record=True, setup=None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    if setup:
        lua.execute(setup)
    ns = lua.table()
    for f in FILES:
        lua.execute((ADDON / f).read_text(encoding="utf-8"), "OxQueue", ns)
    # Addon files read `...`; lupa passes extra execute args as varargs.
    lua.globals().fire("ADDON_LOADED", "OxQueue")
    lua.globals().fire("PLAYER_LOGIN")
    if record:
        lua.globals().SlashCmdList.OXQUEUE("start")
    return lua, ns


class Sim:
    """Player presses on a schedule; the server-ish model starts the next GCD
    at the old GCD end if a press landed inside the queue window."""

    def __init__(self, lua, sqw_ms, gcd=1.0):
        self.lua, self.g, self.sqw, self.gcd = lua, lua.globals(), sqw_ms / 1000, gcd
        self.end = 0.0
        self.queued = False
        self.clock = 0.0

    def start_gcd(self, t):
        self.g.gcdStart, self.g.gcdDur = t, self.gcd
        self.end = t + self.gcd
        self.queued = False
        self.g.now = t
        self.g.fire("SPELL_UPDATE_COOLDOWN")

    def advance(self, t, frame=0.01):
        # Run game frames up to t, starting queued GCDs when the previous one ends.
        while self.clock + frame < t:
            self.clock += frame
            if self.queued and self.end <= self.clock:
                self.start_gcd(self.end)
            self.g.now = self.clock
            self.g.tick()

    def press(self, t):
        self.advance(t)
        while self.queued and self.end <= t:
            self.start_gcd(self.end)
        self.g.now = t
        self.g.tick()  # the frame before the press
        # The game handles the press before our post-hook runs, so a press that
        # starts a GCD is already visible to the hook: the worst case.
        if t >= self.end:
            self.start_gcd(t)
        elif self.end - t <= self.sqw:
            self.queued = True
        self.g.press()


def run(lua, presses, sqw=400):
    g = lua.globals()
    g.fire("PLAYER_REGEN_DISABLED")
    g.combat = True
    sim = Sim(lua, sqw)
    for t in presses:
        sim.press(t)
    g.now = presses[-1] + 2
    g.combat = False
    g.fire("PLAYER_REGEN_ENABLED")


def profile(lua):
    return lua.eval('OxQueueDB.profiles["71"]')


class AnalyzerTest(unittest.TestCase):
    def setUp(self):
        self.lua, self.ns = load()
        self.A = self.ns.Analyzer

    def rec(self, leads, lat, late=0, **opts):
        lua = self.lua
        cycles = [lua.table(lead=l) for l in leads] + [lua.table(late=300)] * late
        data = lua.table(cycles=lua.table(*cycles), intervals=lua.table(), latency=lua.table(*lat))
        return self.A.Recommend(data, lua.table(**opts))

    def test_percentile(self):
        t = self.lua.table(*[10, 20, 30, 40])
        self.assertEqual(self.A.Percentile(t, 0), 10)
        self.assertEqual(self.A.Percentile(t, 1), 40)
        self.assertEqual(self.A.Percentile(t, 0.5), 25)

    def test_needs_data(self):
        r = self.rec([50] * 10, [100])
        self.assertEqual(r.reason, "needData")
        self.assertIsNone(r.value)

    def test_latency_floor_wins_for_spammers(self):
        r = self.rec([30, 40, 50, 60] * 10, [80, 100, 120])
        self.assertEqual(r.reason, "latency")
        self.assertEqual(r.value, 140)  # p90 116 + 20 margin -> 136 -> ceil 140

    def test_early_single_pressers_set_window(self):
        r = self.rec(list(range(100, 300, 5)), [40])
        self.assertEqual(r.reason, "presses")
        self.assertEqual(r.value, 290)

    def test_too_early_presses_do_not_push_to_cap(self):
        # 20% of cycles: last press 600 ms early, unreachable at any window.
        r = self.rec([100] * 32 + [600] * 8, [40])
        self.assertEqual(r.value, 100)
        self.assertAlmostEqual(r.tooEarly, 0.2)

    def test_all_unreachable_falls_back_to_ping(self):
        r = self.rec([600] * 40, [40])
        self.assertEqual(r.reason, "latency")
        self.assertEqual(r.value, 60)

    def test_human_limited_counts_late_presses(self):
        r = self.rec([50] * 30 + [200] * 10, [100], late=10)
        self.assertAlmostEqual(r.humanLimited, 40 / 50)

    def test_spammer_not_human_limited(self):
        lua = self.lua
        cycles = lua.table(*[lua.table(lead=40, first=900) for _ in range(40)])
        data = lua.table(cycles=cycles, intervals=lua.table(), latency=lua.table(100))
        self.assertEqual(self.A.Recommend(data, lua.table()).humanLimited, 0)


class CaptureTest(unittest.TestCase):
    def test_spammer_cadence_and_leads(self):
        lua, _ = load()
        presses = [i * 0.1 + 0.01 for i in range(300)]  # 10 presses/s for 30s
        run(lua, presses)
        p = profile(lua)
        leads = [p.cycles[i].lead for i in range(1, len(p.cycles) + 1)]
        self.assertGreater(len(leads), 25)
        self.assertTrue(all(0 <= l <= 100 for l in leads), leads)
        self.assertEqual(lua.globals().OxQueueDB.latency[1], 120)
        self.assertEqual(p.intervals[1], 100)

    def test_late_presser_recorded_as_late(self):
        lua, _ = load()
        # One press per GCD, always 150 ms after it ended.
        presses, t = [], 0.0
        for _ in range(20):
            presses.append(t)
            t += 1.15
        run(lua, presses)
        p = profile(lua)
        kinds = [("late" if p.cycles[i].late else "lead") for i in range(1, len(p.cycles) + 1)]
        self.assertEqual(kinds.count("lead"), 0)
        self.assertGreaterEqual(kinds.count("late"), 18)
        self.assertEqual(p.cycles[1].late, 150)

    def test_never_takes_keyboard(self):
        lua, _ = load()
        g = lua.globals()
        g.enterCombat()
        g.fire("PLAYER_REGEN_ENABLED")
        g.fire("UPDATE_BINDINGS")
        frames = [g.frames[i] for i in range(1, len(g.frames) + 1)]
        self.assertFalse(any(f.kb for f in frames))
        self.assertFalse(any(f.scripts.OnKeyDown for f in frames))

    def test_bar_addon_click_bindings(self):
        lua, _ = load()
        g = lua.globals()
        g.enterCombat()
        btn = g.BT4Button1
        btn.Click(btn, True)
        g.now = 0.2
        btn.Click(btn, False)  # key-up of the same press
        self.assertEqual(profile(lua).presses, 1)
        g.fire("UPDATE_BINDINGS")  # rescanning must not hook twice
        g.now = 0.4
        btn.Click(btn, True)
        self.assertEqual(profile(lua).presses, 2)

    def test_duplicate_hooks_count_once(self):
        lua, _ = load()
        g = lua.globals()
        g.enterCombat()
        g.press()
        g.MultiActionButtonDown(1, 1)
        self.assertEqual(profile(lua).presses, 1)

    def test_secret_gcd_skips_cycle_but_counts_press(self):
        lua, _ = load()
        g = lua.globals()
        g.enterCombat()
        g.secretGCD = True
        g.gcdStart, g.gcdDur, g.now = 0, 1, 0.5
        g.tick()
        g.press()
        self.assertEqual(profile(lua).presses, 1)
        self.assertEqual(len(profile(lua).cycles), 0)

    def test_hooks_deferred_when_logging_in_during_combat(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(MOCK)
        ns = lua.table()
        for f in FILES:
            lua.execute((ADDON / f).read_text(encoding="utf-8"), "OxQueue", ns)
        g = lua.globals()
        g.enterCombat()
        g.fire("ADDON_LOADED", "OxQueue")
        g.fire("PLAYER_LOGIN")
        self.assertIsNone(g.BT4Button1.hooks.OnClick)
        g.combat = False
        g.fire("PLAYER_REGEN_ENABLED")
        self.assertIsNotNone(g.BT4Button1.hooks.OnClick)

    def test_apply_defers_in_combat(self):
        lua, _ = load()
        g = lua.globals()
        g.combat = True
        g.SlashCmdList.OXQUEUE("apply 150")
        self.assertEqual(g.cvars.SpellQueueWindow, "400")
        g.combat = False
        g.fire("PLAYER_REGEN_ENABLED")
        self.assertEqual(g.cvars.SpellQueueWindow, "150")

    def test_report_end_to_end(self):
        lua, _ = load()
        run(lua, [i * 0.1 + 0.01 for i in range(400)])
        g = lua.globals()
        g.SlashCmdList.OXQUEUE("status")
        out = "\n".join(g.messages[i] for i in range(1, len(g.messages) + 1))
        print("\n" + out)
        self.assertIn("recommended", out)
        self.assertIn("watching 3 API hooks, 1 bound buttons", out)
        self.assertIn("signals this session: ActionButtonDown 400, UseAction 400", out)
        self.assertIn(" 0% of cycles you first pressed later", out)
        g.SlashCmdList.OXQUEUE("apply")
        self.assertEqual(g.cvars.SpellQueueWindow, "140")


def click(b):
    b.scripts.OnClick(b)


def open_panel(lua, ns):
    lua.globals().SlashCmdList.OXQUEUE("")
    return ns.UI.Frame()[1]


class SpecWindowTest(unittest.TestCase):
    def setUp(self):
        self.lua, self.ns = load(record=False)
        self.g = self.lua.globals()

    def switch(self, spec):
        self.g.specID = spec
        self.g.fire("PLAYER_SPECIALIZATION_CHANGED", "player")

    def test_switch_restores_each_specs_window(self):
        self.ns.Apply(150)
        self.switch(72)
        self.assertEqual(self.g.cvars.SpellQueueWindow, "400")
        self.assertIsNone(self.ns.PreviousWindow())
        self.ns.Apply(250)
        self.switch(71)
        self.assertEqual(self.g.cvars.SpellQueueWindow, "150")
        self.assertEqual(self.ns.PreviousWindow(), 400)
        self.switch(72)
        self.assertEqual(self.g.cvars.SpellQueueWindow, "250")
        self.assertEqual(self.ns.PreviousWindow(), 400)
        self.assertIsNone(self.g.OxQueueDB.previousWindow)

    def test_revert_only_changes_current_spec(self):
        self.ns.Apply(150)
        self.ns.Apply(180)
        self.switch(72)
        self.ns.Apply(250)
        self.ns.Apply(self.ns.PreviousWindow())
        self.assertEqual(self.g.cvars.SpellQueueWindow, "400")
        self.switch(71)
        self.assertEqual(self.g.cvars.SpellQueueWindow, "180")
        self.assertEqual(self.ns.PreviousWindow(), 150)

    def test_login_restores_saved_window_without_changing_revert(self):
        lua, ns = load(record=False, setup='''
          OxQueueDB = { windowPerSpec = true, profiles = {
            ["71"] = { cycles = {}, intervals = {}, presses = 0, combatTime = 0,
              window = 150, previousWindow = 200 }
          } }
        ''')
        self.assertEqual(lua.globals().cvars.SpellQueueWindow, "150")
        self.assertEqual(ns.PreviousWindow(), 200)

    def test_migration_only_assigns_global_values_to_active_spec(self):
        lua, ns = load(record=False, setup='''
          cvars.SpellQueueWindow = "180"
          OxQueueDB = { previousWindow = 300, profiles = {
            ["72"] = { cycles = {}, intervals = {}, presses = 5, combatTime = 10 }
          } }
        ''')
        g = lua.globals()
        self.assertEqual(g.OxQueueDB.profiles["71"].window, 180)
        self.assertEqual(ns.PreviousWindow(), 300)
        self.assertIsNone(g.OxQueueDB.previousWindow)
        g.specID = 72
        g.fire("PLAYER_SPECIALIZATION_CHANGED", "player")
        self.assertEqual(g.cvars.SpellQueueWindow, "400")
        self.assertEqual(g.OxQueueDB.profiles["72"].presses, 5)
        self.assertIsNone(ns.PreviousWindow())

    def test_unconfigured_spec_uses_default_on_later_login(self):
        lua, _ = load(record=False, setup='''
          cvars.SpellQueueWindow = "180"
          OxQueueDB = { windowPerSpec = true }
        ''')
        self.assertEqual(lua.globals().cvars.SpellQueueWindow, "400")

    def test_new_spec_uses_client_default(self):
        self.ns.Apply(150)
        self.lua.execute('C_CVar.GetCVarDefault = function() return "350" end')
        self.switch(72)
        self.assertEqual(self.g.cvars.SpellQueueWindow, "350")

    def test_missing_default_api_uses_fallback(self):
        self.ns.Apply(150)
        self.g.C_CVar.GetCVarDefault = None
        self.switch(72)
        self.assertEqual(self.g.cvars.SpellQueueWindow, "400")

    def test_combat_pending_window_stays_with_its_spec(self):
        self.g.combat = True
        self.ns.Apply(150)
        self.assertEqual(self.g.OxQueueDB.profiles["71"].window, 150)
        self.switch(72)
        self.ns.Apply(250)
        self.assertEqual(self.g.cvars.SpellQueueWindow, "400")
        self.g.combat = False
        self.g.fire("PLAYER_REGEN_ENABLED")
        self.assertEqual(self.g.cvars.SpellQueueWindow, "250")
        self.assertEqual(self.ns.PreviousWindow(), 400)
        self.assertIsNone(self.ns.PendingApply())
        self.switch(71)
        self.assertEqual(self.g.cvars.SpellQueueWindow, "150")
        self.assertEqual(self.ns.PreviousWindow(), 400)
        self.assertIsNone(self.ns.PendingApply())

    def test_login_in_combat_defers_restore(self):
        lua, ns = load(record=False, setup='''
          combat = true
          OxQueueDB = { windowPerSpec = true, profiles = {
            ["71"] = { cycles = {}, intervals = {}, presses = 0, combatTime = 0,
              window = 150, previousWindow = 200 }
          } }
        ''')
        g = lua.globals()
        self.assertEqual(g.cvars.SpellQueueWindow, "400")
        self.assertEqual(ns.PendingApply(), 150)
        g.combat = False
        g.fire("PLAYER_REGEN_ENABLED")
        self.assertEqual(g.cvars.SpellQueueWindow, "150")
        self.assertEqual(ns.PreviousWindow(), 200)

    def test_zero_window_is_saved_restored_and_deferred(self):
        self.g.combat = True
        self.ns.Apply(0)
        self.assertEqual(self.ns.PendingApply(), 0)
        self.g.combat = False
        self.g.fire("PLAYER_REGEN_ENABLED")
        self.assertEqual(self.g.cvars.SpellQueueWindow, "0")
        self.switch(72)
        self.switch(71)
        self.assertEqual(self.g.cvars.SpellQueueWindow, "0")

    def test_reset_clears_samples_but_preserves_window_and_revert(self):
        self.ns.Apply(150)
        self.ns.Reset()
        self.assertEqual(profile(self.lua).window, 150)
        self.assertEqual(self.ns.PreviousWindow(), 400)
        self.switch(72)
        self.switch(71)
        self.assertEqual(self.g.cvars.SpellQueueWindow, "150")

    def test_repeated_or_other_unit_events_do_not_restore_window(self):
        self.ns.Apply(150)
        self.g.cvars.SpellQueueWindow = "200"
        self.g.fire("PLAYER_SPECIALIZATION_CHANGED", "player")
        self.g.specID = 72
        self.g.fire("PLAYER_SPECIALIZATION_CHANGED", "party1")
        self.assertEqual(self.g.cvars.SpellQueueWindow, "200")
        self.assertEqual(self.ns.PreviousWindow(), 400)

    def test_missing_spec_waits_to_migrate_until_spec_is_known(self):
        lua, ns = load(record=False, setup='''
          specID = nil
          cvars.SpellQueueWindow = "180"
          OxQueueDB = { previousWindow = 300 }
        ''')
        g = lua.globals()
        ns.Apply(150)
        self.assertEqual(g.cvars.SpellQueueWindow, "180")
        self.assertIsNone(g.OxQueueDB.windowPerSpec)
        self.assertIsNone(g.OxQueueDB.profiles["none"].window)
        g.specID = 71
        g.fire("PLAYER_SPECIALIZATION_CHANGED", "player")
        self.assertEqual(g.OxQueueDB.profiles["71"].window, 180)
        self.assertEqual(ns.PreviousWindow(), 300)

    def test_panel_revert_and_pending_follow_active_spec(self):
        ui = open_panel(self.lua, self.ns)
        self.ns.Apply(150)
        self.assertTrue(ui.revert.shown)
        self.g.combat = True
        self.ns.Apply(180)
        self.assertEqual(ui.apply.label.text, "Applies after combat")
        self.switch(72)
        self.g.combat = False
        self.g.fire("PLAYER_REGEN_ENABLED")
        self.assertFalse(ui.revert.shown)
        self.switch(71)
        self.assertEqual(ui.revert.label.text, "Revert to 150 ms")
        click(ui.revert)
        self.assertEqual(self.g.cvars.SpellQueueWindow, "150")


class PanelTest(unittest.TestCase):
    def setUp(self):
        self.lua, self.ns = load()
        self.g = self.lua.globals()

    def open(self):
        return open_panel(self.lua, self.ns)

    def test_collecting_state(self):
        ui = self.open()
        self.assertEqual(ui.recLabel.text, "Collecting")
        self.assertEqual(ui.big.text, "0")
        self.assertEqual(ui.unit.text, "/ 30 GCDs")
        self.assertFalse(ui.apply.enabled)
        self.assertEqual(ui.apply.label.text, "Apply")
        self.assertEqual(ui.record.label.text, "Stop")

    def test_ready_apply_and_revert(self):
        run(self.lua, [i * 0.1 + 0.01 for i in range(400)])
        ui = self.open()
        self.assertEqual(ui.big.text, "140")
        self.assertEqual(ui.deltaText.text, "-260 ms")
        self.assertEqual(ui.reason.text, "Set by your ping")
        self.assertEqual(ui.insight.text, "At 400 ms, 100% of your GCDs queue in time. At 140 ms: 100%.")
        self.assertEqual(ui.apply.label.text, "Apply 140 ms")
        self.assertFalse(ui.revert.shown)

        click(ui.apply)
        self.assertEqual(self.g.cvars.SpellQueueWindow, "140")
        self.assertEqual(ui.apply.label.text, "Applied")
        self.assertFalse(ui.apply.enabled)
        self.assertTrue(ui.revert.shown)
        self.assertEqual(ui.revert.label.text, "Revert to 400 ms")

        click(ui.revert)
        self.assertEqual(self.g.cvars.SpellQueueWindow, "400")

    def test_apply_in_combat_waits(self):
        run(self.lua, [i * 0.1 + 0.01 for i in range(400)])
        ui = self.open()
        self.g.enterCombat()
        click(ui.apply)
        self.assertEqual(ui.apply.label.text, "Applies after combat")
        self.g.combat = False
        self.g.fire("PLAYER_REGEN_ENABLED")
        self.assertEqual(self.g.cvars.SpellQueueWindow, "140")

    def test_record_button_and_no_cost_when_stopped(self):
        ui = self.open()
        sampler = self.g.frames[2]  # [1] is the mock BT4Button1
        self.assertIsNotNone(sampler.scripts.OnUpdate)  # recording, even before combat
        click(ui.record)  # stop
        self.assertIsNone(sampler.scripts.OnUpdate)
        self.assertEqual(ui.record.label.text, "Start recording")
        click(ui.record)  # start again
        self.assertIsNotNone(sampler.scripts.OnUpdate)
        self.assertEqual(ui.record.label.text, "Stop")

    def test_records_even_if_combat_event_never_arrives(self):
        # Lockdown on with no PLAYER_REGEN_DISABLED (e.g. events missed): still records.
        self.g.combat = True
        sim = Sim(self.lua, 400)
        for i in range(400):
            sim.press(i * 0.1 + 0.01)
        self.assertGreater(len(profile(self.lua).cycles), 25)

    def test_explains_zero_gcds(self):
        ui = self.open()
        self.g.enterCombat()
        self.g.secretGCD = True
        self.g.gcdStart, self.g.gcdDur, self.g.now = 0, 1, 0.5
        self.g.tick()
        self.g.press()
        self.ns.UI.Refresh()
        self.assertEqual(ui.statusMeta.text, "Presses: 0 during GCD · 0 after · 1 unreadable")

    def test_traffic_lights(self):
        ui = self.open()
        panel = self.ns.UI.Frame()[0]
        close, mini, zoom = ui.lights[1], ui.lights[2], ui.lights[3]
        click(mini)
        self.g.settle()
        self.assertTrue(self.g.OxQueueDB.compact)
        self.assertFalse(ui.fullOnly[1].shown)
        click(zoom)
        self.assertFalse(self.g.OxQueueDB.compact)
        self.assertTrue(ui.fullOnly[1].shown)
        click(close)
        self.assertTrue(panel.shown)  # fades out first
        self.g.settle()
        self.assertFalse(panel.shown)

    def test_reset_needs_two_clicks(self):
        run(self.lua, [i * 0.1 + 0.01 for i in range(400)])
        ui = self.open()
        click(ui.reset)
        self.assertEqual(ui.big.text, "140")
        self.assertEqual(ui.reset.label.text, "Click again to reset")
        click(ui.reset)
        self.assertEqual(ui.big.text, "0")

    def test_theme_switch(self):
        ui = self.open()
        click(ui.theme.segments.dark)
        self.assertEqual(self.g.OxQueueDB.theme, "dark")
        self.assertTrue(ui.theme.segments.dark.selected)
        self.assertFalse(ui.theme.segments.light.selected)

    def test_login_mentions_qq_group(self):
        out = "\n".join(self.g.messages[i] for i in range(1, len(self.g.messages) + 1))
        self.assertIn("233489177", out)

    def test_qq_row_copies(self):
        ui = self.open()
        self.assertEqual(ui.qq.text, "233489177")
        self.assertEqual(ui.qqHint.text, "Click to copy")
        self.lua.execute("copied = {}; function CopyToClipboard(s) copied[#copied + 1] = s end")
        ui.qq.scripts.OnEditFocusGained(ui.qq)
        self.lua.execute("timers[#timers]()")
        self.assertEqual(list(self.g.copied.values()), ["233489177"])
        self.assertEqual(ui.qqHint.text, "Copied!")
        # typing into it never changes the number
        ui.qq.scripts.OnTextChanged(ui.qq, True)
        self.assertEqual(ui.qq.text, "233489177")

    def test_qq_row_selects_without_clipboard(self):
        ui = self.open()
        self.g.CopyToClipboard = None
        ui.qq.scripts.OnEditFocusGained(ui.qq)
        self.assertEqual(ui.qqHint.text, "Selected, press Ctrl+C")
        ui.qq.scripts.OnEditFocusLost(ui.qq)
        self.assertEqual(ui.qqHint.text, "Click to copy")

    def test_chinese_locale(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(MOCK)
        lua.globals().locale = "zhCN"
        ns = lua.table()
        for f in FILES:
            lua.execute((ADDON / f).read_text(encoding="utf-8"), "OxQueue", ns)
        g = lua.globals()
        g.fire("ADDON_LOADED", "OxQueue")
        g.fire("PLAYER_LOGIN")
        ui = open_panel(lua, ns)
        self.assertEqual(ui.record.label.text, "开始记录")
        self.assertEqual(ui.apply.label.text, "应用")


class PackagingTest(unittest.TestCase):
    def test_paths_match_folder(self):
        # WoW loads textures by folder name; a stale name shows green squares, with no error.
        name = ADDON.name
        self.assertTrue((ADDON / f"{name}.toc").exists())
        ui = (ADDON / "UI.lua").read_text(encoding="utf-8")
        self.assertIn('"Interface\\\\AddOns\\\\' + name + '\\\\Media\\\\"', ui)
        for tex in ("circle32", "circle64", "circle128", "circle256", "glyph_close", "glyph_mini", "glyph_zoom", "shadow"):
            self.assertTrue((ADDON / "Media" / f"{tex}.tga").exists(), tex)


if __name__ == "__main__":
    unittest.main(verbosity=2)
