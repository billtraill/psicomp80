-- Start COMP80 FORTH (-bios forth), type a program into it and run it.
-- Also used for the other languages that read a line (BASIC, Logo, FOCAL,
-- PILOT, ZASM, Prolog), with C80_CURS set.
--   C80_FORTH  program to type in, a line at a time (optional)
--   C80_TYPE   line to type once it is in, e.g. "50 LIFE"
--   C80_CURS   hex address of the language's cursor pointer (default 1DA0,
--              FORTH's)
--   C80_SNAP   seconds after that line to take snapshots, e.g. "5,60";
--              C80_EXIT=1 also prints the screen at each one and exits after
--              the last
-- The program is typed with the emulator running flat out; it goes back to
-- normal speed for the run line unless there are snapshots to take.
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local run = os.getenv("C80_TYPE") or ""
local quit = os.getenv("C80_EXIT")
local snaps = {}
for s in (os.getenv("C80_SNAP") or ""):gmatch("[%d.]+") do snaps[#snaps + 1] = tonumber(s) end
local lines = {}
local file = os.getenv("C80_FORTH")
if file and file ~= "" then
  for l in io.lines(file) do if l:match("%S") then lines[#lines + 1] = l end end
end

-- FORTH shows its _ cursor (code 1Fh at CURS, 1DA0h) while it waits for a
-- line.  Only type when it is waiting: a key while it is busy resets the
-- COMP80 to the monitor.
local curs = tonumber(os.getenv("C80_CURS") or "", 16) or 0x1DA0
local function waiting()
  return mem:read_u8(mem:read_u16(curs)) == 0x1F
end

local function screen()
  for row = 0, 31 do
    local s = ""
    for col = 0, 63 do
      local v = mem:read_u8(0x8000 + row * 64 + col)
      local c = v & 0x3f
      if v & 0x40 ~= 0 then s = s .. "#"
      elseif c < 0x20 then s = s .. string.char(c + 64)
      else s = s .. string.char(c) end
    end
    print((s:gsub(" +$", "")))
  end
end

local step, i, t0, idle = 0, 1, 0, nil
m.video.throttled = false
emu.register_frame_done(function()
  local t = m.time:as_double()
  if step < 2 then
    -- wait for the keyboard queue to empty and FORTH to settle at its cursor
    if not m.natkeyboard.empty then idle = nil return end
    idle = idle or t
    if t - idle < 0.1 then return end
  end
  if step == 0 then
    if t > 1 then m.natkeyboard:post("^"); step, idle = 1, nil end
  elseif step == 1 then
    if not waiting() then return end
    idle = nil
    if i <= #lines then
      m.natkeyboard:post(lines[i] .. "\r"); i = i + 1
    else
      if #snaps == 0 then m.video.throttled = true end
      if run ~= "" then m.natkeyboard:post(run .. "\r") end
      step, t0 = 2, t
    end
  elseif #snaps > 0 and t - t0 >= snaps[1] then
    m.video:snapshot(); table.remove(snaps, 1)
    if quit then
      print(string.format("--- snapshot at %.1fs", t - t0)); screen()
      if #snaps == 0 then m:exit() end
    elseif #snaps == 0 then m.video.throttled = true end
  end
end)
