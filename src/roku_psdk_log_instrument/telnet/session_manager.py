"""
Session manager for organizing telnet log captures.
"""

import json
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, List


class SessionManager:
    """
    Manages telnet capture sessions and log file organization.
    """
    
    TEMP_DIR_NAME = ".temp"
    SESSION_INFO_FILE = "session_info.json"
    
    def __init__(self, base_path: Optional[Path] = None):
        """
        Initialize the session manager.
        
        Args:
            base_path: Base directory for storing logs (defaults to current directory)
        """
        self.base_path = base_path or Path.cwd()
        self.temp_dir = self.base_path / self.TEMP_DIR_NAME
        self._current_session: Optional[Dict] = None
    
    def initialize_temp_directory(self) -> Path:
        """
        Create .temp directory if it doesn't exist.
        
        Returns:
            Path to .temp directory
        """
        self.temp_dir.mkdir(exist_ok=True)
        
        # Create .gitignore in .temp to prevent committing logs
        gitignore_path = self.temp_dir / ".gitignore"
        if not gitignore_path.exists():
            gitignore_path.write_text("*\n!.gitignore\n")
        
        return self.temp_dir
    
    def create_session(
        self,
        host: str,
        port: int = 8085,
        description: Optional[str] = None
    ) -> Dict:
        """
        Create a new capture session.
        
        Args:
            host: Roku device host
            port: Telnet port
            description: Optional session description
            
        Returns:
            Session information dictionary
        """
        # Initialize temp directory
        self.initialize_temp_directory()
        
        # Create session info
        timestamp = datetime.now()
        session_id = timestamp.strftime("%Y%m%d_%H%M%S")
        
        session_info = {
            "session_id": session_id,
            "host": host,
            "port": port,
            "start_time": timestamp.isoformat(),
            "description": description or f"Roku log capture from {host}",
            "status": "active",
            "log_file": f"roku_logs_{session_id}.log",
            "line_count": 0
        }
        
        # Create session directory
        session_dir = self.temp_dir / session_id
        session_dir.mkdir(exist_ok=True)
        
        # Save session info
        info_file = session_dir / self.SESSION_INFO_FILE
        info_file.write_text(json.dumps(session_info, indent=2))
        
        self._current_session = session_info
        self._current_session["directory"] = session_dir
        
        print(f"✓ Created session: {session_id}")
        print(f"  Directory: {session_dir}")
        
        return self._current_session
    
    def get_session_log_path(self, session: Optional[Dict] = None) -> Path:
        """
        Get the log file path for a session.
        
        Args:
            session: Session dictionary (uses current session if None)
            
        Returns:
            Path to log file
        """
        session = session or self._current_session
        
        if not session:
            raise ValueError("No active session")
        
        session_dir = session.get("directory") or (
            self.temp_dir / session["session_id"]
        )
        
        return session_dir / session["log_file"]
    
    def end_session(
        self,
        session: Optional[Dict] = None,
        line_count: Optional[int] = None
    ) -> None:
        """
        Mark a session as ended.
        
        Args:
            session: Session dictionary (uses current session if None)
            line_count: Number of lines captured
        """
        session = session or self._current_session
        
        if not session:
            print("No active session to end")
            return
        
        # Update session info
        session["end_time"] = datetime.now().isoformat()
        session["status"] = "completed"
        
        if line_count is not None:
            session["line_count"] = line_count
        
        # Save updated session info
        session_dir = session.get("directory") or (
            self.temp_dir / session["session_id"]
        )
        info_file = session_dir / self.SESSION_INFO_FILE
        
        # Remove directory key before saving (not JSON serializable)
        save_session = {k: v for k, v in session.items() if k != "directory"}
        info_file.write_text(json.dumps(save_session, indent=2))
        
        print(f"✓ Session ended: {session['session_id']}")
        
        if session == self._current_session:
            self._current_session = None
    
    def list_sessions(self) -> List[Dict]:
        """
        List all capture sessions.
        
        Returns:
            List of session information dictionaries
        """
        if not self.temp_dir.exists():
            return []
        
        sessions = []
        
        for session_dir in self.temp_dir.iterdir():
            if not session_dir.is_dir():
                continue
            
            info_file = session_dir / self.SESSION_INFO_FILE
            
            if info_file.exists():
                try:
                    session_info = json.loads(info_file.read_text())
                    session_info["directory"] = session_dir
                    sessions.append(session_info)
                except json.JSONDecodeError:
                    continue
        
        # Sort by start time (newest first)
        sessions.sort(key=lambda x: x.get("start_time", ""), reverse=True)
        
        return sessions
    
    def get_active_sessions(self) -> List[Dict]:
        """
        Get all active capture sessions.
        
        Returns:
            List of active session information dictionaries
        """
        all_sessions = self.list_sessions()
        return [s for s in all_sessions if s.get("status") == "active"]
    
    def cleanup_old_sessions(self, days: int = 7) -> int:
        """
        Clean up sessions older than specified days.
        
        Args:
            days: Number of days to keep sessions
            
        Returns:
            Number of sessions cleaned up
        """
        if not self.temp_dir.exists():
            return 0
        
        from datetime import timedelta
        import shutil
        
        cutoff_date = datetime.now() - timedelta(days=days)
        cleaned_count = 0
        
        for session in self.list_sessions():
            try:
                start_time = datetime.fromisoformat(session["start_time"])
                
                if start_time < cutoff_date and session.get("status") != "active":
                    session_dir = session["directory"]
                    shutil.rmtree(session_dir)
                    cleaned_count += 1
                    print(f"Cleaned up session: {session['session_id']}")
            except Exception as e:
                print(f"Warning: Error cleaning session {session.get('session_id')}: {e}")
        
        return cleaned_count
    
    def get_current_session(self) -> Optional[Dict]:
        """
        Get the current active session.
        
        Returns:
            Current session dictionary or None
        """
        return self._current_session
    
    def delete_session(self, session: Optional[Dict] = None) -> bool:
        """
        Delete a session and its log files.
        
        Args:
            session: Session dictionary (uses current session if None)
            
        Returns:
            True if deleted successfully, False otherwise
        """
        import shutil
        
        session = session or self._current_session
        
        if not session:
            print("No session to delete")
            return False
        
        try:
            session_dir = session.get("directory") or (
                self.temp_dir / session["session_id"]
            )
            
            if session_dir.exists():
                shutil.rmtree(session_dir)
                print(f"✓ Deleted session: {session['session_id']}")
                
                if session == self._current_session:
                    self._current_session = None
                
                return True
            else:
                print(f"Session directory not found: {session_dir}")
                return False
        except Exception as e:
            print(f"Error deleting session: {e}")
            return False

