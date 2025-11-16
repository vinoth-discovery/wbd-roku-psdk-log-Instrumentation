# PSDK Event Monitor

## Overview

The PSDK Event Monitor is a Stage 2 feature that automatically opens a separate terminal window to display **only PSDK:: events** from your Roku log capture session. This provides a focused view of PSDK-specific activity while the main terminal shows all logs.

## How It Works

When you run `psdk-instrument`:

```bash
psdk-instrument 192.168.50.81
```

**Two terminals automatically open:**

1. **Main Terminal (current)**:
   - Shows ALL Roku logs
   - PSDK events highlighted in yellow
   - Saves everything to `.temp/<session_id>/`

2. **Monitor Terminal (new window)**:
   - Shows ONLY lines containing `PSDK::`
   - Filters in real-time
   - Displayed in white (default color)
   - **Tracks nested sessions** with visual hierarchy:
     - 🎬 **Player Session** (magenta header/red footer)
       - ▶️ **Playback Session #1** (cyan header/yellow footer)
       - ▶️ **Playback Session #2** (cyan header/yellow footer)
       - ▶️ **Playback Session #N** (cyan header/yellow footer)

## Usage

### Enable Monitor (Default)

```bash
# Automatically opens monitor terminal
psdk-instrument 192.168.50.81
```

### Disable Monitor

```bash
# Single terminal only (no monitor)
psdk-instrument 192.168.50.81 --no-monitor
```

### With Other Options

```bash
# Monitor + duration
psdk-instrument 192.168.50.81 --duration 300

# Monitor + description
psdk-instrument 192.168.50.81 --description "Testing playback"

# No monitor + options
psdk-instrument 192.168.50.81 --duration 300 --no-monitor
```

## Terminal Layout Examples

### Dual Terminal Mode (Default)

```
┌─────────────────────────────────┐  ┌─────────────────────────────────┐
│    Main Terminal (ALL LOGS)     │  │  Monitor Terminal (PSDK ONLY)   │
├─────────────────────────────────┤  ├─────────────────────────────────┤
│ [INFO] Starting app...          │  │ ╔═══════════════════════════╗   │
│ [DEBUG] Network ready           │  │ ║ 🎬 PLAYER SESSION STARTED ║   │
│ INFO: PlayerSDK...Builder: new  │  │ ║ Time: 15:01:47            ║   │
│ PSDK::playbackInitiatedEvent    │  │ ╚═══════════════════════════╝   │
│ PSDK::Initialize()              │  │   ┌─────────────────────────┐   │
│ [INFO] Memory: 512MB            │  │   │ ▶️  PLAYBACK #1 STARTED │   │
│ PSDK::LoadConfig()              │  │   │ ID: 5b54b105-e336-...   │   │
│ [WARN] Cache miss               │  │   └─────────────────────────┘   │
│ PSDK::StartPlayback()           │  │ PSDK::playbackInitiatedEvent    │
│ [DEBUG] Buffer: 2048KB          │  │ PSDK::Initialize()              │
│ PSDK::OnEvent(PLAYING)          │  │ PSDK::LoadConfig()              │
│ ...                             │  │ PSDK::StartPlayback()           │
│ PSDK::playbackSessionEndEvent   │  │   ┌─────────────────────────┐   │
│ [INFO] Starting next video...   │  │   │ ⏹️  PLAYBACK #1 ENDED   │   │
│ PSDK::playbackInitiatedEvent    │  │   │ Duration: 31s | Evt: 78 │   │
│ PSDK::StartPlayback()           │  │   └─────────────────────────┘   │
│ ...                             │  │   ┌─────────────────────────┐   │
│ PSDK::playbackSessionEndEvent   │  │   │ ▶️  PLAYBACK #2 STARTED │   │
│ PSDK::playerSessionEndEvent     │  │   │ ID: b70514d1-4803-...   │   │
│ [INFO] Cleanup...               │  │   └─────────────────────────┘   │
│                                 │  │ PSDK::playbackInitiatedEvent    │
│                                 │  │ ...                             │
│                                 │  │   ┌─────────────────────────┐   │
│                                 │  │   │ ⏹️  PLAYBACK #2 ENDED   │   │
│                                 │  │   │ Duration: 7s | Evt: 45  │   │
│                                 │  │   └─────────────────────────┘   │
│                                 │  │ ╔═══════════════════════════╗   │
│                                 │  │ ║ 🛑 PLAYER SESSION ENDED   ║   │
│                                 │  │ ║ Duration: 72s             ║   │
│                                 │  │ ║ Playback Sessions: 2      ║   │
│                                 │  │ ║ Total PSDK Events: 234    ║   │
└─────────────────────────────────┘  ╚═══════════════════════════╝   │
       ↓ Saves to .temp/
```

### Single Terminal Mode (--no-monitor)

```
┌─────────────────────────────────┐
│    Main Terminal (ALL LOGS)     │
├─────────────────────────────────┤
│ [INFO] Starting app...          │
│ [DEBUG] Network ready           │
│ PSDK::Initialize()  ← highlighted│
│ [INFO] Memory: 512MB            │
│ PSDK::LoadConfig()  ← highlighted│
│ [WARN] Cache miss               │
│ PSDK::StartPlayback() ← highlighted│
│ [DEBUG] Buffer: 2048KB          │
│ PSDK::OnEvent(PLAYING) ← highlighted│
│                                 │
└─────────────────────────────────┘
       ↓ Saves to .temp/
```

## Benefits

### Why Use the Monitor?

1. **Focused View**: See only PSDK events without noise
2. **Dual Context**: Keep both full logs and filtered view visible
3. **Debugging**: Quickly spot PSDK event sequences
4. **Performance**: Independent terminal doesn't slow main capture
5. **Flexible**: Easy to enable/disable with `--monitor`/`--no-monitor`

### Use Cases

- **Development**: Monitor PSDK API calls while debugging
- **Testing**: Verify PSDK event sequences during playback tests
- **Troubleshooting**: Isolate PSDK issues from general logs
- **Documentation**: Record PSDK behavior for documentation

## Monitor Terminal Features

### Header Display

When the monitor terminal opens, you'll see:

```
═══════════════════════════════════════════════════
  PSDK Event Monitor - Real-time PSDK:: Events
═══════════════════════════════════════════════════

📊 Monitoring: .temp/20251116_133206/roku_logs_20251116_133206.log
🔍 Filter: PSDK:: events only

───────────────────────────────────────────────────
```

### Real-Time Filtering

The monitor uses `tail -f` to follow the log file in real-time and filters for lines containing `PSDK::`:

```bash
# Behind the scenes
tail -f .temp/<session_id>/roku_logs_<timestamp>.log | grep "PSDK::"
```

### Color Display

All PSDK events are displayed in **white** (default terminal color) for clear readability.

### Session Hierarchy Tracking

The monitor automatically tracks nested session hierarchy:

#### Player Session (Level 1)

**Player Creation:**
- Detected by pattern: `PlayerSDK.Core.PlayerBuilder: new`
- Displays magenta header with timestamp
- Resets playback session counter
- Starts counting all PSDK events

**Player Destruction:**
- Detected by pattern: `playerSessionEndEvent` (Note: Different from playbackSessionEndEvent)
- Displays red footer with:
  - Player session duration
  - Total playback sessions count
  - Total PSDK events count across all playbacks

#### Playback Session (Level 2 - Nested within Player)

**Playback Initiated:**
- Detected by pattern: `playbackInitiatedEvent`
- Displays indented cyan header with:
  - Playback number (e.g., #1, #2, #3)
  - Playback session ID
  - Start time
- Counts PSDK events for this specific playback

**Playback Ended:**
- Detected by pattern: `playbackSessionEndEvent`
- Displays indented yellow footer with:
  - Playback session ID
  - Playback duration
  - PSDK events count for this playback only

**Key Points:**
- Multiple playback sessions can occur within one player session
- Each playback is numbered sequentially (#1, #2, #3, etc.)
- Events are counted both per-playback and per-player session
- Visual indentation shows hierarchy

**Configuration:**
All patterns are configurable in `config/monitor_config.json` for easy updates if SDK event names change.

## Managing the Monitor Terminal

### Closing the Monitor

- **Manual**: Close the Terminal window (⌘+W on macOS)
- **Automatic**: Monitor exits when log file stops updating
- **No cleanup needed**: Terminal handles cleanup automatically

### Repositioning Windows

You can freely:
- Resize both terminal windows
- Move them to different displays
- Use split-screen view (macOS)
- Minimize/hide the monitor if not needed

## Troubleshooting

### Monitor Doesn't Open

**Problem**: Second terminal window doesn't appear

**Solutions**:
1. Check Terminal.app permissions (macOS System Settings → Privacy)
2. Try running with `--no-monitor` then manually:
   ```bash
   ./scripts/monitor_psdk_events.sh .temp/<session_id>/roku_logs_<timestamp>.log
   ```
3. Verify monitor script exists: `ls scripts/monitor_psdk_events.sh`

### Monitor Shows No Events

**Problem**: Monitor terminal is blank

**Reasons**:
1. No PSDK events have occurred yet (wait for activity)
2. Log file hasn't started recording (wait for connection)
3. Logs don't contain "PSDK::" pattern

**Check**:
```bash
# Verify PSDK events in log file
grep "PSDK::" .temp/*/roku_logs_*.log
```

### Monitor Not Filtering

**Problem**: Shows all logs instead of just PSDK

**Solution**:
- This shouldn't happen with the built-in monitor
- If using custom grep, ensure pattern is: `grep "PSDK::"`

## Manual Monitor Usage

You can also run the monitor script manually on existing log files:

```bash
# Monitor an existing log file
./scripts/monitor_psdk_events.sh .temp/20251116_133206/roku_logs_20251116_133206.log

# Monitor the latest log file
LOG_FILE=$(ls -t .temp/*/roku_logs_*.log | head -1)
./scripts/monitor_psdk_events.sh "$LOG_FILE"
```

## Configuration

### Updating Player Lifecycle Patterns

The monitor uses configurable patterns to detect player creation and destruction. If Roku SDK updates event names, you can easily update them.

**Configuration file:** `config/monitor_config.json`

```json
{
  "player_lifecycle": {
    "creation_pattern": "PlayerSDK.Core.PlayerBuilder: new",
    "destruction_pattern": "playerSessionEndEvent",
    "description": "Patterns to detect player creation and destruction events"
  },
  "playback_lifecycle": {
    "initiation_pattern": "playbackInitiatedEvent",
    "end_pattern": "playbackSessionEndEvent",
    "description": "Patterns to detect playback session start and end within player sessions"
  },
  "display": {
    "show_headers": true,
    "show_footers": true,
    "show_session_summary": true,
    "show_playback_headers": true
  }
}
```

**To update patterns:**

1. Edit `config/monitor_config.json`
2. Change `creation_pattern` or `destruction_pattern`
3. Save the file
4. Next `psdk-instrument` run will use new patterns

**Example: If event names change**

```json
{
  "player_lifecycle": {
    "creation_pattern": "PlayerSDK.V2.Builder: create",
    "destruction_pattern": "playerTerminatedEvent"
  },
  "playback_lifecycle": {
    "initiation_pattern": "playbackStartedEvent",
    "end_pattern": "playbackFinishedEvent"
  }
}
```

**Pattern Details:**
- `player_lifecycle.creation_pattern`: Marks the start of a player instance
- `player_lifecycle.destruction_pattern`: Marks the end of a player instance (NOT playback)
- `playback_lifecycle.initiation_pattern`: Marks the start of a playback within player
- `playback_lifecycle.end_pattern`: Marks the end of a playback session

**Important:** `playerSessionEndEvent` and `playbackSessionEndEvent` are different events!

**Note:** Requires `jq` command-line tool for JSON parsing. Falls back to defaults if `jq` not installed.

### Install jq (optional)

```bash
# macOS
brew install jq

# Verify
jq --version
```

## Advanced: Custom Filtering

Want to filter for other patterns? Copy and modify the monitor script:

```bash
# Create custom filter
cp scripts/monitor_psdk_events.sh scripts/monitor_errors.sh

# Edit to filter for errors instead
# Change: if [[ "$line" == *"PSDK::"* ]]; then
# To:     if [[ "$line" == *"ERROR"* ]]; then
```

## Platform Notes

### macOS (Current Support)

- Uses `osascript` to launch Terminal.app
- Requires Terminal.app automation permissions
- Works with default macOS Terminal

### Linux (Future Support)

Will support common terminal emulators:
- gnome-terminal
- konsole
- xterm

### Windows (Future Support)

Will support:
- Windows Terminal
- Command Prompt
- PowerShell

## Best Practices

1. **Keep Both Visible**: Arrange terminals side-by-side for best debugging experience
2. **Use `--no-monitor` for Scripts**: When automating, disable monitor to avoid popup windows
3. **Monitor Long Sessions**: Especially useful for long captures to track PSDK activity
4. **Save Layout**: macOS Terminal can save window arrangements for future sessions

## Examples

### Standard Development Session

```bash
# Start with monitor (default)
psdk-instrument 192.168.50.81

# Arrange windows side-by-side
# Main: Left half of screen
# Monitor: Right half of screen

# Develop and test your Roku app
# Watch PSDK events in real-time on the right
```

### Automated Testing (No Monitor)

```bash
# Disable monitor for automation
psdk-instrument 192.168.50.81 --duration 600 --no-monitor

# Process logs after capture
grep "PSDK::" .temp/*/roku_logs_*.log > psdk_events.txt
```

### Quick PSDK Check

```bash
# Capture for 1 minute with monitor
psdk-instrument 192.168.50.81 --duration 60

# Watch PSDK events in monitor terminal
# Stop early with Ctrl+C if you see what you need
```

## See Also

- [Quick Start Guide](1_QUICKSTART.md) - Getting started
- [Telnet Usage](3_TELNET_USAGE.md) - Advanced telnet operations
- [Viewing Logs](4_VIEWING_LOGS.md) - Log viewing options
- [Examples](../examples/) - Code examples

---

**Have feedback or suggestions?** Let us know how we can improve the PSDK Monitor!

