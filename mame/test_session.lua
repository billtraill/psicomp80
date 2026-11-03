-- Type a session at the COMP80 and print the screen, for any of the ROMs.
-- The same steps files as web/tools/session.js:
--   SESSION_TEST  file of steps: each line is typed as it stands (\r = Return,
--                 \b = Backspace, ^ = RS), "#wait <s>" waits, "#screen"
--                 prints the screen, "#snap" saves a MAME snapshot,
--                 "#load <file> <hex addr>" (or "#bin") copies a file, found
--                 from the steps file's folder, into memory.  A line ending
--                 in \r, and "#ready", wait until the language is waiting
--                 for a line (its cursor is showing).  Exits after the last
--                 step.
--   SESSION_CURS  hex address where the language keeps its cursor's address
--                 (1DA0 for FORTH, BASIC, PILOT and ZASM, 1A60 for Logo,
--                 0C08 for FOCAL, 0C0E for Prolog, 0C12 for LISP); leave it
--                 unset for BURP and CHIP-8, which have none.
-- Run from the MAME checkout, for example:
--   SESSION_TEST=~/localdev/psicomp80/basic/tests/primes.txt SESSION_CURS=1DA0 \
--     ./mamed psicomp80 -bios basic -video none -sound none -nothrottle \
--     -autoboot_script ~/localdev/psicomp80/mame/test_session.lua
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local file = os.getenv("SESSION_TEST")
local dir = file:match("^(.*)/") or "."
local curs = os.getenv("SESSION_CURS")
curs = curs and curs ~= "" and tonumber(curs, 16) or nil

local steps = {}
for line in io.lines(file) do steps[#steps + 1] = line end

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

local function waiting()
  return not curs or mem:read_u8(mem:read_u16(curs)) == 0x1F
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
  if s == "" then i = i + 1 return end
  if (s:match("\\r$") or s == "#ready") and not waiting() then
    busy = busy or t return
  end
  if busy and t - busy > 1 then print(string.format("--- busy %.1fs", t - busy)) end
  busy = nil; i = i + 1
  local w = s:match("^#wait%s+([%d.]+)")
  local lf, la = s:match("^#%a+%s+(%S+)%s+(%x+)$")
  if w then wake = t + tonumber(w)
  elseif s == "#ready" then wake = t
  elseif s == "#screen" then screen(); wake = t + 0.1
  elseif s == "#snap" then m.video:snapshot(); wake = t + 0.1
  elseif lf and (s:match("^#load") or s:match("^#bin")) then
    local f = assert(io.open(lf:sub(1, 1) == "/" and lf or dir .. "/" .. lf, "rb"))
    local d = f:read("a"); f:close()
    local a = tonumber(la, 16)
    for k = 1, #d do mem:write_u8(a + k - 1, d:byte(k)) end
    wake = t + 0.1
  elseif s:match("^#dump") then wake = t
  else m.natkeyboard:post((s:gsub("\\r", "\r"):gsub("\\b", "\b"))); wake = t + 0.3 end
end)
