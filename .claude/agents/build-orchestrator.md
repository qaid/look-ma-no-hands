---
name: build-orchestrator
description: Build, deploy, and manage the Swift macOS app
model: haiku
triggers:
  - build
  - deploy
  - compile
  - run the app
  - launch the app
  - clean build
  - check logs
  - view logs
  - kill app
  - stop the app
  - debug the app
  - test the build
invocation_patterns:
  - "When user asks to build, compile, or deploy the Swift project"
  - "When user wants to run, launch, or test the macOS app"
  - "When user needs to view logs, debug issues, or check app status"
  - "When user wants to clean build artifacts or kill running instances"
  - "When user references the deploy script or build process"
---

# Build

Build the project without deploying.

Use this for quick compile checks during development.

## Instructions

Run the Swift build in release mode:

```bash
swift build -c release
```

Report any compilation errors or warnings clearly. If successful, confirm the build completed.

# Clean

Clean all build artifacts.

Use this to resolve build cache issues or free up disk space.

## Instructions

Clean the Swift package build directory:

```bash
swift package clean
rm -rf .build
```

Confirm the clean completed successfully.

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

# Deploy

Build, deploy, and launch Look Ma No Hands.

This is the primary development workflow that:
1. Builds the release binary with `swift build -c release`
2. Kills any running instances
3. Creates/updates the app bundle at ~/Applications/Look Ma No Hands.app
4. Code signs and registers with Launch Services
5. Launches the app

## Instructions

Run the deploy script:

```bash
./deploy.sh
```

If the build fails, report the error clearly. If it succeeds, confirm the app has launched.

# Kill

Stop all running instances of Look Ma No Hands.

Use this before manual debugging or when the app becomes unresponsive.

## Instructions

Kill any running instances:

```bash
killall "Look Ma No Hands" 2>/dev/null || killall LookMaNoHands 2>/dev/null || echo "No running instances found"
```

Confirm whether the app was stopped or wasn't running.

# Logs

View recent system logs for Look Ma No Hands.

Useful for debugging crashes, permission issues, and transcription problems.

## Instructions

Show logs from the last 5 minutes:

```bash
log show --predicate 'subsystem == "com.qaid.lookmanhands" OR process == "LookMaNoHands"' --last 5m --style compact
```

If no logs are found, try a broader search:

```bash
log show --predicate 'process == "LookMaNoHands"' --last 10m --style compact
```

Summarize any errors, warnings, or relevant messages found.

# Run

Launch the deployed Look Ma No Hands app.

This opens the existing app bundle without rebuilding.

## Instructions

Launch the app:

```bash
open ~/Applications/"Look Ma No Hands.app"
```

Confirm the app has launched. If it fails (app not found), suggest running `/deploy` first.
