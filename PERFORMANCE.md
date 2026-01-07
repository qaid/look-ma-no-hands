# Performance Optimization Guide

This guide explains how to achieve the fastest possible transcription speeds with WhisperTalk.

## Quick Start: Download Tiny Model with Core ML

For the best dictation experience (fastest speed with good accuracy), download the **tiny** model with Core ML acceleration:

```bash
cd ~/.whisper/models

# Download the tiny model (75 MB)
curl -L -O https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin

# Download Core ML version for GPU acceleration (recommended for Apple Silicon)
curl -L -O https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-encoder.mlmodelc.zip
unzip ggml-tiny-encoder.mlmodelc.zip
rm ggml-tiny-encoder.mlmodelc.zip
```

## Performance Comparison

| Model | Size | Speed (16s audio) | Use Case |
|-------|------|-------------------|----------|
| tiny | 75 MB | ~2-3s (CPU) / ~0.5-1s (Core ML) | ✅ **Dictation (Recommended)** |
| base | 142 MB | ~7-8s (CPU) / ~2-3s (Core ML) | Longer transcriptions |
| small | 466 MB | ~20-25s (CPU) / ~5-7s (Core ML) | High accuracy needed |

## How Core ML Helps

Core ML enables GPU acceleration on Apple Silicon Macs:
- **5-10x faster** transcription
- Uses Apple's Neural Engine
- Lower power consumption
- Seamless fallback to CPU if unavailable

## Verification

When you run WhisperTalk, look for this in the console:

```
✅ GOOD: Core ML loaded successfully
whisper_init_state: loaded Core ML model from '~/.whisper/models/ggml-tiny-encoder.mlmodelc'

❌ NOT OPTIMIZED: Core ML failed to load
whisper_init_state: failed to load Core ML model
```

If you see the failure message, Core ML isn't being used (CPU only).

## Troubleshooting

**Core ML model won't load:**
1. Ensure the `.mlmodelc` file is in the same directory as the `.bin` file
2. The filename must match exactly: `ggml-tiny-encoder.mlmodelc` (not `.zip`)
3. macOS 12+ required for Core ML support

**Still slow transcription:**
1. Check that you're using the `tiny` model (not `base` or larger)
2. Verify Core ML is loading (check console output)
3. Consider closing other GPU-intensive apps

## Download via App

WhisperTalk can download models for you:
1. Launch the app
2. Click the menu bar icon
3. You'll be prompted to download a model
4. Choose "Download Tiny Model (Recommended)"

The app will automatically download both the model and Core ML files.
