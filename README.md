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
| Send B | Go to project start, only when stopped and away from start | Bright white when available; off otherwise |
| Stop Clip | Stop transport | Bright white when available; off when stopped |
| Mute | Master mute | Red when muted; dim white otherwise |
| Solo | Toggle repeat using REAPER's current loop range | Green when on; dim white when off |
| Record Arm | Master mono L+R | Amber when mono; dim white when stereo |

Grid row 6 toggles track mute: red when on, dim white when off. Grid row 7 toggles track solo: amber when on, dim white when off, and dark for missing tracks. Send A, Capture MIDI and the directional buttons are unassigned; grid rows 1–5 remain dark.

Transport controls work only in Session, act immediately even with held notes, and preserve the active Note target. Stop Clip follows REAPER's native Stop behavior and recording prompts, including returning to the playback starting position; it remains functional when its LED is off. Send B never stops transport: it moves the edit cursor to project time zero only when already stopped and more than 1 ms away from zero. While playing, paused, recording, or already at start, Send B is off and does nothing. Recording uses already armed tracks and REAPER's recording modes and count-in. Pulsing uses the Launchpad's hardware timing; no MIDI clock is generated.

An active Note target receives all Note channels with monitoring and record arm enabled. Other direct Launchpad and All MIDI Inputs routes across the project are temporarily suppressed, including tracks beyond column 8; this also blocks other controllers on All MIDI Inputs tracks. Previously armed direct Note routes (including those saved in a reopened project) also disarm when another target activates. Audio-input tracks only toggle arm and leave the Note target unchanged.
