-- Shared configuration. Runtime requires only REAPER's built-in Lua APIs.
local M = { section = 'LaunchpadX.NativeNote.v1' }

function M.get(r, key) return r.GetExtState(M.section, key) end
function M.set(r, key, value, persist)
  r.SetExtState(M.section, key, tostring(value), persist ~= false)
end

-- A false name-API result denotes an absent/stale device, even with a name.
function M.ports(r, output)
  local result = {}
  local count = output and r.GetNumMIDIOutputs() or r.GetNumMIDIInputs()
  local getter = output and (r.GetMIDIOutputNameNoAlias or r.GetMIDIOutputName)
    or (r.GetMIDIInputNameNoAlias or r.GetMIDIInputName)
  for i = 0, count - 1 do
    local ok, name = getter(i, '')
    if ok and name and name ~= '' then result[#result + 1] = { id = i, name = name } end
  end
  return result
end

local roles = {
  { key = 'note_input', label = 'Note input', role = 'midi' },
  { key = 'control_input', label = 'DAW input', role = 'daw' },
  { key = 'control_output', label = 'DAW output', role = 'daw', output = true },
}

function M.discover(r)
  local inputs, outputs = M.ports(r, false), M.ports(r, true)
  local result, report, problems = {}, {}, {}
  for _, role in ipairs(roles) do
    local matches, candidates = {}, {}
    for _, port in ipairs(role.output and outputs or inputs) do
      local name = port.name:lower()
      if name:find('launchpad x', 1, true)
        and name:find('%f[%w]lpx ' .. role.role .. '%f[%W]') then
        matches[#matches + 1] = port
        candidates[#candidates + 1] = port.id .. ': ' .. port.name
      end
    end
    report[#report + 1] = role.label .. ' candidates: '
      .. (#candidates > 0 and table.concat(candidates, '; ') or '(none)')
    if #matches == 1 then result[role.key] = matches[1]
    else problems[#problems + 1] = (#matches == 0 and 'Missing ' or 'Ambiguous ') .. role.label end
  end
  if result.note_input and result.control_input
    and result.note_input.id == result.control_input.id then
    problems[#problems + 1] = 'Note and DAW inputs must be distinct'
  end
  local diagnostic = table.concat(report, '\n')
  if #problems > 0 then return nil, table.concat(problems, '; ') .. '\n' .. diagnostic end
  return result, diagnostic
end

function M.check(r)
  for _, name in ipairs({ 'MIDI_GetRecentInputEvent', 'SendMIDIMessageToHardware',
    'GetMIDIInputName', 'GetMIDIOutputName', 'GetNumMIDIInputs', 'GetNumMIDIOutputs',
    'ValidatePtr2', 'GetMasterTrack', 'GetMasterMuteSoloFlags', 'Main_OnCommand', 'EnumProjects', 'GetAudioDeviceInfo', 'time_precise' }) do
    if type(r[name]) ~= 'function' then
      return nil, 'Missing REAPER API: ' .. name .. '. Update REAPER before installing.'
    end
  end
  return true
end

return M
