"""
Tests for telnet connection functionality.
"""

import pytest
from pathlib import Path
from roku_psdk_log_instrument.telnet import RokuTelnetClient, SessionManager


class TestRokuTelnetClient:
    """Test cases for RokuTelnetClient class."""
    
    def test_client_initialization(self):
        """Test client can be initialized."""
        client = RokuTelnetClient(host="192.168.1.100")
        assert client is not None
        assert client.host == "192.168.1.100"
        assert client.port == 8085
        assert client.connection is None
    
    def test_client_with_custom_port(self):
        """Test client initialization with custom port."""
        client = RokuTelnetClient(host="192.168.1.100", port=9999)
        assert client.port == 9999
    
    def test_is_connected_when_not_connected(self):
        """Test is_connected returns False when not connected."""
        client = RokuTelnetClient(host="192.168.1.100")
        assert client.is_connected() is False


class TestSessionManager:
    """Test cases for SessionManager class."""
    
    def test_session_manager_initialization(self):
        """Test session manager can be initialized."""
        manager = SessionManager()
        assert manager is not None
        assert manager.base_path == Path.cwd()
    
    def test_session_manager_with_custom_path(self):
        """Test session manager with custom base path."""
        custom_path = Path("/tmp/test")
        manager = SessionManager(base_path=custom_path)
        assert manager.base_path == custom_path
    
    def test_temp_directory_creation(self, tmp_path):
        """Test .temp directory is created."""
        manager = SessionManager(base_path=tmp_path)
        temp_dir = manager.initialize_temp_directory()
        
        assert temp_dir.exists()
        assert temp_dir.is_dir()
        assert temp_dir.name == ".temp"
    
    def test_create_session(self, tmp_path):
        """Test creating a new session."""
        manager = SessionManager(base_path=tmp_path)
        session = manager.create_session(
            host="192.168.1.100",
            port=8085,
            description="Test session"
        )
        
        assert session is not None
        assert "session_id" in session
        assert session["host"] == "192.168.1.100"
        assert session["port"] == 8085
        assert session["status"] == "active"
        assert session["description"] == "Test session"
    
    def test_get_session_log_path(self, tmp_path):
        """Test getting session log path."""
        manager = SessionManager(base_path=tmp_path)
        session = manager.create_session(host="192.168.1.100")
        
        log_path = manager.get_session_log_path(session)
        
        assert log_path is not None
        assert log_path.parent.exists()
        assert log_path.name.startswith("roku_logs_")
    
    def test_end_session(self, tmp_path):
        """Test ending a session."""
        manager = SessionManager(base_path=tmp_path)
        session = manager.create_session(host="192.168.1.100")
        
        manager.end_session(session, line_count=100)
        
        assert session["status"] == "completed"
        assert session["line_count"] == 100
        assert "end_time" in session
    
    def test_list_sessions(self, tmp_path):
        """Test listing sessions."""
        manager = SessionManager(base_path=tmp_path)
        
        # Create multiple sessions
        session1 = manager.create_session(host="192.168.1.100")
        manager.end_session(session1)
        
        session2 = manager.create_session(host="192.168.1.101")
        
        sessions = manager.list_sessions()
        
        assert len(sessions) >= 2
    
    def test_get_active_sessions(self, tmp_path):
        """Test getting active sessions."""
        manager = SessionManager(base_path=tmp_path)
        
        # Create and end first session
        session1 = manager.create_session(host="192.168.1.100")
        manager.end_session(session1)
        
        # Create active session
        session2 = manager.create_session(host="192.168.1.101")
        
        active_sessions = manager.get_active_sessions()
        
        assert len(active_sessions) == 1
        assert active_sessions[0]["host"] == "192.168.1.101"

