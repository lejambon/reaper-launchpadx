local directory = debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])')
local config = dofile(directory .. 'launchpad/config.lua')
local ok, problem = config.check(reaper)
if not ok then reaper.MB(problem, 'Launchpad X', 0); return end
if config.get(reaper, 'enabled') == '0' then return end
if config.get(reaper, 'running') ~= '' then return end
local Engine = dofile(directory .. 'launchpad/engine.lua')
local token = tostring(reaper.time_precise()) .. ':' .. tostring({})
local engine = Engine.new(reaper, config)
config.set(reaper, 'running', token, false)
config.set(reaper, 'stop', '', false)
local _, _, section, action = reaper.get_action_context()
reaper.SetToggleCommandState(section, action, 1)
reaper.RefreshToolbar2(section, action)
local cleaned = false
local function cleanup()
  if cleaned then return end
  local called, success, cleanup_error = xpcall(function() return engine:cleanup() end, debug.traceback)
  if not called then cleanup_error = success end
  if config.get(reaper, 'running') == token then
    reaper.DeleteExtState(config.section, 'running', false)
  end
  reaper.SetToggleCommandState(section, action, 0)
  reaper.RefreshToolbar2(section, action)
  cleaned = true
  if not called or not success then
    reaper.ShowConsoleMsg('Launchpad X cleanup failed:\n' .. cleanup_error .. '\n')
  end
end
reaper.atexit(cleanup)
local function tick()
  if config.get(reaper, 'enabled') == '0' or config.get(reaper, 'stop') == token then
    cleanup(); return
  end
  local success, err = xpcall(function() engine:tick() end, debug.traceback)
  if not success then
    cleanup()
    reaper.ShowConsoleMsg('Launchpad X stopped after an error:\n' .. err .. '\n')
    return
  end
  reaper.defer(tick)
end
tick()
