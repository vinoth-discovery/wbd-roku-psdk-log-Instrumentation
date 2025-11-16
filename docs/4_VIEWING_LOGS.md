# Viewing Logs Guide

## Overview

This guide shows you different ways to view and monitor Roku telnet logs from port 8085.

## ⭐ THE ONE COMMAND (Recommended)

**This is all you need!** One command that connects to telnet, shows logs live, AND saves them:

```bash
cd "/Users/vimanoha/Library/CloudStorage/OneDrive-WarnerBros.Discovery/Git/AI & Automation/wbd-roku-psdk-log-instrument"

# Capture and view live (runs until Ctrl+C)
./scripts/connect_telnet.sh 192.168.50.81

# Or with time limit (5 minutes)
./scripts/connect_telnet.sh 192.168.50.81 300
```

**What it does:**
- ✅ Connects to Roku device telnet (port 8085)
- ✅ Shows logs live in terminal with PSDK logs highlighted in yellow
- ✅ Saves logs to `.temp/<session_id>/` folder
- ✅ Press Ctrl+C to stop

**That's it!** This one command does everything you need.

## Alternative: Using the Tool Directly

If you need more control:

```bash
# Activate virtual environment first
source venv/bin/activate

# Capture with live display (default behavior)
roku-log-instrument telnet capture 192.168.50.81

# With duration limit
roku-log-instrument telnet capture 192.168.50.81 --duration 300

# With description
roku-log-instrument telnet capture 192.168.50.81 --description "Testing feature X"

# Save without displaying (silent mode)
roku-log-instrument telnet capture 192.168.50.81 --no-show
```

## View Previously Captured Logs

If you want to view logs that were already captured:

```bash
# Find and view the latest log
tail -f $(find .temp -name "roku_logs_*.log" | sort | tail -1)

# View specific log file
tail -f .temp/20251116_133206/roku_logs_20251116_133206.log
```

## Color Highlighting

**Note:** The live capture command (`psdk-instrument`) already highlights PSDK logs in yellow automatically.

For viewing saved logs or custom highlighting, you can use:

### Using grep

```bash
# Highlight PSDK logs (similar to live capture)
tail -f .temp/*/roku_logs_*.log | grep --color=always -E 'PSDK::|$'

# Highlight errors in red
tail -f .temp/*/roku_logs_*.log | grep --color=always -E 'ERROR|$'

# Highlight multiple patterns
tail -f .temp/*/roku_logs_*.log | \
  grep --color=always -E 'ERROR|WARNING|PSDK::|$'
```

### Using awk

```bash
# Highlight PSDK logs in yellow (same as live capture)
tail -f .temp/*/roku_logs_*.log | awk '
  /PSDK::/ {print "\033[33m" $0 "\033[0m"; next}
  {print}
'

# Or with multiple colors
tail -f .temp/*/roku_logs_*.log | awk '
  /ERROR/ {print "\033[31m" $0 "\033[0m"; next}
  /WARNING|WARN/ {print "\033[33m" $0 "\033[0m"; next}
  /PSDK::/ {print "\033[33m" $0 "\033[0m"; next}
  {print}
'
```

## Filtering Logs

### Show Only Errors

```bash
tail -f .temp/*/roku_logs_*.log | grep -i error
```

### Show Errors and Warnings

```bash
tail -f .temp/*/roku_logs_*.log | grep -iE 'error|warning'
```

### Exclude Debug Messages

```bash
tail -f .temp/*/roku_logs_*.log | grep -v -i debug
```

### Show Specific Component Logs

```bash
tail -f .temp/*/roku_logs_*.log | grep "ComponentName"
```

## Advanced Viewing

### Split Terminal View (using tmux)

```bash
# Install tmux if not available
# brew install tmux

# Start tmux
tmux

# Split window horizontally
Ctrl+b then "

# In top pane: Run capture
source venv/bin/activate && roku-log-instrument telnet capture 192.168.50.81

# Switch to bottom pane
Ctrl+b then ↓

# In bottom pane: View logs
./view_logs.sh

# Switch between panes: Ctrl+b then arrow keys
# Exit tmux: Ctrl+b then x (in each pane)
```

### Using iTerm2 Split Panes (macOS)

1. **Split Vertically**: `Cmd+D`
2. **Split Horizontally**: `Cmd+Shift+D`
3. **Left Pane**: Run capture command
4. **Right Pane**: Run view command

## List All Captured Sessions

```bash
# List all session directories
ls -la .temp/

# List all log files with sizes
find .temp -name "roku_logs_*.log" -exec ls -lh {} \;

# List sessions with line counts
find .temp -name "roku_logs_*.log" -exec sh -c 'echo -n "$1: "; wc -l < "$1"' _ {} \;
```

## View Session Information

```bash
# View session metadata
cat .temp/20251116_133206/session_info.json

# Pretty print session info
python3 -m json.tool .temp/20251116_133206/session_info.json
```

## Quick Commands Reference

```bash
# View latest log in real-time
./view_logs.sh

# Capture and view simultaneously
./capture_and_view.sh 192.168.50.81

# View specific log file
tail -f .temp/SESSION_ID/roku_logs_SESSION_ID.log

# Count lines in latest log
wc -l $(find .temp -name "roku_logs_*.log" | sort | tail -1)

# Search for pattern in latest log
grep "pattern" $(find .temp -name "roku_logs_*.log" | sort | tail -1)

# List all sessions
roku-log-instrument telnet sessions
```

## Troubleshooting

### "nc: command not found"

Install netcat:
```bash
# macOS
brew install netcat

# Or use telnet instead
telnet 192.168.50.81 8085
```

### "tail: cannot open"

The log file hasn't been created yet. Make sure:
1. You've run a capture command
2. The `.temp` directory exists
3. There are log files in `.temp`

### No Output Appearing

1. Check if Roku device is sending logs
2. Verify the IP address is correct
3. Ensure port 8085 is accessible
4. Try restarting the Roku device

## Best Practices

1. **Use Color Highlighting**: Makes it easier to spot errors
2. **Filter Wisely**: Don't overwhelm yourself with debug logs
3. **Use Multiple Terminals**: One for capture, one for viewing
4. **Save Important Logs**: Copy interesting sessions before cleanup
5. **Monitor Disk Space**: Long captures can generate large files

## Related Documentation

- **[0_RUNNING.md](0_RUNNING.md)** - How to run the tool
- **[1_QUICKSTART.md](1_QUICKSTART.md)** - Quick start guide
- **[3_TELNET_USAGE.md](3_TELNET_USAGE.md)** - Complete telnet documentation

