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
