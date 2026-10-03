-- No MIDI injection or consumption: observe global input history only.
local Engine = {}
Engine.__index = Engine
local fields = { 'I_RECINPUT', 'I_RECMON', 'I_RECARM', 'B_AUTO_RECARM' }

function Engine.new(r, config)
  local self = setmetatable({ r = r, config = config,
    notes = {}, sustain = {}, buttons = {}, held = 0, last_seq = 0,
    ready_at = 0, uncertain = false, leds = {}, next_ports = 0 }, Engine)
  self.records = {}
  self.project = r.EnumProjects(-1, "")
  self.last_seq = r.MIDI_GetRecentInputEvent(0)
  -- Allow releases and the audio thread to finish before transferring input.
  local rate_ok, rate = r.GetAudioDeviceInfo('SRATE')
  local block_ok, block = r.GetAudioDeviceInfo('BSIZE')
  rate, block = tonumber(rate), tonumber(block)
  self.grace = (rate_ok and block_ok and rate and rate > 0 and block)
    and math.max(0.05, 2 * block / rate) or 0.1
  self.ready_at = r.time_precise() + self.grace
  return self
end

function Engine:log(message)
  self.r.ShowConsoleMsg('Launchpad X: ' .. message .. '\n')
end

function Engine:project_open(project)
  local index = 0
  while true do
    local p = self.r.EnumProjects(index, '')
    if not p then return false end
    if p == project then return true end
    index = index + 1
  end
end

function Engine:valid(track, project)
  return track and project and self:project_open(project)
    and self.r.ValidatePtr2(project, track, 'MediaTrack*')
end

function Engine:send(command, value)
  if self.output ~= nil then
    self.r.SendMIDIMessageToHardware(self.output,
      string.char(0xF0, 0, 0x20, 0x29, 2, 0x0C, command) .. (value ~= nil and string.char(value) or "") .. string.char(0xF7))
  end
end

function Engine:connect()
  self:send(0x10, 1) -- DAW mode; native Live/Note remains available.
  self:send(0x00, 1) -- Select Note layout; do not set Note/velocity/pressure configuration.
  self.layout = 1
  self:send(0x00) -- Supported layout readback.
  self.owns_hardware = true
  self.leds = {}
  self.repaint = true
end

function Engine:ports(now)
  if now < self.next_ports then return end
  self.next_ports = now + 1
  local ports, problem = self.config.discover(self.r)
  if problem and not ports then
    if problem ~= self.port_error then self:log(problem .. '; waiting for Launchpad X ports.') end
    self.port_error = problem
    self.online = false
    return
  end
  local note, control, output = ports.note_input.id, ports.control_input.id, ports.control_output.id
  local changed = not self.online or note ~= self.note_input
    or control ~= self.control_input or output ~= self.output
    or ports.note_input.name ~= self.note_name
    or ports.control_input.name ~= self.control_name
    or ports.control_output.name ~= self.output_name
  if changed then
    -- If history was lost while disconnected, never guess that notes have released.
    if self.held > 0 or next(self.sustain) then
      self:suspend('MIDI ports changed while notes or sustain were held')
    end
    self.note_input, self.control_input, self.output = note, control, output
    self.note_name, self.control_name, self.output_name =
      ports.note_input.name, ports.control_input.name, ports.control_output.name
    self.buttons = {}
    self.ready_at = now + self.grace
    self:connect()
  end
  self.online, self.port_error = true, nil
end

function Engine:record(track)
  local record = self.records[track]
  if not record then
    record = { track = track, project = self.project, saved = {} }
    for _, field in ipairs(fields) do
      record.saved[field] = self.r.GetMediaTrackInfo_Value(track, field)
    end
    self.records[track] = record
  end
  return record
end

function Engine:conflict(input)
  if input < 4096 then return false end
  local device = (input - 4096) // 32
  return device == 63 or device == self.note_input
end

function Engine:release()
  local owner = self.owner
  if owner and self:valid(owner.track, owner.project) then
    for _, field in ipairs(fields) do
      local value = owner.saved[field]
      if field == 'I_RECINPUT' and self:conflict(value) then value = -1 end
      if field == 'I_RECARM' then value = 0 end
      self.r.SetMediaTrackInfo_Value(owner.track, field, value)
    end
  end
  self.owner = nil
end

function Engine:restore()
  self:release()
  for track, record in pairs(self.records) do
    if self:valid(track, record.project) then
      if record.targeted then
        for _, field in ipairs(fields) do
          local value = record.saved[field]
          if field == 'I_RECARM' then value = 0 end
          self.r.SetMediaTrackInfo_Value(track, field, value)
        end
      else
        if record.suppressed then self.r.SetMediaTrackInfo_Value(track, 'I_RECINPUT', record.saved.I_RECINPUT) end
      end
    end
  end
  self.records, self.requested = {}, nil
end

function Engine:safe(now)
  return self.online and not self.uncertain and self.held == 0
    and not next(self.sustain) and now >= self.ready_at
end

function Engine:exclusive()
  if not self.owner then return end
  for i = 0, self.r.CountTracks(self.project) - 1 do
    local track = self.r.GetTrack(self.project, i)
    if track ~= self.owner.track then
      local input = self.r.GetMediaTrackInfo_Value(track, 'I_RECINPUT')
      if self:conflict(input) then
        local record = self:record(track)
        record.suppressed = true
        self.r.SetMediaTrackInfo_Value(track, 'I_RECINPUT', -1)
      end
    end
  end
end

function Engine:suspend(reason)
  if not self.uncertain then
    self:log(reason .. '; track transfer suspended. Release all pads, disable, then enable again.')
  end
  self.uncertain = true
end

function Engine:transfer(track, project, now)
  if self.owner and not self:valid(self.owner.track, self.owner.project) then
    self.owner = nil
    if self.held > 0 or next(self.sustain) then self:suspend('The playing track was deleted or its project closed') end
  end
  if not self:safe(now) then return end
  if self.owner and self.owner.track == track and self.owner.input == self.note_input then return end
  -- Recheck pending requests: routing may change during held-note grace.
  if self:valid(track, project) then
    local input = self.r.GetMediaTrackInfo_Value(track, 'I_RECINPUT')
    if input >= 0 and input < 4096 then
      self.requested = self.owner and self.owner.track or nil
      return
    end
  end
  self:release()
  if not self:valid(track, project) then self.requested = nil; return end
  local record = self:record(track)
  record.targeted, record.input = true, self.note_input
  self.owner = record
  self.r.SetMediaTrackInfo_Value(track, 'B_AUTO_RECARM', 0)
  self.r.SetMediaTrackInfo_Value(track, 'I_RECINPUT', 4096 + self.note_input * 32)
  self.r.SetMediaTrackInfo_Value(track, 'I_RECMON', 1)
  self.r.SetMediaTrackInfo_Value(track, 'I_RECARM', 1)
  self:exclusive()
end

function Engine:mode(layout)
  if self.layout ~= layout then
    self.layout, self.leds = layout, {}
  end
end

function Engine:toggle(track, field)
  local value = self.r.GetMediaTrackInfo_Value(track, field)
  self.r.SetMediaTrackInfo_Value(track, field, value == 0 and 1 or 0)
  self.r.Undo_OnStateChangeEx2(self.project, 'Launchpad X: toggle ' .. field, 1, -1)
end

function Engine:event(message, device, now)
  if #message < 2 then return end
  device = device & 0xFFFF -- REAPER marks control-only inputs in bit 16.
  local status, key, value = message:byte(1, 3)
  local kind, channel = status & 0xF0, status & 0x0F
  if device == self.note_input then
    local id = channel * 128 + key
    if kind == 0x90 and value and value > 0 then
      self.notes[id] = (self.notes[id] or 0) + 1
      self.held = self.held + 1
    elseif kind == 0x80 or (kind == 0x90 and value == 0) then
      if self.notes[id] then
        self.notes[id] = self.notes[id] - 1
        self.held = self.held - 1
        if self.notes[id] == 0 then self.notes[id] = nil end
      end
      self.ready_at = now + self.grace
    elseif kind == 0xB0 and key == 64 and value then
      self.sustain[channel] = value >= 64 or nil
      self.ready_at = now + self.grace
    end
    return -- Notes, aftertouch, transpose and octave controls are never rewritten.
  end
  if not self.online or device ~= self.control_input then return end
  if message:sub(1, 7) == string.char(0xF0, 0, 32, 41, 2, 12, 0)
    and #message == 9 and message:byte(9) == 0xF7 then
    self:mode(message:byte(8)); return
  end
  if channel ~= 0 or value == nil then return end
  local button
  if kind == 0xB0 then button = 'cc' .. key
  elseif kind == 0x90 or kind == 0x80 then button = 'pad' .. key
  else return end
  local down = kind ~= 0x80 and value > 0
  local was_down = self.buttons[button]
  self.buttons[button] = down or nil
  if not down or was_down then return end
  if kind == 0xB0 and (key == 95 or key == 96 or key == 97) then
    self:mode(key == 95 and 0 or key == 96 and 1 or 4)
    self:send(0x00)
    return
  end
  if self.layout ~= 0 or self.r.EnumProjects(-1, '') ~= self.project then return end
  if kind == 0xB0 then
    if key == 39 then self:toggle(self.r.GetMasterTrack(self.project), 'B_MUTE')
    elseif key == 79 then
      -- Native action explicitly selects L+R rather than retaining L/R/L-R summing.
      self.r.Main_OnCommand(40917, 0)
    end
    return
  end
  local column, row = key % 10, 9 - key // 10
  if column < 1 or column > 8 or row < 1 or row > 8 then return end
  local track = self.r.GetTrack(self.project, column - 1)
  if not track then return end
  if row == 6 then self:toggle(track, 'B_MUTE')
  elseif row == 7 then self:toggle(track, 'I_SOLO')
  elseif row == 8 then
    local input = self.r.GetMediaTrackInfo_Value(track, 'I_RECINPUT')
    if input >= 0 and input < 4096 then
      self:toggle(track, 'I_RECARM')
    elseif self.requested == track then
      -- Cancel a pending transfer, or request shutdown of the active owner.
      self.requested = self.owner and self.owner.track ~= track and self.owner.track or nil
    else
      -- Includes cancellation of a pending shutdown by pressing its owner again.
      self.requested = track
    end
  end
end

function Engine:history(now)
  local events, found, newest = {}, false, nil
  local index = 0
  while true do
    local sequence, message, _, device = self.r.MIDI_GetRecentInputEvent(index)
    if sequence == 0 then break end
    newest = newest or sequence
    if sequence == self.last_seq then found = true; break end
    events[#events + 1] = { message = message, device = device }
    index = index + 1
  end
  if newest then
    if self.last_seq ~= 0 and not found then
      self:suspend('MIDI history lost')
      self.last_seq = newest
      return -- Do not replay incomplete control history.
    end
    self.last_seq = newest
  end
  for i = #events, 1, -1 do self:event(events[i].message, events[i].device, now) end
end

function Engine:light(status, key, value)
  local id = status * 128 + key
  if self.leds[id] ~= value then
    self.r.SendMIDIMessageToHardware(self.output, string.char(status, key, value))
    self.leds[id] = value
  end
end

function Engine:feedback()
  if not self.online or (self.layout ~= 0 and not (self.repaint and self.layout == 1)) then return end
  self.repaint = false
  for column = 1, 8 do
    local track = self.r.GetTrack(self.project, column - 1)
    for row = 1, 8 do
      local color = 0
      if track then
        if row == 6 then color = self.r.GetMediaTrackInfo_Value(track, 'B_MUTE') ~= 0 and 5 or 3
        elseif row == 7 and self.r.GetMediaTrackInfo_Value(track, 'I_SOLO') ~= 0 then color = 9
        elseif row == 8 and self.r.GetMediaTrackInfo_Value(track, 'I_RECARM') ~= 0 then
          local input = self.r.GetMediaTrackInfo_Value(track, 'I_RECINPUT')
          color = input >= 0 and input < 4096 and 53 or 49
        end
      end
      self:light(0x90, (9 - row) * 10 + column, color)
    end
  end
  for _, key in ipairs({91, 92, 93, 94, 98, 89, 79, 69, 59, 49, 39, 29, 19}) do
    local color = 0
    if key == 39 then
      color = self.r.GetMediaTrackInfo_Value(self.r.GetMasterTrack(self.project), 'B_MUTE') ~= 0 and 5 or 3
    elseif key == 79 then color = (self.r.GetMasterMuteSoloFlags() & 4) ~= 0 and 45 or 3 end
    self:light(0xB0, key, color)
  end
end

function Engine:tick()
  local now = self.r.time_precise()
  self:ports(now)
  self:history(now)
  local project = self.r.EnumProjects(-1, '')
  if project ~= self.project and self:safe(now) then
    self:restore()
    self.project, self.leds = project, {}
  end
  if project == self.project then
    self:transfer(self.requested, project, now)
    if self.online then self:exclusive() end
    self:feedback()
  end
  -- Stop deliberately has no lifecycle effect.
end

function Engine:cleanup()
  self:restore()
  if self.owns_hardware then
    -- Resolve again so a changed index cannot send SysEx to an unrelated device.
    local ports = self.config.discover(self.r)
    self.output = ports and ports.control_output.id or nil
    self:send(0x10, 0)
    self.owns_hardware = false
  end
end

return Engine
