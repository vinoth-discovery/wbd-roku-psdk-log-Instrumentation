# Monitor Configuration

This directory contains configuration files for the PSDK event monitor.

## monitor_config.json

Controls player lifecycle tracking in the PSDK event monitor terminal.

### Configuration Options

```json
{
  "player_lifecycle": {
    "creation_pattern": "PlayerSDK.Core.PlayerBuilder: new",
    "destruction_pattern": "playerSessionEndEvent",
    "description": "Patterns to detect player creation and destruction events"
  },
  "playback_lifecycle": {
    "initiation_pattern": "playbackInitiatedEvent",
    "end_pattern": "playbackSessionEndEvent",
    "description": "Patterns to detect playback session start and end within player sessions"
  },
  "content_metadata": {
    "load_pattern": "Player Controller: Load",
    "fields": ["id", "title", "contentType", "initialPlaybackPosition"],
    "description": "Pattern to detect content load events and fields to extract from contentMetadata"
  },
  "display": {
    "show_headers": true,
    "show_footers": true,
    "show_session_summary": true,
    "show_playback_headers": true,
    "show_content_metadata": true
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

### Content Metadata Patterns

**`load_pattern`**: Text pattern that indicates content metadata is being loaded.
- Default: `"Player Controller: Load"`
- When detected, the monitor extracts content information to display in the playback header
- Extracted fields include: `id`, `title`, `contentType`, `initialPlaybackPosition`

**Configurable Fields:**
- The fields to extract are defined in the `fields` array
- Each field maps to a property in the content metadata structure
- If the pattern changes, update `load_pattern` in the config

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
     - Content Type
     - Initial Playback Position
   - Start time
3. Counts PSDK events specific to this playback
4. Watches for `playback_lifecycle.end_pattern`
5. When found, displays an indented green footer with:
   - Playback duration
   - PSDK events count for this playback only

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

## Notes

- If `jq` is not installed, the monitor falls back to default patterns
- The monitor script loads configuration on startup
- No restart needed for main capture - only affects the monitor terminal
- Configuration is version controlled and shared across the team

