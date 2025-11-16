# Examples

This directory contains example scripts demonstrating how to use the Roku PSDK Log Instrumentation tool.

## Running Examples

### Prerequisites

1. Install the package:
   ```bash
   cd /path/to/wbd-roku-psdk-log-instrument
   pip install -e .
   ```

2. Update the Roku device IP address in the example scripts

## Available Examples

### 1. `capture_example.py`

Demonstrates how to:
- Connect to a Roku device via telnet
- Create a capture session
- Capture logs with a callback function
- Handle errors and disconnection
- List all sessions

**Usage:**
```bash
# Edit the script to set your Roku IP address
nano examples/capture_example.py

# Run the example
python examples/capture_example.py
```

**What it does:**
1. Tests the telnet connection
2. Connects to the Roku device
3. Creates a new capture session
4. Captures logs for 60 seconds (or until Ctrl+C)
5. Highlights ERROR/CRITICAL messages in real-time
6. Saves logs to `.temp/<session_id>/roku_logs_<timestamp>.log`
7. Ends the session and disconnects

## Customization

### Change Capture Duration

Edit the `max_duration` parameter:

```python
client.capture_logs(
    output_file=log_file,
    callback=log_callback,
    max_duration=300  # 5 minutes
)
```

Remove `max_duration` to capture indefinitely.

### Custom Log Processing

Modify the callback function to process logs differently:

```python
def log_callback(line: str):
    """Custom log processing."""
    # Filter specific events
    if "playback" in line.lower():
        print(f"📺 Playback event: {line}")
    
    # Count errors
    if "ERROR" in line:
        error_count += 1
    
    # Send to external system
    # send_to_api(line)
```

### Multiple Devices

Capture from multiple devices simultaneously:

```python
import threading

def capture_from_device(ip_address):
    client = RokuTelnetClient(host=ip_address)
    # ... capture logic ...

# Start multiple capture threads
threads = []
for ip in ["192.168.1.100", "192.168.1.101", "192.168.1.102"]:
    t = threading.Thread(target=capture_from_device, args=(ip,))
    t.start()
    threads.append(t)

# Wait for all captures to complete
for t in threads:
    t.join()
```

## Next Steps

After capturing logs, you can:

1. **Parse the logs:**
   ```bash
   roku-log-instrument parse .temp/20241116_143022/roku_logs_*.log
   ```

2. **Validate the logs:**
   ```bash
   roku-log-instrument validate .temp/20241116_143022/roku_logs_*.log
   ```

3. **Instrument with metadata:**
   ```bash
   roku-log-instrument instrument \
     .temp/20241116_143022/roku_logs_*.log \
     instrumented_logs.json
   ```

## Troubleshooting

### "Cannot connect to device"

1. Verify Roku IP address:
   - On Roku: Settings > Network > About
   
2. Test connectivity:
   ```bash
   ping 192.168.1.100
   ```

3. Test telnet manually:
   ```bash
   telnet 192.168.1.100 8085
   ```

### "Permission denied"

Make the script executable:
```bash
chmod +x examples/capture_example.py
./examples/capture_example.py
```

### No logs appearing

1. Ensure Roku developer mode is enabled
2. Try triggering actions on the Roku device
3. Check if logs are enabled in developer settings

## Related Documentation

- **[0. Running Guide](../docs/0_RUNNING.md)** - How to run the tool 🔧
- **[1. Quick Start Guide](../docs/1_QUICKSTART.md)** - Get started quickly ⭐
- **[2. Setup Instructions](../docs/2_SETUP.md)** - Detailed setup guide
- **[3. Telnet Usage Guide](../docs/3_TELNET_USAGE.md)** - Complete telnet documentation

