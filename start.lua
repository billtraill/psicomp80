-- Start straight into a program: optionally copy C80_BIN into RAM at 1000h,
-- then type C80_TYPE at the monitor (e.g. "RUN 1000"). Used by c80.sh.
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local bin, typed = os.getenv("C80_BIN"), os.getenv("C80_TYPE") or ""

-- Ctrl+\ on the emulated keyboard gives FS, which puts the monitor back in
-- command state in case a stray key (the Return that launched us) got in.
local fields = {}
for _, port in pairs(m.ioport.ports) do
  for name, fld in pairs(port.fields) do fields[name] = fld end
end
local ctrl, bslash = fields["Ctrl"], fields["\\  |"]

local step = 0
emu.register_frame_done(function()
  local t = m.time:as_double()
  if step == 0 and t > 1 then
    if ctrl and bslash then ctrl:set_value(1); bslash:set_value(1) end
    step = 1
  elseif step == 1 and t > 1.1 then
    if ctrl and bslash then bslash:set_value(0); ctrl:set_value(0) end
    step = 2
  elseif step == 2 and t > 1.6 then
    if bin and bin ~= "" then
      local f = assert(io.open(bin, "rb")); local d = f:read("a"); f:close()
      for i = 1, #d do mem:write_u8(0x1000 + i - 1, d:byte(i)) end
    end
    m.natkeyboard:post(typed)
    step = 3
  end
end)
