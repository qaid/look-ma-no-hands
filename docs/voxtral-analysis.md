# Voxtral Realtime vs Whisper.cpp Analysis (Issue #109)

## Executive Summary

**Recommendation: Stay with whisper.cpp for now, monitor Voxtral ecosystem maturity**

While Voxtral Realtime offers impressive latency improvements, the lack of Swift/macOS integration tools makes it impractical for immediate adoption in Look Ma No Hands. Whisper.cpp remains the better choice due to mature Swift bindings, Core ML acceleration, and proven local deployment.

---

## Feature Comparison

| Feature | Whisper.cpp (Current) | Voxtral Realtime |
|---------|----------------------|------------------|
| **Latency** | Variable (depends on model size) | Sub-200ms (configurable) |
| **Model Size** | 75MB - 3.1GB (5 models) | 4B parameters (~2-4GB estimated) |
| **Accuracy** | Proven, industry standard | 1-2% WER @ 480ms, 4% WER @ 2.4s |
| **Swift Integration** | ✅ Native (SwiftWhisper) | ❌ No known Swift bindings |
| **macOS Acceleration** | ✅ Core ML support | ❓ Unknown |
| **License** | MIT | Apache 2.0 |
| **Languages** | 99 languages | 13 languages |
| **Local Deployment** | ✅ Fully local | ✅ Open weights available |
| **Speaker Diarization** | ❌ No | ✅ Yes |
| **Context Biasing** | ✅ initial_prompt | ✅ Up to 100 terms |
| **Maturity** | Mature ecosystem | Brand new (Feb 2026) |

---

## Detailed Analysis

### 1. Latency Performance

**Voxtral Realtime Advantage:**
- Sub-200ms delay configurable
- ~3x faster than comparable solutions
- Streaming architecture designed for real-time use

**Current Whisper.cpp:**
- Base model with Core ML: typically 2-5 seconds for 5-second audio
- Real-time factor (RTF) varies: 0.5-2.0x depending on hardware
- Not optimized for streaming/real-time

**Impact on Look Ma No Hands:**
- Current latency is acceptable for dictation (users expect brief processing)
- Sub-200ms would feel nearly instant but may not be critical differentiator
- Meeting mode would benefit more from real-time streaming

### 2. Integration & Development Effort

**Whisper.cpp (Current):**
```swift
// Mature Swift integration via SwiftWhisper
.package(url: "https://github.com/exPHAT/SwiftWhisper.git", from: "1.0.0")

// Simple API
let whisper = Whisper(fromFileURL: modelURL, withParams: params)
let segments = try await whisper.transcribe(audioFrames: samples)
```

**Voxtral Realtime:**
- No Swift package available (as of Feb 2026)
- Would require either:
  1. REST API calls to Mistral's hosted service ($0.006/min) ❌ Breaks privacy-first promise
  2. Python bindings + inter-process communication ⚠️ Complex, fragile
  3. Wait for community Swift bindings ⏳ Unknown timeline
  4. Build custom Swift bindings ⚠️ Months of work, maintenance burden

**Verdict:** Significant integration barrier for Voxtral Realtime

### 3. Core ML Acceleration

**Whisper.cpp:**
- Mature Core ML encoder support for tiny, base, small models
- GPU acceleration on Apple Silicon
- Well-tested on macOS

**Voxtral Realtime:**
- No documentation about Core ML/Metal support
- Likely requires custom integration work
- Unknown performance on Apple Silicon

### 4. Model Size & Resource Usage

**Whisper.cpp:**
- Flexible: 75MB (tiny) to 3.1GB (large-v3)
- Users can choose based on accuracy/speed tradeoff
- Small models work well on older Macs

**Voxtral Realtime:**
- 4B parameters (~2-4GB estimated)
- Single model size, no tiny/base alternatives
- "Edge device operation" mentioned but specifics unclear

### 5. Language Support

**Whisper.cpp:**
- 99 languages supported
- English-optimized mode available

**Voxtral Realtime:**
- 13 languages only
- English included, but limited multilingual coverage

**Impact:** Not critical for current English-only focus, but limits future expansion

### 6. Additional Features

**Voxtral Realtime Advantages:**
- ✅ Built-in speaker diarization (valuable for meeting mode)
- ✅ Word-level timestamps (already in Whisper too)
- ✅ Optimized for 3-hour long audio

**Whisper.cpp Advantages:**
- ✅ Proven reliability across millions of deployments
- ✅ Active community, regular updates
- ✅ Extensive documentation and examples

---

## Risk Assessment

### Risks of Switching to Voxtral Realtime

1. **Integration Complexity** (HIGH)
   - No Swift bindings = weeks/months of custom work
   - Inter-process communication adds failure points
   - Debugging harder across language boundaries

2. **Ecosystem Immaturity** (MEDIUM)
   - Brand new model (Feb 2026)
   - Unknown macOS optimization status
   - Community tooling not yet developed

3. **Maintenance Burden** (MEDIUM)
   - Custom bindings require ongoing maintenance
   - Breaking changes in early releases
   - Less community support for troubleshooting

4. **Privacy Concerns** (LOW if self-hosted, HIGH if API)
   - API option breaks "100% local" promise
   - Self-hosted requires solving integration challenges

### Risks of Staying with Whisper.cpp

1. **Latency** (LOW)
   - Current 2-5s latency acceptable for dictation
   - Not critical for core use case

2. **Feature Gap** (LOW)
   - No built-in diarization (can add with other tools if needed)
   - Not a deal-breaker for v1

---

## Recommendations

### Immediate (Now)

**✅ KEEP whisper.cpp as primary transcription engine**

Reasons:
1. Mature Swift integration works well today
2. Core ML acceleration on Apple Silicon
3. Proven reliability and accuracy
4. Flexible model sizes
5. Privacy-first local processing

### Short-term (3-6 months)

**🔍 MONITOR Voxtral ecosystem development**

Watch for:
- Swift/macOS bindings emergence
- Community adoption and tooling
- Performance benchmarks on Apple Silicon
- Integration examples with native apps

### Long-term (6-12 months)

**🧪 EVALUATE Voxtral again IF:**
1. Swift Package Manager bindings available
2. Core ML/Metal acceleration confirmed
3. Proven track record of local deployment
4. Community reports successful macOS integration

**Potential hybrid approach:**
- Use whisper.cpp for quick dictation (proven, reliable)
- Evaluate Voxtral for meeting mode (benefits from diarization)
- A/B test if integration becomes feasible

---

## Implementation Notes

If Voxtral becomes viable in the future:

```swift
// Hypothetical integration approach (when bindings exist)
.package(url: "https://github.com/mistralai/swift-voxtral", from: "1.0.0")

// Would need similar API to Whisper
let voxtral = Voxtral(modelPath: modelPath, params: params)
let result = try await voxtral.transcribe(audioFrames: samples)
// result.transcription, result.speakers (diarization)
```

Until then, maintain current architecture with clear abstraction:

```swift
protocol TranscriptionService {
    func transcribe(samples: [Float]) async throws -> String
}

class WhisperTranscriptionService: TranscriptionService { /* current impl */ }
// class VoxtralTranscriptionService: TranscriptionService { /* future */ }
```

---

## References

- Voxtral Announcement: https://mistral.ai/news/voxtral-transcribe-2
- SwiftWhisper: https://github.com/exPHAT/SwiftWhisper
- Whisper.cpp: https://github.com/ggerganov/whisper.cpp
- Current Implementation: [WhisperService.swift](../Sources/LookMaNoHands/Services/WhisperService.swift)

---

## Conclusion

**Whisper.cpp remains the best choice for Look Ma No Hands** due to:
1. ✅ Excellent Swift integration (SwiftWhisper)
2. ✅ Core ML acceleration on Apple Silicon
3. ✅ Proven local-first architecture
4. ✅ Flexible model sizes (75MB - 3.1GB)
5. ✅ Mature ecosystem and documentation

**Voxtral Realtime is promising but premature** due to:
1. ❌ No Swift/macOS bindings available
2. ❌ Unknown Core ML/Metal support
3. ❌ Brand new (Feb 2026) with immature tooling
4. ❌ Would require significant custom integration work

**Revisit this decision in 6-12 months** when the Voxtral ecosystem matures and macOS integration becomes clearer.
