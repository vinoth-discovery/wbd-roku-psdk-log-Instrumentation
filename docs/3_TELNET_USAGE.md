# Telnet Connection Usage Guide

This guide explains how to use the telnet functionality to capture logs from Roku devices.

## Overview

The tool connects to Roku devices via telnet on port 8085, captures logs in real-time, and stores them in organized sessions within a `.temp` directory.

## Prerequisites

1. Roku device must be on the same network as your computer
2. Roku device must have developer mode enabled
3. Telnet port 8085 must be accessible

## Quick Start

### 1. Test Connection

First, test if you can connect to your Roku device:

```bash
roku-log-instrument telnet test 192.168.1.100
```

Replace `192.168.1.100` with your Roku device's IP address.

### 2. Capture Logs

Start capturing logs from your Roku device:

```bash
roku-log-instrument telnet capture 192.168.1.100
```

This will:
- ✓ Check if telnet connection is active
- ✓ Prompt to reconnect if connection fails
- ✓ Create a new session in `.temp/<session_id>/`
- ✓ Start capturing logs to `.temp/<session_id>/roku_logs_<timestamp>.log`
- ✓ Continue until you press Ctrl+C

### 3. Capture with Options

```bash
# Capture for a specific duration (in seconds)
roku-log-instrument telnet capture 192.168.1.100 --duration 300

# Add a description to the session
roku-log-instrument telnet capture 192.168.1.100 --description "Testing playback feature"

# Use a different port (if needed)
roku-log-instrument telnet capture 192.168.1.100 --port 9999
```

## Session Management

### List All Sessions

View all capture sessions:

```bash
roku-log-instrument telnet sessions
```

Output example:
```
Found 3 session(s):

● 20241116_143022
  Host: 192.168.1.100:8085
  Started: 2024-11-16T14:30:22
  Status: active
  Lines: 1523

○ 20241116_120530
  Host: 192.168.1.100:8085
  Started: 2024-11-16T12:05:30
  Ended: 2024-11-16T12:15:45
  Status: completed
  Lines: 3421
```

### Clean Up Old Sessions

Remove sessions older than 7 days:

```bash
roku-log-instrument telnet cleanup --days 7
```

Skip confirmation prompt:

```bash
roku-log-instrument telnet cleanup --days 7 --yes
```

## Directory Structure

```
your-project/
└── .temp/
    ├── .gitignore                    # Prevents logs from being committed
    ├── 20241116_143022/             # Session directory
    │   ├── session_info.json        # Session metadata
    │   └── roku_logs_20241116_143022.log  # Captured logs
    └── 20241116_120530/
        ├── session_info.json
        └── roku_logs_20241116_120530.log
```

### Session Info Format

Each session includes a `session_info.json` file:

```json
{
  "session_id": "20241116_143022",
  "host": "192.168.1.100",
  "port": 8085,
  "start_time": "2024-11-16T14:30:22",
  "end_time": "2024-11-16T14:45:30",
  "description": "Testing playback feature",
  "status": "completed",
  "log_file": "roku_logs_20241116_143022.log",
  "line_count": 1523
}
```

## Connection Status Checking

The tool automatically checks if the telnet connection is active:

1. **Connection Successful**: Starts capturing logs immediately
2. **Connection Failed**: Shows error message with troubleshooting tips
3. **Retry Option**: Prompts to enter a new IP address if connection fails

Example error handling:

```bash
$ roku-log-instrument telnet capture 192.168.1.100

✗ Cannot connect to 192.168.1.100:8085

Please check:
  1. Roku device IP address is correct
  2. Device is powered on and connected to network
  3. Telnet port 8085 is accessible

Would you like to retry with a different host? [Y/n]: y
Enter Roku device IP address: 192.168.1.101

✓ Successfully connected to 192.168.1.101:8085
```

## Programmatic Usage

You can also use the telnet client in your Python code:

```python
from roku_psdk_log_instrument import RokuTelnetClient, SessionManager

# Create session manager
session_mgr = SessionManager()

# Create telnet client
client = RokuTelnetClient(host="192.168.1.100", port=8085)

# Check if connected
if not client.is_connected():
    # Connect to device
    if client.connect():
        print("Connected!")
    else:
        print("Connection failed")
        exit(1)

# Create capture session
session = session_mgr.create_session(
    host="192.168.1.100",
    port=8085,
    description="My test session"
)

# Get log file path
log_file = session_mgr.get_session_log_path(session)

# Capture logs
try:
    client.capture_logs(log_file, max_duration=300)
finally:
    # End session
    session_mgr.end_session(session)
    
    # Disconnect
    client.disconnect()
```

### Using Callbacks

Process logs in real-time with callbacks:

```python
def log_callback(line: str):
    """Called for each log line captured."""
    if "ERROR" in line:
        print(f"⚠️  Error detected: {line}")

client.capture_logs(log_file, callback=log_callback)
```

### Async Capture

Capture logs in the background:

```python
# Start capture in background thread
client.start_capture_async(log_file)

# Do other work...
time.sleep(60)

# Stop capture
client.stop_capture()
```

## Troubleshooting

### Cannot Connect to Device

**Problem**: `Connection timeout: Unable to connect to 192.168.1.100:8085`

**Solutions**:
1. Verify the IP address is correct:
   ```bash
   # On Roku: Settings > Network > About
   ```
2. Ensure Roku is in developer mode
3. Check firewall settings
4. Verify network connectivity:
   ```bash
   ping 192.168.1.100
   ```

### Connection Drops During Capture

**Problem**: Connection drops while capturing logs

**Solutions**:
1. Check network stability
2. Move closer to WiFi router if using wireless
3. Use wired connection if possible
4. Restart Roku device

### No Logs Appearing

**Problem**: Connection successful but no logs are captured

**Solutions**:
1. Verify developer mode is enabled on Roku
2. Try triggering actions on the Roku device
3. Check if logs are enabled in Roku developer settings

### Finding Roku IP Address

1. **On Roku Device**:
   - Go to Settings > Network > About
   - Note the IP address

2. **Using Network Scanner**:
   ```bash
   # macOS/Linux
   arp -a | grep roku
   
   # Or use nmap
   nmap -sn 192.168.1.0/24
   ```

## Best Practices

1. **Regular Cleanup**: Run cleanup regularly to prevent disk space issues
   ```bash
   roku-log-instrument telnet cleanup --days 7
   ```

2. **Descriptive Sessions**: Use meaningful descriptions for sessions
   ```bash
   roku-log-instrument telnet capture 192.168.1.100 \
     --description "Bug reproduction - video playback freeze"
   ```

3. **Test Connection First**: Always test the connection before starting long captures
   ```bash
   roku-log-instrument telnet test 192.168.1.100
   ```

4. **Monitor Disk Space**: Long captures can generate large log files
   ```bash
   du -sh .temp/
   ```

## Advanced Usage

### Capture Multiple Devices

Capture logs from multiple Roku devices simultaneously:

```bash
# Terminal 1
roku-log-instrument telnet capture 192.168.1.100 --description "Device 1"

# Terminal 2
roku-log-instrument telnet capture 192.168.1.101 --description "Device 2"
```

### Integration with Other Commands

Capture and parse logs in a pipeline:

```bash
# Capture logs for 5 minutes, then parse
roku-log-instrument telnet capture 192.168.1.100 --duration 300

# Find the latest session log
LOG_FILE=$(find .temp -name "roku_logs_*.log" | sort | tail -1)

# Parse the captured logs
roku-log-instrument parse "$LOG_FILE" --output parsed_results.json
```

## Safety Features

1. **Automatic Disconnection**: Properly disconnects on Ctrl+C or errors
2. **Session Tracking**: All sessions are tracked with metadata
3. **Gitignore**: Automatically creates `.gitignore` to prevent committing logs
4. **Error Recovery**: Handles network errors gracefully

## Next Steps

After capturing logs, you can:

1. **Parse logs**: Convert raw logs to structured format
   ```bash
   roku-log-instrument parse .temp/20241116_143022/roku_logs_20241116_143022.log
   ```

2. **Validate logs**: Check logs against expected patterns
   ```bash
   roku-log-instrument validate .temp/20241116_143022/roku_logs_20241116_143022.log
   ```

3. **Instrument logs**: Add metadata and tracking information
   ```bash
   roku-log-instrument instrument \
     .temp/20241116_143022/roku_logs_20241116_143022.log \
     instrumented_logs.json
   ```

## Related Documentation

- **[0_RUNNING.md](0_RUNNING.md)** - How to run the tool 🔧
- **Previous: [2_SETUP.md](2_SETUP.md)** - Setup and development guide
- **Start: [1_QUICKSTART.md](1_QUICKSTART.md)** - Quick start guide
- **[Examples](../examples/README.md)** - Code examples

