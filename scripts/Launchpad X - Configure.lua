local directory = debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])')
local config = dofile(directory .. 'launchpad/config.lua')
local ok, problem = config.check(reaper)
if not ok then reaper.MB(problem, 'Launchpad X', 0); return end
local ports, diagnostic = config.discover(reaper)
reaper.ShowConsoleMsg('\nLaunchpad X automatic discovery:\n' .. diagnostic .. '\n')
reaper.MB((ports and 'Launchpad X ports detected automatically.' or 'Waiting for Launchpad X ports.')
  .. '\n\n' .. diagnostic
  .. '\n\nIn REAPER MIDI Preferences, enable LPX MIDI for Note input, LPX DAW input for control only, and LPX DAW output. Only one Launchpad X is supported. No port settings are saved.',
  'Launchpad X', 0)
