"""
Roku Telnet Client for capturing logs from Roku devices.
"""

import socket
import time
from datetime import datetime
from pathlib import Path
from typing import Optional, Callable
from threading import Thread, Event


class RokuTelnetClient:
    """
    Client for connecting to Roku device via telnet on port 8085.
    """
    
    DEFAULT_PORT = 8085
    TIMEOUT = 5
    BUFFER_SIZE = 4096
    
    def __init__(
        self,
        host: str,
        port: int = DEFAULT_PORT,
        timeout: int = TIMEOUT
    ):
        """
        Initialize the Roku telnet client.
        
        Args:
            host: Roku device IP address or hostname
            port: Telnet port (default: 8085)
            timeout: Connection timeout in seconds
        """
        self.host = host
        self.port = port
        self.timeout = timeout
        self.socket: Optional[socket.socket] = None
        self._stop_event = Event()
        self._capture_thread: Optional[Thread] = None
        self._buffer = b""
    
    def is_connected(self) -> bool:
        """
        Check if telnet connection is active.
        
        Returns:
            True if connected, False otherwise
        """
        if self.socket is None:
            return False
        
        try:
            # Try to send empty data to check if connection is alive
            self.socket.send(b'')
            return True
        except (socket.error, AttributeError, OSError):
            return False
    
    def connect(self) -> bool:
        """
        Establish telnet connection to Roku device.
        
        Returns:
            True if connection successful, False otherwise
        """
        if self.is_connected():
            print(f"Already connected to {self.host}:{self.port}")
            return True
        
        try:
            print(f"Connecting to Roku device at {self.host}:{self.port}...")
            
            # Create socket
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.settimeout(self.timeout)
            
            # Connect to device
            self.socket.connect((self.host, self.port))
            
            # Set to non-blocking mode after connection
            self.socket.setblocking(False)
            
            print(f"✓ Successfully connected to {self.host}:{self.port}")
            return True
            
        except socket.timeout:
            print(f"✗ Connection timeout: Unable to connect to {self.host}:{self.port}")
            self.socket = None
            return False
        except socket.error as e:
            print(f"✗ Connection error: {e}")
            self.socket = None
            return False
        except Exception as e:
            print(f"✗ Unexpected error: {e}")
            self.socket = None
            return False
    
    def disconnect(self) -> None:
        """
        Close the telnet connection.
        """
        self._stop_event.set()
        
        if self._capture_thread and self._capture_thread.is_alive():
            self._capture_thread.join(timeout=2)
        
        if self.socket:
            try:
                self.socket.close()
                print(f"✓ Disconnected from {self.host}:{self.port}")
            except Exception as e:
                print(f"Warning: Error during disconnect: {e}")
            finally:
                self.socket = None
                self._buffer = b""
    
    def read_line(self, timeout: Optional[float] = None) -> Optional[str]:
        """
        Read a single line from the telnet connection.
        
        Args:
            timeout: Read timeout in seconds
            
        Returns:
            Line as string or None if error/timeout
        """
        if not self.is_connected() or self.socket is None:
            return None
        
        try:
            # Check if we have a complete line in buffer
            while b'\n' not in self._buffer:
                # Set socket timeout
                self.socket.settimeout(timeout or 1.0)
                
                try:
                    # Read data from socket
                    data = self.socket.recv(self.BUFFER_SIZE)
                    
                    if not data:
                        # Connection closed
                        return None
                    
                    self._buffer += data
                    
                except socket.timeout:
                    # No data available
                    if not self._buffer:
                        return None
                    break
                except BlockingIOError:
                    # No data available in non-blocking mode
                    time.sleep(0.01)
                    continue
            
            # Extract line from buffer
            if b'\n' in self._buffer:
                line, self._buffer = self._buffer.split(b'\n', 1)
                return line.decode('utf-8', errors='ignore').strip()
            
            return None
            
        except (socket.error, OSError) as e:
            return None
        except Exception as e:
            print(f"Error reading line: {e}")
            return None
    
    def capture_logs(
        self,
        output_file: Path,
        callback: Optional[Callable[[str], None]] = None,
        max_duration: Optional[int] = None
    ) -> None:
        """
        Capture logs from telnet connection and write to file.
        
        Args:
            output_file: Path to save captured logs
            callback: Optional callback function for each log line
            max_duration: Optional maximum capture duration in seconds
        """
        if not self.is_connected():
            print("✗ Not connected. Cannot capture logs.")
            return
        
        print(f"Starting log capture to {output_file}")
        print("Press Ctrl+C to stop capturing...")
        
        start_time = time.time()
        line_count = 0
        
        try:
            with open(output_file, 'w', encoding='utf-8') as f:
                while not self._stop_event.is_set():
                    # Check max duration
                    if max_duration and (time.time() - start_time) > max_duration:
                        print(f"\nReached max duration of {max_duration} seconds")
                        break
                    
                    # Read line from telnet
                    line = self.read_line(timeout=1.0)
                    
                    if line is None:
                        continue
                    
                    if line:  # Skip empty lines
                        # Write to file
                        f.write(f"{line}\n")
                        f.flush()
                        
                        # Call callback if provided
                        if callback:
                            callback(line)
                        
                        line_count += 1
                        
                        # Print progress
                        if line_count % 100 == 0:
                            print(f"Captured {line_count} log lines...", end='\r')
        
        except KeyboardInterrupt:
            print("\n\n✓ Log capture stopped by user")
        except Exception as e:
            print(f"\n✗ Error during log capture: {e}")
        finally:
            print(f"\n✓ Captured {line_count} log lines to {output_file}")
    
    def start_capture_async(
        self,
        output_file: Path,
        callback: Optional[Callable[[str], None]] = None,
        max_duration: Optional[int] = None
    ) -> None:
        """
        Start log capture in a background thread.
        
        Args:
            output_file: Path to save captured logs
            callback: Optional callback function for each log line
            max_duration: Optional maximum capture duration in seconds
        """
        if self._capture_thread and self._capture_thread.is_alive():
            print("Capture already in progress")
            return
        
        self._stop_event.clear()
        self._capture_thread = Thread(
            target=self.capture_logs,
            args=(output_file, callback, max_duration),
            daemon=True
        )
        self._capture_thread.start()
    
    def stop_capture(self) -> None:
        """
        Stop the ongoing log capture.
        """
        self._stop_event.set()
        if self._capture_thread:
            self._capture_thread.join(timeout=2)
    
    def send_command(self, command: str) -> bool:
        """
        Send a command to the Roku device via telnet.
        
        Args:
            command: Command string to send
            
        Returns:
            True if sent successfully, False otherwise
        """
        if not self.is_connected() or self.socket is None:
            return False
        
        try:
            # Ensure command ends with newline
            if not command.endswith('\n'):
                command += '\n'
            
            # Send command
            self.socket.send(command.encode('utf-8'))
            return True
        except (socket.error, OSError) as e:
            print(f"Error sending command: {e}")
            return False
    
    @staticmethod
    def test_connection(host: str, port: int = DEFAULT_PORT, timeout: int = TIMEOUT) -> bool:
        """
        Test if a telnet connection can be established.
        
        Args:
            host: Roku device IP address or hostname
            port: Telnet port
            timeout: Connection timeout in seconds
            
        Returns:
            True if connection successful, False otherwise
        """
        try:
            test_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            test_socket.settimeout(timeout)
            test_socket.connect((host, port))
            test_socket.close()
            return True
        except Exception:
            return False

