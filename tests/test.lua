local Engine = dofile('scripts/launchpad/engine.lua')
local config = dofile('scripts/launchpad/config.lua')
local startup = dofile('scripts/launchpad/startup.lua')
local count = 0
local function eq(actual, expected, message)
  assert(actual == expected, (message or '') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local function test(name, fn)
  fn(); count = count + 1; print('PASS ' .. name)
end

local function fixture()
  local f = { now = 0, ext = {}, history = {}, seq = 0, sent = {}, logs = {}, writes = {},
    inputs = { [0] = 'Other', [1] = 'Launchpad X LPX MIDI', [2] = 'Launchpad X LPX DAW' },
    outputs = { [0] = 'Other output', [1] = 'Launchpad X LPX DAW out' }, exits = {}, deferred = {} }
  local function track(name, visible, selected)
    return { name = name, visible = visible ~= false, selected = selected or false,
      I_RECINPUT = -1, I_RECMON = 0, I_RECARM = 0, B_AUTO_RECARM = 1, B_MUTE = 0, I_SOLO = 0 }
  end
  f.a, f.hidden, f.b, f.c = track('a', true, true), track('hidden', false), track('b'), track('c')
  f.project = { tracks = { f.a, f.hidden, f.b, f.c }, play_state = 0, cursor = 0, repeat_on = 0 }
  f.transport_calls = {}
  f.active, f.projects = f.project, { f.project }
  local r = {}
  f.r = r
  function r.GetExtState(_, key) return f.ext[key] or '' end
  function r.SetExtState(_, key, value, persist) f.ext[key] = value; f.last_persist = persist end
  function r.DeleteExtState(_, key) f.ext[key] = nil end
  function r.time_precise() return f.now end
  function r.GetNumMIDIInputs() return 8 end
  function r.GetNumMIDIOutputs() return 8 end
  function r.GetMIDIInputName(id) return f.inputs[id] ~= nil, f.inputs[id] or '' end
  function r.GetMIDIOutputName(id) return f.outputs[id] ~= nil, f.outputs[id] or '' end
  function r.GetAudioDeviceInfo(key) return true, key == 'SRATE' and '48000' or '256' end
  function r.MIDI_GetRecentInputEvent(index)
    local event = f.history[#f.history - index]
    if event then return event.seq, event.msg, 0, event.device, -1, 0 end
    return 0, '', 0, 0, -1, 0
  end
  function r.EnumProjects(index)
    if index == -1 then return f.active end
    return f.projects[index + 1]
  end
  function r.CountTracks(project) return #project.tracks end
  function r.GetTrack(project, index) return project.tracks[index + 1] end
  function r.ValidatePtr2(project, target)
    for _, p in ipairs(f.projects) do
      if p == project then
        for _, t in ipairs(p.tracks) do if t == target then return true end end
      end
    end
    return false
  end
  f.master = {B_MUTE = 0}
  function r.GetMasterTrack() return f.master end
  function r.GetMasterMuteSoloFlags() return f.mono and 4 or 0 end
  function r.Main_OnCommand(id) eq(id, 40917); f.mono = not f.mono end
  function r.GetPlayStateEx(project) return project.play_state or 0 end
  function r.GetCursorPositionEx(project) return project.cursor or 0 end
  local function transport_call(name, project)
    f.transport_calls[#f.transport_calls + 1] = { name = name, project = project }
  end
  function r.OnPlayButtonEx(project)
    transport_call('play', project)
    project.play_state = (r.GetPlayStateEx(project) & 4) | 1
  end
  function r.OnPauseButtonEx(project)
    transport_call('pause', project)
    project.play_state = (r.GetPlayStateEx(project) & 4) | 2
  end
  function r.OnStopButtonEx(project)
    transport_call('stop', project)
    if not f.cancel_stop then project.play_state = 0 end
  end
  function r.Main_OnCommandEx(id, flag, project)
    eq(flag, 0)
    eq(id, 1013); transport_call('record', project)
    if (r.GetPlayStateEx(project) & 4) ~= 0 then
      project.play_state = 1
    else
      project.play_state = 5
    end
  end
  function r.GetSetRepeatEx(project, value)
    if value == 2 then
      transport_call('repeat', project)
      project.repeat_on = (project.repeat_on or 0) == 0 and 1 or 0
    else
      eq(value, -1)
    end
    return project.repeat_on or 0
  end
  function r.SetEditCurPos2(project, position, moveview, seekplay)
    transport_call('cursor', project)
    eq(position, 0); eq(moveview, true); eq(seekplay, false)
    project.cursor = position
  end
  function r.SetOnlyTrackSelected(target)
    for _, t in ipairs(f.active.tracks) do t.selected = t == target end
  end
  function r.GetMediaTrackInfo_Value(t, key) return t[key] end
  function r.SetMediaTrackInfo_Value(t, key, value)
    f.writes[#f.writes + 1] = { t, key, value }; t[key] = value
  end
  function r.SendMIDIMessageToHardware(id, msg) f.sent[#f.sent + 1] = { id = id, msg = msg } end
  function r.ShowConsoleMsg(msg) f.logs[#f.logs + 1] = msg end
  function r.Undo_OnStateChangeEx2() end
  function r.get_action_context() return false, '', 0, 1234 end
  function r.SetToggleCommandState(_, _, value) f.toggle = value end
  function r.RefreshToolbar2() end
  function r.atexit(fn) f.exits[#f.exits + 1] = fn end
  function r.defer(fn) f.deferred[#f.deferred + 1] = fn end
  function r.MB(msg) f.logs[#f.logs + 1] = msg end
  function f:event(device, ...)
    self.seq = self.seq + 1
    self.history[#self.history + 1] = { seq = self.seq, msg = string.char(...), device = device }
  end
  function f:tick(dt)
    self.now = self.now + (dt or 0.2); self.engine:tick()
  end
  function f:cc(key, value, device) self:event(device or 0x10002, 0xB0, key, value or 127) end
  function f:press(key) self:cc(key); self:cc(key, 0) end
  function f:select(target) self.r.SetOnlyTrackSelected(target) end
  function f:pump()
    self.now = self.now + 0.2
    local queue = self.deferred; self.deferred = {}
    for _, fn in ipairs(queue) do fn() end
  end
  f.engine = Engine.new(r, config)
  f:tick(); f:tick() -- hardware connection followed by input transfer grace period
  function f:pad(row, column, value, status)
    self:event(self.engine.control_input, status or 0x90, (9-row)*10+column, value or 127)
  end
  function f:tap(row, column) self:pad(row,column); self:pad(row,column,0) end
  function f:session() self:press(95); self:tick() end
  function f:target(column) self:tap(8,column); self:tick() end
  return f
end

test('missing device at startup never manages a track', function()
  local f = fixture()
  f.engine:cleanup(); f.inputs[1] = nil
  f.engine = Engine.new(f.r, config); f:tick(); f:tick()
  eq(f.engine.owner, nil); eq(f.a.I_RECINPUT, -1)
end)

test('duplicate port names fail safely', function()
  local f = fixture()
  f.inputs[4] = 'Launchpad X LPX MIDI'; f:tick(1.1)
  eq(f.engine.online, false)
  local port, err = config.discover(f.r)
  eq(port, nil); assert(err:find('Ambiguous'))
end)

test('cleanup does not send to an unrelated device after output reorder', function()
  local f = fixture()
  f.outputs[1] = 'Different device'; f.engine:cleanup()
  eq(#f.sent, 75); eq(f.a.I_RECINPUT, -1)
end)

test('Start prevents duplicates and Disable persists through automatic startup', function()
  local f = fixture(); f.engine:cleanup()
  reaper = f.r
  dofile('scripts/Launchpad X - Start.lua'); f:pump(); f:pump()
  eq(f.toggle, 1); local token = f.ext.running; assert(token ~= '')
  local exits = #f.exits
  dofile('scripts/Launchpad X - Start.lua'); eq(#f.exits, exits); eq(f.ext.running, token)
  dofile('scripts/Launchpad X - Disable.lua'); eq(f.ext.enabled, '0')
  f:pump(); eq(f.ext.running, nil); eq(f.toggle, 0); eq(f.a.I_RECINPUT, -1)
  dofile('scripts/Launchpad X - Start.lua'); eq(f.ext.running, nil)
  dofile('scripts/Launchpad X - Enable.lua'); f:pump(); f:pump(); eq(f.toggle, 1)
  for _, fn in ipairs(f.exits) do fn() end
  eq(f.ext.running, nil); eq(f.a.I_RECINPUT, -1)
end)

test('back-to-back Disable and Enable wait for restoration before restarting', function()
  local f = fixture(); f.engine:cleanup(); reaper = f.r
  dofile('scripts/Launchpad X - Start.lua'); f:pump(); f:pump()
  local token = f.ext.running
  dofile('scripts/Launchpad X - Disable.lua'); dofile('scripts/Launchpad X - Enable.lua')
  f:pump(); f:pump(); f:pump()
  assert(f.ext.running and f.ext.running ~= token); eq(f.a.I_RECINPUT, -1)
  dofile('scripts/Launchpad X - Disable.lua'); f:pump(); eq(f.a.I_RECINPUT, -1)
end)

test('runtime errors clean up managed settings and the duplicate lock', function()
  local f = fixture(); f.engine:cleanup(); reaper = f.r
  dofile('scripts/Launchpad X - Start.lua'); f:pump(); f:pump()
  f.r.MIDI_GetRecentInputEvent = function() error('simulated failure') end
  f:pump(); eq(f.a.I_RECINPUT, -1); eq(f.ext.running, nil); eq(f.toggle, 0)
end)

test('startup block preserves exact code and BOM, supports returns and is idempotent', function()
  local existing = '\239\187\191-- Existing startup\r\nreturn\r\n'
  local script = '/tmp/scripts/Launchpad X - Start.lua'
  local result = startup.render(existing, script)
  eq(result:sub(1, 3), existing:sub(1, 3))
  eq(result:sub(-(#existing - 3)), existing:sub(4))
  eq(startup.render(result, script), result)
  local queued = {}
  -- Lua's loadfile strips a UTF-8 BOM; load(string) does not.
  local fn = assert(load(result:sub(4), 'startup', 't', {
    reaper = { defer = function(f) queued[#queued + 1] = f end },
    xpcall = xpcall, debug = debug, dofile = function(path) eq(path, script) end }))
  fn(); eq(#queued, 1); queued[1]()
end)

test('incomplete startup block is rejected before mutation', function()
  local ok = pcall(startup.render, '-- BEGIN Launchpad X Native Note startup\n', '/tmp/start.lua')
  eq(ok, false)
end)

test('API checks name missing built-in functions', function()
  local f = fixture()
  f.r.MIDI_GetRecentInputEvent = nil
  local ok, err = config.check(f.r)
  eq(ok, nil); assert(err:find('MIDI_GetRecentInputEvent', 1, true))
end)

test('installation keeps a byte-exact backup and replaces only its own block', function()
  local resource = assert(os.getenv('LPX_TEST_RESOURCE'))
  local path = resource .. '/Scripts/__startup.lua'
  local original = '-- unrelated startup\r\nreturn\r\n'
  local function write(content)
    local file = assert(io.open(path, 'wb')); assert(file:write(content)); assert(file:close())
  end
  local function read(p)
    local file = assert(io.open(p, 'rb')); local content = file:read('*a'); file:close(); return content
  end
  write(original)
  startup.install(resource, "/tmp/Launchpad's script.lua")
  local installed = read(path)
  eq(read(path .. '.launchpad-backup'), original)
  startup.install(resource, "/tmp/Launchpad's script.lua"); eq(read(path), installed)
  write(installed .. '-- added later\n')
  startup.install(resource, '/tmp/another script.lua')
  eq(read(path .. '.launchpad-backup'), original)
  assert(read(path):find('-- added later\n', 1, true))
  assert(loadfile(path))
end)

test('Configure reports automatic discovery without dialogs or persistence', function()
  local f = fixture(); reaper = f.r
  f.inputs[1], f.inputs[2] = nil, nil
  f.inputs[70], f.inputs[71] = 'Launchpad X LPX DAW', 'Launchpad X LPX MIDI'
  function f.r.GetNumMIDIInputs() return 128 end
  function f.r.GetUserInputs() error('manual dialog must not be used') end
  f.ext.running = 'active'
  dofile('scripts/Launchpad X - Configure.lua')
  eq(f.ext.note_input, nil); eq(f.ext.control_input, nil); eq(f.ext.control_output, nil)
  assert(f.logs[#f.logs]:find('71: Launchpad X LPX MIDI', 1, true))
end)

test('startup has no target and preserves native settings', function()
  local f = fixture(); eq(f.engine.owner,nil); eq(f.a.I_RECINPUT,-1)
  eq(#f.sent,75); eq(f.sent[2].msg:byte(8),1); eq(#f.sent[3].msg,8)
  f:press(97); f:press(98); f:tick(); eq(f.engine.layout,4); eq(f.engine.owner,nil)
end)

test('grid includes hidden tracks and follows reorder independently of selection', function()
  local f = fixture(); f:session(); f:target(2)
  eq(f.engine.owner.track,f.hidden); eq(f.a.selected,true)
  f:select(f.c); f:tick(); eq(f.engine.owner.track,f.hidden)
  f.project.tracks = {f.c,f.a,f.hidden,f.b}; f:target(1)
  eq(f.engine.owner.track,f.c); eq(f.hidden.I_RECINPUT,-1)
  f:tap(6,2); f:tap(7,2); f:tap(8,2); f:tick()
  eq(f.a.B_MUTE,1); eq(f.a.I_SOLO,1); eq(f.a.I_RECARM,1)
  f:tap(5,8); f:tap(6,8); f:tap(1,1); f:tick(); eq(f.engine.owner.track,f.a)
end)

test('mode gating, channel gating, pressure and press edges', function()
  local f = fixture(); f:tap(6,1); f:tick(); eq(f.a.B_MUTE,0)
  f:session(); f:pad(6,1); f:pad(6,1); f:tick(); eq(f.a.B_MUTE,1)
  f:pad(6,1,64,0x80); f:tap(6,1); f:tick(); eq(f.a.B_MUTE,0)
  f:pad(6,1,100,0x91); f:event(2,0xA0,31,100); f:tick(); eq(f.a.B_MUTE,0)
  f:press(96); f:tap(6,1); f:tick(); eq(f.a.B_MUTE,0)
  f:press(97); f:tap(6,1); f:tick(); eq(f.a.B_MUTE,0)
  local n=#f.sent; f:tick(); eq(#f.sent,n)
end)

test('layout readback gates mixer and Session entry repaints', function()
  local f=fixture(); f:session(); local n=#f.sent; f:tick(); eq(#f.sent,n)
  f:event(2,240,0,32,41,2,12,0,4,247); f:tap(6,1); f:tick(); eq(f.a.B_MUTE,0)
  f:event(2,240,0,32,41,2,12,0,0,247); f:tick(); assert(#f.sent>=n+77)
end)

test('all palette colors, external edits, dark missing columns and master state', function()
  local f=fixture(); f:session(); f:target(1)
  eq(f.engine.leds[0x90*128+31],1); eq(f.engine.leds[0x90*128+38],0)
  eq(f.engine.leds[0xB0*128+39],1); eq(f.engine.leds[0xB0*128+19],1)
  f.a.B_MUTE,f.a.I_SOLO=1,2; f:tick()
  local function led(status,key) return f.engine.leds[status*128+key] end
  eq(led(0x90,81),0); eq(led(0x90,41),0); eq(led(0x90,31),5)
  eq(led(0x90,21),9); eq(led(0x90,11),49); eq(led(0x90,88),0)
  for row=1,5 do eq(led(0x90,(9-row)*10+1),0) end
  f:press(39); f:press(19); f:tick(); eq(f.master.B_MUTE,1); eq(f.mono,true)
  eq(led(0xB0,39),5); eq(led(0xB0,19),9)
  f:press(19); f:tick(); eq(f.mono,false); eq(led(0xB0,19),1)
  f.master.B_MUTE=0; f.a.B_MUTE=0; f:tick()
  eq(led(0xB0,39),1); eq(led(0x90,31),1)
  f.master.B_MUTE=1; f.a.B_MUTE=1; f:tick()
  f.engine:cleanup(); eq(f.master.B_MUTE,1); eq(f.a.B_MUTE,1); eq(f.a.I_SOLO,2)
end)

test('exclusive routes across all tracks restore exactly with audio untouched', function()
  local f=fixture(); f.hidden.I_RECINPUT=4096+32+5; f.b.I_RECINPUT=4096+63*32+16
  for i=5,12 do f.project.tracks[i]={I_RECINPUT=4096+32,I_RECMON=2,I_RECARM=1,B_AUTO_RECARM=0,B_MUTE=0,I_SOLO=0} end
  f:session(); f:target(1)
  eq(f.hidden.I_RECINPUT,-1); eq(f.b.I_RECINPUT,-1); eq(f.c.I_RECINPUT,-1)
  eq(f.project.tracks[12].I_RECINPUT,-1)
  f:target(2); eq(f.a.I_RECINPUT,-1); eq(f.hidden.I_RECINPUT,4128)
  f:target(3); eq(f.hidden.I_RECINPUT,-1)
  f.engine:cleanup(); eq(f.hidden.I_RECINPUT,4133); eq(f.b.I_RECINPUT,6128)
  eq(f.project.tracks[12].I_RECINPUT,4128); eq(f.c.I_RECINPUT,-1)
end)

test('audio tracks toggle only arm and preserve independent edits', function()
  local f=fixture(); f.c.I_RECINPUT=7; f.c.I_RECARM=1
  f:session(); f:target(1); f:target(4)
  eq(f.engine.owner.track,f.a); eq(f.c.I_RECINPUT,7); eq(f.c.I_RECARM,0)
  f:tap(8,4); f:tick(); eq(f.c.I_RECARM,1)
  f.engine:cleanup(); eq(f.c.I_RECINPUT,7); eq(f.c.I_RECARM,1)
end)

test('held overlapping notes and sustain defer transfers and owner feedback', function()
  local f=fixture(); f:session(); f:target(1)
  f:event(1,0x95,60,90); f:event(1,0x95,60,70); f:cc(64,127,1); f:target(2)
  eq(f.engine.owner.track,f.a); eq(f.engine.held,2)
  f:event(1,0x85,60,64); f:event(1,0x95,60,0); f:tick(); eq(f.engine.owner.track,f.a)
  f:cc(64,0,1); f:tick(); eq(f.engine.owner.track,f.a)
  f:tick(0.01); eq(f.engine.owner.track,f.a); f:tick(0.1); eq(f.engine.owner.track,f.hidden)
end)

test('owner shutdown waits for releases then releases routing and can reactivate', function()
  local f=fixture(); f:session(); f:target(1); f:event(1,0x90,60,90); f:target(1)
  eq(f.a.I_RECARM,1); eq(f.engine.owner.track,f.a)
  f:event(1,0x80,60,0); f:tick(); eq(f.a.I_RECARM,1)
  f:tick(); eq(f.a.I_RECARM,0); eq(f.engine.owner,nil); eq(f.a.I_RECINPUT,-1)
  eq(f.a.I_RECMON,0); eq(f.a.B_AUTO_RECARM,1)
  f:tick(); eq(f.engine.owner,nil); f:target(1); eq(f.a.I_RECARM,1)
end)

test('pending transfer and shutdown can be cancelled with the same button', function()
  local f=fixture(); f:session(); f:target(1); f:event(1,0x90,60,90)
  f:target(2); eq(f.engine.requested,f.hidden); f:target(2); eq(f.engine.requested,f.a)
  f:target(1); eq(f.engine.requested,nil); f:target(1); eq(f.engine.requested,f.a)
  f:event(1,0x80,60,0); f:tick(); f:tick()
  eq(f.engine.owner.track,f.a); eq(f.a.I_RECARM,1); eq(f.hidden.I_RECARM,0)
end)

test('dark rows do nothing and arm colors follow current routing and external edits', function()
  local f=fixture(); f.c.I_RECINPUT=0; f.c.I_RECMON=2; f:session(); f:target(1)
  for row=1,5 do f:tap(row,1) end
  f:target(4); eq(f.engine.owner.track,f.a); eq(f.c.I_RECMON,2)
  eq(f.engine.leds[0x90*128+14],53)
  f.c.I_RECARM=0; f.a.I_RECARM=0; f:tick()
  eq(f.engine.leds[0x90*128+14],0); eq(f.engine.leds[0x90*128+11],0)
  f.c.I_RECINPUT=5000; f.c.I_RECARM=1; f:tick()
  eq(f.engine.leds[0x90*128+14],49); eq(f.engine.owner.track,f.a)
end)

test('initial pending activation cancels without taking ownership', function()
  local f=fixture(); f:session(); f:event(1,0x90,60,90)
  f:target(1); eq(f.engine.owner,nil); eq(f.engine.requested,f.a)
  f:target(1); eq(f.engine.requested,nil)
  f:event(1,0x80,60,0); f:tick(); f:tick()
  eq(f.engine.owner,nil); eq(f.a.I_RECARM,0); eq(f.a.I_RECINPUT,-1)
end)

test('sustain defers shutdown and LEDs reflect actual arm through grace', function()
  local f=fixture(); f:session(); f:target(1); f:cc(64,127,1); f:target(1)
  eq(f.engine.owner.track,f.a); eq(f.engine.leds[0x90*128+11],49)
  f:tick(); eq(f.a.I_RECARM,1)
  f:cc(64,0,1); f:tick(); f:tick(0.01); eq(f.a.I_RECARM,1)
  f:tick(0.1); eq(f.engine.owner,nil); eq(f.a.I_RECARM,0)
  eq(f.engine.leds[0x90*128+11],0); eq(f.engine.leds[0x90*128+41],0)
end)

test('audio arms persist through Note transfer and release with routing unchanged', function()
  local f=fixture(); f.c.I_RECINPUT=7; f.c.I_RECMON=2
  f:session(); f:target(1); f:target(4); f:target(2)
  eq(f.a.I_RECARM,0); eq(f.hidden.I_RECARM,1); eq(f.c.I_RECARM,1)
  eq(f.c.I_RECINPUT,7); eq(f.c.I_RECMON,2); eq(f.c.B_AUTO_RECARM,1)
  f:target(2); eq(f.engine.owner,nil); eq(f.hidden.I_RECARM,0)
  f.engine:cleanup(); eq(f.c.I_RECARM,1); eq(f.c.I_RECINPUT,7)
end)

test('project switches defer cleanup and start with no new target', function()
  local f=fixture(); f:session(); f:target(1); f:event(1,0x90,60,90); f:tick()
  local new={tracks={f.b}}; f.project.tracks={f.a,f.hidden}; f.projects[2]=new; f.active=new
  f:tick(); eq(f.engine.owner.track,f.a); f:tap(8,1); f:tick()
  f:event(1,0x80,60,0); f:tick(); f:tick(); eq(f.engine.owner,nil); eq(f.a.I_RECINPUT,-1)
  f:target(1); eq(f.engine.owner.track,f.b)
end)

test('deletion and lost history safeguard held owner', function()
  local f=fixture(); f:session(); f:target(1); f:event(1,0x90,60,90); f:tick()
  f.project.tracks={f.b}; f:tick(); eq(f.engine.owner,nil); eq(f.engine.uncertain,true)
  f=fixture(); f:session(); f:target(1); f:event(1,0x90,60,90); f:tick()
  f.history={}; f:target(2); eq(f.engine.uncertain,true); eq(f.engine.owner.track,f.a)
end)

test('missing ports and reconnect safeguard held notes and resolve new IDs', function()
  local f=fixture(); f:session(); f:target(1); f:event(1,0x90,60,90); f:tick()
  f.inputs[1]=nil; f:tick(1.1); eq(f.engine.online,false)
  f.inputs[3]='Launchpad X LPX MIDI'; f:tick(1.1); eq(f.engine.uncertain,true); eq(f.engine.owner.track,f.a)
  f.engine:cleanup(); eq(f.a.I_RECINPUT,-1)
  f=fixture(); f:session(); f:target(1); f.inputs[1]=nil; f.inputs[3]='Launchpad X LPX MIDI'
  f:tick(1.1); f:tick(); eq(f.a.I_RECINPUT,4192); f.engine:cleanup(); eq(f.a.I_RECINPUT,-1)
end)

test('ports 70/71 are not truncated and transport never gates operation', function()
  local f=fixture(); f.inputs[1],f.inputs[2]=nil,nil; f.inputs[70],f.inputs[71]='Launchpad X LPX DAW','Launchpad X LPX MIDI'
  function f.r.GetNumMIDIInputs() return 128 end
  f:tick(1.1); f:cc(95,127,70); f:cc(95,0,70); f:tick(); f:target(1)
  eq(f.a.I_RECINPUT,6368)
  for _,state in ipairs({0,1,2,5,6,0}) do
    f.project.play_state = state
    f:tap(6,1); f:tick(); eq(f.engine.owner.track,f.a)
  end
  f.engine:cleanup(); eq(f.a.I_RECINPUT,-1)
end)
test('previously armed MIDI targets always disarm on transfer and cleanup', function()
  local f=fixture(); f.b.I_RECINPUT=5007; f.b.I_RECMON=2; f.b.I_RECARM=1; f.b.B_AUTO_RECARM=0
  f:session(); f:target(3); f:target(1)
  eq(f.b.I_RECINPUT,5007); eq(f.b.I_RECMON,2); eq(f.b.I_RECARM,0); eq(f.b.B_AUTO_RECARM,0)
  f:target(3); f.engine:cleanup(); eq(f.b.I_RECARM,0)
end)

test('pending target becoming audio is rejected without releasing current owner', function()
  local f=fixture(); f:session(); f:target(1)
  f:event(1,0x90,60,90); f:target(2); f.hidden.I_RECINPUT=0
  f:event(1,0x80,60,0); f:tick(); f:tick()
  eq(f.engine.owner.track,f.a); eq(f.hidden.I_RECINPUT,0)
end)

test('Disable and exit restore an actual target and all suppressed routes', function()
  local f=fixture(); f.engine:cleanup(); reaper=f.r
  f.hidden.I_RECINPUT=4133
  dofile('scripts/Launchpad X - Start.lua'); f:pump(); f:pump()
  f:press(95); f:tap(8,1); f:pump(); eq(f.a.I_RECINPUT,4128); eq(f.hidden.I_RECINPUT,-1)
  dofile('scripts/Launchpad X - Disable.lua'); f:pump()
  eq(f.a.I_RECINPUT,-1); eq(f.a.I_RECMON,0); eq(f.a.B_AUTO_RECARM,1); eq(f.hidden.I_RECINPUT,4133)
  dofile('scripts/Launchpad X - Enable.lua'); f:pump(); f:pump()
  f:press(95); f:tap(8,1); f:pump(); eq(f.a.I_RECINPUT,4128)
  for _,fn in ipairs(f.exits) do fn() end
  eq(f.a.I_RECINPUT,-1); eq(f.hidden.I_RECINPUT,4133); eq(f.ext.running,nil)
end)

test('prefixed case variations, unrelated devices and legacy settings', function()
  local f = fixture()
  f.inputs[1] = '20: Launchpad X:Launchpad X LPX MIDI 1 24:0'
  f.inputs[2] = 'hw: LAUNCHPAD X lpx daw 2 (USB)'
  f.outputs[1] = 'client Launchpad X LPX DAW 1:0'
  f.inputs[4] = 'Other LPX MIDI'; f.outputs[4] = 'Other LPX DAW'
  f.inputs[5] = 'Launchpad X LPX MIDIExtra'
  f.ext.note_input, f.ext.control_input, f.ext.control_output = 'wrong', 'wrong', 'wrong'
  f.ext.navigation, f.ext.feedback = 'volume-pan', '0'
  local ports = assert(config.discover(f.r))
  eq(ports.note_input.id, 1); eq(ports.control_input.id, 2); eq(ports.control_output.id, 1)
  f:tick(1.1); f:tick(); f:session(); f:target(1)
  eq(f.a.I_RECARM, 1); eq(f.engine.leds[0x90*128+31], 1)
end)

test('no-alias APIs prefer underlying present names and ignore stale entries', function()
  local f = fixture()
  local inputs, outputs = f.inputs, f.outputs
  function f.r.GetMIDIInputNameNoAlias(id)
    if id == 6 then return false, 'Launchpad X LPX MIDI stale' end
    return inputs[id] ~= nil, inputs[id] or ''
  end
  function f.r.GetMIDIOutputNameNoAlias(id) return outputs[id] ~= nil, outputs[id] or '' end
  function f.r.GetMIDIInputName() error('aliases must not be read') end
  function f.r.GetMIDIOutputName() error('aliases must not be read') end
  local ports = assert(config.discover(f.r)); eq(ports.note_input.id, 1)
  inputs[1] = 'Other'; local missing, err = config.discover(f.r)
  eq(missing, nil); assert(err:find('Missing Note input', 1, true))
  eq(err:find('stale', 1, true), nil)
end)

test('each missing or ambiguous role pauses controls and transfers with candidates', function()
  for _, role in ipairs({'note_input', 'control_input', 'control_output'}) do
    for _, ambiguous in ipairs({false, true}) do
      local f = fixture(); f:session(); f:target(1)
      local ports = assert(config.discover(f.r)); local port = ports[role]
      local list = role == 'control_output' and f.outputs or f.inputs
      if ambiguous then list[4] = 'prefix ' .. port.name .. ' suffix' else list[port.id] = nil end
      f:tap(6,1); f:tap(8,2); f:tick(1.1)
      eq(f.engine.online, false); eq(f.a.B_MUTE,0); eq(f.engine.owner.track, f.a)
      assert(f.logs[#f.logs]:find('candidates:', 1, true))
      if ambiguous then assert(f.logs[#f.logs]:find('4: prefix', 1, true)) end
      local n = #f.sent; f.engine:cleanup(); eq(#f.sent, n); eq(f.a.I_RECINPUT, -1)
    end
  end
  local f = fixture(); f.inputs[1], f.inputs[2] = 'Launchpad X LPX MIDI LPX DAW', nil
  local ports, err = config.discover(f.r); eq(ports, nil)
  assert(err:find('distinct', 1, true))
end)

test('same IDs with changed underlying prefixes reconnect with grace and held safeguards', function()
  for _, held in ipairs({'none', 'note', 'sustain'}) do
    local f = fixture(); f:session(); f:target(1)
    if held == 'note' then f:event(1,0x90,60,90)
    elseif held == 'sustain' then f:cc(64,127,1) end
    f:tick()
    f.inputs[1] = 'new path Launchpad X LPX MIDI'
    f.inputs[2] = 'new path Launchpad X LPX DAW'
    f.outputs[1] = 'new path Launchpad X LPX DAW'
    local n = #f.sent; f:tick(1.1)
    assert(#f.sent > n); eq(f.engine.layout,1)
    eq(f.engine.uncertain, held ~= 'none')
    assert(f.engine.ready_at > f.now); eq(f.engine.owner.track,f.a)
    f.engine:cleanup(); eq(f.a.I_RECINPUT,-1)
  end
end)

test('cleanup resolves changed output IDs without touching unrelated outputs', function()
  local f = fixture(); f.outputs[1] = 'Other'; f.outputs[5] = 'new Launchpad X LPX DAW'
  f.engine:cleanup(); eq(f.sent[#f.sent].id,5); eq(f.sent[#f.sent].msg:byte(8),0)
end)

test('disconnected Start waits with no saved configuration and reconnects', function()
  local f = fixture(); f.engine:cleanup(); reaper=f.r
  f.inputs, f.outputs = {}, {}; dofile('scripts/Launchpad X - Start.lua')
  eq(f.toggle,1); assert(f.ext.running); eq(f.a.I_RECINPUT,-1)
  f.inputs[1], f.inputs[2], f.outputs[1] = 'Launchpad X LPX MIDI','Launchpad X LPX DAW','Launchpad X LPX DAW'
  f.now = f.now + 1; f:pump(); f:pump(); f:press(95); f:tap(8,1); f:pump()
  eq(f.a.I_RECARM,1)
  dofile('scripts/Launchpad X - Disable.lua'); f:pump(); eq(f.a.I_RECARM,0)
end)

test('Install startup works disconnected without configuration', function()
  local f=fixture(); f.inputs,f.outputs={},{}; reaper=f.r
  local resource=assert(os.getenv('LPX_TEST_RESOURCE'))
  function f.r.GetResourcePath() return resource end
  function f.r.RecursiveCreateDirectory() end
  function f.r.AddRemoveReaScript() return 123 end
  dofile('scripts/Launchpad X - Install startup.lua')
  eq(f.ext.enabled,'1'); eq(f.ext.note_input,nil)
  assert(f.logs[#f.logs]:find('Automatic startup installed',1,true))
end)

test('diagnostic monitor discovers ports and reports missing roles', function()
  local f=fixture(); reaper=f.r
  dofile('scripts/Launchpad X - Monitor buttons.lua')
  f:event(1,0x90,60,90); f:event(2,0xB0,95,127); f:pump()
  assert(table.concat(f.logs):find('Note port 1 MIDI 90 3C 5A',1,true))
  assert(table.concat(f.logs):find('DAW port 2 MIDI B0 5F 7F',1,true))
  f.inputs[1]=nil; f:pump()
  assert(table.concat(f.logs):find('Missing Note input',1,true))
end)

test('rows one through five stay dark and never write track state', function()
  local f=fixture(); f:session(); f:target(1)
  local writes=#f.writes
  for row=1,5 do
    for column=1,8 do
      f:tap(row,column)
      eq(f.engine.leds[0x90*128+(9-row)*10+column],0)
    end
  end
  f:tick(); eq(#f.writes,writes); eq(f.engine.owner.track,f.a)
end)

test('changes to each underlying role name trigger reconnect independently', function()
  for _, role in ipairs({'note_input','control_input','control_output'}) do
    local f=fixture(); local ports=assert(config.discover(f.r))
    local list=role == 'control_output' and f.outputs or f.inputs
    list[ports[role].id]='new connection ' .. ports[role].name
    local n=#f.sent; f:tick(1.1); assert(#f.sent>n); assert(f.engine.ready_at>f.now)
  end
end)

test('reopened armed Note route disarms on first transfer and stays dark', function()
  local f=fixture(); f:session(); f:target(2)
  -- Saving captures managed values before exit restores the in-memory project.
  local saved={}
  for _,key in ipairs({'I_RECINPUT','I_RECMON','I_RECARM','B_AUTO_RECARM'}) do
    saved[key]=f.hidden[key]
  end
  f.engine:cleanup()
  for key,value in pairs(saved) do f.hidden[key]=value end
  f.b.I_RECINPUT,f.b.I_RECARM,f.b.I_RECMON=3,1,2
  f.engine=Engine.new(f.r,config); f:tick(); f:tick(); f:session()
  eq(f.engine.owner,nil); eq(f.hidden.I_RECARM,1)
  eq(f.engine.leds[0x90*128+12],49)
  f:event(1,0x90,60,90); f:target(1)
  eq(f.a.I_RECARM,0); eq(f.hidden.I_RECARM,1)
  f:event(1,0x80,60,0); f:tick(); f:tick()
  eq(f.a.I_RECINPUT,4128); eq(f.a.I_RECARM,1)
  eq(f.hidden.I_RECINPUT,-1); eq(f.hidden.I_RECARM,0)
  eq(f.engine.leds[0x90*128+11],49); eq(f.engine.leds[0x90*128+12],0)
  eq(f.b.I_RECINPUT,3); eq(f.b.I_RECARM,1); eq(f.b.I_RECMON,2)
  f:target(2); f:target(1)
  eq(f.hidden.I_RECARM,0); eq(f.engine.leds[0x90*128+12],0)
  f.engine:cleanup(); eq(f.hidden.I_RECARM,0)
end)

test('suppressed direct Note arms stay off on cleanup while other MIDI arms persist', function()
  local f=fixture()
  f.hidden.I_RECINPUT,f.hidden.I_RECARM=4096+32+5,1
  f.b.I_RECINPUT,f.b.I_RECARM=4096+63*32,1
  f.c.I_RECINPUT,f.c.I_RECARM=4096+4*32,1
  f:session(); f:target(1)
  eq(f.hidden.I_RECARM,0); eq(f.b.I_RECARM,1); eq(f.c.I_RECARM,1)
  f.engine:cleanup()
  eq(f.hidden.I_RECINPUT,4096+32+5); eq(f.hidden.I_RECARM,0)
  eq(f.hidden.I_RECMON,0); eq(f.hidden.B_AUTO_RECARM,1)
  eq(f.b.I_RECINPUT,4096+63*32); eq(f.b.I_RECARM,1)
  eq(f.c.I_RECINPUT,4096+4*32); eq(f.c.I_RECARM,1)
end)

test('deleted pending destination preserves the current target', function()
  local f = fixture(); f:session(); f:target(1)
  f:event(1, 0x90, 60, 90); f:target(2)
  f.project.tracks = { f.a, f.b, f.c }
  f:event(1, 0x80, 60, 0); f:tick(); f:tick()
  eq(f.engine.owner.track, f.a); eq(f.engine.requested, f.a)
  eq(f.a.I_RECARM, 1); eq(f.a.I_RECINPUT, 4128)
  f:tick(); eq(f.engine.owner.track, f.a)
end)

test('invalid initial destinations cancel without acquiring a target', function()
  for _, change in ipairs({ 'deleted', 'audio' }) do
    local f = fixture(); f:session()
    f:event(1, 0x90, 60, 90); f:target(2)
    if change == 'deleted' then
      f.project.tracks = { f.a, f.b, f.c }
    else
      f.hidden.I_RECINPUT = 0
    end
    f:event(1, 0x80, 60, 0); f:tick(); f:tick()
    eq(f.engine.owner, nil); eq(f.engine.requested, nil)
    eq(f.a.I_RECARM, 0); eq(f.hidden.I_RECARM, 0)
  end
end)

test('cleanup failures finalize the action and allow Enable to restart', function()
  for _, stage in ipairs({ 'restoration', 'hardware' }) do
    local f = fixture(); f.engine:cleanup(); reaper = f.r
    dofile('scripts/Launchpad X - Start.lua'); f:pump(); f:pump()
    f:press(95); f:tap(8, 1); f:pump()
    local token = f.ext.running
    local setter, sender = f.r.SetMediaTrackInfo_Value, f.r.SendMIDIMessageToHardware
    local attempts = 0
    if stage == 'restoration' then
      f.r.SetMediaTrackInfo_Value = function()
        attempts = attempts + 1
        error('simulated restoration failure')
      end
    else
      f.r.SendMIDIMessageToHardware = function()
        attempts = attempts + 1
        error('simulated hardware failure')
      end
    end
    dofile('scripts/Launchpad X - Disable.lua'); f:pump()
    eq(f.ext.running, nil); eq(f.toggle, 0)
    local logs = table.concat(f.logs)
    assert(logs:find('simulated ' .. stage .. ' failure', 1, true))
    assert(logs:find('stack traceback:', 1, true))
    if stage == 'restoration' then
      assert(logs:find('Track restoration incomplete:', 1, true))
      local last = f.sent[#f.sent].msg
      eq(last:byte(7), 0x10); eq(last:byte(8), 0)
    else
      assert(logs:find('Hardware release failed:', 1, true))
      eq(f.a.I_RECARM, 0); eq(f.a.I_RECINPUT, -1)
    end
    local previous_attempts = attempts
    for _, exit in ipairs(f.exits) do exit() end
    eq(attempts, previous_attempts)
    f.r.SetMediaTrackInfo_Value, f.r.SendMIDIMessageToHardware = setter, sender
    dofile('scripts/Launchpad X - Enable.lua'); f:pump(); f:pump()
    assert(f.ext.running and f.ext.running ~= token); eq(f.toggle, 1)
    dofile('scripts/Launchpad X - Disable.lua'); f:pump()
  end
end)

test('engine cleanup reports both failures and does not retry them', function()
  local f = fixture(); f:session(); f:target(1)
  local attempts = 0
  f.r.SetMediaTrackInfo_Value = function()
    attempts = attempts + 1; error('restoration error')
  end
  f.r.SendMIDIMessageToHardware = function()
    attempts = attempts + 1; error('hardware error')
  end
  local ok, err = f.engine:cleanup()
  eq(ok, false); eq(attempts, 2)
  assert(err:find('restoration error', 1, true))
  assert(err:find('hardware error', 1, true))
  local repeated_ok, repeated_err = f.engine:cleanup()
  eq(repeated_ok, false); eq(repeated_err, err); eq(attempts, 2)
end)

test('runtime error remains visible when cleanup also fails', function()
  local f = fixture(); f.engine:cleanup(); reaper = f.r
  dofile('scripts/Launchpad X - Start.lua'); f:pump(); f:pump()
  f:press(95); f:tap(8, 1); f:pump()
  f.r.MIDI_GetRecentInputEvent = function() error('original tick failure') end
  f.r.SetMediaTrackInfo_Value = function() error('secondary cleanup failure') end
  f:pump()
  eq(f.ext.running, nil); eq(f.toggle, 0)
  local logs = table.concat(f.logs)
  assert(logs:find('original tick failure', 1, true))
  assert(logs:find('secondary cleanup failure', 1, true))
end)

test('action finalizes even when engine cleanup unexpectedly throws', function()
  local f = fixture(); f.engine:cleanup(); reaper = f.r
  local original_dofile = dofile
  dofile = function(path)
    local module = original_dofile(path)
    if path:match('launchpad/engine%.lua$') then
      module.cleanup = function() error('unexpected cleanup exception') end
    end
    return module
  end
  local started, err = pcall(function() original_dofile('scripts/Launchpad X - Start.lua') end)
  dofile = original_dofile
  assert(started, err)
  dofile('scripts/Launchpad X - Disable.lua'); f:pump()
  eq(f.ext.running, nil); eq(f.toggle, 0)
  assert(table.concat(f.logs):find('unexpected cleanup exception', 1, true))
  for _, exit in ipairs(f.exits) do exit() end
end)

local function transport_led(f, key, color, effect)
  local id = 0xB0 * 128 + key
  eq(f.engine.leds[id], color, 'LED color for CC ' .. key)
  eq(f.engine.led_effects[id], effect or 0, 'LED effect for CC ' .. key)
  for i = #f.sent, 1, -1 do
    local message = f.sent[i].msg
    if #message == 3 and message:byte(2) == key then
      eq(message:byte(1), 0xB0 | (effect or 0)); eq(message:byte(3), color)
      return
    end
  end
  error('No LED message for CC ' .. key)
end

test('Pan plays pauses and resumes once per press including recording', function()
  local f = fixture(); f:session()
  f:cc(79); f:cc(79); f:tick()
  eq(f.project.play_state, 1); eq(#f.transport_calls, 1)
  f:cc(79, 0); f:press(79); f:tick()
  eq(f.project.play_state, 2); eq(f.transport_calls[2].name, 'pause')
  f:press(79); f:tick(); eq(f.project.play_state, 1)
  f.project.play_state = 5
  f:press(79); f:tick(); eq(f.project.play_state, 6)
  f:press(79); f:tick(); eq(f.project.play_state, 5)
  for _, call in ipairs(f.transport_calls) do eq(call.project, f.project) end
  eq(f.mono, nil)
end)

test('Volume records and punches out without changing track routing', function()
  local f = fixture(); f:session(); f:target(1)
  local writes = #f.writes
  f:cc(89); f:cc(89); f:tick()
  eq(f.project.play_state, 5); eq(#f.transport_calls, 1)
  f:cc(89, 0); f:press(89); f:tick()
  eq(f.project.play_state, 1); eq(#f.transport_calls, 2)
  eq(f.engine.owner.track, f.a); eq(f.a.I_RECARM, 1); eq(#f.writes, writes)
  f:press(98); f:press(69); f:press(93); f:press(94); f:tick()
  eq(#f.transport_calls, 2)
end)

test('Send B only goes to start when stopped away from start and never stops transport', function()
  local f = fixture(); f:session(); f:target(1)
  f:event(1, 0x90, 60, 90); f:target(2)
  f.project.play_state, f.project.cursor = 5, 12
  f:press(49); f:tick()
  eq(f.project.play_state, 0); eq(f.project.cursor, 12)
  eq(f.engine.owner.track, f.a); eq(f.engine.requested, f.hidden); eq(f.engine.held, 1)
  f.project.play_state = 5
  f:press(59); f:tick()
  eq(f.project.play_state, 5); eq(f.project.cursor, 12); eq(#f.transport_calls, 1)
  f.project.play_state = 0
  f:press(59); f:tick()
  eq(f.project.cursor, 0); eq(f.transport_calls[2].name, 'cursor')
  eq(f.engine.owner.track, f.a); eq(f.engine.requested, f.hidden); eq(f.a.I_RECARM, 1)
  for _, state in ipairs({0, 1, 2, 5, 6}) do
    for _, cursor in ipairs({0, 0.001, 12}) do
      f.project.play_state, f.project.cursor = state, cursor
      local calls = #f.transport_calls
      f:cc(59); f:cc(59); f:tick(); f:cc(59, 0); f:tick()
      if state == 0 and cursor > 0.001 then
        eq(#f.transport_calls, calls + 1); eq(f.project.cursor, 0)
      else
        eq(#f.transport_calls, calls); eq(f.project.cursor, cursor)
      end
      eq(f.project.play_state, state)
      transport_led(f, 59, 0)
    end
  end
end)

test('Solo toggles repeat and Record Arm toggles mono independently of grid solo', function()
  local f = fixture(); f:session()
  transport_led(f, 29, 1); transport_led(f, 19, 1)
  f:press(29); f:tick(); eq(f.project.repeat_on, 1); transport_led(f, 29, 19)
  f:press(19); f:tap(7, 1); f:tick()
  eq(f.mono, true); transport_led(f, 19, 9)
  eq(f.a.I_SOLO, 1); eq(f.engine.leds[0x90 * 128 + 21], 9)
  eq(f.engine.leds[0x90 * 128 + 22], 1); eq(f.engine.leds[0x90 * 128 + 28], 0)
  f:press(29); f:press(19); f:tap(7, 1); f:tick()
  eq(f.project.repeat_on, 0); transport_led(f, 29, 1)
  eq(f.mono, false); transport_led(f, 19, 1)
  eq(f.engine.leds[0x90 * 128 + 21], 1)
  f.project.repeat_on = 1; f:tick(); transport_led(f, 29, 19)
end)

test('transport LEDs follow state cursor tolerance and animation changes', function()
  local f = fixture(); f:session()
  local cases = {
    { state = 0, cursor = 0, play = 19, stop = 0, start = 0 },
    { state = 0, cursor = 12, play = 19, stop = 0, start = 3 },
    { state = 1, cursor = 0, play = 19, pulse = 2, stop = 3, start = 0 },
    { state = 2, cursor = 0, play = 9, stop = 3, start = 0 },
    { state = 5, cursor = 0, play = 19, pulse = 2, record = 2, stop = 3, start = 0 },
    { state = 6, cursor = 0, play = 9, record = 2, stop = 3, start = 0 },
    { state = 0, cursor = 0.001, play = 19, stop = 0, start = 0 },
    { state = 0, cursor = 0.0011, play = 19, stop = 0, start = 3 },
  }
  for _, case in ipairs(cases) do
    f.project.play_state, f.project.cursor = case.state, case.cursor; f:tick()
    transport_led(f, 79, case.play, case.pulse)
    transport_led(f, 89, 5, case.record)
    transport_led(f, 49, case.stop); transport_led(f, 59, case.start)
    local sent = #f.sent; f:tick(); eq(#f.sent, sent)
  end
  f.project.play_state = 1; f:tick()
  f.project.play_state = 0
  local sent = #f.sent; f:tick()
  local clear, steady = f.sent[sent + 1].msg, f.sent[sent + 2].msg
  eq(clear, string.char(0xB2, 79, 0)); eq(steady, string.char(0xB0, 79, 19))
end)

test('transport controls and LED writes are gated in Note and Custom modes', function()
  local f = fixture()
  local keys = { 89, 79, 29, 49, 59 }
  for _, sent in ipairs(f.sent) do
    if #sent.msg == 3 then
      for _, key in ipairs(keys) do assert(sent.msg:byte(2) ~= key) end
    end
  end
  for _, mode in ipairs({ 96, 97 }) do
    f:press(mode); f:tick()
    local sent = #f.sent
    for _, key in ipairs(keys) do f:press(key) end
    f.project.play_state = 5; f:tick()
    eq(#f.transport_calls, 0); eq(#f.sent, sent)
  end
  f:session(); transport_led(f, 89, 5, 2); transport_led(f, 79, 19, 2)
  for _, key in ipairs(keys) do
    f:event(0, 0xB0, key, 127); f:event(2, 0xB1, key, 127)
  end
  f:tick(); eq(#f.transport_calls, 0)
  f.inputs[1] = nil
  for _, key in ipairs(keys) do f:press(key) end
  f:tick(1.1); eq(#f.transport_calls, 0)
end)

test('transport reentry and reconnect repaint current external state', function()
  local f = fixture(); f:session(); f.project.play_state = 5; f:tick()
  f:press(96); f:tick(); f.project.play_state = 0; f:session()
  transport_led(f, 79, 19); transport_led(f, 89, 5)
  f.inputs[1] = nil; f:tick(1.1)
  f.inputs[1] = 'Launchpad X LPX MIDI'; f.project.play_state = 5; f:tick(1.1)
  f:session(); transport_led(f, 79, 19, 2); transport_led(f, 89, 5, 2)
end)

test('transport ignores a new project while held notes defer project cleanup', function()
  local f = fixture(); f:session(); f:target(1)
  f:event(1, 0x90, 60, 90); f:tick()
  local new = { tracks = { f.b }, play_state = 0, cursor = 12, repeat_on = 0 }
  f.projects[2], f.active = new, new
  for _, key in ipairs({ 89, 79, 29, 49, 59 }) do f:press(key) end
  f:tick(); eq(#f.transport_calls, 0)
  f:event(1, 0x80, 60, 0); f:tick(); f:tick()
  f:press(79); f:tick()
  eq(new.play_state, 1); eq(f.transport_calls[1].project, new); eq(f.project.play_state, 0)
end)

test('capability checks cover every new transport API', function()
  for _, name in ipairs({ 'GetPlayStateEx', 'OnPlayButtonEx', 'OnPauseButtonEx', 'OnStopButtonEx',
    'Main_OnCommandEx', 'GetSetRepeatEx', 'GetCursorPositionEx', 'SetEditCurPos2' }) do
    local f = fixture(); f.r[name] = nil
    local ok, err = config.check(f.r)
    eq(ok, nil); assert(err:find(name, 1, true))
  end
end)

print(string.format('%d tests passed.',count))
