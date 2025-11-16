"""
Tests for log instrumentation functionality.
"""

import pytest
from datetime import datetime
from roku_psdk_log_instrument.instrumentation import LogInstrumenter
from roku_psdk_log_instrument.models import LogEntry, LogLevel


class TestLogInstrumenter:
    """Test cases for LogInstrumenter class."""
    
    def test_instrumenter_initialization(self):
        """Test instrumenter can be initialized."""
        instrumenter = LogInstrumenter()
        assert instrumenter is not None
        assert instrumenter.config == {}
    
    def test_instrumenter_with_config(self):
        """Test instrumenter initialization with config."""
        config = {"key": "value"}
        instrumenter = LogInstrumenter(config=config)
        assert instrumenter.config == config
    
    def test_add_metadata(self):
        """Test adding metadata to a log entry."""
        instrumenter = LogInstrumenter()
        
        entry = LogEntry(
            timestamp=datetime.now(),
            level=LogLevel.INFO,
            message="Test message"
        )
        
        metadata = {"test_key": "test_value"}
        updated_entry = instrumenter.add_metadata(entry, metadata)
        
        assert "test_key" in updated_entry.metadata
        assert updated_entry.metadata["test_key"] == "test_value"
    
    def test_instrument_entries(self):
        """Test instrumenting a list of log entries."""
        instrumenter = LogInstrumenter()
        
        entries = [
            LogEntry(timestamp=datetime.now(), level=LogLevel.INFO, message="Message 1"),
            LogEntry(timestamp=datetime.now(), level=LogLevel.ERROR, message="Message 2"),
        ]
        
        instrumented = instrumenter.instrument_entries(entries)
        assert len(instrumented) == len(entries)

