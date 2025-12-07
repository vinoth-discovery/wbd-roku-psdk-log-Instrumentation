# Monitor Configuration

Configuration for the PSDK Event Monitor in `monitor_config.json`.

## Quick Reference

```json
{
  "player_lifecycle": { ... },
  "playback_lifecycle": { ... },
  "content_metadata": { ... },
  "display": { ... },
  "event_fields": { ... }
}
```

## Full Configuration

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
    "description": "Patterns to detect playback session start and end"
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
  },
  "event_fields": {
    "enabled": true,
    "description": "Configure which fields to extract per event name",
    "psdk_events": {
      "default": ["playbackSessionId"],
      "playbackInitiatedEvent": ["playbackSessionId"],
      "playbackInfoResolutionStartEvent": ["playbackSessionId", "videoid"],
      "playbackProgressEvent": ["playbackSessionId", "playheaddata.contentplayheadms", "playheaddata.streamplayheadms"],
      "playbackSessionEndEvent": ["playbackSessionId"]
    },
    "isdk_events": {
      "default": ["content.editId", "playback.playbackId"],
      "beam.events.playback.initiated_3.3": ["content.editId", "playback.playbackId", "playback.trigger"],
      "beam.events.playback.buffer_1.4": ["buffer.action", "buffer.type"],
      "beam.events.playback.statechange_1.4": ["stateChange.action", "playhead.contentPosition", "playhead.streamPosition"]
    }
  }
}
```

## Per-Event Field Configuration

### How It Works

Each event type can have different fields displayed:

```json
"psdk_events": {
  "default": ["playbackSessionId"],                    // Fallback for unlisted events
  "playbackProgressEvent": ["playbackSessionId", "playheaddata.contentplayheadms"]
}
```

### Nested Fields

Use dot notation for nested JSON fields:

```
playheaddata.contentplayheadms  →  {"playheaddata": {"contentplayheadms": 12345}}
content.editId                   →  {"content": {"editId": "abc-123"}}
buffer.action                    →  {"buffer": {"action": "BUFFER_START"}}
```

### Adding New Events

1. Find exact event name in logs (case-sensitive!)
2. Identify field paths
3. Add to config:

```json
"isdk_events": {
  "beam.events.playback.myevent_1.0": ["field1", "nested.field2"]
}
```

4. Restart monitor

## Common PSDK Fields

| Event | Fields |
|-------|--------|
| `playbackInitiatedEvent` | `playbackSessionId` |
| `playbackInfoResolutionStartEvent` | `playbackSessionId`, `videoid` |
| `playbackProgressEvent` | `playbackSessionId`, `playheaddata.contentplayheadms`, `playheaddata.streamplayheadms` |

## Common ISDK Fields

| Event | Fields |
|-------|--------|
| `beam.events.playback.initiated_3.3` | `content.editId`, `playback.playbackId`, `playback.trigger` |
| `beam.events.playback.buffer_1.4` | `buffer.action`, `buffer.type` |
| `beam.events.playback.statechange_1.4` | `stateChange.action`, `playhead.contentPosition` |

## Validation

### Required Fields
Fields that must be present for validation to pass:
- `id` - Content identifier
- `title` - Content title
- `playbackType` - How playback was initiated

### Optional Fields
Tracked but not required:
- `subtitle` - Episode name
- `contentType` - Type of content
- `initialPlaybackPosition` - Start position

### Enum Validation

**playbackType values:**
- `userInitiated` - User clicked play
- `AUTO` - Auto-played on page load
- `INLINE` - Inline video in tiles
- `continuous` - Next asset auto-played
- `confirmedContinuous` - Up next button clicked
- `confirmedEndCard` - End card watch button clicked
- `autoPlayEndCard` - End card auto-played

**contentType values:**
- `episode`, `movie`, `standalone`
- `clip`, `trailer`, `promo`, `extra`
- `live`, `live_channel`
- `podcast`, `short_preview`

## Disable Features

```json
// Disable all validation
"content_metadata": {
  "validation": { "enabled": false }
}

// Disable event field display
"event_fields": { "enabled": false }

// Disable only enum validation
"playback_type_enum": { "enabled": false },
"content_type_enum": { "enabled": false }
```

## Troubleshooting

### Fields Not Showing

1. **Case sensitivity** - `statechange` ≠ `stateChange`
2. **Restart required** - Config changes need monitor restart
3. **Check jq** - Required for JSON parsing: `jq --version`

### Find Event Names

```bash
# Search logs for event names
grep "PSDK::ISDK.*Event:" .temp/*/roku_logs_*.log | head -20
```

### Test Field Extraction

```bash
# Check if jq can parse config
jq '.event_fields.isdk_events' config/monitor_config.json
```
