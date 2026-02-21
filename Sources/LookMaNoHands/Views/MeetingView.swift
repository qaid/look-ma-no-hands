import SwiftUI
import UniformTypeIdentifiers

// MARK: - Typography & Color System
// Kept for backwards compatibility with any views that reference these extensions.

extension Font {
    static let meetingTitle = Font.system(size: 16, weight: .semibold)
    static let meetingBody = Font.system(size: 16, weight: .regular)
    static let meetingMetadata = Font.system(size: 14, weight: .regular)
    static let meetingCaption = Font.system(size: 13, weight: .regular)
    static let meetingTimestamp = Font.system(size: 13, weight: .medium, design: .monospaced)
}

extension Color {
    static let meetingPrimary = Color(nsColor: .labelColor)
    static let meetingSecondary = Color(nsColor: .secondaryLabelColor)
    static let meetingTertiary = Color(nsColor: .tertiaryLabelColor)
    static let meetingAccent = Color.accentColor
    static let meetingBackground = Color(nsColor: .textBackgroundColor)
    static let meetingChrome = Color(nsColor: .controlBackgroundColor)
}

// MARK: - Tab Enum

enum MeetingTab: String, CaseIterable {
    case record = "Record"
    case library = "Library"
    case analyze = "Analyze"

    var icon: String {
        switch self {
        case .record: return "mic.fill"
        case .library: return "books.vertical"
        case .analyze: return "sparkles"
        }
    }
}

// MARK: - MeetingView (thin container)

/// Thin TabView container for the three meeting tabs
@available(macOS 13.0, *)
struct MeetingView: View {

    let whisperService: WhisperService
    let recordingIndicator: RecordingIndicatorWindowController?
    weak var appDelegate: AppDelegate?

    @State private var store = MeetingStore()
    @State private var selectedTab: MeetingTab = .record
    @State private var selectedMeeting: MeetingRecord?

    init(
        whisperService: WhisperService,
        recordingIndicator: RecordingIndicatorWindowController? = nil,
        appDelegate: AppDelegate? = nil
    ) {
        self.whisperService = whisperService
        self.recordingIndicator = recordingIndicator
        self.appDelegate = appDelegate
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            MeetingRecordTab(
                store: store,
                whisperService: whisperService,
                recordingIndicator: recordingIndicator,
                appDelegate: appDelegate
            ) { record in
                // After auto-save, select the new meeting and switch to Analyze
                selectedMeeting = record
                selectedTab = .analyze
            }
            .tabItem {
                Label(MeetingTab.record.rawValue, systemImage: MeetingTab.record.icon)
            }
            .tag(MeetingTab.record)

            MeetingLibraryTab(
                store: store,
                whisperService: whisperService
            ) { record in
                selectedMeeting = record
                selectedTab = .analyze
            }
            .tabItem {
                Label(MeetingTab.library.rawValue, systemImage: MeetingTab.library.icon)
            }
            .tag(MeetingTab.library)

            MeetingAnalyzeTab(
                store: store,
                selectedMeeting: $selectedMeeting
            )
            .tabItem {
                Label(MeetingTab.analyze.rawValue, systemImage: MeetingTab.analyze.icon)
            }
            .tag(MeetingTab.analyze)
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
