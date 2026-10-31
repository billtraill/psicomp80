-- Type a BURP session at the COMP80 and print the screen.
--   BURP_TEST  file of steps: each line is typed a key at a time (\r =
--              Return, ^ = RS), each key only once the Z80 is halted waiting
--              for it.  "#wait <s>" waits, "#ready" waits until BURP has
--              been idle (halted) for half a second, "#screen" prints the
--              screen, "#snap" saves a MAME snapshot.  Exits after the last
--              step.
-- BURP talks to the MM57109 between keys, and a key that arrives while the
-- Z80 isn't halted resets the machine, hence typing a key at a time.
local m = manager.machine
local cpu = m.devices[":maincpu"]
local mem = cpu.spaces["program"]

local steps = {}
for line in io.lines(os.getenv("BURP_TEST")) do steps[#steps + 1] = line end

local function screen()
  print("+" .. string.rep("-", 64) .. "+")
  for row = 0, 31 do
    local s = ""
    for col = 0, 63 do
      local v = mem:read_u8(0x8000 + row * 64 + col)
      local c = v & 0x3f
      if v & 0x40 ~= 0 then s = s .. "#"
      elseif c < 0x20 then s = s .. (c == 0 and "@" or string.char(c + 64))
      else s = s .. string.char(c) end
    end
    print("|" .. s .. "|")
  end
  print("+" .. string.rep("-", 64) .. "+")
end

local halted_since = nil
local function halted() return cpu.state["HALT"].value ~= 0 end

local i, wake, keys = 1, 1.5, nil
emu.register_frame_done(function()
  local t = m.time:as_double()
  if halted() then halted_since = halted_since or t else halted_since = nil end
  if t < wake or not m.natkeyboard.empty then return end
  if keys then
    -- the next key of the line being typed
    if not halted() then return end
    m.natkeyboard:post(keys:sub(1, 1))
    keys = keys:sub(2)
    if keys == "" then keys = nil end
    wake = t + 0.05
    return
  end
  if i > #steps then m:exit() return end
  local s = steps[i]
  if s == "#ready" then
    if not halted_since or t - halted_since < 0.5 then return end
    i = i + 1
    return
  end
  i = i + 1
  local w = s:match("^#wait%s+([%d.]+)")
  if w then wake = t + tonumber(w)
  elseif s == "#screen" then screen(); wake = t + 0.1
  elseif s == "#snap" then m.video:snapshot(); wake = t + 0.1
  else keys = s:gsub("\\r", "\r") end
end)
