-- Load life.wav from the mounted tape (fast-forwarded), check it loaded
-- correctly against life.bin, and RUN it. Retries the load if it didn't.
local m = manager.machine
local cass = m.cassettes[":cassette"]
local mem = m.devices[":maincpu"].spaces["program"]

local dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local f = assert(io.open(dir .. "life.bin", "rb")); local data = f:read("a"); f:close()

local function say(s) print(string.format("[autorun %5.1fs] %s", m.time:as_double(), s)) end
local function loaded_ok()
  local bad = 0
  for i = 1, #data do if mem:read_u8(0x1000 + i - 1) ~= data:byte(i) then bad = bad + 1 end end
  return bad
end

-- Ctrl+\ on the emulated keyboard gives FS (1Ch), which puts the monitor back
-- in command state whatever has been typed. Text posting can't send it.
local fields = {}
for _, port in pairs(m.ioport.ports) do
  for name, fld in pairs(port.fields) do fields[name] = fld end
end
local ctrl, bslash = fields["Ctrl"], fields["\\  |"]
local function pc() return m.devices[":maincpu"].state["PC"].value end

local step, t0, tries = 0, 0, 0
emu.register_frame_done(function()
  local t = m.time:as_double()
  if step == 0 and t > 3 then                -- give the host keyboard time to settle
    if ctrl and bslash then ctrl:set_value(1); bslash:set_value(1) end
    step, t0 = 5, t
  elseif step == 5 and t - t0 > 0.1 then
    if ctrl and bslash then bslash:set_value(0); ctrl:set_value(0) end
    step, t0 = 4, t
  elseif step == 4 and t - t0 > 1.5 then
    tries = tries + 1
    for i = 0, #data - 1 do mem:write_u8(0x1000 + i, 0) end
    m.video.throttled = false
    cass:seek(0, "set"); cass:play()
    m.natkeyboard:post("READ 1000")
    say("loading from tape (attempt " .. tries .. ")")
    step, t0 = 1, t
  elseif step == 1 and t - t0 > cass.length + 0.5 then
    cass:stop()
    if pc() < 0x0355 or pc() > 0x0371 then   -- still in READ (not back at the prompt)
      m.natkeyboard:post(" ")                -- any key ends READ
    end
    step, t0 = 2, t
  elseif step == 2 and t - t0 > 1 then
    local bad = loaded_ok()
    if bad == 0 then
      say("loaded OK, running")
      m.video.throttled = true
      m.natkeyboard:post("RUN 1000")
      step = 3
    elseif tries < 3 then
      say(bad .. " bytes wrong (was a key pressed during loading?), retrying")
      step, t0 = 0, t - 3
    else
      say("load failed " .. tries .. " times, giving up")
      m.video.throttled = true
      step = 3
    end
  end
end)
