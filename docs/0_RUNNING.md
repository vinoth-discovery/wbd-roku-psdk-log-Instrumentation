# How to Run the Tool

## Quick Start (New Terminal)

Every time you open a **new terminal**, you need to activate the virtual environment first.

### Manual Activation (For Advanced Commands)

```bash
# Navigate to project directory
cd "/Users/vimanoha/Library/CloudStorage/OneDrive-WarnerBros.Discovery/Git/AI & Automation/wbd-roku-psdk-log-instrument"

# Activate virtual environment
source venv/bin/activate

# Now you can use the command
roku-log-instrument --help
```

### The Easy Way: Use connect_telnet.sh (Recommended) ⭐

**No activation needed!** The script handles it automatically:

```bash
./scripts/connect_telnet.sh 192.168.50.81
```

This automatically activates the venv, connects to telnet, and captures logs!

### Advanced: One-Line Command

```bash
# Run command without permanent activation
source "/Users/vimanoha/Library/CloudStorage/OneDrive-WarnerBros.Discovery/Git/AI & Automation/wbd-roku-psdk-log-instrument/venv/bin/activate" && roku-log-instrument telnet test 192.168.50.81
```

## How to Know if Virtual Environment is Active

When the virtual environment is active, you'll see `(venv)` at the beginning of your terminal prompt:

```bash
# Not activated
user@computer ~ %

# Activated ✓
(venv) user@computer ~ %
```

## Common Commands

Once virtual environment is activated:

```bash
# Test connection
roku-log-instrument telnet test 192.168.50.81

# Capture logs
roku-log-instrument telnet capture 192.168.50.81

# List sessions
roku-log-instrument telnet sessions

# Get help
roku-log-instrument --help
```

## Creating an Alias (Optional)

To make it easier, you can create a shell alias:

### For zsh (macOS default):

Add to `~/.zshrc`:
```bash
alias roku-log='source "/Users/vimanoha/Library/CloudStorage/OneDrive-WarnerBros.Discovery/Git/AI & Automation/wbd-roku-psdk-log-instrument/venv/bin/activate" && roku-log-instrument'
```

Then reload:
```bash
source ~/.zshrc
```

Now you can use:
```bash
roku-log telnet test 192.168.50.81
```

### For bash:

Add to `~/.bashrc` or `~/.bash_profile`:
```bash
alias roku-log='source "/Users/vimanoha/Library/CloudStorage/OneDrive-WarnerBros.Discovery/Git/AI & Automation/wbd-roku-psdk-log-instrument/venv/bin/activate" && roku-log-instrument'
```

## Troubleshooting

### "command not found" Error

**Problem:**
```
zsh: command not found: roku-log-instrument
```

**Solution:**
Activate the virtual environment first:
```bash
cd "/Users/vimanoha/Library/CloudStorage/OneDrive-WarnerBros.Discovery/Git/AI & Automation/wbd-roku-psdk-log-instrument"
source venv/bin/activate
```

### Check Virtual Environment Status

```bash
# See which Python is being used
which python

# Should show:
# /Users/vimanoha/.../wbd-roku-psdk-log-instrument/venv/bin/python

# If it shows system Python, venv is not activated
```

### Deactivate Virtual Environment

When you're done:
```bash
deactivate
```

## Install System-Wide (Advanced)

If you want to use the command without activating the venv every time:

```bash
# Install to user directory
pip install --user -e "/Users/vimanoha/Library/CloudStorage/OneDrive-WarnerBros.Discovery/Git/AI & Automation/wbd-roku-psdk-log-instrument"
```

**Note:** This may require adding `~/.local/bin` to your PATH.

## Quick Reference Card

```bash
# 1. Navigate to project
cd "/Users/vimanoha/Library/CloudStorage/OneDrive-WarnerBros.Discovery/Git/AI & Automation/wbd-roku-psdk-log-instrument"

# 2. Activate venv
source venv/bin/activate

# 3. Run commands
roku-log-instrument telnet test 192.168.50.81

# 4. When done
deactivate
```

## Related Documentation

- **Next: [1_QUICKSTART.md](1_QUICKSTART.md)** - Quick start guide ⭐
- **[2_SETUP.md](2_SETUP.md)** - Setup instructions
- **[3_TELNET_USAGE.md](3_TELNET_USAGE.md)** - Telnet usage guide
- **[README.md](README.md)** - Documentation index

