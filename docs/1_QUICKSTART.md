# Quick Start Guide

## 🚀 Get Started in 5 Minutes

### 1. Install

```bash
cd "/Users/vimanoha/Library/CloudStorage/OneDrive-WarnerBros.Discovery/Git/AI & Automation/wbd-roku-psdk-log-instrument"

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Install package
pip install -e .
```

### ⚠️ Important: For New Terminals

Every time you open a **new terminal**, activate the virtual environment:

```bash
cd "/Users/vimanoha/Library/CloudStorage/OneDrive-WarnerBros.Discovery/Git/AI & Automation/wbd-roku-psdk-log-instrument"
source venv/bin/activate
```

**Note:** The main script `./scripts/connect_telnet.sh` automatically activates the venv, so you only need manual activation for other commands.

You should see `(venv)` in your prompt when activated.

### 2. Find Your Roku IP Address

**On Roku Device:**
- Go to: Settings → Network → About
- Note the IP address (e.g., 192.168.1.100)

### 3. Test Connection

```bash
roku-log-instrument telnet test 192.168.1.100
```

Expected output:
```
Testing connection to 192.168.1.100:8085...
✓ Connection successful!
```

### 4. Capture Logs (Live Display + Save)

**⭐ Recommended: Use the simple command**

```bash
# The easiest way - one command that does everything
psdk-instrument 192.168.50.81
```

**This automatically opens TWO terminals:**
1. **Main Terminal**: Shows ALL logs (PSDK highlighted in yellow)
2. **Monitor Terminal**: Shows ONLY PSDK:: events

**Alternative: Use shell script (auto-activates venv)**

```bash
./scripts/connect_telnet.sh 192.168.50.81
```

Press **Ctrl+C** to stop capturing.

**What you'll see:**
- **Main terminal**:
  - 🟡 PSDK logs highlighted in yellow (lines with `PSDK::`)
  - ⚪ All other logs in white/default color
- **Monitor terminal**:
  - ⚪ ONLY PSDK:: events in white (filtered view)
- 💾 Logs saved to `.temp/<session_id>/`

### 5. View Your Logs

```bash
# List all sessions
roku-log-instrument telnet sessions

# View the latest log file
ls -lt .temp/*/roku_logs_*.log | head -1
```

## 📋 Common Commands

### ⭐ Primary Command

```bash
# Capture logs (live display + save + PSDK monitor)
psdk-instrument <ROKU_IP>

# With duration (5 minutes)
psdk-instrument <ROKU_IP> --duration 300

# With description
psdk-instrument <ROKU_IP> --description "Testing feature X"

# Disable PSDK monitor (single terminal only)
psdk-instrument <ROKU_IP> --no-monitor
```

**Note**: By default, this opens a second terminal showing only PSDK:: events!

### Advanced Telnet Operations

```bash
# Test connection
roku-log-instrument telnet test <ROKU_IP>

# Advanced capture options
roku-log-instrument telnet capture <ROKU_IP> --duration 300

# Capture without displaying (save only)
roku-log-instrument telnet capture <ROKU_IP> --no-show

# List all sessions
roku-log-instrument telnet sessions

# Clean up old sessions (7+ days)
roku-log-instrument telnet cleanup --days 7
```

### Log Processing

```bash
# Parse logs
roku-log-instrument parse <log_file> --output parsed.json

# Validate logs
roku-log-instrument validate <log_file> --schema schema.json

# Instrument logs
roku-log-instrument instrument input.log output.log --format json
```

## 📁 Where Are My Logs?

All captured logs are stored in:
```
.temp/
└── <session_id>/
    ├── session_info.json           # Session metadata
    └── roku_logs_<timestamp>.log   # Captured logs
```

Example:
```
.temp/
└── 20241116_143022/
    ├── session_info.json
    └── roku_logs_20241116_143022.log
```

## 🔧 Troubleshooting

### Can't Connect?

```bash
# 1. Verify IP address
ping <ROKU_IP>

# 2. Test telnet manually
telnet <ROKU_IP> 8085

# 3. Check Roku developer mode is enabled
```

### Command Not Found?

```bash
# Ensure virtual environment is activated
source venv/bin/activate

# Reinstall package
pip install -e .
```

### No Logs Appearing?

1. Enable developer mode on Roku
2. Try triggering actions on the device
3. Check if telnet port 8085 is accessible

## 📚 Next Steps

Now that you've completed the quick start, continue your journey:

- **Having issues?** [0_RUNNING.md](0_RUNNING.md) - Fix "command not found" errors 🔧
- **Next: [2_SETUP.md](2_SETUP.md)** - Detailed setup and development guide
- **Then: [3_TELNET_USAGE.md](3_TELNET_USAGE.md)** - Comprehensive telnet documentation
- **Examples**: Check [../examples/](../examples/) directory for code samples
- **Full Documentation**: See [../README.md](../README.md) or [README.md](README.md)

## 🎯 Example Workflow

```bash
# 1. Test connection
roku-log-instrument telnet test 192.168.1.100

# 2. Start capturing (run for 10 minutes)
roku-log-instrument telnet capture 192.168.1.100 --duration 600

# 3. View sessions
roku-log-instrument telnet sessions

# 4. Parse the logs
LOG_FILE=$(find .temp -name "roku_logs_*.log" | sort | tail -1)
roku-log-instrument parse "$LOG_FILE" --output results.json

# 5. Clean up old sessions
roku-log-instrument telnet cleanup --days 7
```

## 💡 Tips

- **Always test connection first** before capturing
- **Use descriptions** to identify sessions later
- **Set duration limits** to prevent huge log files
- **Clean up regularly** to save disk space
- **Check sessions list** to verify captures

## 🆘 Need Help?

```bash
# General help
roku-log-instrument --help

# Telnet commands help
roku-log-instrument telnet --help

# Specific command help
roku-log-instrument telnet capture --help
```

