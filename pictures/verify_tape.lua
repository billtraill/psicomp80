-- READ a tape into $1000, RUN it, and save a snapshot of the screen.
local m = manager.machine
local cass = m.cassettes[":cassette"]
local step, t0 = 0, 0
emu.register_frame_done(function()
  local t = m.time:as_double()
  if step == 0 and t > 2 then
    cass:seek(0, "set"); cass:play()
    m.natkeyboard:post("READ 1000")
    step, t0 = 1, t
  elseif step == 1 and t - t0 > cass.length + 1 then
    cass:stop()
    m.natkeyboard:post("X")          -- any key ends READ (monitor resets)
    step, t0 = 2, t
  elseif step == 2 and t - t0 > 2 then
    m.natkeyboard:post("RUN 1000")
    step, t0 = 3, t
  elseif step == 3 and t - t0 > 3 then
    m.video:snapshot()
    print("SNAPSHOT taken")
    m:exit()
  end
end)
