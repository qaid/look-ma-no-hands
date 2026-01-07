# WhisperDictation

A macOS dictation app that uses local AI for transcription and smart formatting. Speak anywhere, get perfectly formatted text.

## Features

- **System-wide dictation**: Works in any app, any text field
- **Caps Lock trigger**: Press Caps Lock to start/stop recording
- **Local transcription**: Uses Whisper AI model, runs on your Mac
- **Smart formatting**: AI automatically formats your text appropriately
- **100% private**: No cloud services, all processing happens locally

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon Mac recommended (Intel Macs supported but slower)
- 8GB RAM minimum, 16GB recommended
- [Ollama](https://ollama.ai) installed for smart formatting

## Installation

### 1. Install Ollama

Download and install Ollama from [ollama.ai](https://ollama.ai).

Then install a formatting model:

```bash
ollama pull llama3.2:3b
```

### 2. Build WhisperDictation

```bash
# Clone the repository
git clone <repository-url>
cd WhisperDictation

# Build the app
swift build -c release

# Run the app
.build/release/WhisperDictation
```

### 3. Grant Permissions

On first launch, you'll be asked to grant:

1. **Microphone access**: Required to capture your voice
2. **Accessibility access**: Required to insert text into apps

## Usage

1. Launch WhisperDictation (it will appear in your menu bar)
2. Click on any text field in any application
3. Press **Caps Lock** to start recording
4. Speak your text
5. Press **Caps Lock** again to stop
6. Your formatted text will be inserted

## Examples

### Email Dictation

**You say**:
> "hey john hope you're doing well wanted to follow up on our meeting yesterday let me know if you have time to chat this week thanks"

**You get**:
> Hey John,
>
> Hope you're doing well. Wanted to follow up on our meeting yesterday.
>
> Let me know if you have time to chat this week.
>
> Thanks

### Quick Note

**You say**:
> "remember to buy milk eggs bread and pick up dry cleaning tomorrow"

**You get**:
> Remember to buy: milk, eggs, bread. Pick up dry cleaning tomorrow.

## Settings

Click the menu bar icon and select "Settings" to configure:

- **Trigger key**: Change from Caps Lock to another key
- **Whisper model**: Choose accuracy vs. speed
- **Ollama model**: Choose formatting quality
- **Visual indicator**: Customize recording indicator

## Troubleshooting

### Caps Lock not working?

If Caps Lock doesn't trigger recording, the app will fall back to the Right Option key. You can also configure a different key in Settings.

### Ollama not detected?

Make sure Ollama is running:

```bash
ollama serve
```

If Ollama isn't available, the app will still work but insert raw (unformatted) text.

### Text not inserting?

Some applications have restricted text input. If text doesn't appear, the app will copy it to your clipboard instead. Just press Cmd+V to paste.

## Privacy

WhisperDictation processes everything locally:

- Audio is processed by Whisper on your Mac
- Formatting is done by Ollama on your Mac
- No data is sent to any cloud service
- No internet connection required after initial setup

## Development

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for technical details.

### Building from Source

```bash
swift build          # Debug build
swift build -c release   # Release build
swift test           # Run tests
```

## License

[To be determined]

## Acknowledgments

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for local transcription
- [Ollama](https://ollama.ai) for local LLM inference
