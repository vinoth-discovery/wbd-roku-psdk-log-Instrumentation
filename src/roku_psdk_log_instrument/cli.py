"""
Command-line interface for the Roku PSDK Log Instrumentation tool.
"""

import click
import subprocess
import os
from pathlib import Path
from typing import Optional
from roku_psdk_log_instrument.telnet.client import RokuTelnetClient
from roku_psdk_log_instrument.telnet.session_manager import SessionManager


def launch_psdk_monitor(log_file_path: str) -> Optional[subprocess.Popen]:
    """
    Launch a new terminal window to monitor PSDK events.
    
    Args:
        log_file_path: Path to the log file to monitor
        
    Returns:
        Subprocess object if successful, None otherwise
    """
    try:
        # Try multiple paths to find the monitor script
        possible_paths = [
            # Development mode: relative to source file
            Path(__file__).parent.parent.parent.parent / "scripts" / "monitor_psdk_events.sh",
            # From current working directory
            Path.cwd() / "scripts" / "monitor_psdk_events.sh",
            # User's home directory (if running from there)
            Path.home() / "Library" / "CloudStorage" / "OneDrive-WarnerBros.Discovery" / "Git" / "AI & Automation" / "wbd-roku-psdk-log-instrument" / "scripts" / "monitor_psdk_events.sh"
        ]
        
        monitor_script = None
        for path in possible_paths:
            if path.exists():
                monitor_script = path
                break
        
        if not monitor_script:
            click.echo(f"⚠️  Warning: Monitor script not found. Tried:")
            for path in possible_paths:
                click.echo(f"  - {path}")
            return None
        
        # Launch new Terminal window on macOS with the monitor script
        applescript = f'''
        tell application "Terminal"
            do script "'{monitor_script}' '{log_file_path}'"
            activate
        end tell
        '''
        
        # Run AppleScript and capture output for debugging
        result = subprocess.run(
            ['osascript', '-e', applescript],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            click.echo(f"⚠️  AppleScript error: {result.stderr}")
            return None
        
        return subprocess.Popen(['sleep', '0'])  # Return dummy process
        
    except Exception as e:
        click.echo(f"⚠️  Could not launch PSDK monitor: {e}")
        import traceback
        traceback.print_exc()
        return None


@click.group()
@click.version_option(version="0.1.0")
def main() -> None:
    """WBD Roku PSDK Log Instrumentation & Validation Tool."""
    pass


@main.group()
def telnet() -> None:
    """Telnet connection commands for Roku device log capture."""
    pass


@telnet.command()
@click.argument("host")
@click.option("--port", "-p", default=8085, help="Telnet port (default: 8085)")
@click.option("--duration", "-d", type=int, help="Maximum capture duration in seconds")
@click.option("--description", help="Session description")
@click.option("--show/--no-show", default=True, help="Show logs in terminal while capturing (default: show)")
def capture(host: str, port: int, duration: Optional[int], description: Optional[str], show: bool) -> None:
    """
    Capture logs from Roku device via telnet.
    
    HOST is the IP address or hostname of the Roku device.
    
    By default, logs are displayed in the terminal AND saved to .temp folder.
    Use --no-show to only save without displaying.
    """
    session_manager = SessionManager()
    client = RokuTelnetClient(host, port)
    session = None
    interrupted = False
    
    try:
        # Test connection first
        if not client.test_connection(host, port):
            click.echo(f"\n✗ Cannot connect to {host}:{port}")
            click.echo("\nPlease check:")
            click.echo("  1. Roku device IP address is correct")
            click.echo("  2. Device is powered on and connected to network")
            click.echo("  3. Telnet port 8085 is accessible")
            
            if click.confirm("\nWould you like to retry with a different host?", default=True):
                new_host = click.prompt("Enter Roku device IP address")
                host = new_host
                
                if not client.test_connection(host, port):
                    click.echo(f"✗ Still cannot connect to {host}:{port}")
                    return
        
        # Check if already connected
        if client.is_connected():
            click.echo(f"Already connected to {host}:{port}")
        else:
            # Connect
            if not client.connect():
                click.echo("\n✗ Failed to establish telnet connection")
                return
        
        # Create session
        session = session_manager.create_session(host, port, description)
        log_file = session_manager.get_session_log_path(session)
        
        click.echo(f"\n✓ Session created: {session['session_id']}")
        click.echo(f"✓ Telnet connection established")
        click.echo(f"  Saving logs to: {log_file}")
        if show:
            click.echo("  Displaying logs in terminal: Yes")
        click.echo("\nPress Ctrl+C to stop capturing...\n")
        
        # Create callback to display logs if show is enabled
        def display_callback(line: str):
            if show:
                # Highlight PSDK logs in yellow, everything else in white
                if 'PSDK::' in line:
                    click.echo(click.style(line, fg='yellow'))
                else:
                    click.echo(line)
        
        # Capture logs with callback
        client.capture_logs(log_file, callback=display_callback, max_duration=duration)
        
        # End session
        session_manager.end_session(session)
        
    except KeyboardInterrupt:
        interrupted = True
        click.echo("\n\n" + "─" * 55)
        click.echo("Capture stopped by user")
        click.echo("─" * 55 + "\n")
        
        # End session first
        if session:
            session_manager.end_session(session)
    
    finally:
        client.disconnect()
        
        # Prompt for deletion if interrupted and session exists
        if interrupted and session:
            if click.confirm("\n💾 Would you like to keep the captured logs?", default=True):
                click.echo(f"✓ Logs saved in: {session.get('directory', '.temp/' + session['session_id'])}")
            else:
                click.echo("\n🗑️  Deleting session logs...")
                session_manager.delete_session(session)
                click.echo("✓ Logs deleted")


@telnet.command()
@click.argument("host")
@click.option("--port", "-p", default=8085, help="Telnet port (default: 8085)")
@click.option("--timeout", "-t", default=5, help="Connection timeout in seconds")
def test(host: str, port: int, timeout: int) -> None:
    """
    Test telnet connection to Roku device.
    
    HOST is the IP address or hostname of the Roku device.
    """
    click.echo(f"Testing connection to {host}:{port}...")
    
    if RokuTelnetClient.test_connection(host, port, timeout):
        click.echo(f"✓ Connection successful!")
    else:
        click.echo(f"✗ Connection failed")
        click.echo("\nPlease check:")
        click.echo("  1. Roku device IP address is correct")
        click.echo("  2. Device is powered on and connected to network")
        click.echo("  3. Telnet port 8085 is accessible")


@telnet.command()
def sessions() -> None:
    """List all capture sessions."""
    session_manager = SessionManager()
    sessions = session_manager.list_sessions()
    
    if not sessions:
        click.echo("No capture sessions found.")
        return
    
    click.echo(f"\nFound {len(sessions)} session(s):\n")
    
    for session in sessions:
        status_symbol = "●" if session.get("status") == "active" else "○"
        click.echo(f"{status_symbol} {session['session_id']}")
        click.echo(f"  Host: {session['host']}:{session['port']}")
        click.echo(f"  Started: {session['start_time']}")
        
        if session.get("end_time"):
            click.echo(f"  Ended: {session['end_time']}")
        
        click.echo(f"  Status: {session.get('status', 'unknown')}")
        click.echo(f"  Lines: {session.get('line_count', 0)}")
        click.echo()


@telnet.command()
@click.option("--days", "-d", default=7, help="Clean sessions older than N days")
@click.option("--yes", "-y", is_flag=True, help="Skip confirmation")
def cleanup(days: int, yes: bool) -> None:
    """Clean up old capture sessions."""
    session_manager = SessionManager()
    
    sessions = session_manager.list_sessions()
    if not sessions:
        click.echo("No sessions to clean up.")
        return
    
    click.echo(f"This will remove sessions older than {days} days.")
    
    if not yes:
        if not click.confirm("Continue?", default=True):
            click.echo("Cleanup cancelled.")
            return
    
    cleaned = session_manager.cleanup_old_sessions(days)
    click.echo(f"✓ Cleaned up {cleaned} session(s)")


@main.command()
@click.argument("input_file", type=click.Path(exists=True))
@click.argument("output_file", type=click.Path())
@click.option("--format", "-f", default="json", help="Output format (json, csv, text)")
def instrument(input_file: str, output_file: str, format: str) -> None:
    """Instrument a log file with metadata and tracking information."""
    click.echo(f"Instrumenting {input_file} -> {output_file} (format: {format})")
    # TODO: Implement instrumentation logic
    click.echo("✓ Instrumentation complete")


@main.command()
@click.argument("log_file", type=click.Path(exists=True))
@click.option("--schema", "-s", type=click.Path(exists=True), help="Validation schema file")
@click.option("--strict", is_flag=True, help="Enable strict validation mode")
def validate(log_file: str, schema: Optional[str], strict: bool) -> None:
    """Validate a log file against expected patterns and schemas."""
    click.echo(f"Validating {log_file}")
    if schema:
        click.echo(f"Using schema: {schema}")
    if strict:
        click.echo("Strict mode enabled")
    # TODO: Implement validation logic
    click.echo("✓ Validation complete")


@main.command()
@click.argument("log_file", type=click.Path(exists=True))
@click.option("--output", "-o", type=click.Path(), help="Output file for parsed results")
def parse(log_file: str, output: Optional[str]) -> None:
    """Parse a Roku PSDK log file."""
    click.echo(f"Parsing {log_file}")
    # TODO: Implement parsing logic
    if output:
        click.echo(f"Results saved to {output}")
    click.echo("✓ Parsing complete")


@click.command()
@click.argument("host")
@click.option("--duration", "-d", type=int, help="Maximum capture duration in seconds")
@click.option("--description", help="Session description")
@click.option("--port", "-p", default=8085, help="Telnet port (default: 8085)")
@click.option("--monitor/--no-monitor", default=True, help="Launch PSDK event monitor in separate terminal (default: on)")
@click.version_option(version="0.1.0")
def live_main(host: str, duration: Optional[int], description: Optional[str], port: int, monitor: bool) -> None:
    """
    PSDK Instrument - Live Roku log capture and viewer.
    
    Connects to Roku device, displays logs in real-time, and saves to .temp/ folder.
    
    HOST is the IP address of your Roku device (e.g., 192.168.50.81)
    
    Examples:
        psdk-instrument 192.168.50.81
        psdk-instrument 192.168.50.81 --duration 300
        psdk-instrument 192.168.50.81 --description "Testing playback"
    """
    session_manager = SessionManager()
    client = RokuTelnetClient(host, port)
    session = None
    interrupted = False
    
    # Display banner
    click.echo("\n" + "═" * 55)
    click.echo("  PSDK Instrument - Roku Live Log Viewer")
    click.echo("═" * 55)
    click.echo(f"\n📡 Connecting to: {host}:{port}")
    click.echo(f"💾 Logs saved to: .temp/")
    click.echo(f"👁️  Live display: ENABLED")
    if monitor:
        click.echo(f"📊 PSDK Monitor: ENABLED (separate terminal)")
    click.echo("\nPress Ctrl+C to stop\n")
    click.echo("─" * 55 + "\n")
    
    try:
        # Test connection first
        if not client.test_connection(host, port):
            click.echo(f"\n✗ Cannot connect to {host}:{port}")
            click.echo("\nPlease check:")
            click.echo("  1. Roku device IP address is correct")
            click.echo("  2. Device is powered on and connected to network")
            click.echo("  3. Telnet port 8085 is accessible")
            
            if click.confirm("\nWould you like to retry with a different host?", default=True):
                new_host = click.prompt("Enter Roku device IP address")
                host = new_host
                
                if not client.test_connection(host, port):
                    click.echo(f"✗ Still cannot connect to {host}:{port}")
                    return
        
        # Connect
        if not client.connect():
            click.echo("\n✗ Failed to establish telnet connection")
            return
        
        # Create session
        session = session_manager.create_session(host, port, description)
        log_file = session_manager.get_session_log_path(session)
        
        click.echo(f"✓ Session: {session['session_id']}")
        click.echo(f"✓ Telnet connection established")
        click.echo(f"✓ Starting log capture...\n")
        
        # Launch PSDK event monitor in separate terminal AFTER connection is successful
        monitor_process = None
        monitor_launched = False
        
        # Display callback with color coding
        def display_callback(line: str):
            nonlocal monitor_launched, monitor_process
            
            # Launch monitor on first log line received (confirms connection is working)
            if not monitor_launched and monitor:
                click.echo("\n🚀 Launching PSDK Event Monitor...\n")
                monitor_process = launch_psdk_monitor(str(log_file))
                if monitor_process:
                    click.echo("✓ PSDK Monitor launched successfully\n")
                else:
                    click.echo("⚠️  Could not launch monitor (continuing without it)\n")
                monitor_launched = True
            
            # Highlight PSDK logs in yellow, everything else in white
            if 'PSDK::' in line:
                click.echo(click.style(line, fg='yellow'))
            else:
                click.echo(line)
        
        # Capture logs with live display
        client.capture_logs(log_file, callback=display_callback, max_duration=duration)
        
        # End session
        session_manager.end_session(session)
        
    except KeyboardInterrupt:
        interrupted = True
        click.echo("\n\n" + "─" * 55)
        click.echo("Capture stopped by user")
        click.echo("─" * 55 + "\n")
        
        # End session first
        if session:
            session_manager.end_session(session)
    
    finally:
        client.disconnect()
        
        # Prompt for deletion if interrupted and session exists
        if interrupted and session:
            if click.confirm("\n💾 Would you like to keep the captured logs?", default=True):
                click.echo(f"✓ Logs saved in: {session.get('directory', '.temp/' + session['session_id'])}")
            else:
                click.echo("\n🗑️  Deleting session logs...")
                session_manager.delete_session(session)
                click.echo("✓ Logs deleted")


if __name__ == "__main__":
    main()
