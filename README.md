# Look Ma No Hands

Fast, local voice dictation for macOS. Press Caps Lock, speak, and get perfectly formatted text—instantly.

## ✨ Features

- **Lightning Fast**: ~1 second transcription with Core ML acceleration (8-15x faster than competitors)
- **System-wide**: Works in any app, any text field
- **Multiple Triggers**:
  - Caps Lock toggle (press once to start, again to stop)
  - Menu bar control (Start/Stop Recording)
- **100% Local**: Everything runs on your Mac, no cloud, no internet required
- **Smart formatting**: Automatic capitalization, punctuation, and cleanup
- **Privacy first**: Your voice never leaves your computer
- **Native macOS**:
  - Beautiful floating recording indicator with pulsing animation
  - Menu bar app with status icon that changes during recording
  - Settings window for permission management
  - Custom app icon
- **Core ML Optimized**: Utilizes Apple Neural Engine for maximum performance
- **Visual Feedback**: Recording indicator shows real-time recording status

## 🚀 Quick Start

### 1. Install Dependencies

```bash
# Clone the repository
git clone https://github.com/qaid/lookmanohands.git
cd lookmanohands

# Build
swift build -c release
```

### 2. Download Whisper Model

**Recommended**: Use the tiny model with Core ML for best speed:

```bash
cd ~/.whisper/models

# Download tiny model (75 MB)
curl -L -O https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin

# Download Core ML acceleration (14 MB) - 5-10x faster!
curl -L -O https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-encoder.mlmodelc.zip
unzip ggml-tiny-encoder.mlmodelc.zip
rm ggml-tiny-encoder.mlmodelc.zip
```

Alternatively, Look Ma No Hands can download models for you on first launch.

### 3. Run

```bash
.build/release/LookMaNoHands
```

### 4. Grant Permissions

On first launch, grant:
1. **Microphone access**: To capture your voice
2. **Accessibility access**: To insert text anywhere

## 🎯 Usage

### Recording via Caps Lock
1. Click any text field in any app
2. Press **Caps Lock** to start recording (floating indicator appears)
3. Speak naturally
4. Press **Caps Lock** again to stop
5. Formatted text appears instantly!

### Recording via Menu Bar
1. Click the **Look Ma No Hands** menu bar icon
2. Select **Start Recording**
3. Speak naturally
4. Click the menu bar icon again and select **Stop Recording**

### Settings Window
Access via menu bar → **Settings** to:
- **Permissions Tab**: Check microphone and accessibility permissions status
- **Grant Permissions**: Quick buttons to request required permissions
- **About Tab**: View app version and information

The menu bar icon changes when recording is active, and the menu item toggles between "Start Recording" and "Stop Recording".

## ⚡ Performance

| Model | Size | Speed (16s audio) | Accuracy | Recommended |
|-------|------|-------------------|----------|-------------|
| **tiny** | 75 MB | **~1s** (Core ML) | Good for dictation | ✅ **Yes** |
| base | 142 MB | ~2-3s (Core ML) | Better accuracy | For longer transcriptions |
| small | 466 MB | ~5-7s (Core ML) | High accuracy | Complex terminology |

**With Core ML**: 8-15x faster on Apple Silicon!
**Without Core ML**: Falls back to CPU (still works, just slower)

See [PERFORMANCE.md](PERFORMANCE.md) for optimization details.

## 🛠️ Requirements

- **macOS 14+** (Sonoma or later)
- **Apple Silicon** recommended (Intel Macs supported but slower)
- **~200 MB disk space** for tiny model + Core ML

## 📝 How It Works

1. **Audio Capture**: AVFoundation records high-quality 16kHz mono audio
2. **Transcription**: Whisper.cpp with Core ML converts speech to text
3. **Formatting**: Rule-based system adds capitalization and punctuation
4. **Insertion**: Accessibility API pastes text directly into focused field

All processing happens on your Mac in under 1 second!

## 🔧 Configuration

Click the menu bar icon to:
- Download different Whisper models
- View permissions status
- Quit the app

## 🐛 Troubleshooting

**Core ML not loading?**
- Check console for `whisper_init_state: Core ML model loaded`
- Ensure `.mlmodelc` file is in `~/.whisper/models/`
- Requires macOS 12+ and Apple Silicon for best performance

**Text not inserting?**
- Some apps restrict accessibility—Look Ma No Hands falls back to clipboard
- Check Accessibility permissions in System Settings

**Caps Lock not working?**
- The app monitors Caps Lock presses (doesn't change actual Caps Lock state)
- Ensure Accessibility permission is granted

## 📚 Project Structure

```
LookMaNoHands/
├── Sources/LookMaNoHands/
│   ├── App/              # Main app and menu bar
│   ├── Services/         # Core functionality
│   │   ├── AudioRecorder.swift       # 16kHz audio capture + normalization
│   │   ├── WhisperService.swift      # Whisper.cpp integration + Core ML
│   │   ├── TextFormatter.swift       # Rule-based text cleanup
│   │   ├── TextInsertionService.swift # Accessibility API
│   │   └── KeyboardMonitor.swift     # Caps Lock detection
│   ├── Views/            # SwiftUI + AppKit UI
│   └── Models/           # State management
├── docs/                 # Architecture documentation
└── PERFORMANCE.md        # Optimization guide
```

## 🔒 Privacy

Look Ma No Hands is 100% local:
- ✅ Audio never sent to cloud
- ✅ No telemetry or analytics
- ✅ No internet required (after model download)
- ✅ Open source—verify for yourself

## 🚧 Known Limitations

- Caps Lock monitoring requires Accessibility permission
- Some sandboxed apps may not allow direct text insertion
- Best accuracy with clear audio in quiet environments
- English-only (Whisper supports other languages, but not tested)

## 📖 Advanced Usage

### Using Different Models

Download other models from [Hugging Face](https://huggingface.co/ggerganov/whisper.cpp/tree/main):

```bash
cd ~/.whisper/models
curl -L -O https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
curl -L -O https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-encoder.mlmodelc.zip
unzip ggml-base-encoder.mlmodelc.zip
```

WhisperTalk automatically uses the best model it finds (prefers tiny → base → small).

### Building for Release

```bash
swift build -c release
cp .build/release/WhisperTalk ~/Applications/
```

## 🤝 Contributing

Contributions welcome! Please read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) first.

## 📄 License

MIT License - see [LICENSE](LICENSE) file.

## 🙏 Acknowledgments

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) - Fast Whisper inference
- [SwiftWhisper](https://github.com/exPHAT/SwiftWhisper) - Swift bindings
- Inspired by macOS built-in dictation, but faster and fully local

---

**Made with ❤️ for productive macOS users who value privacy and speed.**
