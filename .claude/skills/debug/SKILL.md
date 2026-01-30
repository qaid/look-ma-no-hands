# Debug

Run the app directly from the build directory with console output visible.

This shows real-time print statements and crash information in the terminal.

## Instructions

First, kill any running instances, then run from the build directory:

```bash
killall "Look Ma No Hands" 2>/dev/null || killall LookMaNoHands 2>/dev/null || true
swift build -c release && .build/release/LookMaNoHands
```

Note: The app will run in the foreground. Press Ctrl+C to stop it.

Watch for and report any errors, warnings, or debug output.
