"""
Tests for log validation functionality.
"""

import pytest
from datetime import datetime
from roku_psdk_log_instrument.validation import LogValidator, ValidationResult
from roku_psdk_log_instrument.models import LogEntry, LogLevel


class TestLogValidator:
    """Test cases for LogValidator class."""
    
    def test_validator_initialization(self):
        """Test validator can be initialized."""
        validator = LogValidator()
        assert validator is not None
        assert validator.schema == {}
        assert validator.strict is False
    
    def test_validator_with_strict_mode(self):
        """Test validator initialization with strict mode."""
        validator = LogValidator(strict=True)
        assert validator.strict is True
    
    def test_validate_entry(self):
        """Test validating a single log entry."""
        validator = LogValidator()
        
        entry = LogEntry(
            timestamp=datetime.now(),
            level=LogLevel.INFO,
            message="Test message"
        )
        
        assert validator.validate_entry(entry) is True
    
    def test_validate_entries(self):
        """Test validating multiple log entries."""
        validator = LogValidator()
        
        entries = [
            LogEntry(timestamp=datetime.now(), level=LogLevel.INFO, message="Message 1"),
            LogEntry(timestamp=datetime.now(), level=LogLevel.ERROR, message="Message 2"),
        ]
        
        result = validator.validate_entries(entries)
        
        assert isinstance(result, ValidationResult)
        assert result.total_entries == 2
        assert result.valid_entries >= 0
    
    def test_validation_result_success_rate(self):
        """Test ValidationResult success rate calculation."""
        result = ValidationResult(
            is_valid=True,
            total_entries=100,
            valid_entries=90
        )
        
        assert result.success_rate == 90.0

