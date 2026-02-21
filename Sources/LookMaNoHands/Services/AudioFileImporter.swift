import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// Imports external audio files and transcribes them via WhisperService
/// Uses AVAssetReader to decode directly to 16kHz mono Linear PCM in 30-second streaming chunks
@available(macOS 13.0, *)
class AudioFileImporter {

    // MARK: - Constants

    private let chunkSamples = 16000 * 30  // 30 seconds at 16kHz

    // MARK: - Public API

    /// Supported audio file types for NSOpenPanel
    static var supportedTypes: [UTType] {
        [
            .wav,
            .aiff,
            .mp3,
            .mpeg4Audio,
            UTType("com.apple.m4a-audio") ?? .mpeg4Audio,
        ]
    }

    /// Transcribe an audio file, yielding progress updates via callback
    /// - Parameters:
    ///   - url: URL of the audio file to transcribe
    ///   - whisperService: WhisperService instance (single-instance, non-reentrant — caller must guard)
    ///   - onProgress: Called with (fractionComplete 0–1, partialTranscript) after each chunk
    /// - Returns: Array of transcript segments covering the full file
    func transcribe(
        url: URL,
        whisperService: WhisperService,
        onProgress: @escaping (Double, String) async -> Void
    ) async throws -> [TranscriptSegment] {
        let asset = AVURLAsset(url: url)

        // Get total duration for progress calculation
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            throw ImportError.cannotReadAsset(error.localizedDescription)
        }
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 0 else { throw ImportError.emptyFile }

        // Build AVAssetReader requesting 16kHz mono Linear PCM
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ImportError.noAudioTrack
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw ImportError.cannotReadAsset(error.localizedDescription)
        }

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()

        var segments: [TranscriptSegment] = []
        var chunkBuffer: [Float] = []
        chunkBuffer.reserveCapacity(chunkSamples)
        var chunkStartTime: Double = 0
        var totalSamplesRead: Double = 0

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            let newSamples = extractSamples(from: sampleBuffer)
            chunkBuffer.append(contentsOf: newSamples)
            totalSamplesRead += Double(newSamples.count)

            // Process full 30-second chunks
            while chunkBuffer.count >= chunkSamples {
                let chunk = Array(chunkBuffer.prefix(chunkSamples))
                chunkBuffer.removeFirst(chunkSamples)

                let chunkText = try await whisperService.transcribe(samples: chunk, initialPrompt: nil)
                let chunkEndTime = chunkStartTime + 30.0

                if !chunkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let segment = TranscriptSegment(
                        text: chunkText.trimmingCharacters(in: .whitespacesAndNewlines),
                        startTime: chunkStartTime,
                        endTime: chunkEndTime,
                        timestamp: Date()
                    )
                    segments.append(segment)
                }

                let progress = min(chunkEndTime / totalSeconds, 1.0)
                await onProgress(progress, chunkText)
                chunkStartTime = chunkEndTime
            }
        }

        // Process any remaining samples
        if !chunkBuffer.isEmpty {
            let chunkText = try await whisperService.transcribe(samples: chunkBuffer, initialPrompt: nil)
            if !chunkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let segment = TranscriptSegment(
                    text: chunkText.trimmingCharacters(in: .whitespacesAndNewlines),
                    startTime: chunkStartTime,
                    endTime: totalSeconds,
                    timestamp: Date()
                )
                segments.append(segment)
            }
            await onProgress(1.0, chunkText)
        }

        if reader.status == .failed {
            throw ImportError.cannotReadAsset(reader.error?.localizedDescription ?? "Unknown read error")
        }

        return segments
    }

    // MARK: - Private Helpers

    private func extractSamples(from sampleBuffer: CMSampleBuffer) -> [Float] {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return [] }

        var length = 0
        var dataPointer: UnsafeMutablePointer<CChar>? = nil
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let pointer = dataPointer, length > 0 else { return [] }

        let sampleCount = length / MemoryLayout<Float>.size
        let samples = Array(UnsafeBufferPointer(
            start: UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self),
            count: sampleCount
        ))
        return samples
    }
}

// MARK: - Errors

enum ImportError: LocalizedError {
    case cannotReadAsset(String)
    case noAudioTrack
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .cannotReadAsset(let msg): return "Cannot read audio file: \(msg)"
        case .noAudioTrack: return "File contains no audio track"
        case .emptyFile: return "Audio file has zero duration"
        }
    }
}
