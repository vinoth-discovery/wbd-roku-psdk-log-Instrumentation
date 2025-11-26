# Monitor Configuration

This directory contains configuration files for the PSDK event monitor.

## monitor_config.json

Controls player lifecycle tracking, content metadata validation, and display settings for the PSDK event monitor terminal.

### Configuration Structure

```json
{
  "player_lifecycle": {
    "creation_pattern": "PlayerSDK.Core.PlayerBuilder: new",
    "destruction_pattern": "playerSessionEndEvent"
  },
  "playback_lifecycle": {
    "initiation_pattern": "playbackInitiatedEvent",
    "end_pattern": "playbackSessionEndEvent"
  },
  "content_metadata": {
    "load_pattern": "Player Controller: Load",
    "fields": ["id", "title", "subtitle", "contentType", "playbackType", "initialPlaybackPosition"],
    "validation": {
      "enabled": true,
      "required_fields": ["id", "title", "playbackType"],
      "optional_fields": ["subtitle", "contentType", "initialPlaybackPosition"],
      "playback_type_enum": {
        "enabled": true,
        "valid_values": ["userInitiated", "AUTO", "INLINE", "continuous", 
                         "confirmedContinuous", "confirmedEndCard", "autoPlayEndCard"]
      },
      "content_type_enum": {
        "enabled": true,
        "valid_values": ["episode", "standalone", "clip", "trailer", "live",
                         "follow_up", "listing", "movie", "podcast", "short_preview",
                         "promo", "extra", "standalone_event", "live_channel"]
      }
    }
  },
  "display": {
    "show_headers": true,
    "show_footers": true,
    "show_session_summary": true,
    "show_playback_headers": true,
    "show_content_metadata": true,
    "show_validation_results": true
  }
}
```

### Player Lifecycle Patterns

**`creation_pattern`**: Text pattern that indicates a new player instance is being created.
- Default: `"PlayerSDK.Core.PlayerBuilder: new"`
- When detected, the monitor displays a **Player Session Started** header (magenta)

**`destruction_pattern`**: Text pattern that indicates a player session is ending.
- Default: `"playerSessionEndEvent"` (Note: This is different from playbackSessionEndEvent)
- When detected, the monitor displays a **Player Session Ended** footer with total statistics (red)

### Playback Lifecycle Patterns

**`initiation_pattern`**: Text pattern that indicates a new playback session is starting within a player.
- Default: `"playbackInitiatedEvent"`
- When detected, the monitor displays an indented **Playback Started** header (cyan)
- Multiple playback sessions can occur within one player session

**`end_pattern`**: Text pattern that indicates a playback session is ending.
- Default: `"playbackSessionEndEvent"`
- When detected, the monitor displays an indented **Playback Ended** footer (green)

### Content Metadata Configuration

**`load_pattern`**: Text pattern that indicates content metadata is being loaded.
- Default: `"Player Controller: Load"`
- When detected, the monitor extracts content information to display in the playback header

**`fields`**: Array of fields to extract from content metadata
- Default: `["id", "title", "subtitle", "contentType", "playbackType", "initialPlaybackPosition"]`
- Each field maps to a property in the content metadata structure
- Add custom fields here if needed

### Validation Configuration

**`content_metadata.validation.enabled`**: Enable/disable all validation
- Default: `true`
- When enabled, validates content metadata at playback session end

**`required_fields`**: Fields that MUST be present
- Default: `["id", "title", "playbackType"]`
- If any required field is missing, validation shows ❌ INVALID

**`optional_fields`**: Fields that SHOULD be present but aren't required
- Default: `["subtitle", "contentType", "initialPlaybackPosition"]`
- Missing optional fields don't cause validation to fail

**`playback_type_enum`**: Validates playbackType has valid enum value
- `enabled`: Enable/disable playbackType enum validation (default: `true`)
- `valid_values`: Array of valid playbackType values
  - `userInitiated` - User clicked "watch now"
  - `AUTO` - Auto-plays on page load
  - `INLINE` - Plays within hero/tiles
  - `continuous` - Auto-plays next asset
  - `confirmedContinuous` - User clicked "up next"
  - `confirmedEndCard` - Auto-plays from end card
  - `autoPlayEndCard` - User clicked watch on end card

**`content_type_enum`**: Validates contentType has valid enum value (when present)
- `enabled`: Enable/disable contentType enum validation (default: `true`)
- `valid_values`: Array of valid contentType values (all lowercase with underscores)
  - `episode`, `standalone`, `clip`, `trailer`, `live`
  - `follow_up`, `listing`, `movie`, `podcast`, `short_preview`
  - `promo`, `extra`, `standalone_event`, `live_channel`

### Display Settings

**`show_validation_results`**: Show validation results in playback end footer
- Default: `true`
- Displays ✅ VALID or ❌ INVALID with details

### How It Works

**Player Session Tracking:**
1. Monitor watches for `player_lifecycle.creation_pattern`
2. When found, displays a magenta header and resets counters
3. Tracks all PSDK events during the player session
4. Watches for `player_lifecycle.destruction_pattern`
5. When found, displays a red footer with:
   - Player session duration
   - Total number of playback sessions
   - Total PSDK events count

**Playback Session Tracking (Nested):**
1. Within an active player session, monitors for `playback_lifecycle.initiation_pattern`
2. When found, displays an indented cyan header with:
   - Playback session number (e.g., #1, #2, #3)
   - Playback session ID
   - Content metadata (if available):
     - Content ID
     - Title
     - Subtitle
     - Content Type
     - Playback Type
     - Initial Playback Position
   - Start time
3. Counts PSDK events specific to this playback
4. Watches for `playback_lifecycle.end_pattern`
5. When found, displays an indented green footer with:
   - Playback duration
   - PSDK events count for this playback only
   - **ContentMetadata validation result** (✅ VALID or ❌ INVALID)
     - Checks required fields are present
     - Validates playbackType enum value
     - Validates contentType enum value (if present)
     - Lists missing fields or invalid values

**Content Metadata Extraction:**
1. Monitor watches for `content_metadata.load_pattern` (e.g., "Player Controller: Load")
2. When found, enters content parsing mode
3. Extracts fields defined in `content_metadata.fields`:
   - `id`: Content identifier
   - `title`: Content title
   - `contentType`: Type of content (e.g., "SHORT_PREVIEW", "EPISODE")
   - `initialPlaybackPosition`: Starting position in seconds
4. Stores metadata temporarily
5. When next playback session starts, displays this metadata in the header
6. Clears metadata after display

### Quick Configuration Examples

**Disable All Validation:**
```json
{
  "content_metadata": {
    "validation": {
      "enabled": false
    }
  }
}
```

**Disable Only Enum Validation:**
```json
{
  "content_metadata": {
    "validation": {
      "playback_type_enum": { "enabled": false },
      "content_type_enum": { "enabled": false }
    }
  }
}
```

**Change Required Fields:**
```json
{
  "content_metadata": {
    "validation": {
      "required_fields": ["id", "title", "playbackType", "contentType"]
    }
  }
}
```

**Add Custom Enum Values:**
```json
{
  "content_metadata": {
    "validation": {
      "playback_type_enum": {
        "valid_values": ["userInitiated", "AUTO", "myCustomType"]
      }
    }
  }
}
```

### Updating Patterns

If Roku SDK changes event names or content load patterns, update the patterns in `monitor_config.json`:

```json
{
  "player_lifecycle": {
    "creation_pattern": "YourNewPlayerInitPattern",
    "destruction_pattern": "yourNewEndEventName"
  },
  "content_metadata": {
    "load_pattern": "Your New Content Load Pattern",
    "fields": ["id", "title", "contentType", "initialPlaybackPosition", "customField"]
  }
}
```

The monitor will automatically load the new patterns on next run.

**Adding Custom Content Fields:**
1. Add the field name to the `fields` array in `content_metadata`
2. Ensure the field exists in the content metadata structure in your logs
3. The monitor will automatically extract and display it

### Example Output

**Complete session with nested playback:**

```
╔═══════════════════════════════════════════════════╗
║           🎬 PLAYER SESSION STARTED               ║
╠═══════════════════════════════════════════════════╣
║ Session: unknown                                  ║
║ Time: 15:01:47                                    ║
╚═══════════════════════════════════════════════════╝

  ┌─────────────────────────────────────────────────┐
  │   ▶️  PLAYBACK SESSION #1 STARTED               │
  ├─────────────────────────────────────────────────┤
  │ Session ID: 5b54b105-e336-42b8-b7e9-8199e3  │
  │ Content ID: PROM1178922                       │
  │ Title: Discovery+ Original                    │
  │ Type: SHORT_PREVIEW                           │
  │ Start Position: 0s                            │
  │ Time: 15:01:53                                │
  └─────────────────────────────────────────────────┘

[15:01:53.456] [S1] playbackInitiatedEvent
[15:01:53.789] [S1] playbackInfoResolutionStartEvent
  ... more PSDK events for playback #1 ...

  ┌─────────────────────────────────────────────────┐
  │   ⏹️  PLAYBACK SESSION #1 ENDED                 │
  ├─────────────────────────────────────────────────┤
  │ ID: 5b54b105-e336-42b8-b7e9-8199e3da06a2      │
  │ Duration: 31s | Events: 78                     │
  ├─────────────────────────────────────────────────┤
  │ ContentMetadata: ✅ VALID (All fields present)  │
  └─────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────┐
  │   ▶️  PLAYBACK SESSION #2 STARTED               │
  ├─────────────────────────────────────────────────┤
  │ Session ID: b70514d1-4803-4c58-aaa5-b0a9d9  │
  │ Content ID: EPIS5847291                       │
  │ Title: Mystery at the Museum                  │
  │ Type: EPISODE                                 │
  │ Start Position: 120s                          │
  │ Time: 15:02:36                                │
  └─────────────────────────────────────────────────┘

[15:02:36.123] [S2] playbackInitiatedEvent
[15:02:36.456] [S2] playbackInfoResolutionStartEvent
  ... more PSDK events for playback #2 ...

  ┌─────────────────────────────────────────────────┐
  │   ⏹️  PLAYBACK SESSION #2 ENDED                 │
  ├─────────────────────────────────────────────────┤
  │ ID: b70514d1-4803-4c58-aaa5-b0a9d9986763      │
  │ Duration: 7s | Events: 45                      │
  ├─────────────────────────────────────────────────┤
  │ ContentMetadata: ✅ VALID (5/6 fields)          │
  └─────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════╗
║           🛑 PLAYER SESSION ENDED                 ║
╠═══════════════════════════════════════════════════╣
║ S1: 5b54b105-e336-42b8-b7e9-8199e3da06a2║
║ S2: b70514d1-4803-4c58-aaa5-b0a9d9986763║
║ Duration: 72s                                     ║
║ Playback Sessions: 2                              ║
║ Total PSDK Events: 234                            ║
╚═══════════════════════════════════════════════════╝
```

### Validation Results

The monitor validates content metadata at the end of each playback session:

**✅ VALID Results:**
- `✅ VALID (All fields present)` - All required and optional fields present with valid enum values
- `✅ VALID (5/6 fields)` - All required fields present, some optional fields missing

**❌ INVALID Results:**
- `❌ INVALID - Missing required: playbackType` - Required field(s) missing
- `❌ INVALID - Invalid playbackType: 'bad_value'` - Invalid enum value
- `❌ INVALID - Invalid contentType: 'INVALID'` - Invalid enum value

**Validation Checks:**
1. **Required fields** - id, title, playbackType must be present
2. **PlaybackType enum** - Must be valid (userInitiated, AUTO, INLINE, continuous, etc.)
3. **ContentType enum** - Must be valid if present (episode, standalone, clip, etc.)
4. **Optional fields** - Tracked but not required (subtitle, contentType, initialPlaybackPosition)

## Troubleshooting

### Missing Fields

If a field like `playbackType` is not showing in the monitor display:

### 1. Check if the field exists in your logs

Look at the raw telnet log file in `.temp/<session>/roku_logs_*.log`:

```bash
# Search for the field in raw logs
grep -i "playbacktype" .temp/*/roku_logs_*.log

# Or check the content load section
grep -A 20 "Player Controller: Load" .temp/*/roku_logs_*.log
```

### 2. Verify the field format

The field might be:
- Under a different name: `PlaybackType` vs `playbackType`
- In a nested object: `contentMetadata.PlaybackType`
- In JSON format: `"playbackType":"value"`
- Not present in your SDK version

### 3. Update extraction pattern

If the field exists but isn't extracted, check `scripts/monitor_psdk_events.sh` around line 338-350 for the extraction pattern:

```bash
# Current patterns try multiple formats:
if [[ "$line" =~ ^playbackType:[[:space:]]*\"([^\"]+)\" ]]; then
    CONTENT_PLAYBACK_TYPE="${BASH_REMATCH[1]}"
elif [[ "$line" =~ ^PlaybackType:[[:space:]]*\"([^\"]+)\" ]]; then
    CONTENT_PLAYBACK_TYPE="${BASH_REMATCH[1]}"
# ... more patterns ...
fi
```

### 4. Field might not be available

Some fields are only available in certain scenarios:
- `playbackType` might only appear for specific content types
- Some metadata is optional and depends on the content source
- SDK version differences may affect available fields

**Solution**: The monitor will only display fields that are present. If a field is empty/missing, it won't show in the header. This is by design to keep the output clean.

### Invalid Enum Values

If validation shows invalid playbackType or contentType:

**Check 1: Case Sensitivity**
- PlaybackType values are mixed case: `userInitiated`, `AUTO`, `INLINE`
- ContentType values are lowercase: `episode`, `short_preview`

```bash
# Check exact case in logs
grep -o 'playbackType":"[^"]*"' .temp/*/roku_logs_*.log
grep -o 'contentType":"[^"]*"' .temp/*/roku_logs_*.log
```

**Check 2: Whitespace**
```bash
# Look for hidden whitespace
grep 'playbackType' .temp/*/roku_logs_*.log | cat -A
```

**Check 3: Add Custom Values**
If your app uses custom values, add them to the config:

```json
{
  "content_metadata": {
    "validation": {
      "playback_type_enum": {
        "valid_values": ["userInitiated", "AUTO", "myCustomValue"]
      }
    }
  }
}
```

**Check 4: Disable Enum Validation**
If you don't want enum validation:

```json
{
  "content_metadata": {
    "validation": {
      "playback_type_enum": { "enabled": false },
      "content_type_enum": { "enabled": false }
    }
  }
}
```

## Notes

- If `jq` is not installed, the monitor falls back to default patterns
- The monitor script loads configuration on startup
- No restart needed for main capture - only affects the monitor terminal
- Configuration is version controlled and shared across the team
- All content metadata fields are optional - they only display if present in the logs
- Validation is configurable and can be disabled or customized per your needs
- See `docs/5_PSDK_MONITOR.md` for complete documentation

