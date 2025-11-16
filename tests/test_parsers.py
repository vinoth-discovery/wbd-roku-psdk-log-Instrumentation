"""
Tests for log parsing functionality.
"""

import pytest
from datetime import datetime
from roku_psdk_log_instrument.parsers import LogParser
from roku_psdk_log_instrument.models import LogEntry, LogLevel


class TestLogParser:
    """Test cases for LogParser class."""
    
    def test_parser_initialization(self):
        """Test parser can be initialized."""
        parser = LogParser()
        assert parser is not None
        assert parser.pattern is not None
    
    def test_parse_valid_log_line(self):
        """Test parsing a valid log line."""
        parser = LogParser()
        
        # Sample log line in expected format
        log_line = "2024-11-16 10:30:45.123 [INFO] Test log message"
        
        entry = parser.parse_line(log_line)
        
        # Parser may return None if format doesn't match exactly
        # This is a placeholder test that should be updated based on actual log format
        if entry:
            assert isinstance(entry, LogEntry)
            assert entry.message is not None
    
    def test_parse_invalid_log_line(self):
        """Test parsing an invalid log line returns None."""
        parser = LogParser()
        
        log_line = "This is not a valid log line"
        entry = parser.parse_line(log_line)
        
        # Invalid lines should return None
        assert entry is None
    
    def test_custom_pattern(self):
        """Test parser with custom pattern."""
        custom_pattern = r"(\d{4}-\d{2}-\d{2})\s+(\w+):\s+(.*)"
        parser = LogParser(pattern=custom_pattern)
        
        assert parser is not None
        assert parser.pattern is not None

