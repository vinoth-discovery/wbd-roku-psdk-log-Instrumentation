# Quick Setup Guide

## Installation Steps

### 1. Create and Activate Virtual Environment

```bash
# Navigate to project directory
cd /Users/vimanoha/Library/CloudStorage/OneDrive-WarnerBros.Discovery/Git/AI\ \&\ Automation/wbd-roku-psdk-log-instrument

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate  # On macOS/Linux
```

### 2. Install Dependencies

```bash
# Install all dependencies including dev tools
pip install -r requirements.txt

# Or install the package in development mode
pip install -e .
```

### 3. Verify Installation

```bash
# Check if CLI is installed
roku-log-instrument --version

# Run tests
pytest

# Check code formatting
black --check src/
flake8 src/
```

## Project Structure Overview

```
wbd-roku-psdk-log-instrument/
├── src/roku_psdk_log_instrument/
│   ├── __init__.py              # Package initialization
│   ├── cli.py                   # Command-line interface
│   ├── models/                  # Data models (LogEntry, etc.)
│   ├── instrumentation/         # Log instrumentation logic
│   ├── validation/              # Log validation logic
│   └── parsers/                 # Log parsing utilities
├── tests/                       # Test suite
├── pyproject.toml              # Modern Python project config
├── requirements.txt            # Dependencies
└── README.md                   # Documentation
```

## Key Components

### 1. **RokuTelnetClient** (`telnet/client.py`) ⭐ NEW
- Connects to Roku devices via telnet on port 8085
- Real-time log capture with connection monitoring
- Supports async capture and callbacks
- Automatic reconnection handling

### 2. **SessionManager** (`telnet/session_manager.py`) ⭐ NEW
- Manages capture sessions in `.temp` directory
- Tracks session metadata (start/end times, line counts)
- Session cleanup and organization
- JSON-based session information storage

### 3. **LogEntry Model** (`models/log_entry.py`)
- Defines the structure of log entries using Pydantic
- Includes timestamp, level, message, source, component, and metadata

### 4. **LogInstrumenter** (`instrumentation/instrumenter.py`)
- Adds metadata and tracking information to logs
- Supports file and entry-level instrumentation

### 5. **LogValidator** (`validation/validator.py`)
- Validates logs against schemas and patterns
- Supports strict mode and custom validation rules
- Returns detailed ValidationResult with success rates

### 6. **LogParser** (`parsers/log_parser.py`)
- Parses raw log files into structured LogEntry objects
- Supports custom regex patterns
- Handles various log formats

### 7. **CLI** (`cli.py`)
- Command-line interface with multiple command groups:
  - **telnet**: Roku device connection and log capture
    - `test`: Test telnet connection
    - `capture`: Capture logs from device
    - `sessions`: List all capture sessions
    - `cleanup`: Clean up old sessions
  - `instrument`: Add metadata to logs
  - `validate`: Validate logs against schemas
  - `parse`: Parse logs into structured format

## Usage Examples

### Capturing Logs from Roku Device ⭐ NEW
```bash
# Test connection
roku-log-instrument telnet test 192.168.1.100

# Capture logs (Press Ctrl+C to stop)
roku-log-instrument telnet capture 192.168.1.100

# Capture with duration limit
roku-log-instrument telnet capture 192.168.1.100 --duration 300

# List all sessions
roku-log-instrument telnet sessions

# Clean up old sessions
roku-log-instrument telnet cleanup --days 7
```

### Parsing Logs
```bash
roku-log-instrument parse /path/to/logfile.log --output parsed_logs.json
```

### Instrumenting Logs
```bash
roku-log-instrument instrument input.log output.log --format json
```

### Validating Logs
```bash
roku-log-instrument validate logfile.log --schema schema.json --strict
```

## Development Workflow

### Running Tests
```bash
pytest                          # Run all tests
pytest -v                       # Verbose output
pytest --cov                    # With coverage report
```

### Code Formatting
```bash
black src/ tests/              # Format code
isort src/ tests/              # Sort imports
flake8 src/ tests/             # Lint code
mypy src/                      # Type checking
```

## Next Steps

1. **Define Roku PSDK Log Format**: Update the regex pattern in `LogParser` to match actual Roku PSDK log format
2. **Implement Core Logic**: Complete the TODO items in each module
3. **Add Test Data**: Create sample Roku PSDK log files for testing
4. **Define Validation Schema**: Create JSON schema for log validation
5. **Add Documentation**: Document Roku-specific log patterns and requirements

## Related Documentation

- **[0_RUNNING.md](0_RUNNING.md)** - How to run the tool 🔧
- **Previous: [1_QUICKSTART.md](1_QUICKSTART.md)** - Quick start guide
- **Next: [3_TELNET_USAGE.md](3_TELNET_USAGE.md)** - Comprehensive telnet documentation
- **[Examples](../examples/README.md)** - Code examples

## Environment Variables (Optional)

You can set these environment variables for configuration:

```bash
export ROKU_LOG_FORMAT="custom_pattern"
export ROKU_LOG_VALIDATION_STRICT=true
```

## Troubleshooting

### Issue: Command not found after installation
```bash
# Ensure virtual environment is activated
source venv/bin/activate

# Reinstall in editable mode
pip install -e .
```

### Issue: Import errors
```bash
# Ensure you're in the project root and venv is activated
cd /path/to/wbd-roku-psdk-log-instrument
source venv/bin/activate
pip install -e .
```

## Additional Resources

- [Pydantic Documentation](https://docs.pydantic.dev/)
- [Click CLI Documentation](https://click.palletsprojects.com/)
- [pytest Documentation](https://docs.pytest.org/)

