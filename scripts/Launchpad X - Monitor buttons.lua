-- Diagnostic observer; can run alongside Start. It never changes tracks or modes.
local directory = debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])')
local config = dofile(directory .. 'launchpad/config.lua')
local ok, problem = config.check(reaper)
if not ok then reaper.MB(problem, 'Launchpad X', 0); return end
if config.get(reaper, 'monitor_running') ~= '' then return end
config.set(reaper, 'monitor_running', 1, false)
reaper.atexit(function() reaper.DeleteExtState(config.section, 'monitor_running', false) end)
local last_sequence = reaper.MIDI_GetRecentInputEvent(0)
local deadline = reaper.time_precise() + 60
reaper.ShowConsoleMsg('\nLaunchpad X: observing notes, releases, CCs and layout readback for 60 seconds. Switch Session/Note/Custom and test the grid and side buttons.\n')
local port_error
local function tick()
  if reaper.time_precise() >= deadline then return end
  local ports, diagnostic = config.discover(reaper)
  if not ports and diagnostic ~= port_error then reaper.ShowConsoleMsg(diagnostic .. '\n') end
  port_error = not ports and diagnostic or nil
  local note = ports and ports.note_input.id
  local control = ports and ports.control_input.id
  local events, newest = {}, nil
  local index = 0
  while true do
    local sequence, message, _, device = reaper.MIDI_GetRecentInputEvent(index)
    if sequence == 0 or sequence == last_sequence then break end
    newest = newest or sequence
    device = device & 0xFFFF
    if device == note or device == control then
      local bytes = {}
      for i = 1, #message do bytes[#bytes + 1] = string.format('%02X', message:byte(i)) end
      events[#events + 1] = string.format('%s port %d MIDI %s\n',
        device == note and 'Note' or 'DAW', device, table.concat(bytes, ' '))
    end
    index = index + 1
  end
  last_sequence = newest or last_sequence
  for i = #events, 1, -1 do reaper.ShowConsoleMsg(events[i]) end
  reaper.defer(tick)
end
tick()
