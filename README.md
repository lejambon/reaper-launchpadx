# Launchpad X for REAPER

Dependency-free Lua integration with native Note mode for playing and Session as an eight-track mixer. Columns follow project tracks 1–8, including hidden tracks.

![Launchpad X Session mixer button mappings](assets/launchpad-x-mappings.svg)

1. Copy the complete `scripts` directory to a permanent location.
2. In REAPER MIDI Preferences, enable Launchpad X **LPX MIDI** for Note input, **LPX DAW** input for control only, and **LPX DAW** output.
3. Load and run **Launchpad X - Install startup.lua** to register actions and preserve existing startup code. Installation works with the device disconnected.
4. Release all pads and run **Enable** (no target is selected automatically). Switch to Session and press row 8 on an instrument track, then return to Note to play.

Ports are discovered automatically; no IDs or saved port configuration are needed. Connect one Launchpad X. Missing or ambiguous ports pause controls and transfers until discovery succeeds. **Configure** reports detected ports and required MIDI preferences.

Row 8 activates a Note target, transfers to another target, or shuts down the active target. Transfers and shutdown wait for notes/sustain to release plus an audio grace period. Press the pending destination or the target awaiting shutdown again to cancel. LEDs show actual arm state during the wait.

Session side buttons control transport and master settings:

| Button label | Function | LED feedback |
| --- | --- | --- |
| Volume | Record; press again to punch out and continue playback | Red; pulses while recording |
| Pan | Play / pause / resume | Green; pulses while playing; amber when paused |
| Send B | Stop and go to project start | White; dim only when stopped within 1 ms of project start |
| Stop Clip | Stop transport | White; dim when already stopped |
| Mute | Master mute | Red when muted; white otherwise |
| Solo | Toggle repeat using REAPER's current loop range | Green when on; white when off |
| Record Arm | Master mono L+R | Amber when mono; white when stereo |

Grid row 7 toggles track solo: amber when on, white when off, and dark for missing tracks. Send A, Capture MIDI and the directional buttons are unassigned; grid rows 1–5 remain dark.

Transport controls work only in Session, act immediately even with held notes, and preserve the active Note target. Dimmed buttons remain functional. Stop follows REAPER's native behavior and recording prompts; Send B moves the edit cursor to project time zero only after transport stops. Recording uses already armed tracks and REAPER's recording modes and count-in. Pulsing uses the Launchpad's hardware timing; no MIDI clock is generated.

An active Note target receives all Note channels with monitoring and record arm enabled. Other direct Launchpad and All MIDI Inputs routes across the project are temporarily suppressed, including tracks beyond column 8; this also blocks other controllers on All MIDI Inputs tracks. Previously armed direct Note routes (including those saved in a reopened project) also disarm when another target activates. Audio-input tracks only toggle arm and leave the Note target unchanged.
