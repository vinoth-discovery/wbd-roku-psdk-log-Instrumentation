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

# Default ISDK validation config
ISDK_VALIDATION_ENABLED=true
ISDK_SHOW_EVENT_LIST=true

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
        
        # Load required fields array (bash 3.2 compatible)
        if [ "$(jq -r '.content_metadata.validation.required_fields' "$CONFIG_FILE" 2>/dev/null)" != "null" ]; then
            REQUIRED_FIELDS=()
            while IFS= read -r field; do
                REQUIRED_FIELDS+=("$field")
            done < <(jq -r '.content_metadata.validation.required_fields[]' "$CONFIG_FILE" 2>/dev/null)
        fi
        
        # Load optional fields array (bash 3.2 compatible)
        if [ "$(jq -r '.content_metadata.validation.optional_fields' "$CONFIG_FILE" 2>/dev/null)" != "null" ]; then
            OPTIONAL_FIELDS=()
            while IFS= read -r field; do
                OPTIONAL_FIELDS+=("$field")
            done < <(jq -r '.content_metadata.validation.optional_fields[]' "$CONFIG_FILE" 2>/dev/null)
        fi
        
        # Load playbackType enum validation (bash 3.2 compatible)
        PLAYBACK_TYPE_ENUM_ENABLED=$(jq -r '.content_metadata.validation.playback_type_enum.enabled // true' "$CONFIG_FILE" 2>/dev/null)
        if [ "$(jq -r '.content_metadata.validation.playback_type_enum.valid_values' "$CONFIG_FILE" 2>/dev/null)" != "null" ]; then
            VALID_PLAYBACK_TYPES=()
            while IFS= read -r val; do
                VALID_PLAYBACK_TYPES+=("$val")
            done < <(jq -r '.content_metadata.validation.playback_type_enum.valid_values[]' "$CONFIG_FILE" 2>/dev/null)
        fi
        
        # Load contentType enum validation (bash 3.2 compatible)
        CONTENT_TYPE_ENUM_ENABLED=$(jq -r '.content_metadata.validation.content_type_enum.enabled // true' "$CONFIG_FILE" 2>/dev/null)
        if [ "$(jq -r '.content_metadata.validation.content_type_enum.valid_values' "$CONFIG_FILE" 2>/dev/null)" != "null" ]; then
            VALID_CONTENT_TYPES=()
            while IFS= read -r val; do
                VALID_CONTENT_TYPES+=("$val")
            done < <(jq -r '.content_metadata.validation.content_type_enum.valid_values[]' "$CONFIG_FILE" 2>/dev/null)
        fi
        
        # Load event fields configuration
        EVENT_FIELDS_ENABLED=$(jq -r '.event_fields.enabled // false' "$CONFIG_FILE" 2>/dev/null)
        
        # Store the full config for per-event field lookup
        EVENT_FIELDS_CONFIG="$CONFIG_FILE"
        
        # Load ISDK validation configuration
        ISDK_VALIDATION_ENABLED=$(jq -r '.isdk_validation.enabled // true' "$CONFIG_FILE" 2>/dev/null)
        ISDK_SHOW_EVENT_LIST=$(jq -r '.isdk_validation.show_event_list // true' "$CONFIG_FILE" 2>/dev/null)
    fi
fi

# Function to get fields for a specific event name
get_event_fields() {
    local event_name="$1"
    local is_isdk="$2"
    local config_path
    
    if [ "$is_isdk" = true ]; then
        config_path=".event_fields.isdk_events"
    else
        config_path=".event_fields.psdk_events"
    fi
    
    # Try to get fields for specific event name
    local fields=$(jq -r "${config_path}.\"${event_name}\" // empty" "$EVENT_FIELDS_CONFIG" 2>/dev/null)
    
    # If no specific config, use default
    if [ -z "$fields" ] || [ "$fields" = "null" ]; then
        fields=$(jq -r "${config_path}.default // empty" "$EVENT_FIELDS_CONFIG" 2>/dev/null)
    fi
    
    # Output fields as array
    if [ -n "$fields" ] && [ "$fields" != "null" ]; then
        echo "$fields" | jq -r '.[]' 2>/dev/null
    fi
}

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
SESSION_METADATA_ID=""
SESSION_METADATA_TITLE=""

# ISDK event tracking for validation
ISDK_EVENT_LIST=""           # Comma-separated list of ISDK event names
ISDK_EVENT_COUNT=0           # Count of ISDK events
SESSION_METADATA_SUBTITLE=""
SESSION_METADATA_TYPE=""
SESSION_METADATA_PLAYBACK_TYPE=""
SESSION_METADATA_POS=""

# Event repetition tracking
LAST_EVENT_NAME=""

# Function to display initial header
show_initial_header() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  PSDK Event Monitor - Player Lifecycle Tracking${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}📊 Monitoring: $1${NC}"
    echo -e "${GREEN}🔍 Tracking: Player creation & destruction${NC}"
    echo -e "${GREEN}⚙️  Config: $(basename "$CONFIG_FILE")${NC}"
    echo ""
    echo -e "${CYAN}──────────────────────────────────────────────────────────${MAGENTA}┬${CYAN}───────────────────────────────────────────────────${NC}"
    printf "${CYAN}%-58s${MAGENTA}│${NC} %-50s\n" "  PSDK Events" "  ISDK Events"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${MAGENTA}┼${CYAN}───────────────────────────────────────────────────${NC}"
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

# Function to display column headers for PSDK | ISDK layout (forward declaration)
show_column_headers() {
    echo -e "${CYAN}───────────────────────────────────────────────────────────────────────────────${MAGENTA}┬${CYAN}───────────────────────────────────────────────────${NC}"
    printf "${CYAN}  %-77s${MAGENTA}│${NC} %-50s\n" "PSDK Events" "ISDK Events"
    echo -e "${CYAN}───────────────────────────────────────────────────────────────────────────────${MAGENTA}┼${CYAN}───────────────────────────────────────────────────${NC}"
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
    
    # Box line helper with proper width calculation
    box_line() {
        local content="$1"
        local color="$2"
        local width=67
        local padding=$((width - ${#content}))
        if [ $padding -lt 0 ]; then padding=0; fi
        local spaces=$(printf '%*s' $padding '')
        echo -e "  ${color}│${NC} ${content}${spaces}${color}│${NC}"
    }
    
    echo ""
    echo -e "  ${CYAN}┌───────────────────────────────────────────────────────────────────┐${NC}"
    box_line "PLAYBACK #${session_num} STARTED  Time: ${time}" "${CYAN}"
    echo -e "  ${CYAN}├───────────────────────────────────────────────────────────────────┤${NC}"
    box_line "Session: ${session_id}" "${CYAN}"
    
    # Display content metadata if available
    if [ -n "$content_id" ]; then
        box_line "ID(editId): ${content_id}" "${CYAN}"
    fi
    if [ -n "$content_title" ]; then
        box_line "Title: ${content_title}" "${CYAN}"
    fi
    if [ -n "$content_subtitle" ]; then
        box_line "Subtitle: ${content_subtitle}" "${CYAN}"
    fi
    if [ -n "$content_type" ]; then
        box_line "contentType: ${content_type}" "${CYAN}"
    fi
    # Always show playbackType
    if [ -n "$playback_type" ]; then
        box_line "playbackType: ${playback_type}" "${CYAN}"
    else
        box_line "playbackType: (missing)" "${CYAN}"
    fi
    if [ -n "$content_pos" ]; then
        box_line "Start Position: ${content_pos}ms" "${CYAN}"
    fi
    
    echo -e "  ${CYAN}└───────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    # Show column headers after playback started
    show_column_headers
}

# Function to display playback session ended (proper completion)
show_playback_ended() {
    local session_id="$1"
    local session_num="$2"
    local event_count="$3"
    local duration="$4"
    
    # Helper function for footer rows (67 char box width)
    format_row() {
        local content="$1"
        local color="$2"
        # Print content and pad to fixed width, accounting for emoji width issues
        echo -e "  ${color}│${NC} ${content}"
    }
    
    # Box line helper
    box_line() {
        local content="$1"
        local color="$2"
        local width=67
        local padding=$((width - ${#content}))
        if [ $padding -lt 0 ]; then padding=0; fi
        local spaces=$(printf '%*s' $padding '')
        echo -e "  ${color}│${NC} ${content}${spaces}${color}│${NC}"
    }
    
    echo ""
    echo -e "${GREEN}  ┌───────────────────────────────────────────────────────────────────┐${NC}"
    box_line "PLAYBACK SESSION #${session_num} ENDED" "${GREEN}"
    echo -e "${GREEN}  ├───────────────────────────────────────────────────────────────────┤${NC}"
    box_line "Session: ${session_id}" "${GREEN}"
    box_line "Duration: ${duration}s | Events: ${event_count}" "${GREEN}"
    
    # Display validation results if enabled
    if [ "$SHOW_VALIDATION_RESULTS" = "true" ] && [ "$VALIDATION_ENABLED" = "true" ]; then
        echo -e "${GREEN}  ├───────────────────────────────────────────────────────────────────┤${NC}"
        
        # Perform validation and display line by line
        local has_errors=false
        local missing_required=()
        local missing_optional=()
        local invalid_playback_type=""
        local invalid_content_type=""
        
        # Check required fields
        for field in "${REQUIRED_FIELDS[@]}"; do
            case "$field" in
                "id") [ -z "$SESSION_METADATA_ID" ] && missing_required+=("id") ;;
                "title") [ -z "$SESSION_METADATA_TITLE" ] && missing_required+=("title") ;;
                "playbackType") [ -z "$SESSION_METADATA_PLAYBACK_TYPE" ] && missing_required+=("playbackType") ;;
            esac
        done
        
        # Check optional fields
        for field in "${OPTIONAL_FIELDS[@]}"; do
            case "$field" in
                "subtitle") [ -z "$SESSION_METADATA_SUBTITLE" ] && missing_optional+=("subtitle") ;;
                "contentType") [ -z "$SESSION_METADATA_TYPE" ] && missing_optional+=("contentType") ;;
                "initialPlaybackPosition") [ -z "$SESSION_METADATA_POS" ] && missing_optional+=("initialPlaybackPosition") ;;
            esac
        done
        
        # Validate playbackType enum
        if [ "$PLAYBACK_TYPE_ENUM_ENABLED" = "true" ] && [ -n "$SESSION_METADATA_PLAYBACK_TYPE" ]; then
            local is_valid=false
            for valid_type in "${VALID_PLAYBACK_TYPES[@]}"; do
                [ "$SESSION_METADATA_PLAYBACK_TYPE" = "$valid_type" ] && is_valid=true && break
            done
            [ "$is_valid" = false ] && invalid_playback_type="$SESSION_METADATA_PLAYBACK_TYPE"
        fi
        
        # Validate contentType enum
        if [ "$CONTENT_TYPE_ENUM_ENABLED" = "true" ] && [ -n "$SESSION_METADATA_TYPE" ]; then
            local is_valid=false
            for valid_type in "${VALID_CONTENT_TYPES[@]}"; do
                [ "$SESSION_METADATA_TYPE" = "$valid_type" ] && is_valid=true && break
            done
            [ "$is_valid" = false ] && invalid_content_type="$SESSION_METADATA_TYPE"
        fi
        
        # Determine if valid or invalid
        if [ ${#missing_required[@]} -gt 0 ] || [ -n "$invalid_playback_type" ] || [ -n "$invalid_content_type" ]; then
            has_errors=true
        fi
        
        # Display validation header
        if [ "$has_errors" = true ]; then
            box_line "ContentMetadata Validation: INVALID" "${GREEN}"
        else
            local present=$((${#REQUIRED_FIELDS[@]} + ${#OPTIONAL_FIELDS[@]} - ${#missing_optional[@]}))
            local total=$((${#REQUIRED_FIELDS[@]} + ${#OPTIONAL_FIELDS[@]}))
            if [ ${#missing_optional[@]} -eq 0 ]; then
                box_line "ContentMetadata Validation: VALID (All fields present)" "${GREEN}"
            else
                box_line "ContentMetadata Validation: VALID (${present}/${total} fields)" "${GREEN}"
            fi
        fi
        
        # Display line-by-line validation details
        if [ ${#missing_required[@]} -gt 0 ]; then
            box_line "  - Missing required: ${missing_required[*]}" "${GREEN}"
        fi
        if [ -n "$invalid_playback_type" ]; then
            box_line "  - Invalid playbackType: '${invalid_playback_type}'" "${GREEN}"
        fi
        if [ -n "$invalid_content_type" ]; then
            box_line "  - Invalid contentType: '${invalid_content_type}'" "${GREEN}"
        fi
        if [ ${#missing_optional[@]} -gt 0 ]; then
            box_line "  - Missing optional: ${missing_optional[*]}" "${GREEN}"
        fi
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
    
    # Box line helper with proper width calculation
    box_line() {
        local content="$1"
        local color="$2"
        local width=67
        local padding=$((width - ${#content}))
        if [ $padding -lt 0 ]; then padding=0; fi
        local spaces=$(printf '%*s' $padding '')
        echo -e "  ${color}│${NC} ${content}${spaces}${color}│${NC}"
    }
    
    echo ""
    echo -e "${RED}  ┌───────────────────────────────────────────────────────────────────┐${NC}"
    box_line "PLAYBACK SESSION #${session_num} ABORTED (no end event)" "${RED}"
    echo -e "${RED}  ├───────────────────────────────────────────────────────────────────┤${NC}"
    box_line "Session: ${session_id}" "${RED}"
    box_line "Duration: ${duration}s | Events: ${event_count}" "${RED}"
    echo -e "${RED}  └───────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Function to display ISDK validation summary on PLAYER_EXIT (in right column)
show_isdk_validation() {
    # Check if ISDK validation is enabled
    if [ "$ISDK_VALIDATION_ENABLED" != "true" ]; then
        return
    fi
    
    # Right column line helper (displays in ISDK column)
    isdk_line() {
        local content="$1"
        printf "%-${COL_WIDTH}s ${MAGENTA}│${NC} ${MAGENTA}${content}${NC}\n" ""
    }
    
    echo ""
    isdk_line "┌─────────────────────────────────────────────────┐"
    isdk_line "│ ISDK VALIDATION SUMMARY                         │"
    isdk_line "├─────────────────────────────────────────────────┤"
    
    # List of unique ISDK events seen (if enabled)
    if [ "$ISDK_SHOW_EVENT_LIST" = "true" ]; then
        isdk_line "│ Events Captured: ${ISDK_EVENT_COUNT}                              │"
        isdk_line "├─────────────────────────────────────────────────┤"
        
        if [ -n "$ISDK_EVENT_LIST" ]; then
            # Get unique events from comma-separated list
            local unique_list=""
            local IFS=','
            for evt in $ISDK_EVENT_LIST; do
                # Check if evt is already in unique_list
                if [[ ",$unique_list," != *",$evt,"* ]]; then
                    if [ -n "$unique_list" ]; then
                        unique_list="${unique_list},${evt}"
                    else
                        unique_list="$evt"
                    fi
                fi
            done
            
            # Count and display unique events
            local evt_count=0
            local total_unique=$(echo "$unique_list" | tr ',' '\n' | wc -l | tr -d ' ')
            for evt in $unique_list; do
                ((evt_count++))
                # Truncate event name if too long
                local display_evt="${evt:0:45}"
                if [ $evt_count -eq $total_unique ]; then
                    printf "%-${COL_WIDTH}s ${MAGENTA}│${NC} ${MAGENTA}│${NC}   └ ${CYAN}${display_evt}${NC}\n" ""
                else
                    printf "%-${COL_WIDTH}s ${MAGENTA}│${NC} ${MAGENTA}│${NC}   ├ ${CYAN}${display_evt}${NC}\n" ""
                fi
            done
        else
            isdk_line "│   (No ISDK events captured)                    │"
        fi
    fi
    
    isdk_line "└─────────────────────────────────────────────────┘"
}

# Function to reset ISDK tracking for new playback
reset_isdk_tracking() {
    ISDK_EVENT_LIST=""
    ISDK_EVENT_COUNT=0
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
    
    # Try to extract event name from "key <eventName>" pattern (e.g., "PSDK:: key playbackInitiatedEvent value:")
    if [[ "$line" =~ key[[:space:]]+([a-zA-Z0-9_]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    
    # Try to extract from [PSDK::ISDK] Event: pattern (e.g., "[PSDK::ISDK] Event: beam.events.playback.initiated_3.3payload")
    if [[ "$line" =~ \[PSDK::ISDK\][[:space:]]*Event:[[:space:]]*([a-zA-Z0-9_.]+) ]]; then
        echo "[ISDK] ${BASH_REMATCH[1]}"
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

# Fixed column widths for two-column display
COL_WIDTH=75

# Function to extract a field value from JSON in a log line
# Supports nested fields like "content.editId" or "playback.trigger"
extract_json_field() {
    local line="$1"
    local field="$2"
    local value=""
    
    # Extract JSON portion from the line (between { and })
    local json=""
    if [[ "$line" =~ \{.*\} ]]; then
        json="${BASH_REMATCH[0]}"
    fi
    
    if [ -z "$json" ]; then
        echo ""
        return
    fi
    
    # Handle nested fields (e.g., content.editId -> "content":{"editId":"value"})
    if [[ "$field" == *"."* ]]; then
        local parent="${field%%.*}"
        local child="${field#*.}"
        
        # First, extract the parent object content
        # Match "parent":{...} and capture everything inside
        if [[ "$json" =~ \"$parent\":\{([^{}]*(\{[^{}]*\}[^{}]*)*)\} ]]; then
            local parent_content="${BASH_REMATCH[1]}"
            # Now extract the child field from the parent content
            if [[ "$parent_content" =~ \"$child\":\"([^\"]+)\" ]]; then
                value="${BASH_REMATCH[1]}"
            elif [[ "$parent_content" =~ \"$child\":([^,}\"]+) ]]; then
                value="${BASH_REMATCH[1]}"
            fi
        fi
    else
        # Simple field extraction
        if [[ "$json" =~ \"$field\":\"([^\"]+)\" ]]; then
            value="${BASH_REMATCH[1]}"
        elif [[ "$json" =~ \"$field\":([^,}\"]+) ]]; then
            value="${BASH_REMATCH[1]}"
        fi
    fi
    
    echo "$value"
}

# Function to display event fields
display_event_fields() {
    local line="$1"
    local is_isdk="$2"
    local event_name="$3"
    
    if [ "$EVENT_FIELDS_ENABLED" != "true" ]; then
        return
    fi
    
    # Get fields for this specific event (or default)
    local fields_array=()
    while IFS= read -r field; do
        [ -n "$field" ] && fields_array+=("$field")
    done < <(get_event_fields "$event_name" "$is_isdk")
    
    if [ ${#fields_array[@]} -eq 0 ]; then
        return
    fi
    
    local num_fields=${#fields_array[@]}
    local field_idx=0
    local displayed_count=0
    
    # First pass: count how many fields have values
    local fields_with_values=()
    for field in "${fields_array[@]}"; do
        local value=$(extract_json_field "$line" "$field")
        if [ -n "$value" ]; then
            fields_with_values+=("$field:$value")
        fi
    done
    
    local total_with_values=${#fields_with_values[@]}
    local display_idx=0
    
    for fv in "${fields_with_values[@]}"; do
        ((display_idx++))
        local field="${fv%%:*}"
        local value="${fv#*:}"
        
        local tree_char="├"
        if [ $display_idx -eq $total_with_values ]; then
            tree_char="└"
        fi
        
        if [ "$is_isdk" = true ]; then
            # Right column field
            printf "%-${COL_WIDTH}s ${MAGENTA}│${NC}     ${GREY}${tree_char} ${field}: ${value}${NC}\n" ""
        else
            # Left column field - calculate padding to align separator
            local field_line="     ${tree_char} ${field}: ${value}"
            local field_len=${#field_line}
            local padding=$((COL_WIDTH - field_len))
            if [ $padding -lt 0 ]; then padding=0; fi
            printf "     ${GREY}${tree_char} ${field}: ${value}${NC}%${padding}s ${MAGENTA}│${NC}\n" ""
        fi
    done
}

# Function to display log line with timestamp (showing only event name)
# Two-column layout: PSDK events left, ISDK events right
display_log_with_timestamp() {
    local line="$1"
    local session_num="${2:-0}"  # Optional session number, defaults to 0
    local timestamp=$(get_timestamp)
    local event_name=$(extract_event_name "$line")
    
    # Check if this is an ISDK event
    local is_isdk=false
    if [[ "$line" == *"[PSDK::ISDK]"* ]]; then
        is_isdk=true
    fi
    
    # Check if this event is a repeat of the last one
    local is_repeat=false
    if [ "$event_name" = "$LAST_EVENT_NAME" ]; then
        is_repeat=true
    fi
    
    # Update last event
    LAST_EVENT_NAME="$event_name"
    
    # Format the event display
    local session_prefix=""
    if [ "$session_num" -gt 0 ]; then
        session_prefix="[S${session_num}] "
    fi
    
    # Build the display string
    local display_str="${session_prefix}${event_name}"
    
    # Extract raw event name for config lookup (without [ISDK] prefix)
    local raw_event_name="$event_name"
    if [[ "$event_name" == "[ISDK] "* ]]; then
        raw_event_name="${event_name#\[ISDK\] }"
    fi
    
    # Two-column display
    if [ "$is_isdk" = true ]; then
        # ISDK event - show in RIGHT column
        if [ "$is_repeat" != true ]; then
            echo ""
        fi
        # Empty left column, separator, then ISDK event
        printf "%-${COL_WIDTH}s ${MAGENTA}│${NC} ${CYAN}[%s]${NC} ${YELLOW}%s${NC}\n" "" "$timestamp" "$display_str"
        # Display configured fields for this event
        display_event_fields "$line" true "$raw_event_name"
    else
        # PSDK event - show in LEFT column
        if [ "$is_repeat" = true ]; then
            # Grey for repeated events
            printf "${CYAN}[%s]${NC} ${GREY}%-$((COL_WIDTH-15))s${NC} ${MAGENTA}│${NC}\n" "$timestamp" "$display_str"
        else
            echo ""
            printf "${CYAN}[%s]${NC} ${YELLOW}%-$((COL_WIDTH-15))s${NC} ${MAGENTA}│${NC}\n" "$timestamp" "$display_str"
            # Display configured fields for this event (only for non-repeated events)
            display_event_fields "$line" false "$raw_event_name"
        fi
    fi
}

# Function to flush any pending events (placeholder for compatibility)
flush_pending_psdk() {
    : # No-op - no longer buffering
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
        reset_isdk_tracking  # Reset ISDK tracking for new playback
        
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
        
        flush_pending_psdk
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
        flush_pending_psdk
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
        flush_pending_psdk
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
        
        # Track ISDK events for validation
        if [[ "$line" == *"[PSDK::ISDK]"* ]]; then
            ((ISDK_EVENT_COUNT++))
            
            # Extract ISDK event name (stop before "payload" or "{")
            if [[ "$line" =~ \[PSDK::ISDK\][[:space:]]*Event:[[:space:]]*([a-zA-Z0-9_.]+) ]]; then
                isdk_event_name="${BASH_REMATCH[1]}"
                # Strip "payload" suffix if present (no space between event name and payload)
                isdk_event_name="${isdk_event_name%payload}"
                # Append to comma-separated list
                if [ -n "$ISDK_EVENT_LIST" ]; then
                    ISDK_EVENT_LIST="${ISDK_EVENT_LIST},${isdk_event_name}"
                else
                    ISDK_EVENT_LIST="$isdk_event_name"
                fi
                
                # Check for PLAYER_EXIT state change - trigger ISDK validation
                if [[ "$isdk_event_name" == *"statechange"* ]]; then
                    state_action=$(extract_json_field "$line" "stateChange.action")
                    if [ "$state_action" = "PLAYER_EXIT" ]; then
                        show_isdk_validation
                        reset_isdk_tracking
                    fi
                fi
            fi
        fi
    fi
done

