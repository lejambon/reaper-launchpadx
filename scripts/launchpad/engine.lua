-- No MIDI injection or consumption: observe global input history only.
local Engine = {}
Engine.__index = Engine
local fields = { 'I_RECINPUT', 'I_RECMON', 'I_RECARM', 'B_AUTO_RECARM' }
local layout = { session = 0, note = 1, custom = 4 }
local command = { layout = 0x00, daw_mode = 0x10 }
local hardware_mode = { standalone = 0, daw = 1 }
local button = {
  session = 95, note = 96, custom = 97, master_mute = 39, master_mono = 19,
  record = 89, play_pause = 79, repeat_toggle = 29, stop = 49, start = 59,
}
local mode_buttons = {
  [button.session] = layout.session, [button.note] = layout.note, [button.custom] = layout.custom,
}
local mixer_row = { mute = 6, solo = 7, arm = 8 }
local palette = {
  off = 0, dim_white = 1, white = 3, muted = 5, solo = 9, midi_arm = 49, audio_arm = 53,
  mono = 9, record = 5, play = 19, paused = 9, repeat_on = 19,
}
local play_state = { playing = 1, paused = 2, recording = 4 }
local lighting = { static = 0, pulse = 2 }
local record_action = 1013
local start_tolerance = 0.001
local mono_action = 40917
local mono_flag = 4
local sysex_prefix = string.char(0xF0, 0, 0x20, 0x29, 2, 0x0C)
local feedback_buttons = {
  91, 92, 93, 94, 98, 69, button.master_mute, button.master_mono,
}

function Engine.new(r, config)
  local self = setmetatable({ r = r, config = config,
    notes = {}, sustain = {}, buttons = {}, held = 0, last_seq = 0,
    ready_at = 0, uncertain = false, leds = {}, led_effects = {}, next_ports = 0 }, Engine)
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

function Engine:send(command_id, value)
  if self.output ~= nil then
    self.r.SendMIDIMessageToHardware(self.output,
      sysex_prefix .. string.char(command_id) .. (value ~= nil and string.char(value) or "") .. string.char(0xF7))
  end
end

function Engine:connect()
  self:send(command.daw_mode, hardware_mode.daw) -- Native Live/Note remains available.
  self:send(command.layout, layout.note) -- Leave Note/velocity/pressure configuration alone.
  self.layout = layout.note
  self:send(command.layout) -- Supported layout readback.
  self.owns_hardware = true
  self.leds, self.led_effects = {}, {}
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
        if record.disarmed then self.r.SetMediaTrackInfo_Value(track, 'I_RECARM', 0) end
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
        -- A project saved while managed can reopen with an armed Note route
        -- that this instance has never owned. Retire its arm as well as input.
        -- All MIDI Inputs suppression leaves independent arm edits intact.
        if (input - 4096) // 32 == self.note_input then
          record.disarmed = true
          self.r.SetMediaTrackInfo_Value(track, 'I_RECARM', 0)
        end
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
  -- nil explicitly requests shutdown; an invalid destination cancels a transfer.
  if track == nil then self:release(); return end
  if not self:valid(track, project) then
    self.requested = self.owner and self.owner.track or nil
    return
  end
  -- Recheck pending requests: routing may change during held-note grace.
  local input = self.r.GetMediaTrackInfo_Value(track, 'I_RECINPUT')
  if input >= 0 and input < 4096 then
    self.requested = self.owner and self.owner.track or nil
    return
  end
  self:release()
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

-- requested: owner track retains it, another track transfers, nil shuts down.
-- With no owner, nil means there is no pending activation.
function Engine:request_target(track)
  if self.requested ~= track then
    -- Select a destination, or cancel a pending shutdown by selecting its owner.
    self.requested = track
  elseif self.owner and self.owner.track ~= track then
    -- Pressing the pending destination again cancels the transfer.
    self.requested = self.owner.track
  else
    -- Shut down the owner, or cancel an activation when there is no owner.
    self.requested = nil
  end
end

function Engine:can_go_to_start()
  return self.r.GetPlayStateEx(self.project) == 0
    and math.abs(self.r.GetCursorPositionEx(self.project)) > start_tolerance
end

function Engine:transport(key)
  local r, project = self.r, self.project
  if key == button.play_pause then
    local state = r.GetPlayStateEx(project)
    if (state & play_state.paused) ~= 0 or (state & play_state.playing) == 0 then
      r.OnPlayButtonEx(project)
    else
      r.OnPauseButtonEx(project)
    end
  elseif key == button.record then
    r.Main_OnCommandEx(record_action, 0, project)
  elseif key == button.repeat_toggle then
    r.GetSetRepeatEx(project, 2)
  elseif key == button.stop then
    r.OnStopButtonEx(project)
  elseif key == button.start and self:can_go_to_start() then
    r.SetEditCurPos2(project, 0, true, false)
  end
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
  if message:sub(1, 7) == sysex_prefix .. string.char(command.layout)
    and #message == 9 and message:byte(9) == 0xF7 then
    self:mode(message:byte(8)); return
  end
  if channel ~= 0 or value == nil then return end
  local button_id
  if kind == 0xB0 then button_id = 'cc' .. key
  elseif kind == 0x90 or kind == 0x80 then button_id = 'pad' .. key
  else return end
  local down = kind ~= 0x80 and value > 0
  local was_down = self.buttons[button_id]
  self.buttons[button_id] = down or nil
  if not down or was_down then return end
  if kind == 0xB0 and mode_buttons[key] ~= nil then
    self:mode(mode_buttons[key])
    self:send(command.layout)
    return
  end
  if self.layout ~= layout.session or self.r.EnumProjects(-1, '') ~= self.project then return end
  if kind == 0xB0 then
    if key == button.master_mute then self:toggle(self.r.GetMasterTrack(self.project), 'B_MUTE')
    elseif key == button.master_mono then
      -- Native action explicitly selects L+R rather than retaining L/R/L-R summing.
      self.r.Main_OnCommand(mono_action, 0)
    else
      self:transport(key)
    end
    return
  end
  local column, row = key % 10, 9 - key // 10
  if column < 1 or column > 8 or row < 1 or row > 8 then return end
  local track = self.r.GetTrack(self.project, column - 1)
  if not track then return end
  if row == mixer_row.mute then self:toggle(track, 'B_MUTE')
  elseif row == mixer_row.solo then self:toggle(track, 'I_SOLO')
  elseif row == mixer_row.arm then
    local input = self.r.GetMediaTrackInfo_Value(track, 'I_RECINPUT')
    if input >= 0 and input < 4096 then
      self:toggle(track, 'I_RECARM')
    else
      self:request_target(track)
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

function Engine:light(status, key, value, effect)
  effect = effect or lighting.static
  local id = status * 128 + key
  if self.leds[id] ~= value or self.led_effects[id] ~= effect then
    if self.led_effects[id] == lighting.pulse and effect == lighting.static then
      self.r.SendMIDIMessageToHardware(self.output, string.char(status | lighting.pulse, key, 0))
    end
    self.r.SendMIDIMessageToHardware(self.output, string.char(status | effect, key, value))
    self.leds[id], self.led_effects[id] = value, effect
  end
end

function Engine:transport_feedback()
  local state = self.r.GetPlayStateEx(self.project)
  local paused = (state & play_state.paused) ~= 0
  local playing = (state & play_state.playing) ~= 0
  local recording = (state & play_state.recording) ~= 0
  local stopped = state == 0
  local repeat_on = self.r.GetSetRepeatEx(self.project, -1) ~= 0
  local play_color, play_effect = palette.play, lighting.static
  if paused then
    play_color = palette.paused
  elseif playing then
    play_effect = lighting.pulse
  end
  self:light(0xB0, button.play_pause, play_color, play_effect)
  self:light(0xB0, button.record, palette.record, recording and lighting.pulse or lighting.static)
  self:light(0xB0, button.repeat_toggle, repeat_on and palette.repeat_on or palette.dim_white)
  self:light(0xB0, button.stop, stopped and palette.off or palette.white)
  self:light(0xB0, button.start, self:can_go_to_start() and palette.white or palette.off)
end

function Engine:feedback()
  if not self.online then return end
  if self.layout ~= layout.session and not (self.repaint and self.layout == layout.note) then return end
  self.repaint = false
  for column = 1, 8 do
    local track = self.r.GetTrack(self.project, column - 1)
    for row = 1, 8 do
      local color = palette.off
      if track then
        if row == mixer_row.mute then
          color = self.r.GetMediaTrackInfo_Value(track, 'B_MUTE') ~= 0
            and palette.muted or palette.dim_white
        elseif row == mixer_row.solo then
          color = self.r.GetMediaTrackInfo_Value(track, 'I_SOLO') ~= 0 and palette.solo or palette.dim_white
        elseif row == mixer_row.arm and self.r.GetMediaTrackInfo_Value(track, 'I_RECARM') ~= 0 then
          local input = self.r.GetMediaTrackInfo_Value(track, 'I_RECINPUT')
          color = input >= 0 and input < 4096 and palette.audio_arm or palette.midi_arm
        end
      end
      self:light(0x90, (9 - row) * 10 + column, color)
    end
  end
  for _, key in ipairs(feedback_buttons) do
    local color = palette.off
    if key == button.master_mute then
      color = self.r.GetMediaTrackInfo_Value(self.r.GetMasterTrack(self.project), 'B_MUTE') ~= 0
        and palette.muted or palette.dim_white
    elseif key == button.master_mono then
      color = (self.r.GetMasterMuteSoloFlags() & mono_flag) ~= 0 and palette.mono or palette.dim_white
    end
    self:light(0xB0, key, color)
  end
  if self.layout == layout.session then self:transport_feedback() end
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
  if self.cleaned then return self.cleanup_error == nil, self.cleanup_error end
  local errors = {}
  local restored, restore_error = xpcall(function() self:restore() end, debug.traceback)
  if not restored then
    errors[#errors + 1] = 'Track restoration incomplete:\n' .. restore_error
  end
  local released, release_error = xpcall(function()
    if not self.owns_hardware then return end
    -- Resolve again so a changed index cannot send SysEx to an unrelated device.
    local ports = self.config.discover(self.r)
    self.output = ports and ports.control_output.id or nil
    self:send(command.daw_mode, hardware_mode.standalone)
    self.owns_hardware = false
  end, debug.traceback)
  if not released then
    errors[#errors + 1] = 'Hardware release failed:\n' .. release_error
  end
  -- Cleanup is terminal; do not automatically retry partially failed restoration.
  if #errors > 0 then self.cleanup_error = table.concat(errors, '\n') end
  self.cleaned = true
  return self.cleanup_error == nil, self.cleanup_error
end

return Engine
