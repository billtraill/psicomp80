-- Load banner.bin at 1000h, RUN it, measure the frame rate, check the letters
-- move from right to left, take a snapshot, then change the message with the
-- monitor's LOAD and run it again, and check a key stops it.
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local f = assert(io.open(os.getenv("BANNER_BIN"), "rb")); local data = f:read("a"); f:close()

local function frames() return mem:read_u16(0x1003) end
local function log(s) print(string.format("[%7.2f] %s", m.time:as_double(), s)) end
local map = { [0x20] = " ", [0x49] = "[", [0x46] = "]", [0x4F] = "#", [0x4C] = "_", [0x43] = "^" }
local function rowtext(r)
  local s = ""
  for c = 0, 63 do local v = mem:read_u8(0x8000 + r*64 + c)
    if map[v] then s = s .. map[v] else
      local ch = v & 0x3f; s = s .. (ch < 0x20 and (ch == 0 and "@" or string.char(ch + 64)) or string.char(ch)) end end
  return s
end
local function screen() for r = 0, 31 do print("|" .. rowtext(r) .. "|") end end
local function band() local s = "" for r = 12, 18 do s = s .. rowtext(r) end return s end
-- how far band b has moved left of band a, in characters (0..20), or -1
local function moved(a, b)
  for d = 0, 20 do local ok = true
    for r = 0, 6 do
      if string.sub(a, r*64 + 1 + d, r*64 + 40 + d) ~= string.sub(b, r*64 + 1, r*64 + 40) then ok = false break end
    end
    if ok then return d end
  end
  return -1
end

local phase, t0, f0, b0 = 0, 0, 0, ""
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
    screen()
    m.video:snapshot()
    mem:write_u8(0x1005, 255)            -- slow it right down to compare two moments
    phase, t0 = 4, t
  elseif phase == 4 and t - t0 > 0.5 then
    b0, f0 = band(), frames(); phase, t0 = 5, t
  elseif phase == 5 and frames() >= f0 + 4 then
    local d = moved(b0, band())
    log(string.format("CHECK %d steps later the letters are %d characters further left: %s",
        frames() - f0, d, d == 2 and "right" or "WRONG"))
    m.natkeyboard:post("X")              -- stop, then a new message with LOAD
    phase, t0 = 6, t
  elseif phase == 6 and t - t0 > 1 then
    m.natkeyboard:post("LOAD 1400")
    phase, t0 = 7, t
  elseif phase == 7 and t - t0 > 1 then
    m.natkeyboard:post("[ABC  ]00@")
    phase, t0 = 8, t
  elseif phase == 8 and t - t0 > 2 then
    m.natkeyboard:post("RUN 1000")
    phase, t0 = 9, t
  elseif phase == 9 and t - t0 > 1.5 then
    local s = ""
    for i = 0, 6 do s = s .. string.format("%02X ", mem:read_u8(0x1400 + i)) end
    log("CHECK message now " .. s .. "(ABC, two spaces, ], 00), " .. mem:read_u16(0x1008) .. " columns: " ..
        (mem:read_u16(0x1008) == 30 and "right" or "WRONG"))
    screen()
    m.natkeyboard:post("X")
    phase, t0 = 10, t
  elseif phase == 10 and t - t0 > 1 then
    f0 = frames(); phase, t0 = 11, t
  elseif phase == 11 and t - t0 > 1 then
    log(string.format("CHECK after a key: %s, row 0 = [%s]", frames() == f0 and "stopped" or "STILL RUNNING",
        string.sub(rowtext(0), 1, 8)))
    m:exit()
  end
end)
