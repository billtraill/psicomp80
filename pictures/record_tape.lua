-- Load a program image into RAM and save it to the mounted cassette with TAPE.
-- Usage: C80_BIN=file.bin [C80_BASE=1D00] mamed psicomp80 -cass out.wav -autoboot_script record_tape.lua
local m = manager.machine
local cass = m.cassettes[":cassette"]
local mem = m.devices[":maincpu"].spaces["program"]
local path = os.getenv("C80_BIN")
local f = assert(io.open(path, "rb")); local data = f:read("a"); f:close()
local base = tonumber(os.getenv("C80_BASE") or "1000", 16)
local stop = base + #data
local step, t0 = 0, 0
emu.register_frame_done(function()
  local t = m.time:as_double()
  if step == 0 and t > 2 then
    for i = 1, #data do mem:write_u8(base + i - 1, data:byte(i)) end
    cass:record()
    m.natkeyboard:post(string.format("TAPE %04X%04X", base, stop))
    step, t0 = 1, t
  -- done when TAPE has finished and the monitor is waiting for a key again
  elseif step == 1 and t - t0 > 8 and m.devices[":maincpu"].state["PC"].value >= 0x0355
         and m.devices[":maincpu"].state["PC"].value <= 0x0371 then
    cass:stop()
    print(string.format("RECORDED %s %d bytes, %.1fs of tape", path, #data, cass.length))
    m:exit()
  end
end)
