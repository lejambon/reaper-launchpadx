# Launchpad X for REAPER

Dependency-free Lua integration with native Note mode for playing and Session as an eight-track mixer. Columns follow project tracks 1–8, including hidden tracks; rows count from the top. Mouse selection is independent; there is no banking.

| Control | Action / feedback |
| --- | --- |
| Rows 1–5 | Unassigned, dark |
| Row 6 | Mute: red when muted, white when unmuted |
| Row 7 | Solo: amber |
| Row 8 | Audio input: toggle arm, pink; MIDI/no input: toggle exclusive Note target and arm, purple |
| Right Mute | Master mute: red when muted, white when unmuted |
| Right Pan | Master mono L+R: blue; stereo: white |

Missing tracks, inactive solo and unarmed tracks are dark. Other Session controls are unassigned.

1. Copy the complete `scripts` directory to a permanent location.
2. In REAPER MIDI Preferences, enable Launchpad X **LPX MIDI** for Note input, **LPX DAW** input for control only, and **LPX DAW** output.
3. Load and run **Launchpad X - Install startup.lua** to register actions and preserve existing startup code. Installation works with the device disconnected.
4. Release all pads and run **Enable** (no target is selected automatically). Switch to Session and press row 8 on an instrument track, then return to Note to play.

Ports are discovered automatically; no IDs or saved port configuration are needed. Connect one Launchpad X. Missing or ambiguous ports pause controls and transfers until discovery succeeds. **Configure** reports detected ports and required MIDI preferences.

Row 8 activates a Note target, transfers to another target, or shuts down the active target. Transfers and shutdown wait for notes/sustain to release plus an audio grace period. Press the pending destination or the target awaiting shutdown again to cancel. LEDs show actual arm state during the wait.

An active Note target receives all Note channels with monitoring and record arm enabled. Other direct Launchpad and All MIDI Inputs routes across the project are temporarily suppressed, including tracks beyond column 8; this also blocks other controllers on All MIDI Inputs tracks. Audio-input tracks only toggle arm and leave the Note target unchanged.

Release all pads before **Disable**. It restores temporary routing, monitoring and automatic-arm settings and disarms all Note targets, even those armed before Enable. Disable persists across restarts; **Enable** resumes. Audio arm edits, mute, solo and master changes persist. Transport Stop leaves the integration active. Project switches wait for releases, restore the previous project and start without a target.

If a connection changes while notes/sustain are held, a playing track is deleted or MIDI history is lost, transfers suspend: release pads, run **Disable**, then **Enable**. **Monitor buttons** prints detected-port MIDI events for 60 seconds to help diagnose controls.

Disable before saving to store original routing. To remove automatic startup, Disable and delete only the marked Launchpad block in REAPER's `Scripts/__startup.lua`; preserve unrelated startup code.
