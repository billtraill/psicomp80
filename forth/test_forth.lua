-- Type a FORTH session at the COMP80 and print the screen after each step.
--   FORTH_BIN  forth.bin to patch over 0400-0BFF first (optional: leave it
--              unset when running with -bios forth)
--   FORTH_TEST file of steps: each line is typed as it stands (\r = Return,
--              \b = Backspace, ^ = RS, which FORTH takes as rubout),
--              "#wait <s>" waits, "#screen" prints the screen, "#snap"
--              saves a MAME snapshot.  Exits after the last step.
local m = manager.machine
local bin = os.getenv("FORTH_BIN")
if bin and bin ~= "" then
  local f = assert(io.open(bin, "rb")); local d = f:read("a"); f:close()
  local rom = m.memory.regions[":maincpu"]
  for i = 1, #d do rom:write_u8(0x400 + i - 1, d:byte(i)) end
end
local mem = m.devices[":maincpu"].spaces["program"]

local steps = {}
for line in io.lines(os.getenv("FORTH_TEST")) do steps[#steps + 1] = line end

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

local i, wake = 1, 1.5
emu.register_frame_done(function()
  local t = m.time:as_double()
  if t < wake or not m.natkeyboard.empty then return end
  if i > #steps then m:exit() return end
  local s = steps[i]; i = i + 1
  local w = s:match("^#wait%s+([%d.]+)")
  if w then wake = t + tonumber(w)
  elseif s == "#screen" then screen(); wake = t + 0.1
  elseif s == "#snap" then m.video:snapshot(); wake = t + 0.1
  else m.natkeyboard:post((s:gsub("\\r", "\r"):gsub("\\b", "\b"))); wake = t + 0.3 end
end)
