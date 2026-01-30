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
