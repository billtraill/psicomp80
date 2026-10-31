-- Load life.bin at 1000h, RUN it, check generations against a reference
-- implementation, and exercise the P / Return / R / S keys.
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local f = assert(io.open(os.getenv("LIFE_BIN"), "rb")); local data = f:read("a"); f:close()

local function board(base)
  local b = {}
  for i = 0, 1023 do b[i] = mem:read_u8(base + i) end
  return b
end
local function get(b, x, y) x = x % 128; y = y % 64
  return (b[y*16 + (x >> 3)] >> (7 - (x & 7))) & 1 end
local function step(b)
  local n = {}
  for i = 0, 1023 do n[i] = 0 end
  for y = 0, 63 do for x = 0, 127 do
    local t = 0
    for dy = -1, 1 do for dx = -1, 1 do t = t + get(b, x+dx, y+dy) end end
    local alive = (t == 3) or (t == 4 and get(b, x, y) == 1)
    if alive then local i = y*16 + (x >> 3); n[i] = n[i] | (1 << (7 - (x & 7))) end
  end end
  return n
end
local function same(a, b) for i = 0, 1023 do if a[i] ~= b[i] then return false end end return true end
local function cur() return mem:read_u16(0x1003) end
local function vtext(a, n) local s = "" for i = 0, n-1 do local c = mem:read_u8(0x8000+a+i) & 0x3f
  s = s .. (c < 0x20 and (c == 0 and " " or string.char(c+64)) or string.char(c)) end return s end
local function population(b) local p = 0 for i = 0, 1023 do local v = b[i] while v > 0 do p = p + (v & 1); v = v >> 1 end end return p end

local phase, t0, lastcur, prev, gens, bad, tgen = 0, 0, 0x1700, nil, 0, 0, nil
local ngen, mark, tfirst = 0, 0, nil   -- generations seen (any phase)
local function log(s) print(string.format("[%7.2f] %s", m.time:as_double(), s)) end

emu.register_frame_done(function()
  local t = m.time:as_double()
  if phase >= 2 and cur() ~= lastcur then ngen = ngen + 1; lastcur = cur() end
  if phase == 0 and t > 2 then
    for i = 1, #data do mem:write_u8(0x1000 + i - 1, data:byte(i)) end
    m.natkeyboard:post("RUN 1000")
    phase, t0 = 1, t
  elseif phase == 1 then
    -- watch generations
    local c = cur()
    if c ~= lastcur then
      local b = board(c)
      if prev then
        gens = gens + 1
        if not same(step(prev), b) then bad = bad + 1; log("generation " .. gens .. " WRONG") end
      else
        tfirst = t
        log(string.format("first generation, population %d", population(b)))
      end
      prev, lastcur = b, c
    end
    if gens >= 10 then
      log(string.format("CHECK %d generations, %d wrong, %.2fs per generation", gens, bad, (t - tfirst) / gens))
      m.natkeyboard:post("P")
      phase, t0 = 2, t
    end
  elseif phase == 2 and t - t0 > 1 then
    mark = ngen; log("after P: top right = [" .. vtext(58, 6) .. "]")
    phase, t0 = 3, t
  elseif phase == 3 and t - t0 > 3 then
    log("PAUSE " .. (ngen == mark and "held (no new generation in 3s)" or "FAILED, still running"))
    m.natkeyboard:post("P")
    phase, t0 = 4, t
  elseif phase == 4 and t - t0 > 3 then
    log(string.format("RESUME %s (%d generations in 3s)", ngen > mark and "ok" or "FAILED", ngen - mark))
    m.natkeyboard:post("\r")
    phase, t0, mark = 5, t, ngen
  elseif phase == 5 and t - t0 > 3 then
    log("RETURN key: " .. (ngen > mark and "still running" or "FAILED") ..
        string.format(" pc=%04X", m.devices[":maincpu"].state["PC"].value))
    prev = board(cur())
    m.natkeyboard:post("R")
    phase, t0 = 6, t
  elseif phase == 6 and t - t0 > 0.3 then
    local b = board(cur())
    log(string.format("after R: population %d, %s", population(b),
        same(b, prev) and "UNCHANGED" or "new board"))
    phase, t0 = 7, t
  elseif phase == 7 and t - t0 > 3 then
    m.video:snapshot()
    m.natkeyboard:post("S")
    phase, t0 = 8, t
  elseif phase == 8 and t - t0 > 2 then
    log("after S: row0 = [" .. vtext(0, 8) .. "] pc=" ..
        string.format("%04X", m.devices[":maincpu"].state["PC"].value))
    m:exit()
  end
end)
