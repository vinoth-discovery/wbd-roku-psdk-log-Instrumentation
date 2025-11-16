#!/usr/bin/env python3
"""
Example script demonstrating how to capture logs from Roku device.
"""

from roku_psdk_log_instrument import RokuTelnetClient, SessionManager


def main():
    """Main example function."""
    
    # Configuration
    ROKU_IP = "192.168.1.100"  # Replace with your Roku device IP
    PORT = 8085
    
    print("=" * 60)
    print("Roku PSDK Log Capture Example")
    print("=" * 60)
    
    # Initialize session manager
    print("\n1. Initializing session manager...")
    session_mgr = SessionManager()
    
    # Initialize telnet client
    print(f"2. Creating telnet client for {ROKU_IP}:{PORT}...")
    client = RokuTelnetClient(host=ROKU_IP, port=PORT)
    
    # Test connection first
    print("\n3. Testing connection...")
    if not RokuTelnetClient.test_connection(ROKU_IP, PORT):
        print(f"✗ Cannot connect to {ROKU_IP}:{PORT}")
        print("\nPlease check:")
        print("  - Roku device IP address is correct")
        print("  - Device is powered on and connected to network")
        print("  - Telnet port 8085 is accessible")
        return
    
    print(f"✓ Connection test successful!")
    
    # Connect to device
    print("\n4. Connecting to Roku device...")
    if not client.connect():
        print("✗ Failed to establish connection")
        return
    
    print("✓ Connected successfully!")
    
    # Create capture session
    print("\n5. Creating capture session...")
    session = session_mgr.create_session(
        host=ROKU_IP,
        port=PORT,
        description="Example capture session"
    )
    
    print(f"✓ Session created: {session['session_id']}")
    
    # Get log file path
    log_file = session_mgr.get_session_log_path(session)
    print(f"  Log file: {log_file}")
    
    # Define callback for processing logs in real-time
    def log_callback(line: str):
        """Process each log line as it's captured."""
        # Example: Print errors in red
        if "ERROR" in line or "CRITICAL" in line:
            print(f"⚠️  {line}")
    
    # Capture logs
    print("\n6. Starting log capture...")
    print("   Press Ctrl+C to stop\n")
    
    try:
        # Capture for 60 seconds or until Ctrl+C
        client.capture_logs(
            output_file=log_file,
            callback=log_callback,
            max_duration=60  # Remove this to capture indefinitely
        )
    except KeyboardInterrupt:
        print("\n\nCapture stopped by user")
    
    # End session
    print("\n7. Ending session...")
    session_mgr.end_session(session)
    
    # Disconnect
    print("8. Disconnecting...")
    client.disconnect()
    
    print("\n" + "=" * 60)
    print("Capture complete!")
    print("=" * 60)
    print(f"\nLogs saved to: {log_file}")
    print(f"Session ID: {session['session_id']}")
    
    # Show how to list sessions
    print("\n" + "-" * 60)
    print("All sessions:")
    print("-" * 60)
    for s in session_mgr.list_sessions():
        print(f"  {s['session_id']}: {s['host']} ({s['status']})")


if __name__ == "__main__":
    main()

