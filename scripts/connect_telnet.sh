#!/bin/bash
# Connect to Roku device via telnet and capture logs live

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if ROKU_IP is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <ROKU_IP> [duration_in_seconds]"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.50.81              # Capture until Ctrl+C"
    echo "  $0 192.168.50.81 300          # Capture for 5 minutes"
    echo ""
    exit 1
fi

ROKU_IP="$1"
DURATION=""

if [ ! -z "$2" ]; then
    DURATION="--duration $2"
fi

# Navigate to project root (parent of scripts directory)
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Activate virtual environment
source venv/bin/activate

# Run the new psdk-instrument command
psdk-instrument "$ROKU_IP" $DURATION

