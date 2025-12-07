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

# Try multiple locations for config file (package install vs development)
CONFIG_FILE=""
POSSIBLE_CONFIGS=(
    "$SCRIPT_DIR/../config/monitor_config.json"   # Installed package: scripts/../config/
    "$PROJECT_ROOT/config/monitor_config.json"     # Development: project_root/config/
    "$(pwd)/config/monitor_config.json"            # Current working directory
)

for cfg in "${POSSIBLE_CONFIGS[@]}"; do
    if [ -f "$cfg" ]; then
        CONFIG_FILE="$cfg"
        break
    fi
done

# Default patterns (fallback if config not found)
PLAYER_CREATE_PATTERN="PlayerSDK.Core.PlayerBuilder: new"
PLAYER_DESTROY_PATTERN="playerSessionEndEvent"
PLAYBACK_INITIATE_PATTERN="playbackInitiatedEvent"
PLAYBACK_END_PATTERN="playbackSessionEndEvent"
CONTENT_LOAD_PATTERN="Player Controller: Load"

# Default validation config (fallback if config not found)
VALIDATION_ENABLED=true
REQUIRED_FIELDS=("id" "title" "playbackType")
OPTIONAL_FIELDS=("subtitle" "contentType" "initialPlaybackPosition")
SHOW_VALIDATION_RESULTS=true
PLAYBACK_TYPE_ENUM_ENABLED=true
VALID_PLAYBACK_TYPES=("userInitiated" "AUTO" "INLINE" "continuous" "confirmedContinuous" "confirmedEndCard" "autoPlayEndCard")
CONTENT_TYPE_ENUM_ENABLED=true
VALID_CONTENT_TYPES=("episode" "standalone" "clip" "trailer" "live" "follow_up" "listing" "movie" "podcast" "short_preview" "promo" "extra" "standalone_event" "live_channel")

# Load configuration if available
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    if command -v jq &> /dev/null; then
        PLAYER_CREATE_PATTERN=$(jq -r '.player_lifecycle.creation_pattern' "$CONFIG_FILE" 2>/dev/null || echo "$PLAYER_CREATE_PATTERN")
        PLAYER_DESTROY_PATTERN=$(jq -r '.player_lifecycle.destruction_pattern' "$CONFIG_FILE" 2>/dev/null || echo "$PLAYER_DESTROY_PATTERN")
        PLAYBACK_INITIATE_PATTERN=$(jq -r '.playback_lifecycle.initiation_pattern' "$CONFIG_FILE" 2>/dev/null || echo "$PLAYBACK_INITIATE_PATTERN")
        PLAYBACK_END_PATTERN=$(jq -r '.playback_lifecycle.end_pattern' "$CONFIG_FILE" 2>/dev/null || echo "$PLAYBACK_END_PATTERN")
        CONTENT_LOAD_PATTERN=$(jq -r '.content_metadata.load_pattern' "$CONFIG_FILE" 2>/dev/null || echo "$CONTENT_LOAD_PATTERN")
        
        # Load validation configuration
        VALIDATION_ENABLED=$(jq -r '.content_metadata.validation.enabled // true' "$CONFIG_FILE" 2>/dev/null)
        SHOW_VALIDATION_RESULTS=$(jq -r '.display.show_validation_results // true' "$CONFIG_FILE" 2>/dev/null)
        
        # Load required fields array
        if [ "$(jq -r '.content_metadata.validation.required_fields' "$CONFIG_FILE" 2>/dev/null)" != "null" ]; then
            mapfile -t REQUIRED_FIELDS < <(jq -r '.content_metadata.validation.required_fields[]' "$CONFIG_FILE" 2>/dev/null)
        fi
        
        # Load optional fields array
        if [ "$(jq -r '.content_metadata.validation.optional_fields' "$CONFIG_FILE" 2>/dev/null)" != "null" ]; then
            mapfile -t OPTIONAL_FIELDS < <(jq -r '.content_metadata.validation.optional_fields[]' "$CONFIG_FILE" 2>/dev/null)
        fi
        
        # Load playbackType enum validation
        PLAYBACK_TYPE_ENUM_ENABLED=$(jq -r '.content_metadata.validation.playback_type_enum.enabled // true' "$CONFIG_FILE" 2>/dev/null)
        if [ "$(jq -r '.content_metadata.validation.playback_type_enum.valid_values' "$CONFIG_FILE" 2>/dev/null)" != "null" ]; then
            mapfile -t VALID_PLAYBACK_TYPES < <(jq -r '.content_metadata.validation.playback_type_enum.valid_values[]' "$CONFIG_FILE" 2>/dev/null)
        fi
        
        # Load contentType enum validation
        CONTENT_TYPE_ENUM_ENABLED=$(jq -r '.content_metadata.validation.content_type_enum.enabled // true' "$CONFIG_FILE" 2>/dev/null)
        if [ "$(jq -r '.content_metadata.validation.content_type_enum.valid_values' "$CONFIG_FILE" 2>/dev/null)" != "null" ]; then
            mapfile -t VALID_CONTENT_TYPES < <(jq -r '.content_metadata.validation.content_type_enum.valid_values[]' "$CONFIG_FILE" 2>/dev/null)
        fi
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
CONTENT_SUBTITLE=""
CONTENT_TYPE=""
CONTENT_PLAYBACK_TYPE=""
CONTENT_PLAYBACK_POS=""

# Content metadata tracking for validation (per playback session)
declare -A SESSION_METADATA_CAPTURED  # Tracks which fields were captured
SESSION_METADATA_ID=""
SESSION_METADATA_TITLE=""
SESSION_METADATA_SUBTITLE=""
SESSION_METADATA_TYPE=""
SESSION_METADATA_PLAYBACK_TYPE=""
SESSION_METADATA_POS=""

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
    
    if [ -n "$session_id" ]; then
        echo -e "${MAGENTA}║${NC} Session: ${session_id:0:40}... ${MAGENTA}║${NC}"
    else
        echo -e "${MAGENTA}║${NC} (Connected mid-stream - auto-created session)   ${MAGENTA}║${NC}"
    fi
    
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to display playback session started
show_playback_started() {
    local session_id="$1"
    local session_num="$2"
    local content_id="$3"
    local content_title="$4"
    local content_subtitle="$5"
    local content_type="$6"
    local playback_type="$7"
    local content_pos="$8"
    local time=$(get_timestamp)
    
    # Helper function to format a box row with exact width (65 chars for full UUIDs)
    format_row() {
        local content="$1"
        local width=65
        local len=${#content}
        if [ $len -gt $width ]; then
            content="${content:0:$((width-3))}..."
        fi
        printf "  ${CYAN}│${NC} %-65s ${CYAN}│${NC}\n" "$content"
    }
    
    echo ""
    echo -e "  ${CYAN}┌───────────────────────────────────────────────────────────────────┐${NC}"
    format_row "▶️  PLAYBACK #${session_num}  Time: ${time}"
    echo -e "  ${CYAN}├───────────────────────────────────────────────────────────────────┤${NC}"
    format_row "Session: ${session_id}"
    
    # Display content metadata if available
    if [ -n "$content_id" ]; then
        format_row "ID(editId): ${content_id}"
    fi
    if [ -n "$content_title" ]; then
        format_row "Title: ${content_title}"
    fi
    if [ -n "$content_subtitle" ]; then
        format_row "Subtitle: ${content_subtitle}"
    fi
    if [ -n "$content_type" ]; then
        format_row "contentType: ${content_type}"
    fi
    # Always show playbackType, display ❌ (invalid) if not available
    if [ -n "$playback_type" ]; then
        format_row "playbackType: ${playback_type}"
    else
        format_row "playbackType: ❌ (missing)"
    fi
    if [ -n "$content_pos" ]; then
        format_row "Start Position: ${content_pos}ms"
    fi
    
    echo -e "  ${CYAN}└───────────────────────────────────────────────────────────────────┘${NC}"
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
    
    # Get validation result
    local validation_result=""
    if [ "$SHOW_VALIDATION_RESULTS" = "true" ]; then
        validation_result=$(validate_content_metadata)
    fi
    
    # Helper function for footer rows
    format_footer_row() {
        local content="$1"
        local color="$2"
        printf "  ${color}│${NC} %-65s ${color}│${NC}\n" "$content"
    }
    
    echo ""
    echo -e "${GREEN}  ┌───────────────────────────────────────────────────────────────────┐${NC}"
    format_footer_row "⏹️  PLAYBACK SESSION #${session_num} ENDED" "${GREEN}"
    echo -e "${GREEN}  ├───────────────────────────────────────────────────────────────────┤${NC}"
    format_footer_row "Session: ${session_id}" "${GREEN}"
    format_footer_row "${stats_line}" "${GREEN}"
    
    # Display validation result if enabled and available
    if [ "$SHOW_VALIDATION_RESULTS" = "true" ] && [ -n "$validation_result" ]; then
        echo -e "${GREEN}  ├───────────────────────────────────────────────────────────────────┤${NC}"
        format_footer_row "ContentMetadata: ${validation_result}" "${GREEN}"
    fi
    
    echo -e "${GREEN}  └───────────────────────────────────────────────────────────────────┘${NC}"
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
    
    # Helper function for aborted footer rows
    format_aborted_row() {
        local content="$1"
        printf "  ${RED}│${NC} %-65s ${RED}│${NC}\n" "$content"
    }
    
    echo ""
    echo -e "${RED}  ┌───────────────────────────────────────────────────────────────────┐${NC}"
    format_aborted_row "⚠️  PLAYBACK SESSION #${session_num} ABORTED (no end event)"
    echo -e "${RED}  ├───────────────────────────────────────────────────────────────────┤${NC}"
    format_aborted_row "Session: ${session_id}"
    format_aborted_row "${stats_line}"
    echo -e "${RED}  └───────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Function to validate content metadata and return validation result
validate_content_metadata() {
    # Check if validation is enabled
    if [ "$VALIDATION_ENABLED" != "true" ]; then
        echo ""
        return
    fi
    
    local missing_required=()
    local missing_optional=()
    local present_count=0
    local total_fields=$((${#REQUIRED_FIELDS[@]} + ${#OPTIONAL_FIELDS[@]}))
    
    # Check required fields
    for field in "${REQUIRED_FIELDS[@]}"; do
        case "$field" in
            "id")
                if [ -n "$SESSION_METADATA_ID" ]; then
                    ((present_count++))
                else
                    missing_required+=("$field")
                fi
                ;;
            "title")
                if [ -n "$SESSION_METADATA_TITLE" ]; then
                    ((present_count++))
                else
                    missing_required+=("$field")
                fi
                ;;
            "playbackType")
                if [ -n "$SESSION_METADATA_PLAYBACK_TYPE" ]; then
                    ((present_count++))
                else
                    missing_required+=("$field")
                fi
                ;;
            "subtitle")
                if [ -n "$SESSION_METADATA_SUBTITLE" ]; then
                    ((present_count++))
                fi
                ;;
            "contentType")
                if [ -n "$SESSION_METADATA_TYPE" ]; then
                    ((present_count++))
                fi
                ;;
            "initialPlaybackPosition")
                if [ -n "$SESSION_METADATA_POS" ]; then
                    ((present_count++))
                fi
                ;;
        esac
    done
    
    # Check optional fields
    for field in "${OPTIONAL_FIELDS[@]}"; do
        case "$field" in
            "id")
                if [ -n "$SESSION_METADATA_ID" ]; then
                    ((present_count++))
                else
                    missing_optional+=("$field")
                fi
                ;;
            "title")
                if [ -n "$SESSION_METADATA_TITLE" ]; then
                    ((present_count++))
                else
                    missing_optional+=("$field")
                fi
                ;;
            "playbackType")
                if [ -n "$SESSION_METADATA_PLAYBACK_TYPE" ]; then
                    ((present_count++))
                else
                    missing_optional+=("$field")
                fi
                ;;
            "subtitle")
                if [ -n "$SESSION_METADATA_SUBTITLE" ]; then
                    ((present_count++))
                else
                    missing_optional+=("$field")
                fi
                ;;
            "contentType")
                if [ -n "$SESSION_METADATA_TYPE" ]; then
                    ((present_count++))
                else
                    missing_optional+=("$field")
                fi
                ;;
            "initialPlaybackPosition")
                if [ -n "$SESSION_METADATA_POS" ]; then
                    ((present_count++))
                else
                    missing_optional+=("$field")
                fi
                ;;
        esac
    done
    
    # Validate playbackType enum value if enabled and field is present
    local invalid_playback_enum=false
    local invalid_playback_msg=""
    
    if [ "$PLAYBACK_TYPE_ENUM_ENABLED" = "true" ] && [ -n "$SESSION_METADATA_PLAYBACK_TYPE" ]; then
        # Check if playbackType value is in the valid list
        local is_valid_playback=false
        for valid_type in "${VALID_PLAYBACK_TYPES[@]}"; do
            if [ "$SESSION_METADATA_PLAYBACK_TYPE" = "$valid_type" ]; then
                is_valid_playback=true
                break
            fi
        done
        
        if [ "$is_valid_playback" = false ]; then
            invalid_playback_enum=true
            invalid_playback_msg="Invalid playbackType: '$SESSION_METADATA_PLAYBACK_TYPE'"
        fi
    fi
    
    # Validate contentType enum value if enabled and field is present
    local invalid_content_enum=false
    local invalid_content_msg=""
    
    if [ "$CONTENT_TYPE_ENUM_ENABLED" = "true" ] && [ -n "$SESSION_METADATA_TYPE" ]; then
        # Check if contentType value is in the valid list
        local is_valid_content=false
        for valid_type in "${VALID_CONTENT_TYPES[@]}"; do
            if [ "$SESSION_METADATA_TYPE" = "$valid_type" ]; then
                is_valid_content=true
                break
            fi
        done
        
        if [ "$is_valid_content" = false ]; then
            invalid_content_enum=true
            invalid_content_msg="Invalid contentType: '$SESSION_METADATA_TYPE'"
        fi
    fi
    
    # Build validation result string
    local validation_result=""
    local has_errors=false
    
    # Check if there are any validation errors
    if [ ${#missing_required[@]} -gt 0 ] || [ "$invalid_playback_enum" = true ] || [ "$invalid_content_enum" = true ]; then
        has_errors=true
    fi
    
    if [ "$has_errors" = false ]; then
        # All required fields present and valid - VALID
        validation_result="✅ VALID"
        if [ ${#missing_optional[@]} -gt 0 ]; then
            validation_result="${validation_result} (${present_count}/${total_fields} fields)"
        else
            validation_result="${validation_result} (All fields present)"
        fi
    else
        # Missing required fields or invalid enum - INVALID
        validation_result="❌ INVALID"
        local first_error=true
        
        # Add missing required fields
        if [ ${#missing_required[@]} -gt 0 ]; then
            validation_result="${validation_result} - Missing required: ${missing_required[*]}"
            first_error=false
        fi
        
        # Add invalid playbackType enum
        if [ "$invalid_playback_enum" = true ]; then
            if [ "$first_error" = true ]; then
                validation_result="${validation_result} - ${invalid_playback_msg}"
                first_error=false
            else
                validation_result="${validation_result}; ${invalid_playback_msg}"
            fi
        fi
        
        # Add invalid contentType enum
        if [ "$invalid_content_enum" = true ]; then
            if [ "$first_error" = true ]; then
                validation_result="${validation_result} - ${invalid_content_msg}"
                first_error=false
            else
                validation_result="${validation_result}; ${invalid_content_msg}"
            fi
        fi
        
        # Add missing optional fields
        if [ ${#missing_optional[@]} -gt 0 ]; then
            validation_result="${validation_result}, optional: ${missing_optional[*]}"
        fi
    fi
    
    echo "$validation_result"
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
        # Grey color for repeated events (no blank line for repeats)
        if [ "$session_num" -gt 0 ]; then
            echo -e "${CYAN}[${timestamp}]${NC} ${YELLOW}[S${session_num}]${NC} ${GREY}${event_name}${NC}"
        else
            echo -e "${CYAN}[${timestamp}]${NC} ${GREY}${event_name}${NC}"
        fi
    else
        # New/different event - add blank line for visual separation
        echo ""
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
    echo "Usage: $0 <log_file_path> [pattern1] [pattern2] ..."
    exit 1
fi

LOG_FILE="$1"
shift  # Remove log file from arguments, remaining are custom patterns

# Store custom patterns in an array
CUSTOM_PATTERNS=("$@")

# Wait for log file to be created
echo "Waiting for log file: $LOG_FILE"
while [ ! -f "$LOG_FILE" ]; do
    sleep 0.5
done

# Show initial header
show_initial_header "$LOG_FILE"

# Show custom patterns if provided
if [ ${#CUSTOM_PATTERNS[@]} -gt 0 ]; then
    echo -e "${MAGENTA}📌 Custom Patterns: ${CUSTOM_PATTERNS[*]}${NC}"
    echo ""
fi

# Monitor the log file and filter for PSDK events
tail -f "$LOG_FILE" | while IFS= read -r line; do
    # Check for content load start
    if [[ "$line" == *"$CONTENT_LOAD_PATTERN"* ]]; then
        CONTENT_LOAD_ACTIVE=true
        CONTENT_ID=""
        CONTENT_TITLE=""
        CONTENT_SUBTITLE=""
        CONTENT_TYPE=""
        CONTENT_PLAYBACK_TYPE=""
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
        
        # Extract id (handle both with and without leading whitespace)
        if [[ "$line" =~ ^[[:space:]]*id:[[:space:]]*\"([^\"]+)\" ]]; then
            CONTENT_ID="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ \"id\":\"([^\"]+)\" ]]; then
            CONTENT_ID="${BASH_REMATCH[1]}"
        fi
        
        # Extract title (handle both with and without leading whitespace)
        if [[ "$line" =~ ^[[:space:]]*title:[[:space:]]*\"([^\"]+)\" ]]; then
            CONTENT_TITLE="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ \"title\":\"([^\"]+)\" ]]; then
            CONTENT_TITLE="${BASH_REMATCH[1]}"
        fi
        
        # Extract subtitle (prioritize 'subtitle' over 'originalSubtitle')
        # 'subtitle' contains episode name, 'originalSubtitle' contains series name
        # Handle both with and without leading whitespace
        if [[ "$line" =~ ^[[:space:]]*subtitle:[[:space:]]*\"([^\"]+)\" ]]; then
            CONTENT_SUBTITLE="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*subTitle:[[:space:]]*\"([^\"]+)\" ]]; then
            CONTENT_SUBTITLE="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*originalSubtitle:[[:space:]]*\"([^\"]+)\" ]]; then
            CONTENT_SUBTITLE="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ \"subtitle\":\"([^\"]+)\" ]]; then
            CONTENT_SUBTITLE="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ \"subTitle\":\"([^\"]+)\" ]]; then
            CONTENT_SUBTITLE="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ \"originalSubtitle\":\"([^\"]+)\" ]]; then
            CONTENT_SUBTITLE="${BASH_REMATCH[1]}"
        fi
        
        # Extract contentType (handle both with and without leading whitespace)
        if [[ "$line" =~ ^[[:space:]]*contentType:[[:space:]]*\"([^\"]+)\" ]]; then
            CONTENT_TYPE="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ \"contentType\":\"([^\"]+)\" ]]; then
            CONTENT_TYPE="${BASH_REMATCH[1]}"
        fi
        
        # Extract playbackType (handle leading whitespace and case variations)
        if [[ "$line" =~ ^[[:space:]]*playbackType:[[:space:]]*\"([^\"]+)\" ]]; then
            CONTENT_PLAYBACK_TYPE="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*PlaybackType:[[:space:]]*\"([^\"]+)\" ]]; then
            CONTENT_PLAYBACK_TYPE="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ \"playbackType\":\"([^\"]+)\" ]]; then
            CONTENT_PLAYBACK_TYPE="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ \"PlaybackType\":\"([^\"]+)\" ]]; then
            CONTENT_PLAYBACK_TYPE="${BASH_REMATCH[1]}"
        fi
        
        # Extract initialPlaybackPosition (handle leading whitespace)
        if [[ "$line" =~ ^[[:space:]]*initialPlaybackPosition:[[:space:]]*([0-9]+) ]]; then
            CONTENT_PLAYBACK_POS="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ \"initialPlaybackPosition\":([0-9]+) ]]; then
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
            
            # Clear session metadata when aborted
            SESSION_METADATA_ID=""
            SESSION_METADATA_TITLE=""
            SESSION_METADATA_SUBTITLE=""
            SESSION_METADATA_TYPE=""
            SESSION_METADATA_PLAYBACK_TYPE=""
            SESSION_METADATA_POS=""
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
    
    # Check for playback initiation
    if [[ "$line" == *"$PLAYBACK_INITIATE_PATTERN"* ]]; then
        # If no player session is active (e.g., connected mid-stream), auto-create one
        if [ "$PLAYER_ACTIVE" = false ]; then
            PLAYER_ACTIVE=true
            PLAYER_SESSION_START_TIME=$(date +%s)
            PLAYER_EVENT_COUNT=0
            PLAYBACK_SESSION_NUMBER=0
            PLAYBACK_SESSION_IDS=()
            LAST_EVENT_NAME=""
            show_player_created
        fi
        
        # If there's already an active playback, force-close it first
        if [ "$PLAYBACK_ACTIVE" = true ]; then
            PLAYBACK_END_TIME=$(date +%s)
            PLAYBACK_DURATION=$((PLAYBACK_END_TIME - PLAYBACK_SESSION_START_TIME))
            show_playback_aborted "$PLAYBACK_SESSION_ID" "$PLAYBACK_SESSION_NUMBER" "$PLAYBACK_EVENT_COUNT" "$PLAYBACK_DURATION"
            PLAYBACK_EVENT_COUNT=0
            
            # Clear session metadata when aborted
            SESSION_METADATA_ID=""
            SESSION_METADATA_TITLE=""
            SESSION_METADATA_SUBTITLE=""
            SESSION_METADATA_TYPE=""
            SESSION_METADATA_PLAYBACK_TYPE=""
            SESSION_METADATA_POS=""
        fi
        
        # Start new playback session
        PLAYBACK_ACTIVE=true
        PLAYBACK_SESSION_START_TIME=$(date +%s)
        PLAYBACK_EVENT_COUNT=0
        ((PLAYBACK_SESSION_NUMBER++))
        PLAYBACK_SESSION_ID=$(extract_session_id "$line")
        LAST_EVENT_NAME=""  # Reset event repetition tracking for new playback session
        
        # Try to extract playbackType from the event line if not already set
        if [ -z "$CONTENT_PLAYBACK_TYPE" ]; then
            if [[ "$line" =~ \"playbackType\":\"([^\"]+)\" ]] || [[ "$line" =~ \"PlaybackType\":\"([^\"]+)\" ]]; then
                CONTENT_PLAYBACK_TYPE="${BASH_REMATCH[1]}"
            fi
        fi
        
        # Add playback session ID to the array
        PLAYBACK_SESSION_IDS+=("$PLAYBACK_SESSION_ID")
        
        # Save content metadata to session variables for validation
        SESSION_METADATA_ID="$CONTENT_ID"
        SESSION_METADATA_TITLE="$CONTENT_TITLE"
        SESSION_METADATA_SUBTITLE="$CONTENT_SUBTITLE"
        SESSION_METADATA_TYPE="$CONTENT_TYPE"
        SESSION_METADATA_PLAYBACK_TYPE="$CONTENT_PLAYBACK_TYPE"
        SESSION_METADATA_POS="$CONTENT_PLAYBACK_POS"
        
        show_playback_started "$PLAYBACK_SESSION_ID" "$PLAYBACK_SESSION_NUMBER" "$CONTENT_ID" "$CONTENT_TITLE" "$CONTENT_SUBTITLE" "$CONTENT_TYPE" "$CONTENT_PLAYBACK_TYPE" "$CONTENT_PLAYBACK_POS"
        display_log_with_timestamp "$line" "$PLAYBACK_SESSION_NUMBER"
        
        # Clear content metadata after displaying (but keep session metadata for validation)
        CONTENT_ID=""
        CONTENT_TITLE=""
        CONTENT_SUBTITLE=""
        CONTENT_TYPE=""
        CONTENT_PLAYBACK_TYPE=""
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
        
        # Clear session metadata after validation
        SESSION_METADATA_ID=""
        SESSION_METADATA_TITLE=""
        SESSION_METADATA_SUBTITLE=""
        SESSION_METADATA_TYPE=""
        SESSION_METADATA_PLAYBACK_TYPE=""
        SESSION_METADATA_POS=""
        
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
    
    # Check if line matches PSDK:: or any custom pattern
    matches_pattern=false
    is_custom_pattern=false
    
    # Check for PSDK:: events
    if [[ "$line" == *"PSDK::"* ]]; then
        matches_pattern=true
    fi
    
    # Check for custom patterns if provided
    if [ ${#CUSTOM_PATTERNS[@]} -gt 0 ]; then
        for pattern in "${CUSTOM_PATTERNS[@]}"; do
            if [[ "$line" == *"$pattern"* ]]; then
                matches_pattern=true
                is_custom_pattern=true
                break
            fi
        done
    fi
    
    # Display matching events
    if [ "$matches_pattern" = true ]; then
        # Auto-create player session if not active (connected mid-stream) - only for PSDK events
        if [[ "$line" == *"PSDK::"* ]] && [ "$PLAYER_ACTIVE" = false ]; then
            PLAYER_ACTIVE=true
            PLAYER_SESSION_START_TIME=$(date +%s)
            PLAYER_EVENT_COUNT=0
            PLAYBACK_SESSION_NUMBER=0
            PLAYBACK_SESSION_IDS=()
            LAST_EVENT_NAME=""
            show_player_created
        fi
        
        # Increment event counters only for PSDK events
        if [[ "$line" == *"PSDK::"* ]]; then
            ((PLAYER_EVENT_COUNT++))
            if [ "$PLAYBACK_ACTIVE" = true ]; then
                ((PLAYBACK_EVENT_COUNT++))
            fi
        fi
        
        # Display custom pattern matches
        if [ "$is_custom_pattern" = true ]; then
            # Custom pattern: show full line with special formatting (with blank line for separation)
            echo ""
            custom_timestamp=$(get_timestamp)
            echo -e "${CYAN}[${custom_timestamp}]${NC} ${MAGENTA}[CUSTOM]${NC} $line"
            # Reset last event name so next PSDK event gets proper spacing
            LAST_EVENT_NAME=""
        fi
        
        # Display PSDK events (separate from custom - a line can match both)
        if [[ "$line" == *"PSDK::"* ]] && [ "$is_custom_pattern" = false ]; then
            if [ "$PLAYBACK_ACTIVE" = true ]; then
                display_log_with_timestamp "$line" "$PLAYBACK_SESSION_NUMBER"
            else
                display_log_with_timestamp "$line" 0
            fi
        fi
    fi
done

