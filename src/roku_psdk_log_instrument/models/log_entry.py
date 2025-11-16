"""
Data models for log entries.
"""

from datetime import datetime
from enum import Enum
from typing import Optional, Dict, Any
from pydantic import BaseModel, Field


class LogLevel(str, Enum):
    """Log level enumeration."""
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"


class LogEntry(BaseModel):
    """Model representing a single log entry."""
    
    timestamp: datetime = Field(..., description="Timestamp of the log entry")
    level: LogLevel = Field(..., description="Log level")
    message: str = Field(..., description="Log message")
    source: Optional[str] = Field(None, description="Source of the log entry")
    component: Optional[str] = Field(None, description="Component that generated the log")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="Additional metadata")
    
    class Config:
        """Pydantic configuration."""
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }
    
    def __str__(self) -> str:
        """String representation of the log entry."""
        return f"[{self.timestamp.isoformat()}] {self.level.value}: {self.message}"

