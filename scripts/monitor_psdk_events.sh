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

# Default event fields config
EVENT_FIELDS_ENABLED=true
EVENT_FIELDS_CONFIG=""

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
        ISDK_FIELD_VALIDATION_ENABLED=$(jq -r '.isdk_validation.field_validation.enabled // true' "$CONFIG_FILE" 2>/dev/null)
    fi
fi

# Function to get fields for a specific event name
# $1 = event_name, $2 = event_type (psdk, isdk, mux)
get_event_fields() {
    local event_name="$1"
    local event_type="${2:-psdk}"
    local config_path
    
    # Return empty if no config file
    if [ -z "$EVENT_FIELDS_CONFIG" ] || [ ! -f "$EVENT_FIELDS_CONFIG" ]; then
        return
    fi
    
    if [ "$event_type" = "isdk" ]; then
        config_path=".event_fields.isdk_events"
    elif [ "$event_type" = "mux" ]; then
        config_path=".event_fields.mux_events"
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
ISDK_CONTENT_ID=""           # content.editId from ISDK events (for validation)
ISDK_PLAYBACK_ID=""          # playback.playbackId from ISDK events (for validation)

# ISDK field validation config
ISDK_FIELD_VALIDATION_ENABLED=true
SESSION_METADATA_SUBTITLE=""
SESSION_METADATA_TYPE=""
SESSION_METADATA_PLAYBACK_TYPE=""
SESSION_METADATA_POS=""

# MUX event tracking for validation
MUX_EVENT_LIST=""            # Comma-separated list of MUX event names
MUX_EVENT_COUNT=0            # Count of MUX events

# Warning tracking during playback
WARNING_LIST=""              # Pipe-separated list of warning messages
WARNING_COUNT=0              # Count of warnings captured

# Error tracking during playback
ERROR_LIST=""                # Pipe-separated list of error messages
ERROR_COUNT=0                # Count of errors captured

# Event repetition tracking
LAST_EVENT_NAME=""

# Function to display initial header
show_initial_header() {
    clear
    # Generate dynamic width headers
    local psdk_dashes=$(printf '%*s' $COL_WIDTH '' | tr ' ' '─')
    local isdk_dashes=$(printf '%*s' $ISDK_COL_WIDTH '' | tr ' ' '─')
    local mux_dashes=$(printf '%*s' $MUX_COL_WIDTH '' | tr ' ' '─')
    local total_dashes=$(printf '%*s' $TOTAL_WIDTH '' | tr ' ' '═')
    
    echo -e "${CYAN}${total_dashes}${NC}"
    echo -e "${CYAN}  PSDK Event Monitor - Player Lifecycle Tracking${NC}"
    echo -e "${CYAN}${total_dashes}${NC}"
    echo ""
    echo -e "${GREEN}📊 Monitoring: $1${NC}"
    echo -e "${GREEN}🔍 Tracking: Player creation & destruction${NC}"
    echo -e "${GREEN}⚙️  Config: $(basename "$CONFIG_FILE")${NC}"
    echo ""
    echo -e "${CYAN}${psdk_dashes}${MAGENTA}┬${CYAN}${isdk_dashes}${MAGENTA}┬${CYAN}${mux_dashes}${NC}"
    printf "${CYAN}  %-$((COL_WIDTH-2))s${MAGENTA}│${CYAN}  %-$((ISDK_COL_WIDTH-2))s${MAGENTA}│${CYAN}  %-$((MUX_COL_WIDTH-2))s${NC}\n" "PSDK Events" "ISDK Events" "MUX Events"
    echo -e "${CYAN}${psdk_dashes}${MAGENTA}┼${CYAN}${isdk_dashes}${MAGENTA}┼${CYAN}${mux_dashes}${NC}"
    echo ""
}

# Function to display player creation header
show_player_created() {
    local session_id="$1"
    local time=$(get_timestamp)
    local box_width=$((TOTAL_WIDTH - 4))  # Account for box borders
    local border=$(printf '%*s' $box_width '' | tr ' ' '═')
    local mid_border=$(printf '%*s' $box_width '' | tr ' ' '═')
    
    echo ""
    echo -e "${MAGENTA}╔${border}╗${NC}"
    
    local title="  🎬 PLAYER SESSION STARTED  Time: ${time}"
    local title_len=${#title}
    local title_padding=$((box_width - title_len))
    if [ $title_padding -lt 0 ]; then title_padding=0; fi
    printf "${MAGENTA}║${NC}${title}%${title_padding}s${MAGENTA}║${NC}\n" ""
    
    echo -e "${MAGENTA}╠${mid_border}╣${NC}"
    
    local content=""
    if [ -n "$session_id" ]; then
        content=" Session: ${session_id}"
    else
        content=" (Connected mid-stream - auto-created session)"
    fi
    local content_len=${#content}
    local content_padding=$((box_width - content_len))
    if [ $content_padding -lt 0 ]; then content_padding=0; fi
    printf "${MAGENTA}║${NC}${content}%${content_padding}s${MAGENTA}║${NC}\n" ""
    
    echo -e "${MAGENTA}╚${border}╝${NC}"
    echo ""
}

# Function to display column headers for PSDK | ISDK | MUX layout
show_column_headers() {
    # Generate dynamic width headers
    local psdk_dashes=$(printf '%*s' $COL_WIDTH '' | tr ' ' '─')
    local isdk_dashes=$(printf '%*s' $ISDK_COL_WIDTH '' | tr ' ' '─')
    local mux_dashes=$(printf '%*s' $MUX_COL_WIDTH '' | tr ' ' '─')
    
    echo -e "${CYAN}${psdk_dashes}${MAGENTA}┬${CYAN}${isdk_dashes}${MAGENTA}┬${CYAN}${mux_dashes}${NC}"
    printf "${CYAN}  %-$((COL_WIDTH-2))s${MAGENTA}│${CYAN}  %-$((ISDK_COL_WIDTH-2))s${MAGENTA}│${CYAN}  %-$((MUX_COL_WIDTH-2))s${NC}\n" "PSDK Events" "ISDK Events" "MUX Events"
    echo -e "${CYAN}${psdk_dashes}${MAGENTA}┼${CYAN}${isdk_dashes}${MAGENTA}┼${CYAN}${mux_dashes}${NC}"
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

# Function to display playback session ended (proper completion) - UNIFIED PLAYBACK SUMMARY
show_playback_ended() {
    local session_id="$1"
    local session_num="$2"
    local event_count="$3"
    local duration="$4"
    
    # Get terminal width for dynamic sizing (default to 160 if not available)
    local term_width=$(tput cols 2>/dev/null || echo 160)
    local box_width=$((term_width - 6))  # Account for margins and borders
    if [ $box_width -lt 80 ]; then box_width=80; fi
    if [ $box_width -gt 200 ]; then box_width=200; fi
    local border_width=$((box_width + 2))
    
    # Generate border strings once for consistent width
    local top_border=$(printf '═%.0s' $(seq 1 $box_width))
    local mid_border=$(printf '─%.0s' $(seq 1 $box_width))
    
    # Box line helper with color support (dynamic width)
    box_line() {
        local content="$1"
        local border_color="$2"
        local text_color="${3:-$NC}"
        local content_len=${#content}
        local padding=$((box_width - content_len - 1))
        if [ $padding -lt 0 ]; then padding=0; fi
        local spaces=$(printf '%*s' $padding '')
        echo -e "  ${border_color}│${NC} ${text_color}${content}${NC}${spaces}${border_color}│${NC}"
    }
    
    # Box line for long content (with right border aligned)
    box_line_nowrap() {
        local content="$1"
        local border_color="$2"
        local text_color="${3:-$NC}"
        local content_len=${#content}
        local padding=$((box_width - content_len - 1))
        if [ $padding -lt 0 ]; then padding=0; fi
        local spaces=$(printf '%*s' $padding '')
        echo -e "  ${border_color}│${NC} ${text_color}${content}${NC}${spaces}${border_color}│${NC}"
    }
    
    # Section header helper (dynamic width)
    section_header() {
        local title="$1"
        local border_color="$2"
        local title_color="${3:-$CYAN}"
        local title_len=${#title}
        local padding=$((box_width - title_len - 2))
        if [ $padding -lt 0 ]; then padding=0; fi
        local spaces=$(printf '%*s' $padding '')
        echo -e "  ${border_color}├${mid_border}┤${NC}"
        echo -e "  ${border_color}│${NC} ${title_color}${title}${NC}${spaces}${border_color}│${NC}"
    }
    
    # Draw top border
    echo ""
    echo -e "${CYAN}  ╔${top_border}╗${NC}"
    local title_padding=$((box_width - 20))  # 20 = length of " 📊 PLAYBACK SUMMARY" with leading space
    if [ $title_padding -lt 0 ]; then title_padding=0; fi
    echo -e "${CYAN}  ║${NC}  📊 ${CYAN}PLAYBACK SUMMARY${NC}$(printf '%*s' $title_padding '')${CYAN}║${NC}"
    echo -e "${CYAN}  ╠${top_border}╣${NC}"
    
    # Session Info Section
    box_line "Session #${session_num}" "${CYAN}" "${YELLOW}"
    box_line "  ID: ${session_id}" "${CYAN}" "${GREY}"
    box_line "  Duration: ${duration}s  |  PSDK Events: ${event_count}  |  ISDK Events: ${ISDK_EVENT_COUNT}" "${CYAN}"
    
    # Content Metadata Validation Section
    if [ "$SHOW_VALIDATION_RESULTS" = "true" ] && [ "$VALIDATION_ENABLED" = "true" ]; then
        section_header "📋 Content Metadata Validation" "${CYAN}" "${YELLOW}"
        
        # Perform validation
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
        
        # Display validation status
        if [ "$has_errors" = true ]; then
            box_line "  Status: ❌ INVALID" "${CYAN}" "${RED}"
        else
            local present=$((${#REQUIRED_FIELDS[@]} + ${#OPTIONAL_FIELDS[@]} - ${#missing_optional[@]}))
            local total=$((${#REQUIRED_FIELDS[@]} + ${#OPTIONAL_FIELDS[@]}))
            if [ ${#missing_optional[@]} -eq 0 ]; then
                box_line "  Status: ✅ VALID (All fields present)" "${CYAN}" "${GREEN}"
            else
                box_line "  Status: ✅ VALID (${present}/${total} fields)" "${CYAN}" "${GREEN}"
            fi
        fi
        
        # Display validation details
        if [ ${#missing_required[@]} -gt 0 ]; then
            box_line "    ├ Missing required: ${missing_required[*]}" "${CYAN}" "${RED}"
        fi
        if [ -n "$invalid_playback_type" ]; then
            box_line "    ├ Invalid playbackType: '${invalid_playback_type}'" "${CYAN}" "${RED}"
        fi
        if [ -n "$invalid_content_type" ]; then
            box_line "    ├ Invalid contentType: '${invalid_content_type}'" "${CYAN}" "${RED}"
        fi
        if [ ${#missing_optional[@]} -gt 0 ]; then
            box_line "    └ Missing optional: ${missing_optional[*]}" "${CYAN}" "${YELLOW}"
        fi
    fi
    
    # ISDK Validation Section (if enabled)
    if [ "$ISDK_VALIDATION_ENABLED" = "true" ]; then
        section_header "🔗 ISDK Validation" "${CYAN}" "${MAGENTA}"
        
        # ISDK Events List
        if [ "$ISDK_SHOW_EVENT_LIST" = "true" ]; then
            if [ -n "$ISDK_EVENT_LIST" ]; then
                # Get unique events
                local unique_list=""
                local IFS=','
                for evt in $ISDK_EVENT_LIST; do
                    if [[ ",$unique_list," != *",$evt,"* ]]; then
                        if [ -n "$unique_list" ]; then
                            unique_list="${unique_list},${evt}"
                        else
                            unique_list="$evt"
                        fi
                    fi
                done
                
                local total_unique=$(echo "$unique_list" | tr ',' '\n' | wc -l | tr -d ' ')
                box_line "  Events Captured: ${ISDK_EVENT_COUNT} total, ${total_unique} unique" "${CYAN}"
                
                # Display unique events as a tree
                local evt_count=0
                for evt in $unique_list; do
                    ((evt_count++))
                    local display_evt="${evt:0:95}"
                    if [ $evt_count -eq $total_unique ]; then
                        box_line "    └ ${display_evt}" "${CYAN}" "${GREY}"
                    else
                        box_line "    ├ ${display_evt}" "${CYAN}" "${GREY}"
                    fi
                done
            else
                box_line "  Events Captured: 0 (No ISDK events)" "${CYAN}" "${YELLOW}"
            fi
        fi
        
        # Field Validation
        if [ "$ISDK_FIELD_VALIDATION_ENABLED" = "true" ]; then
            box_line "" "${CYAN}"
            box_line "  Field Cross-Validation:" "${CYAN}" "${YELLOW}"
            
            # Validate content.editId against contentMetadata.id
            local content_status="⚠️  N/A"
            local content_color="${YELLOW}"
            if [ -n "$ISDK_CONTENT_ID" ] && [ -n "$SESSION_METADATA_ID" ]; then
                if [ "$ISDK_CONTENT_ID" = "$SESSION_METADATA_ID" ]; then
                    content_status="✅ MATCH"
                    content_color="${GREEN}"
                else
                    content_status="❌ MISMATCH"
                    content_color="${RED}"
                fi
            elif [ -z "$ISDK_CONTENT_ID" ]; then
                content_status="⚠️  No ISDK editId"
            elif [ -z "$SESSION_METADATA_ID" ]; then
                content_status="⚠️  No Metadata ID"
            fi
            box_line "    ├ content.editId ↔ metadata.id: ${content_status}" "${CYAN}" "${content_color}"
            if [ -n "$ISDK_CONTENT_ID" ]; then
                box_line "      │ ISDK: ${ISDK_CONTENT_ID:0:85}" "${CYAN}" "${GREY}"
            fi
            if [ -n "$SESSION_METADATA_ID" ]; then
                box_line "      │ Meta: ${SESSION_METADATA_ID:0:85}" "${CYAN}" "${GREY}"
            fi
            
            # Validate playback.playbackId against playbackSessionId
            local playback_status="⚠️  N/A"
            local playback_color="${YELLOW}"
            if [ -n "$ISDK_PLAYBACK_ID" ] && [ -n "$PLAYBACK_SESSION_ID" ]; then
                if [ "$ISDK_PLAYBACK_ID" = "$PLAYBACK_SESSION_ID" ]; then
                    playback_status="✅ MATCH"
                    playback_color="${GREEN}"
                else
                    playback_status="❌ MISMATCH"
                    playback_color="${RED}"
                fi
            elif [ -z "$ISDK_PLAYBACK_ID" ]; then
                playback_status="⚠️  No ISDK playbackId"
            elif [ -z "$PLAYBACK_SESSION_ID" ]; then
                playback_status="⚠️  No PSDK playbackId"
            fi
            box_line "    └ playback.playbackId ↔ sessionId: ${playback_status}" "${CYAN}" "${playback_color}"
            if [ -n "$ISDK_PLAYBACK_ID" ]; then
                box_line "        ISDK: ${ISDK_PLAYBACK_ID:0:85}" "${CYAN}" "${GREY}"
            fi
            if [ -n "$PLAYBACK_SESSION_ID" ]; then
                box_line "        PSDK: ${PLAYBACK_SESSION_ID:0:85}" "${CYAN}" "${GREY}"
            fi
        fi
    fi
    
    # Errors Section
    section_header "❌ Errors Captured" "${CYAN}" "${RED}"
    if [ "$ERROR_COUNT" -gt 0 ]; then
        box_line "  Total Errors: ${ERROR_COUNT}" "${CYAN}" "${RED}"
        box_line "" "${CYAN}"
        
        # Display all errors (pipe-separated list) - full line, no truncation
        local err_idx=0
        local IFS='|'
        for error in $ERROR_LIST; do
            ((err_idx++))
            # Show full error without truncation
            if [ $err_idx -eq $ERROR_COUNT ]; then
                box_line_nowrap "    └ ${error}" "${CYAN}" "${RED}"
            else
                box_line_nowrap "    ├ ${error}" "${CYAN}" "${RED}"
            fi
        done
    else
        box_line "  No errors captured during this session ✅" "${CYAN}" "${GREEN}"
    fi
    
    # Warnings Section
    section_header "⚠️  Warnings Captured" "${CYAN}" "${YELLOW}"
    if [ "$WARNING_COUNT" -gt 0 ]; then
        box_line "  Total Warnings: ${WARNING_COUNT}" "${CYAN}" "${YELLOW}"
        box_line "" "${CYAN}"
        
        # Display all warnings (pipe-separated list) - full line, no truncation
        local warn_idx=0
        local IFS='|'
        for warning in $WARNING_LIST; do
            ((warn_idx++))
            # Show full warning without truncation
            if [ $warn_idx -eq $WARNING_COUNT ]; then
                box_line_nowrap "    └ ${warning}" "${CYAN}" "${YELLOW}"
            else
                box_line_nowrap "    ├ ${warning}" "${CYAN}" "${YELLOW}"
            fi
        done
    else
        box_line "  No warnings captured during this session ✅" "${CYAN}" "${GREEN}"
    fi
    
    echo -e "${CYAN}  ╚${top_border}╝${NC}"
    echo ""
    
    # Reset tracking after displaying summary
    reset_isdk_tracking
    reset_mux_tracking
    reset_warning_tracking
    reset_error_tracking
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

# Function to reset ISDK tracking for new playback
reset_isdk_tracking() {
    ISDK_EVENT_LIST=""
    ISDK_EVENT_COUNT=0
    ISDK_CONTENT_ID=""
    ISDK_PLAYBACK_ID=""
}

# Function to reset MUX tracking for new playback
reset_mux_tracking() {
    MUX_EVENT_LIST=""
    MUX_EVENT_COUNT=0
}

# Function to reset warning tracking for new playback
reset_warning_tracking() {
    WARNING_LIST=""
    WARNING_COUNT=0
}

# Function to reset error tracking for new playback
reset_error_tracking() {
    ERROR_LIST=""
    ERROR_COUNT=0
}

# Function to capture a warning during playback
capture_warning() {
    local warning_msg="$1"
    ((WARNING_COUNT++))
    # Store full warning message (no truncation)
    if [ -n "$WARNING_LIST" ]; then
        WARNING_LIST="${WARNING_LIST}|${warning_msg}"
    else
        WARNING_LIST="$warning_msg"
    fi
}

# Function to capture an error during playback
capture_error() {
    local error_msg="$1"
    ((ERROR_COUNT++))
    # Store full error message (no truncation)
    if [ -n "$ERROR_LIST" ]; then
        ERROR_LIST="${ERROR_LIST}|${error_msg}"
    else
        ERROR_LIST="$error_msg"
    fi
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

# Fixed column widths for three-column display (PSDK | ISDK | MUX)
COL_WIDTH=75          # PSDK column width
ISDK_COL_WIDTH=75     # ISDK column width  
MUX_COL_WIDTH=70      # MUX column width (wider for field display)
TOTAL_WIDTH=$((COL_WIDTH + ISDK_COL_WIDTH + MUX_COL_WIDTH + 2))  # Total width including separators

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
# $1 = line, $2 = event_type (psdk, isdk, mux), $3 = event_name
display_event_fields() {
    local line="$1"
    local event_type="${2:-psdk}"
    local event_name="$3"
    
    if [ "$EVENT_FIELDS_ENABLED" != "true" ]; then
        return
    fi
    
    # Get fields for this specific event (or default)
    local fields_array=()
    while IFS= read -r field; do
        [ -n "$field" ] && fields_array+=("$field")
    done < <(get_event_fields "$event_name" "$event_type")
    
    if [ ${#fields_array[@]} -eq 0 ]; then
        return
    fi
    
    local num_fields=${#fields_array[@]}
    local field_idx=0
    local displayed_count=0
    
    # First pass: count how many fields have values
    local fields_with_values=()
    for field in "${fields_array[@]}"; do
        local value=""
        if [ "$event_type" = "mux" ]; then
            # MUX payload format: field:value, separated by comma/space
            # e.g., view_session_id:abc123, viewer_time:12345
            value=$(extract_mux_field "$line" "$field")
        else
            value=$(extract_json_field "$line" "$field")
        fi
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
        
        if [ "$event_type" = "isdk" ]; then
            # ISDK field - middle column (Empty PSDK | ISDK field | Empty MUX)
            local field_display="   ${tree_char} ${field}: ${value}"
            local field_len=${#field_display}
            local padding=$((ISDK_COL_WIDTH - field_len - 1))
            if [ $padding -lt 0 ]; then padding=0; fi
            printf "%-${COL_WIDTH}s${MAGENTA}│${NC}${GREY}${field_display}${NC}%${padding}s${MAGENTA}│${NC}%-${MUX_COL_WIDTH}s\n" "" "" ""
        elif [ "$event_type" = "mux" ]; then
            # MUX field - right column (Empty PSDK | Empty ISDK | MUX field)
            local field_display="   ${tree_char} ${field}: ${value}"
            printf "%-${COL_WIDTH}s${MAGENTA}│${NC}%-${ISDK_COL_WIDTH}s${MAGENTA}│${NC}${GREY}${field_display}${NC}\n" "" ""
        else
            # PSDK field - left column (PSDK field | Empty ISDK | Empty MUX)
            local field_line="   ${tree_char} ${field}: ${value}"
            local field_len=${#field_line}
            local padding=$((COL_WIDTH - field_len - 1))
            if [ $padding -lt 0 ]; then padding=0; fi
            printf "${GREY}${field_line}${NC}%${padding}s${MAGENTA}│${NC}%-${ISDK_COL_WIDTH}s${MAGENTA}│${NC}%-${MUX_COL_WIDTH}s\n" "" "" ""
        fi
    done
}

# Function to extract field value from MUX event payload
# MUX format can vary:
#   [mux-analytics] EVENT eventname{field:value, field2:value2, ...}
#   [mux-analytics] EVENT eventname{field: value, field2: value2}
#   field=value or field:"value" formats
extract_mux_field() {
    local line="$1"
    local field_name="$2"
    local value=""
    
    # Extract the payload portion after eventname{ or after EVENT eventname
    local payload=""
    if [[ "$line" == *"{"* ]]; then
        payload="${line#*\{}"
        payload="${payload%\}*}"
    else
        # Try extracting from after EVENT eventname
        payload="$line"
    fi
    
    if [ -n "$payload" ]; then
        # Try multiple extraction patterns (bash 3.2 compatible via sed)
        
        # Pattern 1: field:value or field: value (colon separator, with optional space)
        value=$(echo "$payload" | sed -n "s/.*${field_name}:[[:space:]]*\([^,}]*\).*/\1/p" | head -1)
        
        # Pattern 2: field=value (equals separator) 
        if [ -z "$value" ]; then
            value=$(echo "$payload" | sed -n "s/.*${field_name}=[[:space:]]*\([^,}]*\).*/\1/p" | head -1)
        fi
        
        # Pattern 3: "field":"value" or "field": "value" (JSON-like)
        if [ -z "$value" ]; then
            value=$(echo "$payload" | sed -n "s/.*\"${field_name}\":[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1)
        fi
        
        # Pattern 4: "field":value (JSON-like without value quotes)
        if [ -z "$value" ]; then
            value=$(echo "$payload" | sed -n "s/.*\"${field_name}\":[[:space:]]*\([^,}\"]*\).*/\1/p" | head -1)
        fi
        
        # Trim whitespace and trailing commas
        value="${value## }"
        value="${value%% }"
        value="${value%,}"
    fi
    
    echo "$value"
}

# Function to display log line with timestamp (showing only event name)
# Two-column layout: PSDK events left, ISDK events right, MUX events right (magenta)
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
    
    # Check if this is a MUX event
    local is_mux=false
    if [[ "$line" == *"[mux-analytics]"* ]] || [[ "$line" == *"mux:"* ]] || [[ "$line" == *"MUX:"* ]]; then
        is_mux=true
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
    
    # Three-column display: PSDK left | ISDK middle | MUX right
    if [ "$is_mux" = true ]; then
        # MUX event - show in RIGHT (3rd) column
        if [ "$is_repeat" != true ]; then
            echo ""
        fi
        
        # Extract MUX event name for field config lookup (using sed for bash 3.2 compatibility)
        local mux_event_name=""
        mux_event_name=$(echo "$line" | sed -n 's/.*\[mux-analytics\] EVENT \([a-zA-Z_]*\).*/\1/p')
        if [ -z "$mux_event_name" ]; then
            mux_event_name=$(echo "$line" | sed -n 's/.*\[mux-analytics\] \([a-zA-Z_]*\).*/\1/p')
        fi
        
        # Empty PSDK column | Empty ISDK column | MUX event
        printf "%-${COL_WIDTH}s${MAGENTA}│${NC}%-${ISDK_COL_WIDTH}s${MAGENTA}│${NC} ${CYAN}[%s]${NC} ${GREEN}%s${NC}\n" "" "" "$timestamp" "$display_str"
        # Display configured fields for MUX event (only for non-repeated events)
        if [ "$is_repeat" != true ] && [ -n "$mux_event_name" ]; then
            display_event_fields "$line" "mux" "$mux_event_name"
        fi
    elif [ "$is_isdk" = true ]; then
        # ISDK event - show in MIDDLE (2nd) column
        if [ "$is_repeat" != true ]; then
            echo ""
        fi
        # Empty PSDK column | ISDK event | Empty MUX column
        printf "%-${COL_WIDTH}s${MAGENTA}│${NC} ${CYAN}[%s]${NC} ${YELLOW}%-$((ISDK_COL_WIDTH-18))s${NC}${MAGENTA}│${NC}%-${MUX_COL_WIDTH}s\n" "" "$timestamp" "$display_str" ""
        # Display configured fields for this event
        display_event_fields "$line" "isdk" "$raw_event_name"
    else
        # PSDK event - show in LEFT (1st) column
        if [ "$is_repeat" = true ]; then
            # Grey for repeated events
            printf "${CYAN}[%s]${NC} ${GREY}%-$((COL_WIDTH-16))s${NC}${MAGENTA}│${NC}%-${ISDK_COL_WIDTH}s${MAGENTA}│${NC}%-${MUX_COL_WIDTH}s\n" "$timestamp" "$display_str" "" ""
        else
            echo ""
            printf "${CYAN}[%s]${NC} ${YELLOW}%-$((COL_WIDTH-16))s${NC}${MAGENTA}│${NC}%-${ISDK_COL_WIDTH}s${MAGENTA}│${NC}%-${MUX_COL_WIDTH}s\n" "$timestamp" "$display_str" "" ""
            # Display configured fields for this event (only for non-repeated events)
            display_event_fields "$line" "psdk" "$raw_event_name"
        fi
    fi
}

# Function to display MUX event with timestamp
display_mux_event() {
    local line="$1"
    local session_num="${2:-0}"
    local timestamp=$(get_timestamp)
    
    # Extract MUX event name using sed (bash 3.2 compatible)
    # Format: [mux-analytics] EVENT eventname{...} or [mux-analytics] EVENT eventname ...
    local mux_event=""
    
    # Try to extract EVENT name (e.g., "EVENT viewstart{" -> "viewstart")
    mux_event=$(echo "$line" | sed -n 's/.*\[mux-analytics\] EVENT \([a-zA-Z_]*\).*/\1/p')
    
    # Fallback: extract first word after [mux-analytics] (e.g., "[mux-analytics] running" -> "running")
    if [ -z "$mux_event" ]; then
        mux_event=$(echo "$line" | sed -n 's/.*\[mux-analytics\] \([a-zA-Z_]*\).*/\1/p')
    fi
    
    # Default fallback
    if [ -z "$mux_event" ]; then
        mux_event="mux_event"
    fi
    
    local session_prefix=""
    if [ "$session_num" -gt 0 ]; then
        session_prefix="[S${session_num}] "
    fi
    
    echo ""
    # Display in MUX column (3rd column)
    printf "%-${COL_WIDTH}s${MAGENTA}│${NC}%-${ISDK_COL_WIDTH}s${MAGENTA}│${NC} ${CYAN}[%s]${NC} ${GREEN}${session_prefix}${mux_event}${NC}\n" "" "" "$timestamp"
    
    # Display configured fields for MUX event (always try if we have a valid event name)
    if [ -n "$mux_event" ]; then
        display_event_fields "$line" "mux" "$mux_event"
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
        reset_mux_tracking   # Reset MUX tracking for new playback
        reset_warning_tracking  # Reset warning tracking for new playback
        reset_error_tracking  # Reset error tracking for new playback
        
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
    
    # Check for MUX analytics events
    if [[ "$line" == *"[mux-analytics]"* ]] || [[ "$line" == *"mux:"* ]] || [[ "$line" == *"MUX:"* ]]; then
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
                
                # Extract fields for validation (capture first occurrence)
                if [ -z "$ISDK_CONTENT_ID" ]; then
                    extracted_id=$(extract_json_field "$line" "content.editId")
                    [ -n "$extracted_id" ] && ISDK_CONTENT_ID="$extracted_id"
                fi
                if [ -z "$ISDK_PLAYBACK_ID" ]; then
                    extracted_pid=$(extract_json_field "$line" "playback.playbackId")
                    [ -n "$extracted_pid" ] && ISDK_PLAYBACK_ID="$extracted_pid"
                fi
                
                # Note: ISDK validation is now displayed as part of the unified Playback Summary
                # when playbackSessionEndEvent occurs (see show_playback_ended function)
            fi
        fi
        
        # Track MUX analytics events
        if [[ "$line" == *"[mux-analytics]"* ]] || [[ "$line" == *"mux:"* ]] || [[ "$line" == *"MUX:"* ]]; then
            ((MUX_EVENT_COUNT++))
            
            # Extract MUX event name using sed (bash 3.2 compatible)
            # Format: [mux-analytics] EVENT eventname{...} or [mux-analytics] EVENT eventname ...
            mux_event_name=""
            mux_event_name=$(echo "$line" | sed -n 's/.*\[mux-analytics\] EVENT \([a-zA-Z_]*\).*/\1/p')
            if [ -z "$mux_event_name" ]; then
                mux_event_name=$(echo "$line" | sed -n 's/.*\[mux-analytics\] \([a-zA-Z_]*\).*/\1/p')
            fi
            if [ -z "$mux_event_name" ]; then
                mux_event_name=$(echo "$line" | sed -n 's/.*mux: *\([a-zA-Z_]*\).*/\1/p')
            fi
            if [ -z "$mux_event_name" ]; then
                mux_event_name=$(echo "$line" | sed -n 's/.*MUX: *\([a-zA-Z_]*\).*/\1/p')
            fi
            if [ -z "$mux_event_name" ]; then
                mux_event_name="mux_event"
            fi
            
            # Append to comma-separated list
            if [ -n "$mux_event_name" ]; then
                if [ -n "$MUX_EVENT_LIST" ]; then
                    MUX_EVENT_LIST="${MUX_EVENT_LIST},${mux_event_name}"
                else
                    MUX_EVENT_LIST="$mux_event_name"
                fi
            fi
            
            # Display MUX event in real-time
            display_mux_event "$line" "$PLAYBACK_SESSION_NUMBER"
        fi
    fi
    
    # Capture warnings and errors during active playback session
    # Only capture actual log lines, not JSON payloads or data
    if [ "$PLAYBACK_ACTIVE" = true ]; then
        # Skip JSON payloads and data lines (they contain errors/warnings as field names, not actual errors)
        # Skip if line starts with { or contains typical JSON patterns like "events": or "http
        is_json_data=false
        if [[ "$line" =~ ^[[:space:]]*\{ ]] || [[ "$line" =~ \"events\": ]] || [[ "$line" =~ \"http ]]; then
            is_json_data=true
        fi
        
        if [ "$is_json_data" = false ]; then
            # Check for error patterns - must be at start of line or after timestamp/log prefix
            # Patterns: "ERROR:", "Error:", "FATAL:", "[ERROR]", "BRIGHTSCRIPT: ERROR:", "❌"
            if [[ "$line" =~ ^[[:space:]]*(ERROR|Error|FATAL|fatal):[[:space:]]* ]] || \
               [[ "$line" =~ \[(ERROR|Error|FATAL)\] ]] || \
               [[ "$line" =~ [0-9]{2}:[0-9]{2}:[0-9]{2}.*ERROR: ]] || \
               [[ "$line" == *"BRIGHTSCRIPT: ERROR:"* ]] || \
               [[ "$line" == *"❌"* ]]; then
                # Extract a meaningful error message
                error_msg=""
                
                # Try to extract error from common formats
                if [[ "$line" =~ BRIGHTSCRIPT:[[:space:]]*ERROR:[[:space:]]*(.+) ]]; then
                    error_msg="[BrightScript] ${BASH_REMATCH[1]}"
                elif [[ "$line" =~ (ERROR|Error|FATAL):[[:space:]]*(.+) ]]; then
                    error_msg="${BASH_REMATCH[2]}"
                elif [[ "$line" =~ \[(ERROR|Error|FATAL)\][[:space:]]*(.+) ]]; then
                    error_msg="${BASH_REMATCH[2]}"
                else
                    error_msg="$line"
                fi
                
                # Capture the error (skip if it looks like JSON)
                if [[ ! "$error_msg" =~ ^\{ ]]; then
                    capture_error "$error_msg"
                fi
            # Check for warning patterns - must be at start of line or after timestamp/log prefix
            # Patterns: "WARN:", "WARNING:", "Warning:", "[WARN]", "Warning occurred", "Type mismatch", "⚠️"
            elif [[ "$line" =~ ^[[:space:]]*(WARN|WARNING|Warning|warn|warning):[[:space:]]* ]] || \
                 [[ "$line" =~ \[(WARN|WARNING|Warning)\] ]] || \
                 [[ "$line" =~ [0-9]{2}:[0-9]{2}:[0-9]{2}.*(WARN|WARNING): ]] || \
                 [[ "$line" == *"Warning occurred"* ]] || \
                 [[ "$line" == *"Type mismatch occurred"* ]] || \
                 [[ "$line" == *"⚠️"* ]]; then
                # Extract a meaningful warning message
                warning_msg=""
                
                # Try to extract warning from common formats
                if [[ "$line" =~ Warning[[:space:]]occurred[[:space:]](.+) ]]; then
                    warning_msg="[Roku] ${BASH_REMATCH[1]}"
                elif [[ "$line" =~ Type[[:space:]]mismatch[[:space:]]occurred[[:space:]](.+) ]]; then
                    warning_msg="[Roku] Type mismatch: ${BASH_REMATCH[1]}"
                elif [[ "$line" =~ (WARN|WARNING|Warning|warning):[[:space:]]*(.+) ]]; then
                    warning_msg="${BASH_REMATCH[2]}"
                elif [[ "$line" =~ \[(WARN|WARNING|Warning)\][[:space:]]*(.+) ]]; then
                    warning_msg="${BASH_REMATCH[2]}"
                else
                    warning_msg="$line"
                fi
                
                # Capture the warning (skip if it looks like JSON or separator lines)
                if [[ ! "$warning_msg" =~ ^\{ ]] && [[ ! "$warning_msg" =~ ^=+$ ]]; then
                    capture_warning "$warning_msg"
                fi
            fi
        fi
    fi
done

