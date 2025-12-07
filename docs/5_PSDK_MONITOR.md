# PSDK Event Monitor

## Overview

The PSDK Event Monitor opens a separate terminal window with a **two-column layout** displaying PSDK events on the left and ISDK events on the right. It provides real-time monitoring of player lifecycle, playback sessions, and configurable field extraction.

## Quick Start

```bash
# Basic - opens monitor terminal automatically
psdk-instrument 192.168.50.81

# With custom pattern filtering
psdk-instrument 192.168.50.81 --pattern "[mux-analytics]"

# Multiple custom patterns
psdk-instrument 192.168.50.81 --pattern "[PLAYER_SDK]" --pattern "ERROR"

# Disable monitor
psdk-instrument 192.168.50.81 --no-monitor
```

## Two-Column Layout

The monitor displays events in a side-by-side layout:

```
───────────────────────────────────────────────────────────────────────────────┬───────────────────────────────────────────────────
  PSDK Events                                                                  │ ISDK Events
───────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────

[20:15:22.506] [S1] playbackInitiatedEvent                                     │
     └ playbackSessionId: cbbae0c3-6253-4b91-82d7-0fa4a69f9e52                 │

[20:15:22.507] [S1] playbackInfoResolutionStartEvent                           │
     ├ playbackSessionId: cbbae0c3-6253-4b91-82d7-0fa4a69f9e52                 │
     └ videoid: fe840c63-2779-484f-aeaa-85fc1a8d2c2a                           │

                                                                               │ [20:15:22.619] [S1] [ISDK] beam.events.playback.initiated_3.3
                                                                               │     ├ content.editId: fe840c63-2779-484f-aeaa-85fc1a8d2c2a
                                                                               │     ├ playback.playbackId: cbbae0c3-6253-4b91-82d7-0fa4a69f9e52
                                                                               │     └ playback.trigger: USER_INITIATED
```

## Session Headers & Footers

### Playback Started
```
  ┌───────────────────────────────────────────────────────────────────┐
  │ PLAYBACK #1 STARTED  Time: 20:15:22                               │
  ├───────────────────────────────────────────────────────────────────┤
  │ Session: cbbae0c3-6253-4b91-82d7-0fa4a69f9e52                     │
  │ ID(editId): fe840c63-2779-484f-aeaa-85fc1a8d2c2a                  │
  │ Title: Barry                                                      │
  │ Subtitle: Chapter One: Make Your Mark                             │
  │ contentType: episode                                              │
  │ playbackType: userInitiated                                       │
  └───────────────────────────────────────────────────────────────────┘
```

### Playback Ended (with Validation)
```
  ┌───────────────────────────────────────────────────────────────────┐
  │ PLAYBACK SESSION #1 ENDED                                         │
  ├───────────────────────────────────────────────────────────────────┤
  │ Session: cbbae0c3-6253-4b91-82d7-0fa4a69f9e52                     │
  │ Duration: 45s | Events: 156                                       │
  ├───────────────────────────────────────────────────────────────────┤
  │ ContentMetadata Validation: VALID (All fields present)            │
  └───────────────────────────────────────────────────────────────────┘
```

### Validation Failure Example
```
  ┌───────────────────────────────────────────────────────────────────┐
  │ PLAYBACK SESSION #1 ENDED                                         │
  ├───────────────────────────────────────────────────────────────────┤
  │ Session: c7a72565-3ddc-4913-833e-e4417fadecd7                     │
  │ Duration: 22s | Events: 92                                        │
  ├───────────────────────────────────────────────────────────────────┤
  │ ContentMetadata Validation: INVALID                               │
  │   - Missing required: playbackType                                │
  │   - Invalid contentType: 'UNKNOWN_TYPE'                           │
  └───────────────────────────────────────────────────────────────────┘
```

## Custom Pattern Filtering

Filter for custom log patterns in addition to PSDK/ISDK events:

```bash
# Single pattern
psdk-instrument 192.168.50.81 --pattern "[mux-analytics]"

# Multiple patterns
psdk-instrument 192.168.50.81 -f "[PLAYER_SDK]" -f "ERROR" -f "WARNING"
```

Custom pattern matches appear with `[CUSTOM]` tag:
```
[20:15:30.123] [CUSTOM] [mux-analytics] EVENT playerready{...}
```

## Configuration

All monitoring is configured in `config/monitor_config.json`.

### Per-Event Field Display

Configure which fields to extract and display for each event type:

```json
{
  "event_fields": {
    "enabled": true,
    "psdk_events": {
      "default": ["playbackSessionId"],
      "playbackInitiatedEvent": ["playbackSessionId"],
      "playbackInfoResolutionStartEvent": ["playbackSessionId", "videoid"],
      "playbackProgressEvent": ["playbackSessionId", "playheaddata.contentplayheadms", "playheaddata.streamplayheadms"]
    },
    "isdk_events": {
      "default": ["content.editId", "playback.playbackId"],
      "beam.events.playback.initiated_3.3": ["content.editId", "playback.playbackId", "playback.trigger"],
      "beam.events.playback.buffer_1.4": ["buffer.action", "buffer.type"],
      "beam.events.playback.statechange_1.4": ["stateChange.action", "playhead.contentPosition"]
    }
  }
}
```

**Key Points:**
- Use `default` for events not explicitly configured
- Event names are **case-sensitive** - match exactly as they appear in logs
- Nested fields use dot notation: `playhead.contentPosition`, `buffer.action`
- Each event can have different fields configured

### ContentMetadata Validation

```json
{
  "content_metadata": {
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
                         "movie", "podcast", "promo", "extra", "live_channel"]
      }
    }
  }
}
```

### Lifecycle Patterns

```json
{
  "player_lifecycle": {
    "creation_pattern": "PlayerSDK.Core.PlayerBuilder: new",
    "destruction_pattern": "playerSessionEndEvent"
  },
  "playback_lifecycle": {
    "initiation_pattern": "playbackInitiatedEvent",
    "end_pattern": "playbackSessionEndEvent"
  }
}
```

## Display Options

```json
{
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

## Event Field Examples

### PSDK Events

| Event | Available Fields |
|-------|------------------|
| `playbackInitiatedEvent` | `playbackSessionId`, `contentmetadata` (null) |
| `playbackInfoResolutionStartEvent` | `playbackSessionId`, `videoid`, `streamtype` |
| `playbackProgressEvent` | `playbackSessionId`, `playheaddata.contentplayheadms`, `playheaddata.streamplayheadms` |
| `playbackSessionEndEvent` | `playbackSessionId` |

### ISDK Events

| Event | Available Fields |
|-------|------------------|
| `beam.events.playback.initiated_3.3` | `content.editId`, `playback.playbackId`, `playback.trigger` |
| `beam.events.playback.buffer_1.4` | `buffer.action`, `buffer.type`, `playhead.contentPosition` |
| `beam.events.playback.statechange_1.4` | `stateChange.action`, `playhead.contentPosition`, `playhead.streamPosition` |

## Adding New Events

1. Find the exact event name in your logs (case-sensitive)
2. Identify the field paths you want to display
3. Add to `monitor_config.json`:

```json
{
  "isdk_events": {
    "beam.events.playback.mynewevent_1.0": ["field1", "nested.field2", "another.nested.field"]
  }
}
```

4. Restart the monitor to apply changes

## Troubleshooting

### Fields Not Showing

1. **Check event name case** - Must match exactly (e.g., `statechange` not `stateChange`)
2. **Check field path** - Use dot notation for nested fields
3. **Restart monitor** - Config changes require restart
4. **Verify jq installed** - Required for JSON parsing: `brew install jq`

### Monitor Doesn't Open

1. Check Terminal.app permissions (macOS)
2. Try manually: `./scripts/monitor_psdk_events.sh .temp/<session>/roku_logs_*.log`

### Events Not Appearing

1. Wait for activity - events appear in real-time
2. Check log file has content: `tail -f .temp/<session>/roku_logs_*.log`
3. Verify PSDK patterns match your SDK version

## Manual Usage

```bash
# Monitor existing log file
./scripts/monitor_psdk_events.sh .temp/20251207_201522/roku_logs_20251207_201522.log

# With custom patterns
./scripts/monitor_psdk_events.sh .temp/20251207_201522/roku_logs_20251207_201522.log "[mux-analytics]" "ERROR"
```

## Platform Support

| Platform | Status | Terminal |
|----------|--------|----------|
| macOS | ✅ Supported | Terminal.app via AppleScript |
| Linux | ✅ Supported | gnome-terminal, xterm, konsole |
| Windows | ⚠️ Manual | WSL/Git Bash required |

## See Also

- [Quick Start Guide](1_QUICKSTART.md)
- [Telnet Usage](3_TELNET_USAGE.md)
- [Configuration README](../config/README.md)
