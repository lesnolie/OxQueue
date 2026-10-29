local _, ns = ...
local A, L = ns.Analyzer, ns.L

local UI = {}
ns.UI = UI

local MEDIA = "Interface\\AddOns\\OxQueue\\Media\\"
local FONT = STANDARD_TEXT_FONT
local W, PAD = 440, 16
local H_FULL, H_COMPACT = 584, 216
local INNER = W - PAD * 2           -- card width
local CHART_W, CHART_H = INNER - 32, 92
local CHART_MAX, BIN = 400, 20       -- ms shown on the x axis, ms per bar
local BINS = CHART_MAX / BIN + 1     -- last bar collects everything past the cap

-- Motion: one ease-out curve family, short durations, nothing loops except the live dot.
local DUR = { open = 0.22, close = 0.16, resize = 0.22, data = 0.3 }
local RISE = 8                       -- px the panel rises while it fades in

-- macOS (Sonoma/Sequoia) system colours. Alpha-on-background greys, as AppKit uses.
local THEMES = {
  light = {
    bg = { 0.937, 0.937, 0.945, 1 }, surface = { 1, 1, 1, 1 }, border = { 0, 0, 0, 0.09 },
    text = { 0, 0, 0, 0.85 }, muted = { 0, 0, 0, 0.5 }, faint = { 0, 0, 0, 0.26 },
    accent = { 0, 0.478, 1, 1 }, accentDown = { 0, 0.4, 0.86, 1 }, onAccent = { 1, 1, 1, 1 },
    accentSoft = { 0, 0.478, 1, 0.12 }, bar = { 0, 0, 0, 0.1 }, barLost = { 0, 0, 0, 0.05 },
    track = { 0, 0, 0, 0.07 }, button = { 1, 1, 1, 1 }, buttonDown = { 0.9, 0.9, 0.91, 1 },
    buttonEdge = { 0, 0, 0, 0.14 }, buttonShadow = { 0, 0, 0, 0.06 }, segTrack = { 0, 0, 0, 0.06 },
    segOn = { 1, 1, 1, 1 }, live = { 1, 0.231, 0.188, 1 }, wait = { 1, 0.584, 0, 1 },
    shadow = { 0, 0, 0, 0.22 }, pingBand = { 0, 0.478, 1, 0.07 }, close = { 1, 0.373, 0.341, 1 },
    mini = { 0.996, 0.737, 0.18, 1 }, zoom = { 0.157, 0.784, 0.251, 1 }, glyph = { 0, 0, 0, 0.5 },
    lightRing = { 0, 0, 0, 0.12 }, ok = { 0.204, 0.78, 0.349, 1 },
  },
  dark = {
    bg = { 0.118, 0.118, 0.125, 1 }, surface = { 0.173, 0.173, 0.18, 1 }, border = { 1, 1, 1, 0.08 },
    text = { 1, 1, 1, 0.85 }, muted = { 1, 1, 1, 0.55 }, faint = { 1, 1, 1, 0.25 },
    accent = { 0.039, 0.518, 1, 1 }, accentDown = { 0.03, 0.43, 0.86, 1 }, onAccent = { 1, 1, 1, 1 },
    accentSoft = { 0.039, 0.518, 1, 0.2 }, bar = { 1, 1, 1, 0.12 }, barLost = { 1, 1, 1, 0.05 },
    track = { 1, 1, 1, 0.09 }, button = { 0.36, 0.36, 0.373, 1 }, buttonDown = { 0.43, 0.43, 0.45, 1 },
    buttonEdge = { 1, 1, 1, 0.06 }, buttonShadow = { 0, 0, 0, 0.2 }, segTrack = { 1, 1, 1, 0.07 },
    segOn = { 0.39, 0.39, 0.4, 1 }, live = { 1, 0.271, 0.227, 1 }, wait = { 1, 0.624, 0.039, 1 },
    shadow = { 0, 0, 0, 0.55 }, pingBand = { 0.039, 0.518, 1, 0.1 }, close = { 1, 0.373, 0.341, 1 },
    mini = { 0.996, 0.737, 0.18, 1 }, zoom = { 0.157, 0.784, 0.251, 1 }, glyph = { 0, 0, 0, 0.55 },
    lightRing = { 0, 0, 0, 0.25 }, ok = { 0.188, 0.82, 0.345, 1 },
  },
}

local painters = {}
local function theme() return THEMES[ns.DB().theme] or THEMES.light end
local function onPaint(fn) painters[#painters + 1] = fn end
local function repaint()
  local T = theme()
  for _, fn in ipairs(painters) do fn(T) end
end

---------------------------------------------------------------- pixel grid

-- UI units per physical pixel for this panel. Everything is placed on whole physical
-- pixels: fractional edges are what make 1px lines blur, double up, or look ragged.
local P = 1
local function measurePixel(scale)
  local _, h = GetPhysicalScreenSize()
  P = (h and h > 0) and 768 / h / scale or 1
end
local function snap(v) return math.floor(v / P + 0.5) * P end

-- Pick the disc texture closest above the on-screen size; addon TGAs have no mipmaps,
-- so minifying a large texture several times over is what produces stair-stepped edges.
local function circleFor(diameter)
  local need = diameter / P
  for _, n in ipairs({ 32, 64, 128, 256 }) do
    if n >= need then return MEDIA .. "circle" .. n end
  end
  return MEDIA .. "circle256"
end

---------------------------------------------------------------- motion

local function easeOut(t) return 1 - (1 - t) ^ 3 end

-- One driver for every tween; its OnUpdate exists only while something is moving.
local tweens, driver = {}, nil
local function reducedMotion() return ns.DB().reduceMotion or InCombatLockdown() end

local function tick(_, elapsed)
  local busy = false
  for key, tw in pairs(tweens) do
    tw.t = math.min(1, tw.t + elapsed / tw.dur)
    tw.apply(tw.from + (tw.to - tw.from) * easeOut(tw.t))
    if tw.t >= 1 then
      tweens[key] = nil
      if tw.done then tw.done() end
    else
      busy = true
    end
  end
  if not busy and not next(tweens) then driver:SetScript("OnUpdate", nil) end
end

-- Retargeting a running tween continues from where it is now, so interruptions never jump.
local function tween(key, from, to, dur, apply, done)
  local running = tweens[key]
  if running then from = running.value or from end
  if reducedMotion() or math.abs(to - from) < 0.001 then
    tweens[key] = nil
    apply(to)
    if done then done() end
    return
  end
  local tw = { from = from, to = to, t = 0, dur = dur, done = done }
  tw.apply = function(v) tw.value = v; apply(v) end
  tweens[key] = tw
  driver:SetScript("OnUpdate", tick)
end

---------------------------------------------------------------- primitives

-- Rounded rectangle covering `parent` (grown by -inset, shifted down by dy), built from four
-- disc quarters and three plain strips so no overlapping alpha shows through.
local function RoundRect(parent, layer, sublevel, radius, inset, dy)
  local r, i, y = snap(radius), snap(inset or 0), snap(dy or 0)
  local rect = { corners = {}, strips = {} }
  local function tex(list)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    list[#list + 1] = t
    return t
  end
  local disc = circleFor(r * 2)
  for _, c in ipairs({ { "TOPLEFT", 0, 0.5, 0, 0.5, i, -i }, { "TOPRIGHT", 0.5, 1, 0, 0.5, -i, -i },
      { "BOTTOMLEFT", 0, 0.5, 0.5, 1, i, i }, { "BOTTOMRIGHT", 0.5, 1, 0.5, 1, -i, i } }) do
    local t = tex(rect.corners)
    t:SetTexture(disc, "CLAMP", "CLAMP", "LINEAR")
    t:SetTexCoord(c[2], c[3], c[4], c[5])
    t:SetSize(r, r)
    t:SetPoint(c[1], c[6], c[7] - y)
  end
  local mid = tex(rect.strips)
  mid:SetPoint("TOPLEFT", i + r, -i - y)
  mid:SetPoint("BOTTOMRIGHT", -i - r, i - y)
  local left = tex(rect.strips)
  left:SetPoint("TOPLEFT", i, -i - r - y)
  left:SetPoint("BOTTOMLEFT", i, i + r - y)
  left:SetWidth(r)
  local right = tex(rect.strips)
  right:SetPoint("TOPRIGHT", -i, -i - r - y)
  right:SetPoint("BOTTOMRIGHT", -i, i + r - y)
  right:SetWidth(r)
  function rect.SetColor(c)
    for _, t in ipairs(rect.corners) do t:SetVertexColor(c[1], c[2], c[3], c[4]) end
    for _, t in ipairs(rect.strips) do t:SetColorTexture(c[1], c[2], c[3], c[4]) end
  end
  function rect.SetShown(on)
    for _, t in ipairs(rect.corners) do t:SetShown(on) end
    for _, t in ipairs(rect.strips) do t:SetShown(on) end
  end
  return rect
end

-- Window shadow: one pre-blurred texture as a 9-slice (no stacked layers, so no banding).
-- shadow.tga is 128px with the shape inset 32px; corners take 48px of it.
local function Shadow(frame, spread, dy)
  local k = spread / 32               -- UI units per shadow texel
  local c = snap(48 * k)
  local o, y = snap(spread), snap(dy)
  local parts = {}
  local function part(l, r, t, b)
    local tex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    tex:SetTexture(MEDIA .. "shadow", "CLAMP", "CLAMP", "LINEAR")
    tex:SetTexCoord(l, r, t, b)
    parts[#parts + 1] = tex
    return tex
  end
  local e = 48 / 128
  local tl = part(0, e, 0, e); tl:SetSize(c, c); tl:SetPoint("TOPLEFT", -o, o - y)
  local tr = part(1 - e, 1, 0, e); tr:SetSize(c, c); tr:SetPoint("TOPRIGHT", o, o - y)
  local bl = part(0, e, 1 - e, 1); bl:SetSize(c, c); bl:SetPoint("BOTTOMLEFT", -o, -o - y)
  local br = part(1 - e, 1, 1 - e, 1); br:SetSize(c, c); br:SetPoint("BOTTOMRIGHT", o, -o - y)
  local top = part(e, 1 - e, 0, e); top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  local bot = part(e, 1 - e, 1 - e, 1); bot:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  local lft = part(0, e, e, 1 - e); lft:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); lft:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  local rgt = part(1 - e, 1, e, 1 - e); rgt:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); rgt:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  onPaint(function(T) for _, t in ipairs(parts) do t:SetVertexColor(unpack(T.shadow)) end end)
end

-- Grouped-form section, as in System Settings: white, 10px corners, hairline edge.
local function Card(parent, radius)
  local f = CreateFrame("Frame", nil, parent)
  local edge = RoundRect(f, "BACKGROUND", 0, radius)
  local fill = RoundRect(f, "BACKGROUND", 1, radius - P, P)
  onPaint(function(T)
    edge.SetColor(T.border)
    fill.SetColor(T.surface)
  end)
  return f
end

local function Text(parent, size, colorKey, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(FONT, size, "")
  fs:SetShadowOffset(0, 0)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  fs.colorKey = colorKey
  onPaint(function(T) fs:SetTextColor(unpack(T[fs.colorKey])) end)
  return fs
end

local function setKey(fs, key)
  fs.colorKey = key
  fs:SetTextColor(unpack(theme()[key]))
end

-- Push button. style "primary" = default (accent) button, "secondary" = plain push button.
-- Like AppKit: no hover effect, darker while held, dimmed when disabled.
local function Button(parent, w, h, style, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(snap(w), snap(h))
  local shadow = RoundRect(b, "BACKGROUND", 0, 6, 0, P)
  local edge = RoundRect(b, "BACKGROUND", 1, 6)
  local fill = RoundRect(b, "BACKGROUND", 2, 6 - P, P)
  b.label = Text(b, 12, "text", "CENTER")
  b.label:SetPoint("CENTER", 0, 0)
  b.style, b.enabled = style, true

  function b.Paint(T)
    T = T or theme()
    local primary = b.style == "primary" and b.enabled
    local fillC = primary and (b.down and T.accentDown or T.accent) or (b.down and T.buttonDown or T.button)
    fill.SetColor(fillC)
    edge.SetColor(primary and fillC or T.buttonEdge)
    shadow.SetColor(T.buttonShadow)
    setKey(b.label, primary and "onAccent" or (b.enabled and "text" or "faint"))
    b:SetAlpha(b.enabled and 1 or 0.75)
  end
  function b.SetActive(on)
    b.enabled = on
    b.Paint()
  end
  b:SetScript("OnMouseDown", function() if b.enabled then b.down = true; b.Paint() end end)
  b:SetScript("OnMouseUp", function() b.down = false; b.Paint() end)
  b:SetScript("OnClick", function() if b.enabled then onClick(b) end end)
  onPaint(b.Paint)
  return b
end

-- Segmented control: a recessed track; the raised selection slides between segments.
local function Segmented(parent, labels, onSelect)
  local track = CreateFrame("Frame", nil, parent)
  local segW, h = 52, 22
  track:SetSize(snap(segW * #labels + 4), snap(h + 4))
  local bg = RoundRect(track, "BACKGROUND", 0, 7)
  onPaint(function(T) bg.SetColor(T.segTrack) end)

  local knob = CreateFrame("Frame", nil, track)
  knob:SetSize(snap(segW), snap(h))
  local knobShadow = RoundRect(knob, "BACKGROUND", 1, 6, 0, P)
  local knobFill = RoundRect(knob, "BACKGROUND", 2, 6)
  onPaint(function(T) knobFill.SetColor(T.segOn); knobShadow.SetColor(T.buttonShadow) end)
  local function placeKnob(x)
    knob:ClearAllPoints()
    knob:SetPoint("LEFT", snap(x), 0)
  end

  track.segments, track.index = {}, {}
  for i, item in ipairs(labels) do
    local b = CreateFrame("Button", nil, track)
    b:SetSize(snap(segW), snap(h))
    b:SetPoint("LEFT", snap(2 + (i - 1) * segW), 0)
    b:SetFrameLevel(knob:GetFrameLevel() + 1)
    b.label = Text(b, 11, "text", "CENTER")
    b.label:SetPoint("CENTER")
    b.label:SetText(item.text)
    b.key = item.key
    function b.Paint() setKey(b.label, b.selected and "text" or "muted") end
    b:SetScript("OnClick", function() onSelect(b.key) end)
    onPaint(b.Paint)
    track.segments[item.key] = b
    track.index[item.key] = i
  end
  function track.Select(key, instant)
    for k, b in pairs(track.segments) do b.selected = (k == key); b.Paint() end
    local x = 2 + (track.index[key] - 1) * segW
    if instant then placeKnob(x); track.knobX = x
    else
      tween("seg", track.knobX or x, x, DUR.resize, function(v) track.knobX = v; placeKnob(v) end)
    end
  end
  return track
end

-- Window control ("traffic light"); symbols appear while hovering the group, as on macOS.
local function TrafficLight(parent, colorKey, glyph, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(snap(12), snap(12))
  local ring = b:CreateTexture(nil, "ARTWORK", nil, 0)
  ring:SetTexture(circleFor(12), "CLAMP", "CLAMP", "LINEAR")
  ring:SetAllPoints()
  local dot = b:CreateTexture(nil, "ARTWORK", nil, 1)
  dot:SetTexture(circleFor(12), "CLAMP", "CLAMP", "LINEAR")
  dot:SetPoint("TOPLEFT", P, -P)
  dot:SetPoint("BOTTOMRIGHT", -P, P)
  b.glyph = b:CreateTexture(nil, "OVERLAY")
  b.glyph:SetTexture(MEDIA .. "glyph_" .. glyph, "CLAMP", "CLAMP", "LINEAR")
  b.glyph:SetSize(snap(10), snap(10))
  b.glyph:SetPoint("CENTER")
  b.glyph:SetAlpha(0)
  onPaint(function(T)
    ring:SetVertexColor(unpack(T.lightRing))
    dot:SetVertexColor(unpack(T[colorKey]))
    b.glyph:SetVertexColor(unpack(T.glyph))
  end)
  b:SetScript("OnClick", onClick)
  return b
end

local function Solid(parent, layer, colorKey, sublevel)
  local t = parent:CreateTexture(nil, layer, nil, sublevel or 2)
  t.colorKey = colorKey
  onPaint(function(T) t:SetColorTexture(unpack(T[t.colorKey])) end)
  return t
end

-- Thin capsule progress bar whose fill eases to its value.
local function Progress(parent, w)
  local track = CreateFrame("Frame", nil, parent)
  track:SetSize(snap(w), snap(4))
  local bg = RoundRect(track, "ARTWORK", 0, 2)
  local fillFrame = CreateFrame("Frame", nil, track)
  fillFrame:SetPoint("TOPLEFT")
  fillFrame:SetPoint("BOTTOMLEFT")
  local fill = RoundRect(fillFrame, "ARTWORK", 1, 2)
  onPaint(function(T) bg.SetColor(T.track); fill.SetColor(T.accent) end)
  function track.SetValue(p)
    local target = math.max(4, w * math.min(1, p))
    tween("progress", track.value or target, target, DUR.data, function(v)
      track.value = v
      fillFrame:SetWidth(snap(v))
    end)
  end
  return track
end

local function clock(sec)
  sec = math.floor(sec + 0.5)
  if sec >= 3600 then return string.format("%d:%02d:%02d", sec / 3600, sec % 3600 / 60, sec % 60) end
  return string.format("%d:%02d", sec / 60, sec % 60)
end

---------------------------------------------------------------- panel

local panel, ticker
local ui = {}
local anchor                         -- { left, top } in UIParent coordinates

local function chartX(ms) return math.min(ms, CHART_MAX) / CHART_MAX * CHART_W end

local function place(offsetY)
  panel:ClearAllPoints()
  if anchor then
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", snap(anchor[1]), snap(anchor[2] + (offsetY or 0)))
  else
    panel:SetPoint("TOP", UIParent, "TOP", 0, snap(-140 + (offsetY or 0)))
  end
end

local function setCompact(on, instant)
  ns.DB().compact = on
  local from = panel:GetHeight()
  local to = on and H_COMPACT or H_FULL
  if not on then for _, f in ipairs(ui.fullOnly) do f:Show() end end
  local function done() if on then for _, f in ipairs(ui.fullOnly) do f:Hide() end end end
  if instant then
    panel:SetHeight(to)
    done()
  else
    -- The window top stays put; content below is clipped while it grows or shrinks.
    tween("height", from, to, DUR.resize, function(v) panel:SetHeight(snap(v)) end, done)
  end
end

local function buildTitleBar()
  -- Traffic lights: close, collapse to the summary, expand to the full panel.
  local lights = CreateFrame("Frame", nil, panel)
  lights:SetSize(snap(56), snap(16))
  lights:SetPoint("TOPLEFT", snap(14), snap(-14))
  ui.lights = {
    TrafficLight(lights, "close", "close", function() UI.Close() end),
    TrafficLight(lights, "mini", "mini", function() setCompact(true) end),
    TrafficLight(lights, "zoom", "zoom", function() setCompact(false) end),
  }
  local function showGlyphs(on)
    tween("glyphs", ui.glyphAlpha or 0, on and 1 or 0, 0.12, function(v)
      ui.glyphAlpha = v
      for _, b in ipairs(ui.lights) do b.glyph:SetAlpha(v) end
    end)
  end
  for i, b in ipairs(ui.lights) do
    b:SetPoint("LEFT", snap((i - 1) * 20), 0)
    b:SetScript("OnEnter", function() showGlyphs(true) end)
    b:SetScript("OnLeave", function() showGlyphs(false) end)
  end

  local title = Text(panel, 13, "text", "CENTER")
  title:SetPoint("TOP", 0, snap(-14))
  title:SetText(L.TITLE)
  local subtitle = Text(panel, 10, "muted", "CENTER")
  subtitle:SetPoint("TOP", title, "BOTTOM", 0, snap(-2))
  subtitle:SetText(L.SUBTITLE)

  ui.theme = Segmented(panel, { { key = "light", text = L.LIGHT }, { key = "dark", text = L.DARK } },
    function(key)
      ns.DB().theme = key
      ui.theme.Select(key)
      repaint()
      UI.Refresh()
    end)
  ui.theme:SetPoint("TOPRIGHT", snap(-PAD + 2), snap(-11))
end

local function buildStatus(y)
  local card = Card(panel, 10)
  card:SetSize(snap(INNER), snap(52))
  card:SetPoint("TOPLEFT", snap(PAD), snap(y))

  local dot = card:CreateTexture(nil, "ARTWORK")
  dot:SetTexture(circleFor(8), "CLAMP", "CLAMP", "LINEAR")
  dot:SetSize(snap(8), snap(8))
  dot:SetPoint("TOPLEFT", snap(14), snap(-15))
  local pulse = dot:CreateAnimationGroup()
  pulse:SetLooping("BOUNCE")
  local fade = pulse:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0.3)
  fade:SetDuration(0.8)
  fade:SetSmoothing("IN_OUT")
  ui.dot, ui.pulse = dot, pulse

  ui.status = Text(card, 12, "text")
  ui.status:SetPoint("LEFT", dot, "RIGHT", snap(8), 0)
  ui.statusMeta = Text(card, 10, "muted")
  ui.statusMeta:SetPoint("TOPLEFT", ui.status, "BOTTOMLEFT", 0, snap(-5))
  ui.statusMeta:SetWidth(snap(INNER - 160))

  ui.record = Button(card, 112, 24, "primary", function() ns.SetRecording(not ns.IsRecording()) end)
  ui.record:SetPoint("RIGHT", snap(-12), 0)
end

local function buildHero(y)
  local card = Card(panel, 10)
  card:SetSize(snap(INNER), snap(88))
  card:SetPoint("TOPLEFT", snap(PAD), snap(y))

  ui.recLabel = Text(card, 11, "muted")
  ui.recLabel:SetPoint("TOPLEFT", snap(16), snap(-14))
  ui.big = Text(card, 32, "text")
  ui.big:SetPoint("TOPLEFT", ui.recLabel, "BOTTOMLEFT", 0, snap(-6))
  ui.unit = Text(card, 13, "muted")
  ui.unit:SetPoint("BOTTOMLEFT", ui.big, "BOTTOMRIGHT", snap(5), snap(4))

  ui.now = Text(card, 12, "text", "RIGHT")
  ui.now:SetPoint("TOPRIGHT", snap(-16), snap(-18))
  ui.delta = CreateFrame("Frame", nil, card)
  ui.delta:SetSize(snap(64), snap(20))
  ui.delta:SetPoint("RIGHT", ui.now, "LEFT", snap(-8), 0)
  local pill = RoundRect(ui.delta, "BACKGROUND", 2, 10)
  onPaint(function(T) pill.SetColor(T.accentSoft) end)
  ui.deltaText = Text(ui.delta, 11, "accent", "CENTER")
  ui.deltaText:SetPoint("CENTER")
  ui.reason = Text(card, 11, "muted", "RIGHT")
  ui.reason:SetPoint("BOTTOMRIGHT", snap(-16), snap(18))

  ui.progress = Progress(card, 160)
  ui.progress:SetPoint("BOTTOMRIGHT", snap(-16), snap(22))
end

local function buildChart(y)
  local card = Card(panel, 10)
  card:SetSize(snap(INNER), snap(220))
  card:SetPoint("TOPLEFT", snap(PAD), snap(y))

  local title = Text(card, 12, "text")
  title:SetPoint("TOPLEFT", snap(16), snap(-14))
  title:SetText(L.CHART_TITLE)
  local hint = Text(card, 10, "muted")
  hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, snap(-4))
  hint:SetWidth(snap(CHART_W))
  hint:SetText(L.CHART_HINT)

  local chart = CreateFrame("Frame", nil, card)
  chart:SetSize(snap(CHART_W), snap(CHART_H))
  chart:SetPoint("TOPLEFT", snap(16), snap(-64))
  ui.chart = chart

  ui.pingBand = Solid(chart, "BACKGROUND", "pingBand", 3)
  ui.pingBand:SetPoint("TOPLEFT")
  ui.pingBand:SetPoint("BOTTOMLEFT")
  ui.pingLabel = Text(chart, 10, "accent")
  ui.pingLabel:SetPoint("TOPLEFT", snap(4), snap(-3))
  ui.pingLabel:SetText(L.MARK_PING)

  local baseline = Solid(chart, "ARTWORK", "border")
  baseline:SetHeight(P)
  baseline:SetPoint("BOTTOMLEFT")
  baseline:SetPoint("BOTTOMRIGHT")

  -- Whole-pixel bar widths and gaps, so every bar is identical on screen.
  local pitch = CHART_W / BINS
  local gap = math.max(P, snap(3))
  ui.bars = {}
  for i = 1, BINS do
    local bar = Solid(chart, "ARTWORK", "bar", 1)
    local x0, x1 = snap((i - 1) * pitch), snap(i * pitch)
    bar:SetWidth(x1 - x0 - gap)
    bar:SetPoint("BOTTOMLEFT", x0 + snap(gap / 2), P)
    bar:SetHeight(P)
    bar.h = 0
    ui.bars[i] = bar
  end

  -- Recommended: solid accent line. Now: dashed line.
  ui.recLine = Solid(chart, "OVERLAY", "accent")
  ui.recLine:SetSize(snap(2), snap(CHART_H + 6))
  ui.nowDashes = {}
  for i = 1, math.floor((CHART_H + 6) / 6) do
    local d = Solid(chart, "OVERLAY", "muted")
    d:SetSize(P, snap(3))
    ui.nowDashes[i] = d
  end
  ui.recMark = Text(chart, 10, "accent")
  ui.nowMark = Text(chart, 10, "muted")

  for _, ms in ipairs({ 0, 100, 200, 300, 400 }) do
    local t = Text(chart, 10, "faint", "CENTER")
    t:SetPoint("TOP", chart, "BOTTOMLEFT", snap(chartX(ms)), snap(-4))
    t:SetText(ms == 400 and "400+" or tostring(ms))
  end

  ui.insight = Text(card, 11, "text")
  ui.insight:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, snap(-22))
  ui.insight:SetWidth(snap(CHART_W))
  ui.insight:SetWordWrap(true)
  ui.lateWarn = Text(card, 10, "muted")
  ui.lateWarn:SetPoint("TOPLEFT", ui.insight, "BOTTOMLEFT", 0, snap(-4))
  ui.lateWarn:SetWidth(snap(CHART_W))
  ui.lateWarn:SetWordWrap(true)
  return card
end

local function buildTiles(y)
  ui.tiles = {}
  local frames = {}
  local tw = (INNER - 3 * 8) / 4
  for i, key in ipairs({ "PING", "RHYTHM", "RATE", "LATE" }) do
    local tile = Card(panel, 10)
    local x0, x1 = snap(PAD + (i - 1) * (tw + 8)), snap(PAD + (i - 1) * (tw + 8) + tw)
    tile:SetSize(x1 - x0, snap(64))
    tile:SetPoint("TOPLEFT", x0, snap(y))
    local label = Text(tile, 10, "muted")
    label:SetPoint("TOPLEFT", snap(12), snap(-10))
    label:SetText(L["TILE_" .. key])
    tile.value = Text(tile, 16, "text")
    tile.value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, snap(-5))
    tile.sub = Text(tile, 10, "faint")
    tile.sub:SetPoint("TOPLEFT", tile.value, "BOTTOMLEFT", 0, snap(-4))
    tile.sub:SetText(L["TILE_" .. key .. "_SUB"])
    ui.tiles[key] = tile
    frames[i] = tile
  end
  return frames
end

-- QQ group row, as in ExecutionerWatch: a click copies with CopyToClipboard. If that isn't
-- available the row is a read-only edit box, so the click selects the number for Ctrl+C.
-- No OnKeyDown: the box only holds the keyboard while focused, and Esc/Enter/any click away
-- gives it back.
local function buildQQ(y)
  local card = Card(panel, 8)
  card:SetSize(snap(INNER), snap(28))
  card:SetPoint("TOPLEFT", snap(PAD), snap(y))
  local label = Text(card, 11, "muted")
  label:SetPoint("LEFT", snap(12), 0)
  label:SetText(L.QQ_LABEL)
  local hint = Text(card, 10, "faint", "RIGHT")
  hint:SetPoint("RIGHT", snap(-12), 0)

  local box = CreateFrame("EditBox", nil, card)
  box:SetAllPoints()
  box:SetAutoFocus(false)
  box:SetFont(FONT, 12, "")
  box:SetShadowOffset(0, 0)
  box:SetTextInsets(snap((label:GetStringWidth() or 0) + 22), snap(90), 0, 0)
  onPaint(function(T) box:SetTextColor(unpack(T.accent)) end)
  ui.qq, ui.qqHint = box, hint

  local group = ns.QQ_GROUP
  local function idle()
    box:SetText(group); box:SetCursorPosition(0)
    hint:SetText(L.QQ_COPY); setKey(hint, "faint")
  end
  local function copied()
    hint:SetText(L.QQ_COPIED); setKey(hint, "ok")
    ns.Print(string.format(L.QQ_COPIED_CHAT, group))
    box.copiedAt = GetTime()
    C_Timer.After(2, function() if not box:HasFocus() and GetTime() - box.copiedAt >= 1.9 then idle() end end)
  end
  box:SetScript("OnEditFocusGained", function(self)
    local copier = _G.CopyToClipboard
    if type(copier) == "function" and pcall(copier, group) then
      C_Timer.After(0, function() self:ClearFocus(); copied() end)
      return
    end
    self:SetText(group); self:HighlightText()
    hint:SetText(L.QQ_SELECTED); setKey(hint, "ok")
  end)
  box:SetScript("OnEditFocusLost", function(self)
    self:HighlightText(0, 0)
    if not self.copiedAt or GetTime() - self.copiedAt >= 1.9 then idle() end
  end)
  box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(group); self:HighlightText() end end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  idle()
  return card
end

local function buildFooter()
  local footer = CreateFrame("Frame", nil, panel)
  footer:SetSize(snap(INNER), snap(28))
  footer:SetPoint("TOPLEFT", snap(PAD), snap(-(H_FULL - PAD - 28)))

  ui.reset = Button(footer, 104, 28, "secondary", function(b)
    if b.armed then
      b.armed = nil
      ns.Reset()
    else
      b.armed = true
      b.label:SetText(L.RESET_CONFIRM)
      C_Timer.After(3, function() b.armed = nil; UI.Refresh() end)
    end
  end)
  ui.reset:SetPoint("LEFT")

  ui.revert = Button(footer, 116, 28, "secondary", function() ns.Apply(ns.PreviousWindow()) end)
  ui.revert:SetPoint("LEFT", ui.reset, "RIGHT", snap(8), 0)

  ui.apply = Button(footer, 140, 28, "primary", function() ns.Apply(ui.applyValue) end)
  ui.apply:SetPoint("RIGHT")
  return footer
end

local function build()
  panel = CreateFrame("Frame", "OxQueuePanel", UIParent)
  driver = CreateFrame("Frame")
  measurePixel(panel:GetEffectiveScale())
  panel:SetSize(snap(W), snap(H_FULL))
  panel:SetFrameStrata("DIALOG")
  panel:SetClampedToScreen(true)
  panel:SetClipsChildren(true)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    anchor = { self:GetLeft(), self:GetTop() }
    ns.DB().anchor = anchor
    place()
  end)
  anchor = ns.DB().anchor
  place()
  panel:Hide()
  tinsert(UISpecialFrames, "OxQueuePanel")  -- Esc closes it

  -- The shadow lives outside the panel's clip rect, on a sibling frame underneath.
  local shadowHost = CreateFrame("Frame", nil, UIParent)
  shadowHost:SetFrameStrata("DIALOG")
  shadowHost:SetFrameLevel(math.max(0, panel:GetFrameLevel() - 1))
  shadowHost:SetPoint("TOPLEFT", panel)
  shadowHost:SetPoint("BOTTOMRIGHT", panel)
  Shadow(shadowHost, 24, 6)
  ui.shadowHost = shadowHost
  shadowHost:Hide()

  local edge = RoundRect(panel, "BACKGROUND", -2, 12)
  local fill = RoundRect(panel, "BACKGROUND", -1, 12 - P, P)
  onPaint(function(T) edge.SetColor(T.border); fill.SetColor(T.bg) end)

  buildTitleBar()
  buildStatus(-48)
  buildHero(-108)
  ui.fullOnly = { buildChart(-204) }
  for _, t in ipairs(buildTiles(-432)) do ui.fullOnly[#ui.fullOnly + 1] = t end
  ui.fullOnly[#ui.fullOnly + 1] = buildQQ(-504)
  ui.fullOnly[#ui.fullOnly + 1] = buildFooter()

  panel:SetScript("OnShow", function()
    ui.shadowHost:Show()
    UI.Refresh()
    ticker = C_Timer.NewTicker(1, UI.Refresh)
  end)
  panel:SetScript("OnHide", function()
    ui.shadowHost:Hide()
    if ticker then ticker:Cancel(); ticker = nil end
  end)

  ui.theme.Select(ns.DB().theme, true)
  repaint()
  setCompact(ns.DB().compact and true or false, true)
end

---------------------------------------------------------------- open / close

-- Opening fades in while rising RISE px; closing plays the same path backwards, from
-- wherever an interrupted open had got to. Offsets are snapped so text never shimmers.
local function presence(v)
  panel:SetAlpha(v)
  ui.shadowHost:SetAlpha(v)
  place(-RISE * (1 - v))
end

function UI.Open()
  if not panel then build() end
  -- Hidden (including by Esc, which skips UI.Close): start from nothing, before the first
  -- frame draws, so the panel never flashes at full opacity.
  if not panel:IsShown() then
    tweens.presence = nil
    ui.presence = 0
    presence(reducedMotion() and 1 or 0)
  end
  panel:Show()
  tween("presence", ui.presence or 0, 1, DUR.open, function(v)
    ui.presence = v
    presence(v)
  end)
end

function UI.Close()
  if not panel or not panel:IsShown() then return end
  tween("presence", ui.presence or 1, 0, DUR.close, function(v)
    ui.presence = v
    presence(v)
  end, function() panel:Hide(); presence(1); ui.presence = 0 end)
end

function UI.Toggle()
  if panel and panel:IsShown() and (ui.presence or 1) > 0.5 then UI.Close() else UI.Open() end
end

---------------------------------------------------------------- refresh

-- Marker labels sit above their lines, nudged apart when close and kept inside the chart.
local function placeLabel(fs, x, side)
  local top = snap(CHART_H + 8)
  local w = fs:GetStringWidth() or 0
  fs:ClearAllPoints()
  local left
  if side == "left" then left = x - 3 - w
  elseif side == "right" then left = x + 3
  else left = x - w / 2 end
  left = math.max(0, math.min(CHART_W - w, left))
  fs:SetPoint("BOTTOMLEFT", ui.chart, "BOTTOMLEFT", snap(left), top)
end

local function drawMarkers(recX, nowX)
  ui.recLine:SetShown(recX ~= nil)
  ui.recMark:SetShown(recX ~= nil)
  if recX then
    ui.recLine:ClearAllPoints()
    ui.recLine:SetPoint("BOTTOMLEFT", ui.chart, "BOTTOMLEFT", snap(math.min(recX, CHART_W - 2) - 1), 0)
  end
  for i, d in ipairs(ui.nowDashes) do
    d:SetShown(nowX ~= nil)
    if nowX then
      d:ClearAllPoints()
      d:SetPoint("BOTTOMLEFT", ui.chart, "BOTTOMLEFT", snap(nowX), snap((i - 1) * 6))
    end
  end
  ui.nowMark:SetShown(nowX ~= nil)
  if recX and nowX and math.abs(recX - nowX) < 64 then
    local recRight = recX >= nowX
    placeLabel(ui.recMark, recX, recRight and "right" or "left")
    placeLabel(ui.nowMark, nowX, recRight and "left" or "right")
  else
    if recX then placeLabel(ui.recMark, recX) end
    if nowX then placeLabel(ui.nowMark, nowX) end
  end
end

local function refreshChart(r, cur)
  local bins = A.Histogram(r.leads, BIN, CHART_MAX + BIN)
  local peak = 0
  for _, n in ipairs(bins) do peak = math.max(peak, n) end
  local targets = {}
  for i, bar in ipairs(ui.bars) do
    targets[i] = peak > 0 and (CHART_H - 16) * (bins[i] or 0) / peak or 0
    -- Caught by the recommended window: accent. Past the 400 ms cap: lost at any setting.
    local key
    if i == BINS then key = "barLost"
    elseif r.value and i * BIN <= r.value + BIN / 2 then key = "accent"
    else key = r.value and "bar" or "accentSoft" end
    if bar.colorKey ~= key then
      bar.colorKey = key
      bar:SetColorTexture(unpack(theme()[key]))
    end
  end

  -- Bars and markers move together toward the new data instead of jumping.
  local recX = r.value and chartX(r.value)
  local showNow = cur and not (r.value and r.value == cur)
  local nowX = showNow and chartX(cur) or nil
  if r.value then ui.recMark:SetText(L.MARK_REC .. " " .. r.value) end
  if showNow then ui.nowMark:SetText(L.MARK_NOW .. " " .. cur) end

  local signature = table.concat(targets, ",") .. "|" .. tostring(recX) .. "|" .. tostring(nowX)
  if signature ~= ui.chartSignature then
    ui.chartSignature = signature
    local from = {}
    for i, bar in ipairs(ui.bars) do from[i] = bar.h end
    local fromRec, fromNow = ui.recX or recX, ui.nowX or nowX
    tween("chart", 0, 1, DUR.data, function(t)
      for i, bar in ipairs(ui.bars) do
        bar.h = from[i] + (targets[i] - from[i]) * t
        bar:SetHeight(math.max(P, snap(bar.h)))
      end
      ui.recX = recX and fromRec and fromRec + (recX - fromRec) * t or recX
      ui.nowX = nowX and fromNow and fromNow + (nowX - fromNow) * t or nowX
      drawMarkers(ui.recX, ui.nowX)
    end)
  end

  ui.pingBand:SetShown(r.floor ~= nil)
  ui.pingLabel:SetShown(r.floor ~= nil)
  if r.floor then ui.pingBand:SetWidth(math.max(P, snap(chartX(r.floor)))) end

  if r.value and cur then
    local nowPct = math.floor(A.CoverageAt(r.leads, cur) * 100 + 0.5)
    local recPct = math.floor(A.CoverageAt(r.leads, r.value) * 100 + 0.5)
    ui.insight:SetText(r.value == cur and string.format(L.INSIGHT_SAME, recPct, cur)
      or string.format(L.INSIGHT, cur, nowPct, r.value, recPct))
  else
    ui.insight:SetText(L.NEED_DATA_HINT)
  end
  local warns = {}
  if r.tooEarly and r.tooEarly >= 0.05 then warns[#warns + 1] = string.format(L.EARLY_WARN, r.tooEarly * 100 + 0.5) end
  if r.humanLimited and r.humanLimited >= 0.05 then warns[#warns + 1] = string.format(L.LATE_WARN, r.humanLimited * 100 + 0.5) end
  ui.lateWarn:SetShown(#warns > 0)
  ui.lateWarn:SetText(table.concat(warns, " "))
end

local function refreshStatus(r, st)
  local T = theme()
  local recording, live = ns.IsRecording(), ns.InRecordedCombat()
  if not recording then
    ui.dot:SetVertexColor(unpack(T.faint))
    ui.status:SetText(L.STATUS_OFF)
  elseif live then
    ui.dot:SetVertexColor(unpack(T.live))
    ui.status:SetText(L.STATUS_LIVE)
  else
    ui.dot:SetVertexColor(unpack(T.wait))
    ui.status:SetText(st.combatTime > 0 and L.STATUS_PAUSED or L.STATUS_WAITING)
  end
  if live and not ns.DB().reduceMotion then
    if not ui.pulse:IsPlaying() then ui.pulse:Play() end
  else
    ui.pulse:Stop()
  end

  -- Presses but no GCDs: say exactly where the chain breaks instead of showing a bare 0.
  local gcds = r.cycles - r.lateCycles
  local pressedThisSession = st.duringGCD + st.afterGCD + st.noTiming
  if gcds == 0 and pressedThisSession > 0 then
    ui.statusMeta:SetText(string.format(L.DIAG, st.duringGCD, st.afterGCD, st.noTiming))
    setKey(ui.statusMeta, "wait")
  else
    local meta = string.format(L.GCDS, gcds)
    if st.combatTime > 0 then meta = meta .. "  ·  " .. string.format(L.COMBAT_TIME, clock(st.combatTime)) end
    ui.statusMeta:SetText(meta)
    setKey(ui.statusMeta, "muted")
  end

  ui.record.style = recording and "secondary" or "primary"
  ui.record.label:SetText(recording and L.STOP or L.START)
  ui.record.Paint()
end

local function refreshHero(r, cur)
  local ready = r.value ~= nil
  ui.now:SetText(cur and string.format(L.NOW, cur) or "")
  ui.progress:SetShown(not ready)
  if ready then
    ui.recLabel:SetText(L.RECOMMENDED)
    ui.big:SetText(tostring(r.value))
    ui.unit:SetText("ms")
    local same = r.value == cur
    ui.delta:SetShown(not same and cur ~= nil)
    if cur and not same then ui.deltaText:SetText(string.format(L.DELTA, r.value - cur)) end
    ui.reason:SetText(same and L.ALREADY or (r.reason == "presses" and L.BY_PRESSES or L.BY_PING))
    ui.reason:Show()
  else
    local have = math.min(r.cycles - r.lateCycles, 30)
    ui.recLabel:SetText(L.NEED_DATA)
    ui.big:SetText(tostring(have))
    ui.unit:SetText(L.NEED_UNIT)
    ui.progress.SetValue(have / 30)
    ui.delta:Hide()
    ui.reason:Hide()
  end
end

local function refreshTiles(r, st)
  local t = ui.tiles
  t.PING.value:SetText(r.latP50 and string.format("%d ms", r.latP50 + 0.5) or "—")
  t.PING.sub:SetText(r.latP90 and string.format(L.TILE_PING_SUB, r.latP90 + 0.5) or "")
  t.RHYTHM.value:SetText(r.cadence and string.format("%d ms", r.cadence + 0.5) or "—")
  t.RATE.value:SetText(st.pps and string.format("%.1f", st.pps) or "—")
  t.LATE.value:SetText(r.humanLimited and string.format("%d%%", r.humanLimited * 100 + 0.5) or "—")
  setKey(t.LATE.value, (r.humanLimited or 0) >= 0.1 and "wait" or "text")
end

local function refreshFooter(r, cur)
  local pending, prev = ns.PendingApply(), ns.PreviousWindow()
  ui.applyValue = r.value
  if pending then
    ui.apply.label:SetText(L.APPLY_PENDING)
    ui.apply.SetActive(false)
  elseif not r.value then
    ui.apply.label:SetText(L.APPLY_NONE)
    ui.apply.SetActive(false)
  elseif r.value == cur then
    ui.apply.label:SetText(L.APPLIED_BTN)
    ui.apply.SetActive(false)
  else
    ui.apply.label:SetText(string.format(L.APPLY, r.value))
    ui.apply.SetActive(true)
  end
  ui.revert:SetShown(prev ~= nil and prev ~= cur and not pending)
  if prev then ui.revert.label:SetText(string.format(L.REVERT, prev)) end
  if not ui.reset.armed then ui.reset.label:SetText(L.RESET) end
end

function UI.Refresh()
  if not panel or not panel:IsShown() then return end
  local r, st, cur = ns.Recommend(), ns.Stats(), ns.CurrentWindow()
  refreshStatus(r, st)
  refreshHero(r, cur)
  refreshChart(r, cur)
  refreshTiles(r, st)
  refreshFooter(r, cur)
end

function UI.Frame() return panel, ui end
