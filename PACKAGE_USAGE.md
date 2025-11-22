# Package Installation & Usage Guide

> **For users who want to install and use this tool as a Python package** (without cloning the source code)

## Prerequisites

- Python 3.8 or higher
- `pipx` (recommended) or `pip`
- macOS (for dual-terminal monitoring feature)

## Installation

### Option 1: Install with pipx (Recommended for CLI Tools)

**Best for:** Installing command-line tools that you want to use system-wide.

```bash
# Install pipx if you don't have it
brew install pipx
pipx ensurepath

# Close and reopen terminal, then install the package
pipx install git+https://github.com/vinoth-discovery/wbd-roku-psdk-log-Instrumentation.git
```

**Benefits:**
- ✅ Commands available system-wide
- ✅ Automatic isolated environment
- ✅ No PATH configuration needed
- ✅ Easy to update: `pipx upgrade wbd-roku-psdk-log-instrument`

### Option 2: Install from PyPI with pipx

```bash
pipx install wbd-roku-psdk-log-instrument
```

### Option 3: Install from Wheel File

```bash
pipx install wbd_roku_psdk_log_instrument-0.1.0-py3-none-any.whl
```

### Option 4: Install with pip in Virtual Environment

If you prefer traditional pip installation:

```bash
# Create a virtual environment
python3 -m venv ~/.venvs/roku-psdk
source ~/.venvs/roku-psdk/bin/activate

# Install from git
pip install git+https://github.com/vinoth-discovery/wbd-roku-psdk-log-Instrumentation.git

# Create alias for easy access (add to ~/.zshrc)
echo 'alias psdk-instrument="~/.venvs/roku-psdk/bin/psdk-instrument"' >> ~/.zshrc
source ~/.zshrc
```

### ⚠️ Note on Python 3.11+

If you see "externally-managed-environment" error, use **pipx** (recommended) or install in a virtual environment. See [Troubleshooting](#troubleshooting) section below.

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
  - **Main Terminal**: Shows ALL logs (PSDK events highlighted in yellow) + accepts interactive commands
  - **Monitor Terminal**: Shows ONLY PSDK events with player/playback session tracking
- ✅ **Interactive commands**: Type and press Enter to send commands to Roku during capture
- ✅ Saves logs to `.temp/<session_timestamp>/` in your current directory
- ✅ Tracks player and playback sessions with visual headers/footers
- ✅ Displays content metadata (ID, title, type, position)
- ✅ Shows timestamps with milliseconds for each event
- ✅ Highlights repeated events in grey

### 🔥 Interactive Commands During Capture

**While capturing logs, you can send commands to the Roku device at any time:**

1. Simply type your command in the main terminal
2. Press Enter to send it to the device
3. Your command appears in **green**: `→ Sent: your_command`
4. Device responses appear in the log stream in real-time

**When is this useful?**
- 🔥 **During crashes**: Send debug commands without stopping the capture
- 🐛 **Real-time debugging**: Test device behavior while monitoring logs
- 📊 **Interactive testing**: Trigger specific actions and see immediate results

**Example:**
```
... (logs streaming) ...
[INFO] Some log line
your_debug_command          ← You type this and press Enter
→ Sent: your_debug_command  ← Confirmation in green
[INFO] Device response...   ← Response appears in log stream
... (logs continue) ...
```

### 4. Stop Capturing

Press **Ctrl+C** in the main terminal to stop.

**After stopping, you'll be prompted:**
```
💾 Would you like to keep the captured logs? [Y/n]:
```

- Press **Y** (default) to keep the logs in `.temp/`
- Press **N** to delete the logs immediately

This helps keep your `.temp/` directory clean by removing unwanted test captures.

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
zsh: command not found: psdk-instrument
```

**Solution:**

**1. If installed with pipx:**
```bash
# Verify installation
pipx list

# Reinstall if needed
pipx reinstall wbd-roku-psdk-log-instrument

# Ensure pipx path is configured
pipx ensurepath
source ~/.zshrc
```

**2. If installed with pip, verify installation:**
```bash
pip3 show wbd-roku-psdk-log-instrument
# or
pip3 list | grep roku-psdk
```

**3. Add Python scripts to PATH (if using pip):**

On macOS/Linux, add to `~/.zshrc` or `~/.bashrc`:
```bash
# For Python 3.13 (adjust version as needed)
export PATH="$HOME/Library/Python/3.13/bin:$PATH"

# Reload shell config
source ~/.zshrc
```

Find your Python version:
```bash
python3 --version
```

**4. Alternative: Use Python module directly:**
```bash
python3 -m roku_psdk_log_instrument.cli live <ROKU_IP>
```

### Externally Managed Environment Error

```bash
error: externally-managed-environment
```

**This is Python 3.11+ protection (PEP 668).**

**Solution 1: Use pipx (Recommended)**
```bash
brew install pipx
pipx ensurepath
pipx install git+https://github.com/vinoth-discovery/wbd-roku-psdk-log-Instrumentation.git
```

**Solution 2: Use virtual environment**
```bash
python3 -m venv ~/.venvs/roku-psdk
source ~/.venvs/roku-psdk/bin/activate
pip install git+https://github.com/vinoth-discovery/wbd-roku-psdk-log-Instrumentation.git

# Add alias to ~/.zshrc
echo 'alias psdk-instrument="~/.venvs/roku-psdk/bin/psdk-instrument"' >> ~/.zshrc
source ~/.zshrc
```

**Solution 3: Override (Not Recommended)**
```bash
pip3 install --user --break-system-packages git+https://github.com/vinoth-discovery/wbd-roku-psdk-log-Instrumentation.git
```

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
# 1. Install the package with pipx
brew install pipx
pipx ensurepath
pipx install git+https://github.com/vinoth-discovery/wbd-roku-psdk-log-Instrumentation.git

# 2. Test connection to your Roku
roku-log-instrument telnet test 192.168.50.81

# 3. Start capturing and monitoring
psdk-instrument 192.168.50.81

# 4. Reproduce the issue on your Roku device

# 5. Stop with Ctrl+C
# You'll be prompted: "Would you like to keep the captured logs?"
# - Press Y to keep the logs
# - Press N to delete them

# 6. If you kept the logs, find them in .temp/<timestamp>/
ls -la .temp/

# 7. Share or analyze the logs
cat .temp/20251116_160944/roku_logs_20251116_160944.log | grep "error"

# 8. Update the tool when needed
pipx upgrade wbd-roku-psdk-log-instrument
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

