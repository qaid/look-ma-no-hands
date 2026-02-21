import Foundation
import SwiftUI

/// Status of an in-flight meeting recording
enum MeetingStatus: Equatable {
    case ready
    case missingModel
    case missingPermissions
    case recording
    case processing
    case completed

    var displayText: String {
        switch self {
        case .ready: return "Ready"
        case .missingModel: return "Model Required"
        case .missingPermissions: return "Permissions Required"
        case .recording: return "Recording"
        case .processing: return "Processing"
        case .completed: return "Completed"
        }
    }

    var badgeColor: Color {
        switch self {
        case .ready: return .green
        case .missingModel, .missingPermissions: return .orange
        case .recording: return .red
        case .processing: return .blue
        case .completed: return .purple
        }
    }
}

/// Represents a single recording session within a meeting
struct RecordingSession: Identifiable {
    let id = UUID()
    let startTime: Date
    var endTime: Date?
    var duration: TimeInterval {
        guard let end = endTime else { return 0 }
        return end.timeIntervalSince(startTime)
    }
    var segmentRange: Range<Int>
}

/// In-flight recording state for the Record tab
/// Does NOT own persistence — that lives in MeetingStore
@Observable
class LiveMeetingState {
    var status: MeetingStatus = .ready
    var isRecording = false
    var isPaused = false
    var currentTranscript = ""
    var segments: [TranscriptSegment] = []
    var recordingSessions: [RecordingSession] = []
    var selectedSessionIndex: Int? = nil
    var structuredNotes: String?
    var isAnalyzing = false
    var statusMessage = "Ready to start"
    var elapsedTime: TimeInterval = 0
    var sessionStartDate: Date?
    var frequencyBands: [Float] = Array(repeating: 0.0, count: 40)
    var isActive = true

    // Streaming progress
    var generationProgress: Double = 0.0
    var estimatedTotalChars: Int = 0
    var receivedChars: Int = 0
    var isStreaming: Bool = false
    var streamedNotesPreview: String = ""

    var meetingTitle: String {
        if let date = sessionStartDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy h:mm a"
            return "Meeting - \(formatter.string(from: date))"
        }
        return "Meeting Recording"
    }

    var canRecord: Bool {
        status != .missingModel && status != .missingPermissions
    }

    func updateFrequencyBands(_ newBands: [Float]) {
        guard frequencyBands.count == newBands.count else {
            frequencyBands = newBands
            return
        }
        var smoothed: [Float] = []
        for i in 0..<newBands.count {
            smoothed.append(frequencyBands[i] * 0.7 + newBands[i] * 0.3)
        }
        frequencyBands = smoothed
    }
}
