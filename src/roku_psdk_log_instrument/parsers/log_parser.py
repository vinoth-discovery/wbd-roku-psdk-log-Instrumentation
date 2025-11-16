"""
Log parsing functionality.
"""

import re
from datetime import datetime
from typing import List, Optional, TextIO
from pathlib import Path
from roku_psdk_log_instrument.models.log_entry import LogEntry, LogLevel


class LogParser:
    """
    Parses Roku PSDK log files into structured log entries.
    """
    
    # Default regex pattern for log parsing (can be customized)
    DEFAULT_PATTERN = r"(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+)\s+\[(\w+)\]\s+(.*)"
    
    def __init__(self, pattern: Optional[str] = None):
        """
        Initialize the log parser.
        
        Args:
            pattern: Optional regex pattern for parsing logs
        """
        self.pattern = re.compile(pattern or self.DEFAULT_PATTERN)
    
    def parse_file(self, log_path: Path) -> List[LogEntry]:
        """
        Parse a log file and return structured log entries.
        
        Args:
            log_path: Path to the log file
            
        Returns:
            List of parsed log entries
        """
        entries = []
        
        with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line_num, line in enumerate(f, start=1):
                entry = self.parse_line(line, line_num)
                if entry:
                    entries.append(entry)
        
        return entries
    
    def parse_line(self, line: str, line_num: Optional[int] = None) -> Optional[LogEntry]:
        """
        Parse a single log line into a LogEntry.
        
        Args:
            line: Log line to parse
            line_num: Optional line number for tracking
            
        Returns:
            LogEntry object or None if parsing fails
        """
        match = self.pattern.match(line.strip())
        
        if not match:
            return None
        
        try:
            timestamp_str = match.group(1)
            level_str = match.group(2).upper()
            message = match.group(3)
            
            # Parse timestamp
            timestamp = datetime.fromisoformat(timestamp_str.replace(' ', 'T'))
            
            # Parse level
            try:
                level = LogLevel[level_str]
            except KeyError:
                level = LogLevel.INFO
            
            # Create log entry
            entry = LogEntry(
                timestamp=timestamp,
                level=level,
                message=message,
                metadata={"line_number": line_num} if line_num else {}
            )
            
            return entry
            
        except Exception:
            return None
    
    def parse_stream(self, stream: TextIO) -> List[LogEntry]:
        """
        Parse logs from a stream.
        
        Args:
            stream: Text stream to parse
            
        Returns:
            List of parsed log entries
        """
        entries = []
        
        for line_num, line in enumerate(stream, start=1):
            entry = self.parse_line(line, line_num)
            if entry:
                entries.append(entry)
        
        return entries

