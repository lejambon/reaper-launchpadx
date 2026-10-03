local directory = debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])')
local config = dofile(directory .. 'launchpad/config.lua')
config.set(reaper, 'enabled', 0)
config.set(reaper, 'stop', config.get(reaper, 'running'), false)
-- The running instance restores its snapshots and returns the device to Standalone.
