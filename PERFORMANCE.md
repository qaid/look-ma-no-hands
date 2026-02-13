# Performance Optimization Guide

This guide explains how to achieve the fastest possible transcription speeds with Look Ma No Hands using WhisperKit.

## Quick Start: WhisperKit with Core ML Acceleration

Look Ma No Hands uses **WhisperKit** (v1.2.0+) for optimal performance on Apple Silicon:

- **2.7x faster** transcription compared to previous whisper.cpp implementation
- **75% less energy** consumption thanks to native async/await and Core ML optimization
- **Automatic model management** — models download and optimize automatically in the Settings app
- **Apple Neural Engine** acceleration on all Apple Silicon Macs

### Fastest Setup

1. Launch the app
2. Go to **Settings → Models → Dictation**
3. Click **Download Tiny Model (Recommended)**
4. WhisperKit handles all optimization and Core ML setup automatically

## Performance Benchmarks

| Model | Size | Speed (WhisperKit with Core ML) | Use Case |
|-------|------|----------------------------------|----------|
| **tiny** | 75 MB | ~0.5-1s | ✅ **Dictation (Recommended)** |
| **base** | 142 MB | ~1-2s | Better accuracy for complex terminology |
| **small** | 466 MB | ~3-5s | High accuracy, technical terms |
| **medium** | 1.5 GB | ~7-10s | Highest accuracy, challenging audio |
| **large-v3-turbo** | 3.1 GB | ~8-12s | Maximum accuracy with optimized inference |

### Performance Improvement (v1.2.0 with WhisperKit)

**Before (whisper.cpp):**
- Tiny model: ~2-3s (CPU) / ~0.5-1s (Core ML)
- Energy consumption: Baseline

**After (WhisperKit, v1.2.0):**
- Tiny model: ~0.5-1s (with Apple Neural Engine optimization)
- Energy consumption: 75% less

## How WhisperKit Optimizes Performance

WhisperKit achieves these improvements through:
- **Native Swift async/await** for non-blocking transcription
- **Apple Neural Engine** acceleration on M-series chips
- **Streaming inference** — results arrive as speech is recognized
- **Core ML integration** — automatic optimization for your hardware
- **Memory efficiency** — optimized buffer management for long audio

## Model Selection

### For Dictation (Recommended)
Use the **tiny** model:
- 75 MB download
- <1 second transcription per audio chunk
- Good accuracy for clear speech
- Minimal CPU/power impact

### For Meeting Transcription
Choose based on your needs:
- **Tiny** if you just need a basic transcript
- **Base** for better accuracy with multiple speakers
- **Small** or **Medium** for technical discussions requiring high accuracy

## Verification

When you run Look Ma No Hands, check the console for WhisperKit initialization:

```
✅ WhisperKit model loaded successfully
✅ Core ML acceleration enabled for Apple Neural Engine
✅ Transcription ready
```

If you see warnings about Core ML, WhisperKit will automatically fall back to CPU (slower but still functional).

## Troubleshooting

**Slow transcription even with WhisperKit:**
1. Check that you've downloaded the **tiny** model, not a larger one
2. Verify Core ML is enabled — check console output during app startup
3. Close other apps using significant GPU resources
4. Restart the app (Core ML might need reinitialization)

**Model won't download:**
1. Ensure you have enough disk space (at least 1 GB free)
2. Check internet connection for the initial download
3. Go to **Settings → Models → Dictation** and retry

**Still having issues:**
Check the console logs:
```bash
log stream --predicate 'process == "LookMaNoHands"' --level debug
```

Look for messages about WhisperKit initialization and Core ML loading.
