# Whisper Model Directory

Place your Whisper model files here.

## Downloading Models

You can download models from the whisper.cpp repository:
https://huggingface.co/ggerganov/whisper.cpp/tree/main

Recommended model for starting: `ggml-base.bin`

## Model Sizes

| Model | Filename | Size |
|-------|----------|------|
| tiny | ggml-tiny.bin | 75 MB |
| base | ggml-base.bin | 142 MB |
| small | ggml-small.bin | 466 MB |
| medium | ggml-medium.bin | 1.5 GB |
| large | ggml-large.bin | 2.9 GB |

## Download Commands

```bash
# Download base model (recommended)
curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin" -o ggml-base.bin

# Download tiny model (for testing)
curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin" -o ggml-tiny.bin
```
