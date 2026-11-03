-- Load dump.bin at 1000h, RUN it and try each key: check the address in the
-- title and the first line, that the bytes shown match memory, that keys
-- pressed while a page is being drawn are taken, and that Q goes back to the
-- monitor.
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local f = assert(io.open(os.getenv("DUMP_BIN"), "rb")); local data = f:read("a"); f:close()

local function log(s) print(string.format("[%7.2f] %s", m.time:as_double(), s)) end
local function rowtext(r)
  local s = ""
  for c = 0, 63 do local ch = mem:read_u8(0x8000 + r*64 + c) & 0x3f
    s = s .. (ch < 0x20 and (ch == 0 and "@" or string.char(ch + 64)) or string.char(ch)) end
  return s
end
local function expect(a)                -- the first data line as it should be for address a
  local s = string.format("%04X ", a)
  for i = 0, 15, 2 do s = s .. string.format("%02X%02X ", mem:read_u8((a + i) & 0xffff), mem:read_u8((a + i + 1) & 0xffff)) end
  return s
end
local function check(what, a)
  local title, line = rowtext(0), rowtext(2)
  local ok = string.sub(title, 6, 9) == string.format("%04X", a) and string.sub(line, 1, 45) == expect(a)
  log(string.format("CHECK %-22s %s  %s", what, string.sub(line, 1, 61), ok and "right" or "WRONG"))
end

local steps = {
  { "RUN 1000", "start", 0x0000 },
  { "N", "N, next page", 0x01E0 },
  { "N", "N again", 0x03C0 },
  { "B", "B, back a page", 0x01E0 },
  { "D", "D, down a line", 0x01F0 },
  { "U", "U, up a line", 0x01E0 },
  { "G1D00", "G 1D00", 0x1D00 },
  { "\r", "Return, down a line", 0x1D10 },
  { "NNNNN", "N five times quickly", 0x1D10 + 5 * 0x1E0 },
  { "G0BB5", "G 0BB5", 0x0BB5 },
}
local phase, t0, i = 0, 0, 0
emu.register_frame_done(function()
  local t = m.time:as_double()
  if phase == 0 and t > 2 then
    m.natkeyboard:post("\28")            -- FS: into the monitor
    phase, t0 = 1, t
  elseif phase == 1 and t - t0 > 0.5 then
    for j = 1, #data do mem:write_u8(0x1000 + j - 1, data:byte(j)) end
    phase, t0 = 2, t
  elseif phase == 2 and t - t0 > 0.3 then
    i = i + 1
    if i > #steps then
      m.natkeyboard:post("Q")
      phase, t0 = 4, t
    else
      m.natkeyboard:post(steps[i][1])
      phase, t0 = 3, t
    end
  elseif phase == 3 and t - t0 > 1.5 then
    check(steps[i][2], steps[i][3])
    if i == 1 then for r = 0, 6 do print("|" .. rowtext(r) .. "|") end m.video:snapshot() end
    phase, t0 = 2, t
  elseif phase == 4 and t - t0 > 1 then
    log(string.format("CHECK Q: row 0 = [%s], address kept %04X", string.sub(rowtext(0), 1, 8), mem:read_u16(0x1003)))
    m:exit()
  end
end)
