-- Load plasma.bin at 1000h, RUN it, measure the frame rate, check the screen
-- holds only shading characters, take a snapshot, then press a key and check
-- the monitor is back.
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local f = assert(io.open(os.getenv("PLASMA_BIN"), "rb")); local data = f:read("a"); f:close()

local shades = { [0x20] = true, [0x40] = true, [0x41] = true, [0x45] = true, [0x47] = true, [0x4F] = true }
local function frames() return mem:read_u16(0x1003) end
local function log(s) print(string.format("[%7.2f] %s", m.time:as_double(), s)) end
local function screen()
  local map = { [0x20] = " ", [0x41] = ".", [0x45] = ":", [0x40] = "+", [0x47] = "%", [0x4F] = "#" }
  for r = 0, 31 do local s = ""
    for c = 0, 63 do local v = mem:read_u8(0x8000 + r*64 + c); s = s .. (map[v] or "?") end
    print("|" .. s .. "|") end
end

local phase, t0, f0 = 0, 0, 0
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
    f0 = frames(); phase, t0 = 3, t
  elseif phase == 3 and t - t0 > 5 then
    log(string.format("CHECK %.1f frames a second", (frames() - f0) / (t - t0)))
    local bad = 0
    for a = 0x8000, 0x87FF do if not shades[mem:read_u8(a)] then bad = bad + 1 end end
    log("CHECK screen: " .. (bad == 0 and "all shading characters" or bad .. " other characters"))
    screen()
    m.video:snapshot()
    m.natkeyboard:post("X")
    phase, t0 = 4, t
  elseif phase == 4 and t - t0 > 1 then
    f0 = frames(); phase, t0 = 5, t
  elseif phase == 5 and t - t0 > 1 then
    local s = ""
    for i = 0, 7 do local c = mem:read_u8(0x8000 + i) & 0x3f; s = s .. (c < 0x20 and (c == 0 and " " or string.char(c + 64)) or string.char(c)) end
    log(string.format("CHECK after a key: %s, row 0 = [%s] pc=%04X", frames() == f0 and "stopped" or "STILL RUNNING", s,
        m.devices[":maincpu"].state["PC"].value))
    m:exit()
  end
end)
