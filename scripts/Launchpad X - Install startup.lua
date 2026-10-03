local directory = debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])')
local config = dofile(directory .. 'launchpad/config.lua')
local ok, problem = config.check(reaper)
if not ok then reaper.MB(problem, 'Launchpad X', 0); return end
local success, err = xpcall(function()
  reaper.RecursiveCreateDirectory(reaper.GetResourcePath() .. '/Scripts', 0)
  local startup = dofile(directory .. 'launchpad/startup.lua')
  local path = startup.install(reaper.GetResourcePath(), directory .. 'Launchpad X - Start.lua')
  for _, name in ipairs({ 'Start', 'Enable', 'Disable', 'Configure', 'Monitor buttons', 'Install startup' }) do
    assert(reaper.AddRemoveReaScript(true, 0, directory .. 'Launchpad X - ' .. name .. '.lua', true) ~= 0,
      'Could not register action: ' .. name)
  end
  config.set(reaper, 'enabled', 1)
  reaper.MB('Automatic startup installed at:\n' .. path
    .. '\n\nExisting startup code is preserved. Run Enable now, or restart REAPER with pads released. Disable persists across restarts.',
    'Launchpad X', 0)
end, debug.traceback)
if not success then reaper.MB(err, 'Launchpad X installation failed', 0) end
