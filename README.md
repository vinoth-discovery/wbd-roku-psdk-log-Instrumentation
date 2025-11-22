# WBD Roku PSDK Log Instrumentation & Validation Tool

A Python-based tool for instrumenting and validating Roku Player Software Development Kit (PSDK) logs.

## Overview

This tool provides capabilities to:
- **Capture logs** from Roku devices via telnet (port 8085)
- **Interactive commands** - Send commands to Roku while capturing logs (perfect for crash debugging!)
- **PSDK Event Monitoring** with automatic dual-terminal display
- **Session management** with automatic organization in `.temp` directory
- **Connection monitoring** with automatic reconnection prompts
- **Instrument** log files with metadata and tracking information
- **Validate** log entries against expected patterns and schemas
- **Parse** and analyze Roku PSDK logs
- Generate reports on log quality and compliance

## Project Status

✅ **Stage 1 Complete** - Telnet capture and live log viewing
✅ **Stage 2 Complete** - PSDK event monitoring with dual-terminal display

## Installation

### 📦 For Package Users (No Source Code)

**If you want to use this tool as an installed package**, see **[PACKAGE_USAGE.md](PACKAGE_USAGE.md)** for:
- Installing via pip
- Using the `psdk-instrument` command
- Quick start without source access

### 🛠️ For Developers (With Source Code)

**If you're developing or contributing to this project:**

#### Prerequisites
- Python 3.8 or higher
- pip

#### Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd wbd-roku-psdk-log-instrument
```

2. Create a virtual environment:
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

3. Install dependencies:
```bash
pip install -r requirements.txt
```

4. Install the package in development mode:
```bash
pip install -e .
```

### ⚠️ Important: Activating the Virtual Environment

Every time you open a **new terminal**, you must activate the virtual environment:

```bash
# Navigate to project directory
cd "/path/to/wbd-roku-psdk-log-instrument"

# Activate venv (only needed for manual commands)
source venv/bin/activate
```

When active, you'll see `(venv)` in your prompt. See [docs/0_RUNNING.md](docs/0_RUNNING.md) for details.

## Project Structure

```
wbd-roku-psdk-log-instrument/
├── src/
│   └── roku_psdk_log_instrument/
│       ├── __init__.py
│       ├── cli.py              # Command-line interface
│       ├── telnet/             # Telnet connection modules
│       │   ├── __init__.py
│       │   ├── client.py       # Roku telnet client
│       │   └── session_manager.py  # Session management
│       ├── instrumentation/    # Log instrumentation modules
│       │   ├── __init__.py
│       │   └── instrumenter.py
│       ├── validation/         # Log validation modules
│       │   ├── __init__.py
│       │   └── validator.py
│       ├── parsers/           # Log parsing utilities
│       │   ├── __init__.py
│       │   └── log_parser.py
│       └── models/            # Data models
│           ├── __init__.py
│           └── log_entry.py
├── tests/                     # Test suite
│   ├── __init__.py
│   ├── test_telnet.py
│   ├── test_instrumentation.py
│   ├── test_validation.py
│   └── test_parsers.py
├── docs/                      # Documentation
│   ├── README.md             # Documentation index
│   ├── 0_RUNNING.md          # How to run the tool
│   ├── 1_QUICKSTART.md       # Quick start guide
│   ├── 2_SETUP.md            # Setup instructions
│   └── 3_TELNET_USAGE.md     # Telnet usage guide
├── examples/                 # Example scripts
├── scripts/                  # Shell scripts
│   ├── connect_telnet.sh    # Telnet connection script (auto-activates venv)
│   └── monitor_psdk_events.sh # PSDK event monitor with lifecycle tracking
├── config/                   # Configuration files
│   ├── monitor_config.json  # PSDK monitor configuration (player patterns)
│   └── README.md            # Configuration documentation
├── .temp/                    # Capture session logs (auto-generated)
├── pyproject.toml          # Project configuration
├── requirements.txt        # Dependencies
├── .gitignore             # Git ignore rules
└── README.md              # This file
```

## Usage

### ⭐ THE ONE COMMAND (Recommended)

The simplest way to capture and view live Roku logs with automatic PSDK event monitoring:

```bash
# Activate virtual environment (once per terminal session)
source venv/bin/activate

# Capture and view logs live (auto-opens PSDK monitor terminal)
psdk-instrument 192.168.50.81

# With duration (5 minutes)
psdk-instrument 192.168.50.81 --duration 300

# With description
psdk-instrument 192.168.50.81 --description "Testing playback"

# Disable PSDK monitor (single terminal only)
psdk-instrument 192.168.50.81 --no-monitor
```

**What it does:**
- ✅ Connects to Roku telnet (port 8085)
- ✅ **Main terminal**: Shows ALL logs (PSDK logs highlighted in yellow)
- ✅ **Interactive commands**: Type commands and press Enter to send them to Roku (useful during crashes!)
- ✅ **Monitor terminal**: Shows ONLY PSDK:: events in white (automatically opens)
- ✅ Saves logs to `.temp/<session_id>/` folder
- ✅ Press Ctrl+C to stop capture

**Interactive Command Feature:**
While logs are streaming, you can type commands directly in the main terminal and press Enter to send them to the Roku device. This is especially useful when:
- 🔥 A crash occurs and you need to send debug commands
- 🐛 You need to test device behavior in real-time
- 📊 You want to trigger specific actions without stopping the capture

Your sent commands appear in **green**, and responses are shown in real-time along with the log stream.

**Example:**
```
... (logs streaming) ...
[INFO] Player initialized
[DEBUG] Loading content...
get_crash_log                    ← You type this and press Enter
→ Sent: get_crash_log            ← Confirmation in green
[INFO] Crash log: <details>     ← Response appears immediately
[PSDK::] playbackProgressEvent   ← Logs continue streaming
... (logs continue) ...
```

### 🔄 Alternative: Shell Script (Auto-activates venv)

If you don't want to manually activate venv:

```bash
./scripts/connect_telnet.sh 192.168.50.81
./scripts/connect_telnet.sh 192.168.50.81 300  # With duration
```

### Advanced Commands

For more control, activate venv and use advanced options:

```bash
source venv/bin/activate

# Test connection to Roku device
roku-log-instrument telnet test 192.168.50.81

# Advanced capture options
roku-log-instrument telnet capture 192.168.50.81 \
  --duration 300 \
  --description "Testing playback feature"

# Capture without displaying (save only)
roku-log-instrument telnet capture 192.168.50.81 --no-show

# List all capture sessions
roku-log-instrument telnet sessions

# Clean up old sessions
roku-log-instrument telnet cleanup --days 7
```

**See [docs/3_TELNET_USAGE.md](docs/3_TELNET_USAGE.md) for detailed telnet documentation.**

### Log Processing

```bash
# Parse logs
roku-log-instrument parse logfile.log --output parsed_logs.json

# Validate logs
roku-log-instrument validate logfile.log --schema schema.json --strict

# Instrument logs with metadata
roku-log-instrument instrument input.log output.log --format json
```

## Documentation

- **[0. Running Guide](docs/0_RUNNING.md)** - How to run the tool (fix "command not found" errors) 🔧
- **[1. Quick Start Guide](docs/1_QUICKSTART.md)** - Get started in 5 minutes ⭐ Start here!
- **[2. Setup Instructions](docs/2_SETUP.md)** - Detailed installation and configuration
- **[3. Telnet Usage Guide](docs/3_TELNET_USAGE.md)** - Complete telnet capture documentation
- **[4. Viewing Logs](docs/4_VIEWING_LOGS.md)** - Log viewing and analysis
- **[5. PSDK Monitor](docs/5_PSDK_MONITOR.md)** - Dual-terminal PSDK event monitoring ⭐ Stage 2
- **[Examples](examples/)** - Code examples and usage patterns

## Development

### Running Tests

```bash
pytest
```

### Code Formatting

```bash
# Format code with black
black src/ tests/

# Sort imports
isort src/ tests/
```

### Linting

```bash
# Run flake8
flake8 src/ tests/

# Run type checking
mypy src/
```

## Contributing

(To be updated)

## License

MIT License

## Contact

WBD Team

