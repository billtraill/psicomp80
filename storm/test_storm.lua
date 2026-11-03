-- Load storm.bin at 1000h and RUN it; check the title, start a game, play
-- it with keys pressed at any moment (never waiting for a HALT, as on the
-- real machine), check no key ever resets the COMP80, measure the frame
-- rate, and print the title, a frame of play and the game-over screen.
--   STORM_BIN=storm/storm.bin ./mamed psicomp80 -autoboot_script storm/test_storm.lua
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local f = assert(io.open(os.getenv("STORM_BIN"), "rb")); local data = f:read("a"); f:close()

local S = 0x0F10                       -- the game between frames
local function frames() return mem:read_u16(0x0C60) end
local function log(s) print(string.format("[%7.2f] %s", m.time:as_double(), s)) end
local function row0()
  local s = ""
  for i = 0, 11 do local c = mem:read_u8(0x8000 + i) & 0x3f
    s = s .. (c < 0x20 and (c == 0 and "@" or string.char(c + 64)) or string.char(c)) end
  return s
end
local function screen(tag)
  print("---- " .. tag)
  for r = 0, 31 do local s = ""
    for c = 0, 63 do
      local v = mem:read_u8(0x8000 + r * 64 + c)
      if v == 0x20 then s = s .. " "
      elseif v & 0x40 ~= 0 then s = s .. (v == 0x40 and "+" or "#")
      else local ch = v & 0x3f; s = s .. (ch < 0x20 and string.char(ch + 64) or string.char(ch)) end
    end
    print("|" .. s .. "|")
  end
end
local function state()
  return string.format("mode %d score %d wave %d lives %d px %d",
    mem:read_u8(S), mem:read_u16(S + 4), mem:read_u8(S + 7), mem:read_u8(S + 6), mem:read_u8(S + 2))
end

local phase, t0, f0, n, resets, tf, dump = 0, 0, 0, 0, 0, 0, false
local keys = { "Z", "Z", "X", " ", "X", "\r", ",", ".", " " }
emu.register_frame_done(function()
  local t = m.time:as_double()
  if phase == 0 and t > 2 then
    m.natkeyboard:post("\28")            -- FS: into the monitor
    phase, t0 = 1, t
  elseif phase == 1 and t - t0 > 0.5 then
    for i = 1, #data do mem:write_u8(0x1000 + i - 1, data:byte(i)) end
    m.natkeyboard:post("RUN 1000")
    phase, t0 = 2, t
  elseif phase == 2 and t - t0 > 2 then
    screen("title")
    f0 = frames(); phase, t0 = 3, t
  elseif phase == 3 and t - t0 > 3 then
    log(string.format("CHECK title: %.1f frames a second", (frames() - f0) / (t - t0)))
    m.natkeyboard:post(" ")              -- start
    phase, t0 = 4, t
  elseif phase == 4 and t - t0 > 1 then
    f0 = frames(); phase, t0, tf = 5, t, t
  elseif phase == 5 and dump and mem:read_u8(0x0C40) == 2 then
    screen("playing")                    -- between frames: the screen is whole
    dump = false
  elseif phase == 5 then
    -- a key every 70-130 ms (once the last has gone in), at whatever the
    -- program is doing
    if t - t0 > 0.07 + (n % 7) * 0.01 and m.natkeyboard.empty then
      n = n + 1
      local px, best, by = mem:read_u8(S + 2), nil, -1
      for k = 0, 31 do local b = S + 48 + k * 6
        if mem:read_u8(b + 2) & 1 ~= 0 and mem:read_u8(b + 1) > by then best, by = mem:read_u8(b), mem:read_u8(b + 1) end
      end
      local k = keys[(n % #keys) + 1]
      if best and n % 3 ~= 0 then k = (best < px and "Z") or (best > px and "X") or " " end
      m.natkeyboard:post(k)
      t0 = t
      if row0():find("READY") then resets = resets + 1 end
      if n == 120 then
        log(string.format("CHECK playing: %.1f frames a second; %s", (frames() - f0) / (t - tf), state()))
        dump = true
      end
      if mem:read_u8(S) == 3 or n > 3000 then phase, t0 = 6, t end
    end
  elseif phase == 6 and t - t0 > 3 and m.natkeyboard.empty then
    log("CHECK " .. state() .. string.format("; %d keys, %d times back at READY", n, resets))
    screen("game over")
    m.natkeyboard:post("Q")
    phase, t0 = 7, t
  elseif phase == 7 and t - t0 > 1 and m.natkeyboard.empty then
    log(string.format("CHECK after Q: row 0 = [%s] pc=%04X", row0(), m.devices[":maincpu"].state["PC"].value))
    m:exit()
  end
end)
