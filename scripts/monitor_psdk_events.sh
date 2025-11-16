#!/bin/bash
# Monitor PSDK events from active Roku log capture session with player lifecycle tracking

# Color codes
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
RED='\033[0;31m'
GREY='\033[0;90m'
NC='\033[0m' # No Color

# Get script directory for config file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/config/monitor_config.json"

# Default patterns (fallback if config not found)
PLAYER_CREATE_PATTERN="PlayerSDK.Core.PlayerBuilder: new"
PLAYER_DESTROY_PATTERN="playerSessionEndEvent"
PLAYBACK_INITIATE_PATTERN="playbackInitiatedEvent"
PLAYBACK_END_PATTERN="playbackSessionEndEvent"
CONTENT_LOAD_PATTERN="Player Controller: Load"

# Load configuration if available
if [ -f "$CONFIG_FILE" ]; then
    if command -v jq &> /dev/null; then
        PLAYER_CREATE_PATTERN=$(jq -r '.player_lifecycle.creation_pattern' "$CONFIG_FILE" 2>/dev/null || echo "$PLAYER_CREATE_PATTERN")
        PLAYER_DESTROY_PATTERN=$(jq -r '.player_lifecycle.destruction_pattern' "$CONFIG_FILE" 2>/dev/null || echo "$PLAYER_DESTROY_PATTERN")
        PLAYBACK_INITIATE_PATTERN=$(jq -r '.playback_lifecycle.initiation_pattern' "$CONFIG_FILE" 2>/dev/null || echo "$PLAYBACK_INITIATE_PATTERN")
        PLAYBACK_END_PATTERN=$(jq -r '.playback_lifecycle.end_pattern' "$CONFIG_FILE" 2>/dev/null || echo "$PLAYBACK_END_PATTERN")
        CONTENT_LOAD_PATTERN=$(jq -r '.content_metadata.load_pattern' "$CONFIG_FILE" 2>/dev/null || echo "$CONTENT_LOAD_PATTERN")
    fi
fi

# Player session tracking
PLAYER_ACTIVE=false
PLAYER_SESSION_ID=""
PLAYER_EVENT_COUNT=0
PLAYER_SESSION_START_TIME=""
declare -a PLAYBACK_SESSION_IDS=()  # Array to store all playback session IDs

# Playback session tracking
PLAYBACK_ACTIVE=false
PLAYBACK_SESSION_ID=""
PLAYBACK_EVENT_COUNT=0
PLAYBACK_SESSION_START_TIME=""
PLAYBACK_SESSION_NUMBER=0

# Content metadata tracking
CONTENT_LOAD_ACTIVE=false
CONTENT_ID=""
CONTENT_TITLE=""
CONTENT_TYPE=""
CONTENT_PLAYBACK_POS=""

# Event repetition tracking
LAST_EVENT_NAME=""

# Function to display initial header
show_initial_header() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  PSDK Event Monitor - Player Lifecycle Tracking${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}📊 Monitoring: $1${NC}"
    echo -e "${GREEN}🔍 Tracking: Player creation & destruction${NC}"
    echo -e "${GREEN}⚙️  Config: $(basename "$CONFIG_FILE")${NC}"
    echo ""
    echo -e "${CYAN}───────────────────────────────────────────────────${NC}"
    echo ""
}

# Function to display player creation header
show_player_created() {
    local session_id="$1"
    local time=$(get_timestamp)
    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  🎬 PLAYER SESSION STARTED  Time: ${time}  ║${NC}"
    echo -e "${MAGENTA}╠═══════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC} Session: ${session_id:0:40}... ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to display playback session started
show_playback_started() {
    local session_id="$1"
    local session_num="$2"
    local content_id="$3"
    local content_title="$4"
    local content_type="$5"
    local content_pos="$6"
    local time=$(get_timestamp)
    
    # Format session number to handle different lengths
    local header_text="▶️  PLAYBACK SESSION #${session_num} STARTED"
    
    echo ""
    echo -e "${CYAN}  ┌─────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │ ${header_text}  Time: ${time}  │${NC}"
    echo -e "${CYAN}  ├─────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}  │${NC} Session ID: ${session_id:0:37}  ${CYAN}│${NC}"
    
    # Display content metadata if available
    if [ -n "$content_id" ]; then
        echo -e "${CYAN}  │${NC} Content ID: ${content_id:0:37}  ${CYAN}│${NC}"
    fi
    if [ -n "$content_title" ]; then
        echo -e "${CYAN}  │${NC} Title: ${content_title:0:42}  ${CYAN}│${NC}"
    fi
    if [ -n "$content_type" ]; then
        echo -e "${CYAN}  │${NC} Type: ${content_type:0:43}  ${CYAN}│${NC}"
    fi
    if [ -n "$content_pos" ]; then
        echo -e "${CYAN}  │${NC} Start Position: ${content_pos}s                         ${CYAN}│${NC}"
    fi
    
    echo -e "${CYAN}  └─────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Function to display playback session ended (proper completion)
show_playback_ended() {
    local session_id="$1"
    local session_num="$2"
    local event_count="$3"
    local duration="$4"
    
    # Format the duration and events line
    local stats_line=$(printf "Duration: %ss | Events: %-4s" "$duration" "$event_count")
    
    echo ""
    echo -e "${GREEN}  ┌─────────────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}  │   ⏹️  PLAYBACK SESSION #${session_num} ENDED                │${NC}"
    echo -e "${GREEN}  ├─────────────────────────────────────────────────┤${NC}"
    echo -e "${GREEN}  │${NC} ID: ${session_id:0:41}  ${GREEN}│${NC}"
    echo -e "${GREEN}  │${NC} ${stats_line}                 ${GREEN}│${NC}"
    echo -e "${GREEN}  └─────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Function to display playback session force-closed (when new playback starts without proper end)
show_playback_aborted() {
    local session_id="$1"
    local session_num="$2"
    local event_count="$3"
    local duration="$4"
    
    # Format the duration and events line
    local stats_line=$(printf "Duration: %ss | Events: %-4s" "$duration" "$event_count")
    
    echo ""
    echo -e "${RED}  ┌─────────────────────────────────────────────────┐${NC}"
    echo -e "${RED}  │   ⚠️  PLAYBACK SESSION #${session_num} ABORTED (no end)      │${NC}"
    echo -e "${RED}  ├─────────────────────────────────────────────────┤${NC}"
    echo -e "${RED}  │${NC} ID: ${session_id:0:41}  ${RED}│${NC}"
    echo -e "${RED}  │${NC} ${stats_line}                 ${RED}│${NC}"
    echo -e "${RED}  └─────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Function to display player destruction footer with playback session IDs
show_player_destroyed() {
    local event_count="$1"
    local duration="$2"
    local playback_count="$3"
    shift 3
    local playback_ids=("$@")  # Remaining arguments are playback session IDs
    
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           🛑 PLAYER SESSION ENDED                 ║${NC}"
    echo -e "${RED}╠═══════════════════════════════════════════════════╣${NC}"
    
    # Display playback session IDs
    if [ ${#playback_ids[@]} -gt 0 ]; then
        local idx=1
        for session_id in "${playback_ids[@]}"; do
            echo -e "${RED}║${NC} S${idx}: ${session_id:0:40}${RED}║${NC}"
            ((idx++))
        done
    else
        echo -e "${RED}║${NC} No playback sessions                              ${RED}║${NC}"
    fi
    
    echo -e "${RED}║${NC} Duration: ${duration}s                                    ${RED}║${NC}"
    echo -e "${RED}║${NC} Playback Sessions: ${playback_count}                              ${RED}║${NC}"
    echo -e "${RED}║${NC} Total PSDK Events: ${event_count}                             ${RED}║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to extract playback session ID from log line
extract_session_id() {
    local line="$1"
    # Try to extract playbackSessionId from JSON payload
    if [[ "$line" =~ \"playbackSessionId\":\"([^\"]+)\" ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "unknown"
    fi
}

# Function to get current timestamp with milliseconds
get_timestamp() {
    # Get current time with milliseconds
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        python3 -c "import datetime; print(datetime.datetime.now().strftime('%H:%M:%S.%f')[:-3])"
    else
        # Linux
        date +"%H:%M:%S.%3N"
    fi
}

# Function to extract event name from PSDK log line
extract_event_name() {
    local line="$1"
    
    # Try to extract event name from "key <eventName>" pattern
    if [[ "$line" =~ key[[:space:]]+([a-zA-Z0-9_]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    
    # Try to extract from JSON "event":"<eventName>" pattern
    if [[ "$line" =~ \"event\":\"([^\"]+)\" ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    
    # If no pattern matches, return the line as-is
    echo "$line"
}

# Function to display log line with timestamp (showing only event name)
display_log_with_timestamp() {
    local line="$1"
    local session_num="${2:-0}"  # Optional session number, defaults to 0
    local timestamp=$(get_timestamp)
    local event_name=$(extract_event_name "$line")
    
    # Check if this event is a repeat of the last one
    local is_repeat=false
    if [ "$event_name" = "$LAST_EVENT_NAME" ]; then
        is_repeat=true
    fi
    
    # Update last event
    LAST_EVENT_NAME="$event_name"
    
    # Display with appropriate color
    if [ "$is_repeat" = true ]; then
        # Grey color for repeated events
        if [ "$session_num" -gt 0 ]; then
            echo -e "${CYAN}[${timestamp}]${NC} ${YELLOW}[S${session_num}]${NC} ${GREY}${event_name}${NC}"
        else
            echo -e "${CYAN}[${timestamp}]${NC} ${GREY}${event_name}${NC}"
        fi
    else
        # Normal color for new/different events
        if [ "$session_num" -gt 0 ]; then
            echo -e "${CYAN}[${timestamp}]${NC} ${YELLOW}[S${session_num}]${NC} ${event_name}"
        else
            echo -e "${CYAN}[${timestamp}]${NC} ${event_name}"
        fi
    fi
}

# Check if log file path is provided
if [ -z "$1" ]; then
    echo "Error: No log file specified"
    echo "Usage: $0 <log_file_path>"
    exit 1
fi

LOG_FILE="$1"

# Wait for log file to be created
echo "Waiting for log file: $LOG_FILE"
while [ ! -f "$LOG_FILE" ]; do
    sleep 0.5
done

# Show initial header
show_initial_header "$LOG_FILE"

# Monitor the log file and filter for PSDK events
tail -f "$LOG_FILE" | while IFS= read -r line; do
    # Check for content load start
    if [[ "$line" == *"$CONTENT_LOAD_PATTERN"* ]]; then
        CONTENT_LOAD_ACTIVE=true
        CONTENT_ID=""
        CONTENT_TITLE=""
        CONTENT_TYPE=""
        CONTENT_PLAYBACK_POS=""
        continue
    fi
    
    # Parse content metadata fields when inside a content load block
    if [ "$CONTENT_LOAD_ACTIVE" = true ]; then
        # Check for closing brace - end of content load block
        if [[ "$line" == "}" ]]; then
            CONTENT_LOAD_ACTIVE=false
            continue
        fi
        
        # Extract id
        if [[ "$line" =~ ^id:[[:space:]]*\"([^\"]+)\" ]]; then
            CONTENT_ID="${BASH_REMATCH[1]}"
        fi
        
        # Extract title
        if [[ "$line" =~ ^title:[[:space:]]*\"([^\"]+)\" ]]; then
            CONTENT_TITLE="${BASH_REMATCH[1]}"
        fi
        
        # Extract contentType
        if [[ "$line" =~ ^contentType:[[:space:]]*\"([^\"]+)\" ]]; then
            CONTENT_TYPE="${BASH_REMATCH[1]}"
        fi
        
        # Extract initialPlaybackPosition
        if [[ "$line" =~ ^initialPlaybackPosition:[[:space:]]*([0-9]+) ]]; then
            CONTENT_PLAYBACK_POS="${BASH_REMATCH[1]}"
        fi
        
        continue
    fi
    
    # Check for player creation
    if [[ "$line" == *"$PLAYER_CREATE_PATTERN"* ]]; then
        # If there's an active playback session from previous player, abort it first
        if [ "$PLAYBACK_ACTIVE" = true ]; then
            PLAYBACK_END_TIME=$(date +%s)
            PLAYBACK_DURATION=$((PLAYBACK_END_TIME - PLAYBACK_SESSION_START_TIME))
            show_playback_aborted "$PLAYBACK_SESSION_ID" "$PLAYBACK_SESSION_NUMBER" "$PLAYBACK_EVENT_COUNT" "$PLAYBACK_DURATION"
            PLAYBACK_ACTIVE=false
            PLAYBACK_EVENT_COUNT=0
        fi
        
        # If there was a previous player session active, end it
        if [ "$PLAYER_ACTIVE" = true ]; then
            PLAYER_END_TIME=$(date +%s)
            PLAYER_DURATION=$((PLAYER_END_TIME - PLAYER_SESSION_START_TIME))
            show_player_destroyed "$PLAYER_EVENT_COUNT" "$PLAYER_DURATION" "$PLAYBACK_SESSION_NUMBER" "${PLAYBACK_SESSION_IDS[@]}"
        fi
        
        # Start new player session
        PLAYER_ACTIVE=true
        PLAYER_SESSION_START_TIME=$(date +%s)
        PLAYER_EVENT_COUNT=0
        PLAYBACK_SESSION_NUMBER=0
        PLAYBACK_SESSION_IDS=()  # Reset playback session IDs array
        LAST_EVENT_NAME=""  # Reset event repetition tracking
        PLAYER_SESSION_ID=$(extract_session_id "$line")
        show_player_created "$PLAYER_SESSION_ID"
        display_log_with_timestamp "$line" 0
        continue
    fi
    
    # Check for playback initiation (within player session)
    if [[ "$line" == *"$PLAYBACK_INITIATE_PATTERN"* ]] && [ "$PLAYER_ACTIVE" = true ]; then
        # If there's already an active playback, force-close it first
        if [ "$PLAYBACK_ACTIVE" = true ]; then
            PLAYBACK_END_TIME=$(date +%s)
            PLAYBACK_DURATION=$((PLAYBACK_END_TIME - PLAYBACK_SESSION_START_TIME))
            show_playback_aborted "$PLAYBACK_SESSION_ID" "$PLAYBACK_SESSION_NUMBER" "$PLAYBACK_EVENT_COUNT" "$PLAYBACK_DURATION"
            PLAYBACK_EVENT_COUNT=0
        fi
        
        # Start new playback session
        PLAYBACK_ACTIVE=true
        PLAYBACK_SESSION_START_TIME=$(date +%s)
        PLAYBACK_EVENT_COUNT=0
        ((PLAYBACK_SESSION_NUMBER++))
        PLAYBACK_SESSION_ID=$(extract_session_id "$line")
        LAST_EVENT_NAME=""  # Reset event repetition tracking for new playback session
        
        # Add playback session ID to the array
        PLAYBACK_SESSION_IDS+=("$PLAYBACK_SESSION_ID")
        
        show_playback_started "$PLAYBACK_SESSION_ID" "$PLAYBACK_SESSION_NUMBER" "$CONTENT_ID" "$CONTENT_TITLE" "$CONTENT_TYPE" "$CONTENT_PLAYBACK_POS"
        display_log_with_timestamp "$line" "$PLAYBACK_SESSION_NUMBER"
        
        # Clear content metadata after displaying
        CONTENT_ID=""
        CONTENT_TITLE=""
        CONTENT_TYPE=""
        CONTENT_PLAYBACK_POS=""
        
        continue
    fi
    
    # Check for playback end (within player session)
    if [[ "$line" == *"$PLAYBACK_END_PATTERN"* ]] && [ "$PLAYBACK_ACTIVE" = true ]; then
        # Show the log line first, then the footer
        display_log_with_timestamp "$line" "$PLAYBACK_SESSION_NUMBER"
        PLAYBACK_ACTIVE=false
        PLAYBACK_END_TIME=$(date +%s)
        PLAYBACK_DURATION=$((PLAYBACK_END_TIME - PLAYBACK_SESSION_START_TIME))
        show_playback_ended "$PLAYBACK_SESSION_ID" "$PLAYBACK_SESSION_NUMBER" "$PLAYBACK_EVENT_COUNT" "$PLAYBACK_DURATION"
        PLAYBACK_EVENT_COUNT=0
        continue
    fi
    
    # Check for player destruction (note: different from playbackSessionEndEvent)
    if [[ "$line" == *"$PLAYER_DESTROY_PATTERN"* ]] && [[ "$line" != *"$PLAYBACK_END_PATTERN"* ]] && [ "$PLAYER_ACTIVE" = true ]; then
        # Show the log line first, then the footer
        display_log_with_timestamp "$line" "$PLAYBACK_SESSION_NUMBER"
        PLAYER_ACTIVE=false
        PLAYER_END_TIME=$(date +%s)
        PLAYER_DURATION=$((PLAYER_END_TIME - PLAYER_SESSION_START_TIME))
        
        # Pass event count, duration, playback count, and all playback session IDs
        show_player_destroyed "$PLAYER_EVENT_COUNT" "$PLAYER_DURATION" "$PLAYBACK_SESSION_NUMBER" "${PLAYBACK_SESSION_IDS[@]}"
        
        PLAYER_EVENT_COUNT=0
        PLAYBACK_SESSION_NUMBER=0
        PLAYBACK_SESSION_IDS=()  # Clear the array
        continue
    fi
    
    # Display all PSDK events
    if [[ "$line" == *"PSDK::"* ]]; then
        if [ "$PLAYER_ACTIVE" = true ]; then
            ((PLAYER_EVENT_COUNT++))
            if [ "$PLAYBACK_ACTIVE" = true ]; then
                ((PLAYBACK_EVENT_COUNT++))
            fi
        fi
        
        # Display with session number if playback is active
        if [ "$PLAYBACK_ACTIVE" = true ]; then
            display_log_with_timestamp "$line" "$PLAYBACK_SESSION_NUMBER"
        else
            display_log_with_timestamp "$line" 0
        fi
    fi
done

