local directory = debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])')
local config = dofile(directory .. 'launchpad/config.lua')
config.set(reaper, 'enabled', 1)
-- If Disable and Enable are run back-to-back, wait for the old instance's cleanup.
local function start()
  if config.get(reaper, 'enabled') == '0' then return end
  if config.get(reaper, 'running') ~= '' and config.get(reaper, 'stop') ~= '' then
    reaper.defer(start)
  elseif config.get(reaper, 'running') == '' then
    dofile(directory .. 'Launchpad X - Start.lua')
  end
end
start()
