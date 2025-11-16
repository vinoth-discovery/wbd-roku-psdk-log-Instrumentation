# Package Installation & Usage Guide

> **For users who want to install and use this tool as a Python package** (without cloning the source code)

## Prerequisites

- Python 3.8 or higher
- pip
- macOS (for dual-terminal monitoring feature)

## Installation

### Option 1: Install from PyPI (Recommended)

```bash
pip install wbd-roku-psdk-log-instrument
```

### Option 2: Install from Git Repository

```bash
pip install git+https://github.com/your-org/wbd-roku-psdk-log-instrument.git
```

### Option 3: Install from Wheel File

```bash
pip install wbd_roku_psdk_log_instrument-0.1.0-py3-none-any.whl
```

## Quick Start

### 1. Find Your Roku IP Address

**On your Roku device:**
- Navigate to: **Settings → Network → About**
- Note the IP address (e.g., `192.168.1.100`)

### 2. Test Connection

```bash
roku-log-instrument telnet test <ROKU_IP>
```

Example:
```bash
roku-log-instrument telnet test 192.168.50.81
```

Expected output:
```
Testing connection to 192.168.50.81:8085...
✓ Connection successful!
```

### 3. Start Capturing Logs

**⭐ Recommended Method: Single Command**

```bash
psdk-instrument <ROKU_IP>
```

Example:
```bash
psdk-instrument 192.168.50.81
```

**This command automatically:**
- ✅ Opens **TWO terminals**:
  - **Main Terminal**: Shows ALL logs (PSDK events highlighted in yellow)
  - **Monitor Terminal**: Shows ONLY PSDK events with player/playback session tracking
- ✅ Saves logs to `.temp/<session_timestamp>/` in your current directory
- ✅ Tracks player and playback sessions with visual headers/footers
- ✅ Displays content metadata (ID, title, type, position)
- ✅ Shows timestamps with milliseconds for each event
- ✅ Highlights repeated events in grey

### 4. Stop Capturing

Press **Ctrl+C** in the main terminal to stop.

## Understanding the Monitor Terminal

The monitor terminal provides advanced PSDK event tracking:

### Visual Elements

```
╔═══════════════════════════════════════════════════╗
║  🎬 PLAYER SESSION STARTED  Time: 16:09:44.123  ║  ← Player created
╚═══════════════════════════════════════════════════╝

  ┌─────────────────────────────────────────────────┐
  │ ▶️  PLAYBACK SESSION #1 STARTED  Time: 16:09:50.456  │  ← Playback started
  ├─────────────────────────────────────────────────┤
  │ Session ID: d4ae7e03-7e80-48d8-984d-51227980e5│
  │ Content ID: PROM1178922                       │  ← Content metadata
  │ Title: Discovery+ Original                    │
  │ Type: SHORT_PREVIEW                           │
  │ Start Position: 0s                            │
  └─────────────────────────────────────────────────┘

[16:09:50.789] [S1] playbackInitiatedEvent          ← PSDK events
[16:09:51.012] [S1] loadingStartEvent
[16:09:52.234] [S1] playbackProgressEvent
[16:09:53.456] [S1] playbackProgressEvent           ← Repeated event (grey)

  ┌─────────────────────────────────────────────────┐
  │   ⏹️  PLAYBACK SESSION #1 ENDED                 │  ← Playback ended
  ├─────────────────────────────────────────────────┤
  │ Duration: 45s | Events: 234                    │
  └─────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════╗
║           🛑 PLAYER SESSION ENDED                 ║  ← Player destroyed
╠═══════════════════════════════════════════════════╣
║ S1: d4ae7e03-7e80-48d8-984d-51227980e5da06a2║
║ Duration: 72s                                     ║
║ Playback Sessions: 1                              ║
║ Total PSDK Events: 234                            ║
╚═══════════════════════════════════════════════════╝
```

### Color Coding

- **Cyan** `[16:09:50.789]` - Timestamps with milliseconds
- **Yellow** `[S1]` - Session number indicator
- **White** - First occurrence of an event
- **Grey** - Repeated events (helps spot patterns)
- **Magenta** - Player session headers
- **Cyan** - Playback session start headers
- **Green** - Playback session end footers (successful)
- **Red** - Playback session end footers (aborted/errors)

## Advanced Usage

### Disable Monitor Terminal

If you only want the main terminal:

```bash
psdk-instrument --no-monitor <ROKU_IP>
```

### View Saved Logs

Logs are saved in `.temp/<timestamp>/`:

```bash
# List all sessions
roku-log-instrument telnet sessions

# View a specific log file
cat .temp/20251116_160944/roku_logs_20251116_160944.log
```

### Clean Up Old Logs

```bash
# Remove all old log sessions
roku-log-instrument telnet cleanup
```

## Configuration

### Customizing Event Patterns

If Roku SDK changes event patterns, you can create a `monitor_config.json` file:

```json
{
  "player_lifecycle": {
    "creation_pattern": "PlayerSDK.Core.PlayerBuilder: new",
    "destruction_pattern": "playerSessionEndEvent"
  },
  "playback_lifecycle": {
    "initiation_pattern": "playbackInitiatedEvent",
    "end_pattern": "playbackSessionEndEvent"
  },
  "content_metadata": {
    "load_pattern": "Player Controller: Load",
    "fields": ["id", "title", "contentType", "initialPlaybackPosition"]
  }
}
```

Place this file in a `config/` directory where you run the command.

## Troubleshooting

### Connection Failed

```
✗ Connection failed: [Errno 61] Connection refused
```

**Solution:**
1. Verify Roku IP address
2. Ensure Roku is on the same network
3. Check that port 8085 is accessible
4. Try rebooting the Roku device

### Monitor Terminal Not Opening

**Solution:**
1. Ensure you're on macOS (AppleScript required)
2. Check Terminal app has necessary permissions
3. Run with `--no-monitor` flag as alternative

### Command Not Found

```bash
-bash: psdk-instrument: command not found
```

**Solution:**
1. Verify installation: `pip list | grep roku-psdk`
2. Check Python scripts directory is in PATH
3. Try using full command: `python -m roku_psdk_log_instrument.cli live <ROKU_IP>`

## Available Commands

### Main Commands

```bash
# Quick capture (recommended)
psdk-instrument <ROKU_IP>

# Disable monitor terminal
psdk-instrument --no-monitor <ROKU_IP>
```

### Telnet Commands

```bash
# Test connection
roku-log-instrument telnet test <ROKU_IP>

# Manual capture with options
roku-log-instrument telnet capture <ROKU_IP> --show

# List all log sessions
roku-log-instrument telnet sessions

# Clean up old sessions
roku-log-instrument telnet cleanup
```

## Example Workflow

```bash
# 1. Install the package
pip install wbd-roku-psdk-log-instrument

# 2. Test connection to your Roku
roku-log-instrument telnet test 192.168.50.81

# 3. Start capturing and monitoring
psdk-instrument 192.168.50.81

# 4. Reproduce the issue on your Roku device

# 5. Stop with Ctrl+C

# 6. Find your logs in .temp/<timestamp>/
ls -la .temp/

# 7. Share or analyze the logs
cat .temp/20251116_160944/roku_logs_20251116_160944.log | grep "error"
```

## Support

For issues, questions, or feature requests:
- Check existing documentation in the `docs/` folder (if you have source access)
- Contact your team's Roku development support
- Submit an issue to the project repository

## Version

Current version: 0.1.0

---

**Note:** This tool is designed for internal development and testing purposes. Ensure you have proper authorization to capture logs from Roku devices on your network.

