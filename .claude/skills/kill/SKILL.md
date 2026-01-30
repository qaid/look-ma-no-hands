# Kill

Stop all running instances of Look Ma No Hands.

Use this before manual debugging or when the app becomes unresponsive.

## Instructions

Kill any running instances:

```bash
killall "Look Ma No Hands" 2>/dev/null || killall LookMaNoHands 2>/dev/null || echo "No running instances found"
```

Confirm whether the app was stopped or wasn't running.
