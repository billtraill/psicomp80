-- Type a LISP session at the COMP80 and print the screen after each step.
--   LISP_BIN   lisp.bin to patch over 0400-0BFF first (optional: leave it
--              unset when running with -bios lisp)
--   LISP_TEST  file of steps: each line is typed as it stands (\r = Return,
--              \b = Backspace, ^ = RS, which LISP takes as rubout),
--              "#wait <s>" waits, "#screen" prints the screen, "#snap"
--              saves a MAME snapshot, "#dump <hex addr> <n>" prints n bytes
--              of memory.  A line ending in \r is typed only once LISP is
--              waiting for input (its cursor is showing), and the time it
--              waited is printed if over a second; "#ready" just waits.  Exits after the last
--              step.
local m = manager.machine
local bin = os.getenv("LISP_BIN")
if bin and bin ~= "" then
  local f = assert(io.open(bin, "rb")); local d = f:read("a"); f:close()
  local rom = m.memory.regions[":maincpu"]
  for i = 1, #d do rom:write_u8(0x400 + i - 1, d:byte(i)) end
end
local mem = m.devices[":maincpu"].spaces["program"]

local steps = {}
for line in io.lines(os.getenv("LISP_TEST")) do steps[#steps + 1] = line end

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

-- LISP shows its _ cursor (code 1Fh at CURS, 0C12h) while it waits for a line.
local function waiting()
  return mem:read_u8(mem:read_u16(0x0C12)) == 0x1F
end

local i, wake, busy, idle = 1, 1.5, nil, nil
emu.register_frame_done(function()
  local t = m.time:as_double()
  -- let the last key typed reach the machine before looking at the cursor
  if not m.natkeyboard.empty then idle = nil return end
  idle = idle or t
  if t < wake or t - idle < 0.2 then return end
  if i > #steps then m:exit() return end
  local s = steps[i]
  if (s:match("\\r$") or s == "#ready") and not waiting() then
    busy = busy or t return
  end
  if busy and t - busy > 1 then print(string.format("--- busy %.1fs", t - busy)) end
  busy = nil; i = i + 1
  local w = s:match("^#wait%s+([%d.]+)")
  if w then wake = t + tonumber(w)
  elseif s == "#ready" then wake = t
  elseif s == "#screen" then screen(); wake = t + 0.1
  elseif s:match("^#dump") then
    local a, n = s:match("^#dump%s+(%x+)%s+(%d+)")
    a, n = tonumber(a, 16), tonumber(n)
    local h = {}
    for k = 0, n - 1 do h[#h + 1] = string.format("%02X", mem:read_u8(a + k)) end
    print(string.format("%04X: %s", a, table.concat(h, " "))); wake = t + 0.1
  elseif s == "#snap" then m.video:snapshot(); wake = t + 0.1
  else m.natkeyboard:post((s:gsub("\\r", "\r"):gsub("\\b", "\b"))); wake = t + 0.3 end
end)
