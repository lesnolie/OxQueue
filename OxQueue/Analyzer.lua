-- Pure math: no WoW API calls here, so tests can load this file as-is.
local _, ns = ...
ns = ns or {}
local A = {}
ns.Analyzer = A

A.MAX_WINDOW = 400 -- SpellQueueWindow CVar ceiling

local function sorted(list)
  local out = {}
  for i = 1, #list do out[i] = list[i] end
  table.sort(out)
  return out
end

-- Linear-interpolated percentile, p in [0, 1].
function A.Percentile(list, p)
  local n = #list
  if n == 0 then return nil end
  local s = sorted(list)
  local pos = 1 + (n - 1) * p
  local lo = math.floor(pos)
  local hi = math.min(lo + 1, n)
  return s[lo] + (s[hi] - s[lo]) * (pos - lo)
end

local function ceil10(v) return math.ceil(v / 10) * 10 end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- data.cycles: { {lead = ms} | {late = ms}, ... }
--   lead  = how long before the GCD/cast ended your LAST press of that cycle landed
--   first = same for your FIRST press of that cycle (defaults to lead)
--   late = no press before the end; your first press came this long after it
-- data.intervals: ms between consecutive ability presses (spam cadence)
-- data.latency:   world latency samples in ms
-- opts.coverage (0-1), opts.margin (ms), opts.minCycles
function A.Recommend(data, opts)
  opts = opts or {}
  local coverage = opts.coverage or 0.95
  local margin = opts.margin or 20
  local minCycles = opts.minCycles or 30

  local r = { cycles = 0, lateCycles = 0 }

  -- reachable: leads a legal window (<= MAX_WINDOW) can catch. A last press earlier than
  -- that is lost at any setting, so it must not drag the recommendation to the cap.
  local leads, firsts, reachable = {}, {}, {}
  local tooEarly = 0
  for _, c in ipairs(data.cycles or {}) do
    if c.lead then
      leads[#leads + 1] = c.lead
      firsts[#firsts + 1] = c.first or c.lead
      if c.lead <= A.MAX_WINDOW then reachable[#reachable + 1] = c.lead else tooEarly = tooEarly + 1 end
    elseif c.late then r.lateCycles = r.lateCycles + 1 end
  end
  r.cycles = #leads + r.lateCycles
  r.leads = leads
  r.tooEarly = r.cycles > 0 and tooEarly / r.cycles or nil

  r.cadence = A.Percentile(data.intervals or {}, 0.5)
  r.latP50 = A.Percentile(data.latency or {}, 0.5)
  r.latP90 = A.Percentile(data.latency or {}, 0.9)

  -- Network floor: a queued request must reach the server before its GCD ends,
  -- so the window has to open at least one (jittery) round trip early.
  r.floor = r.latP90 and (r.latP90 + margin) or nil

  -- Human term: smallest window that still catches your last press in `coverage` of the
  -- cycles a window can affect at all.
  r.cover = A.Percentile(reachable, coverage)

  -- Cycles where even your first press landed later than the median ping: no window
  -- size can hide that gap, only pressing earlier can.
  if r.cycles > 0 and r.latP50 then
    local slow = 0
    for _, l in ipairs(firsts) do if l < r.latP50 then slow = slow + 1 end end
    r.humanLimited = (slow + r.lateCycles) / r.cycles
  end

  if #leads < minCycles or not r.floor then
    r.reason = (#leads < minCycles) and "needData" or "needLatency"
    return r
  end

  if r.cover and r.cover >= r.floor then
    r.value, r.reason = r.cover, "presses"
  else
    r.value, r.reason = r.floor, "latency"
  end
  r.value = clamp(ceil10(r.value), 0, A.MAX_WINDOW)
  return r
end

-- Share of cycles whose last press lands inside a window of `w` ms.
function A.CoverageAt(leads, w)
  if #leads == 0 then return nil end
  local n = 0
  for _, l in ipairs(leads) do if l <= w then n = n + 1 end end
  return n / #leads
end

-- Counts per `binMs` bucket from 0 to `maxMs`; anything later lands in the last bucket.
function A.Histogram(leads, binMs, maxMs)
  local bins = {}
  local count = math.ceil(maxMs / binMs)
  for i = 1, count do bins[i] = 0 end
  for _, l in ipairs(leads) do
    local i = math.min(count, math.floor(l / binMs) + 1)
    bins[i] = bins[i] + 1
  end
  return bins
end

return A
