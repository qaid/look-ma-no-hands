# Meeting Type Selection & Quality Check Implementation Plan

## Overview

This document provides the complete implementation plan for adding automatic meeting type detection and quality verification to Look Ma No Hands.

### Feature Summary

| Feature | Description |
|---------|-------------|
| **Meeting Type Detection** | Automatically identify meeting type from transcript content |
| **Specialized Prompts** | Different prompt templates optimized for each meeting type |
| **Quality Verification** | Verify generated notes against original transcript for accuracy |

### Meeting Types Supported

| Type | Use Case | Key Indicators |
|------|----------|----------------|
| General Meeting | Team meetings, project updates, planning | Default when no strong signals |
| Daily Standup | Scrum standups, daily syncs | "yesterday I", "blockers", "sprint" |
| One-to-One | Manager check-ins, career discussions | 2 speakers, "feedback", "career" |
| Project Kickoff | New project launches, scope definition | "kick off", "scope", "stakeholders" |
| Brainstorming | Creative sessions, ideation | "what if", "idea", "brainstorm" |

---

## Architecture

### New Files to Create

```
Sources/LookMaNoHands/
├── Models/
│   ├── MeetingType.swift          ← Enum for meeting types
│   └── QualityReport.swift        ← Quality check result structures
├── Services/
│   ├── PromptManager.swift        ← Load/save/manage prompts
│   ├── MeetingTypeDetector.swift  ← Auto-detection logic
│   └── QualityChecker.swift       ← Quality verification service
└── Views/
    ├── MeetingTypePickerView.swift ← Type selection UI
    └── QualityReportView.swift    ← Quality results display

Resources/
└── Prompts/
    ├── general-meeting-prompt.txt
    ├── standup-prompt.txt
    ├── one-to-one-prompt.txt
    ├── kickoff-prompt.txt
    ├── brainstorming-prompt.txt
    └── quality-check-prompt.txt
```

### Files to Modify

| File | Changes |
|------|---------|
| `MeetingAnalyzer.swift` | Accept MeetingType parameter, use PromptManager |
| `MeetingView.swift` | Add type picker, detection UI, quality check UI |
| `SettingsView.swift` | Add prompt customization options |

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Flow                                 │
└─────────────────────────────────────────────────────────────────┘

1. User records meeting transcription
                    │
                    ▼
2. User clicks "Auto-detect Type" (optional)
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│  MeetingTypeDetector analyzes transcript                        │
│  Returns: detectedType, confidence, indicators                  │
└─────────────────────────────────────────────────────────────────┘
                    │
                    ▼
3. User confirms or changes meeting type selection
                    │
                    ▼
4. User clicks "Generate Notes"
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│  PromptManager.getPrompt(for: selectedType)                     │
│  MeetingAnalyzer.generateNotes(transcript, prompt)              │
└─────────────────────────────────────────────────────────────────┘
                    │
                    ▼
5. Notes displayed to user
                    │
                    ▼
6. User clicks "Run Quality Check" (optional)
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│  QualityChecker.checkQuality(transcript, notes)                 │
│  Returns: QualityReport with score, issues, corrections         │
└─────────────────────────────────────────────────────────────────┘
                    │
                    ▼
7. Quality report displayed, user can apply corrections
```

---

## Phase 1: Foundation Setup

### Objective
Create the core data models and prompt management system.

### File: `Sources/LookMaNoHands/Models/MeetingType.swift`

```swift
import Foundation

enum MeetingType: String, CaseIterable, Codable, Identifiable {
    case general
    case standup
    case oneToOne
    case projectKickoff
    case brainstorming
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .general: return "General Meeting"
        case .standup: return "Daily Standup / Scrum"
        case .oneToOne: return "One-to-One Meeting"
        case .projectKickoff: return "Project Kickoff"
        case .brainstorming: return "Brainstorming Session"
        }
    }
    
    var description: String {
        switch self {
        case .general: return "Team meetings, project updates, planning sessions"
        case .standup: return "Quick status updates, blocker identification"
        case .oneToOne: return "Manager check-ins, career discussions, feedback"
        case .projectKickoff: return "New project launches, scope definition"
        case .brainstorming: return "Creative sessions, idea generation"
        }
    }
    
    var iconName: String {
        switch self {
        case .general: return "person.3.fill"
        case .standup: return "clock.fill"
        case .oneToOne: return "person.2.fill"
        case .projectKickoff: return "flag.fill"
        case .brainstorming: return "lightbulb.fill"
        }
    }
    
    var promptFileName: String {
        switch self {
        case .general: return "general-meeting-prompt"
        case .standup: return "standup-prompt"
        case .oneToOne: return "one-to-one-prompt"
        case .projectKickoff: return "kickoff-prompt"
        case .brainstorming: return "brainstorming-prompt"
        }
    }
}
```

### File: `Sources/LookMaNoHands/Services/PromptManager.swift`

```swift
import Foundation

class PromptManager: ObservableObject {
    static let shared = PromptManager()
    
    private let userDefaults = UserDefaults.standard
    private let customPromptKeyPrefix = "customPrompt_"
    private let qualityCheckKey = "qualityCheckPrompt"
    
    @Published var selectedMeetingType: MeetingType = .general
    
    // MARK: - Prompt Retrieval
    
    func getPrompt(for type: MeetingType) -> String {
        // Check for custom prompt first
        if let customPrompt = userDefaults.string(forKey: customPromptKeyPrefix + type.rawValue),
           !customPrompt.isEmpty {
            return customPrompt
        }
        
        // Fall back to default prompt from bundle
        return getDefaultPrompt(for: type)
    }
    
    func getDefaultPrompt(for type: MeetingType) -> String {
        guard let url = Bundle.main.url(forResource: type.promptFileName, withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            // Fall back to embedded prompt if resource not found
            return getEmbeddedPrompt(for: type)
        }
        return content
    }
    
    func getQualityCheckPrompt() -> String {
        if let customPrompt = userDefaults.string(forKey: qualityCheckKey),
           !customPrompt.isEmpty {
            return customPrompt
        }
        
        guard let url = Bundle.main.url(forResource: "quality-check-prompt", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return getEmbeddedQualityCheckPrompt()
        }
        return content
    }
    
    // MARK: - Custom Prompts
    
    func setCustomPrompt(_ prompt: String, for type: MeetingType) {
        userDefaults.set(prompt, forKey: customPromptKeyPrefix + type.rawValue)
        objectWillChange.send()
    }
    
    func resetToDefault(for type: MeetingType) {
        userDefaults.removeObject(forKey: customPromptKeyPrefix + type.rawValue)
        objectWillChange.send()
    }
    
    func hasCustomPrompt(for type: MeetingType) -> Bool {
        return userDefaults.string(forKey: customPromptKeyPrefix + type.rawValue) != nil
    }
    
    // MARK: - Embedded Prompts (Fallback)
    
    private func getEmbeddedPrompt(for type: MeetingType) -> String {
        switch type {
        case .general:
            return EmbeddedPrompts.generalMeeting
        case .standup:
            return EmbeddedPrompts.standup
        case .oneToOne:
            return EmbeddedPrompts.oneToOne
        case .projectKickoff:
            return EmbeddedPrompts.projectKickoff
        case .brainstorming:
            return EmbeddedPrompts.brainstorming
        }
    }
    
    private func getEmbeddedQualityCheckPrompt() -> String {
        return EmbeddedPrompts.qualityCheck
    }
}

// MARK: - Embedded Prompts Namespace

enum EmbeddedPrompts {
    // These serve as fallbacks if resource files aren't found
    // Full prompts are in Resources/Prompts/*.txt
    
    static let generalMeeting = """
    Role: You are an expert Technical Project Manager and Executive Assistant. Your task is to transform a raw meeting transcript into a clean, organized, and highly actionable document.
    
    [See Resources/Prompts/general-meeting-prompt.txt for full prompt]
    """
    
    static let standup = """
    Role: You are a Scrum Master assistant. Your task is to transform a standup meeting transcript into a clean, scannable status update document.
    
    [See Resources/Prompts/standup-prompt.txt for full prompt]
    """
    
    static let oneToOne = """
    Role: You are an executive assistant specializing in one-on-one meeting documentation.
    
    [See Resources/Prompts/one-to-one-prompt.txt for full prompt]
    """
    
    static let projectKickoff = """
    Role: You are a Project Manager assistant specializing in kickoff documentation.
    
    [See Resources/Prompts/kickoff-prompt.txt for full prompt]
    """
    
    static let brainstorming = """
    Role: You are a creative facilitator assistant specializing in capturing brainstorming sessions.
    
    [See Resources/Prompts/brainstorming-prompt.txt for full prompt]
    """
    
    static let qualityCheck = """
    Role: You are a Quality Assurance Reviewer specializing in meeting documentation.
    
    [See Resources/Prompts/quality-check-prompt.txt for full prompt]
    """
}
```

### Deliverables for Phase 1

- [ ] `MeetingType.swift` created and compiles
- [ ] `PromptManager.swift` created and compiles
- [ ] `Resources/Prompts/` folder created
- [ ] Placeholder `.txt` files created for each prompt
- [ ] Unit test: PromptManager returns prompts for all types

---

## Phase 2: Meeting Type Detection

### Objective
Automatically detect meeting type from transcript content with confidence levels.

### File: `Sources/LookMaNoHands/Services/MeetingTypeDetector.swift`

```swift
import Foundation

// MARK: - Detection Models

enum DetectionConfidence: String, Codable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    case defaultType = "Default"
    
    var description: String {
        switch self {
        case .high: return "Strong match based on multiple indicators"
        case .medium: return "Moderate match, consider reviewing"
        case .low: return "Weak match, manual selection recommended"
        case .defaultType: return "No specific indicators found"
        }
    }
}

struct DetectionResult {
    let detectedType: MeetingType
    let confidence: DetectionConfidence
    let indicators: [String]
    let allScores: [MeetingType: Int]
    
    var shouldConfirmWithUser: Bool {
        confidence == .low || confidence == .defaultType
    }
}

// MARK: - Detector

class MeetingTypeDetector {
    
    // MARK: - Indicator Configuration
    
    private struct IndicatorConfig {
        let patterns: [String]
        let meetingType: MeetingType
    }
    
    private let indicatorConfigs: [IndicatorConfig] = [
        // Standup indicators
        IndicatorConfig(
            patterns: [
                "yesterday i",
                "today i'll",
                "today i will",
                "blocker",
                "blocked by",
                "stand up",
                "standup",
                "sprint",
                "scrum",
                "daily sync",
                "daily standup",
                "what did you work on",
                "what are you working on",
                "anything blocking",
                "any blockers"
            ],
            meetingType: .standup
        ),
        
        // One-to-One indicators
        IndicatorConfig(
            patterns: [
                "your development",
                "your growth",
                "your career",
                "career development",
                "feedback for you",
                "give you some feedback",
                "how are you feeling",
                "how do you feel about",
                "one on one",
                "one-on-one",
                "1 on 1",
                "1-on-1",
                "1:1",
                "check in with you",
                "checking in",
                "your performance",
                "your goals"
            ],
            meetingType: .oneToOne
        ),
        
        // Project Kickoff indicators
        IndicatorConfig(
            patterns: [
                "kick off",
                "kickoff",
                "kick-off",
                "new project",
                "project scope",
                "define the scope",
                "stakeholder",
                "stakeholders",
                "timeline",
                "milestone",
                "milestones",
                "success criteria",
                "project start",
                "project launch",
                "project plan",
                "deliverables",
                "project goals"
            ],
            meetingType: .projectKickoff
        ),
        
        // Brainstorming indicators
        IndicatorConfig(
            patterns: [
                "what if we",
                "what if you",
                "brainstorm",
                "brainstorming",
                "ideation",
                "how might we",
                "let's explore",
                "i have an idea",
                "i've got an idea",
                "here's an idea",
                "building on that",
                "to add to what",
                "piggyback on",
                "blue sky",
                "think outside",
                "no bad ideas",
                "wild idea"
            ],
            meetingType: .brainstorming
        )
    ]
    
    // MARK: - Detection
    
    func detect(transcript: String) -> DetectionResult {
        let transcriptLower = transcript.lowercased()
        
        // Calculate scores for each meeting type
        var scores: [MeetingType: Int] = [:]
        var matchedIndicators: [MeetingType: [String]] = [:]
        
        for config in indicatorConfigs {
            var matches: [String] = []
            for pattern in config.patterns {
                if transcriptLower.contains(pattern) {
                    matches.append(pattern)
                }
            }
            scores[config.meetingType] = matches.count
            matchedIndicators[config.meetingType] = matches
        }
        
        // Additional heuristic: check speaker count for one-to-one detection
        let speakerCount = countSpeakers(in: transcript)
        if speakerCount == 2 {
            scores[.oneToOne, default: 0] += 3
            matchedIndicators[.oneToOne, default: []].append("exactly 2 speakers detected")
        }
        
        // Find highest scoring type
        let maxScore = scores.values.max() ?? 0
        
        // Determine confidence based on score
        let confidence: DetectionConfidence
        switch maxScore {
        case 4...:
            confidence = .high
        case 2...3:
            confidence = .medium
        case 1:
            confidence = .low
        default:
            confidence = .defaultType
        }
        
        // Get winning type or default to general
        let detectedType: MeetingType
        let indicators: [String]
        
        if maxScore >= 2, let winner = scores.max(by: { $0.value < $1.value })?.key {
            detectedType = winner
            indicators = matchedIndicators[winner] ?? []
        } else {
            detectedType = .general
            indicators = ["No strong indicators for specialized type"]
        }
        
        return DetectionResult(
            detectedType: detectedType,
            confidence: confidence,
            indicators: Array(indicators.prefix(5)), // Limit to 5 indicators
            allScores: scores
        )
    }
    
    // MARK: - Speaker Detection
    
    private func countSpeakers(in transcript: String) -> Int {
        // Match patterns like "Name:" or "JOHN:" at the start of lines
        // Also matches "John Smith:" format
        let pattern = #"^([A-Z][a-zA-Z]*(?:\s[A-Z][a-zA-Z]*)?)\s*:"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return 0
        }
        
        let range = NSRange(transcript.startIndex..., in: transcript)
        var speakers = Set<String>()
        
        regex.enumerateMatches(in: transcript, options: [], range: range) { match, _, _ in
            if let match = match,
               let speakerRange = Range(match.range(at: 1), in: transcript) {
                speakers.insert(String(transcript[speakerRange]).lowercased())
            }
        }
        
        return speakers.count
    }
}
```

### Deliverables for Phase 2

- [ ] `MeetingTypeDetector.swift` created and compiles
- [ ] Detection returns correct type for standup transcript
- [ ] Detection returns correct type for one-to-one transcript (2 speakers)
- [ ] Detection returns correct type for kickoff transcript
- [ ] Detection returns correct type for brainstorming transcript
- [ ] Detection returns general with low confidence for ambiguous transcript
- [ ] Confidence levels correctly assigned based on match count

---

## Phase 3: UI Components

### Objective
Create the meeting type selection UI and integrate with MeetingView.

### File: `Sources/LookMaNoHands/Views/MeetingTypePickerView.swift`

```swift
import SwiftUI

struct MeetingTypePickerView: View {
    @Binding var selectedType: MeetingType
    var detectionResult: DetectionResult?
    var onAutoDetect: (() -> Void)?
    var isDetecting: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with auto-detect button
            HStack {
                Text("Meeting Type")
                    .font(.headline)
                
                Spacer()
                
                if let onAutoDetect = onAutoDetect {
                    Button(action: onAutoDetect) {
                        HStack(spacing: 4) {
                            if isDetecting {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                            Text("Auto-detect")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isDetecting)
                }
            }
            
            // Detection result banner (if available)
            if let result = detectionResult {
                DetectionBannerView(result: result)
            }
            
            // Meeting type grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(MeetingType.allCases) { type in
                    MeetingTypeCardView(
                        type: type,
                        isSelected: selectedType == type,
                        isAutoDetected: detectionResult?.detectedType == type
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedType = type
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Meeting Type Card

struct MeetingTypeCardView: View {
    let type: MeetingType
    let isSelected: Bool
    let isAutoDetected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: type.iconName)
                    .foregroundColor(isSelected ? .white : .accentColor)
                
                Text(type.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                
                Spacer()
                
                if isAutoDetected && !isSelected {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Text(type.description)
                .font(.caption)
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor : Color(NSColor.controlColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isAutoDetected ? Color.orange : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Detection Banner

struct DetectionBannerView: View {
    let result: DetectionResult
    
    var confidenceColor: Color {
        switch result.confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        case .defaultType: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Detected:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(result.detectedType.displayName)
                        .font(.system(size: 12, weight: .medium))
                }
                
                HStack(spacing: 4) {
                    Text("Confidence:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(result.confidence.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(confidenceColor)
                }
            }
            
            Spacer()
            
            // Show first 2 indicators as tags
            if !result.indicators.isEmpty && result.indicators.first != "No strong indicators for specialized type" {
                HStack(spacing: 4) {
                    ForEach(result.indicators.prefix(2), id: \.self) { indicator in
                        Text(indicator)
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Preview

#if DEBUG
struct MeetingTypePickerView_Previews: PreviewProvider {
    static var previews: some View {
        MeetingTypePickerView(
            selectedType: .constant(.general),
            detectionResult: DetectionResult(
                detectedType: .standup,
                confidence: .high,
                indicators: ["yesterday i", "blockers", "sprint"],
                allScores: [.standup: 4, .general: 0]
            ),
            onAutoDetect: {}
        )
        .frame(width: 400)
        .padding()
    }
}
#endif
```

### Changes to MeetingView.swift

Add these state properties and integrate the picker:

```swift
// Add to MeetingView:

// MARK: - State Properties (add these)
@State private var selectedMeetingType: MeetingType = .general
@State private var detectionResult: DetectionResult?
@State private var isDetecting = false
@StateObject private var meetingTypeDetector = MeetingTypeDetector()

// MARK: - Add this view in the appropriate location
MeetingTypePickerView(
    selectedType: $selectedMeetingType,
    detectionResult: detectionResult,
    onAutoDetect: detectMeetingType,
    isDetecting: isDetecting
)

// MARK: - Add this function
private func detectMeetingType() {
    guard !transcriptionText.isEmpty else { return }
    
    isDetecting = true
    
    // Run detection on background thread
    DispatchQueue.global(qos: .userInitiated).async {
        let result = meetingTypeDetector.detect(transcript: transcriptionText)
        
        DispatchQueue.main.async {
            withAnimation {
                detectionResult = result
                selectedMeetingType = result.detectedType
                isDetecting = false
            }
        }
    }
}

// MARK: - Update generateNotes() to use selected type
private func generateNotes() {
    let prompt = PromptManager.shared.getPrompt(for: selectedMeetingType)
    // Pass prompt to MeetingAnalyzer...
}
```

### Deliverables for Phase 3

- [ ] `MeetingTypePickerView.swift` created and compiles
- [ ] Picker displays all 5 meeting types in grid
- [ ] Selection highlights correctly
- [ ] Auto-detect button triggers detection
- [ ] Detection result banner shows when available
- [ ] Auto-detected type has orange badge
- [ ] MeetingView updated with type picker
- [ ] Generate Notes uses selected type's prompt

---

## Phase 4: Quality Check System

### Objective
Add quality verification to check generated notes against original transcript.

### File: `Sources/LookMaNoHands/Models/QualityReport.swift`

```swift
import Foundation

// MARK: - Quality Score

enum QualityScore: String, Codable {
    case excellent = "Excellent"
    case good = "Good"
    case needsRevision = "Needs Revision"
    case poor = "Poor"
    
    var systemColor: String {
        switch self {
        case .excellent: return "systemGreen"
        case .good: return "systemBlue"
        case .needsRevision: return "systemOrange"
        case .poor: return "systemRed"
        }
    }
    
    var description: String {
        switch self {
        case .excellent: return "Notes are accurate and complete"
        case .good: return "Notes are mostly accurate with minor issues"
        case .needsRevision: return "Notes have some issues that should be addressed"
        case .poor: return "Notes have significant issues and need rework"
        }
    }
}

// MARK: - Issue Types

struct AccuracyIssue: Identifiable, Codable {
    let id: UUID
    let issueType: String // "Incorrect", "Misattributed", "Out of Context"
    let notesContent: String
    let transcriptContent: String
    let severity: String // "High", "Medium", "Low"
    let location: String
    
    init(issueType: String, notesContent: String, transcriptContent: String, severity: String, location: String) {
        self.id = UUID()
        self.issueType = issueType
        self.notesContent = notesContent
        self.transcriptContent = transcriptContent
        self.severity = severity
        self.location = location
    }
}

struct MissingItem: Identifiable, Codable {
    let id: UUID
    let item: String
    let importance: String // "High", "Medium", "Low"
    let transcriptLocation: String
    let recommendedAction: String
    
    init(item: String, importance: String, transcriptLocation: String, recommendedAction: String) {
        self.id = UUID()
        self.item = item
        self.importance = importance
        self.transcriptLocation = transcriptLocation
        self.recommendedAction = recommendedAction
    }
}

struct SuspiciousContent: Identifiable, Codable {
    let id: UUID
    let content: String
    let location: String
    let verificationStatus: String // "Not found", "Partially supported", "Interpretation not justified"
    let recommendation: String
    
    init(content: String, location: String, verificationStatus: String, recommendation: String) {
        self.id = UUID()
        self.content = content
        self.location = location
        self.verificationStatus = verificationStatus
        self.recommendation = recommendation
    }
}

struct RecommendedCorrection: Identifiable, Codable {
    let id: UUID
    let priority: String // "High", "Medium", "Low"
    let issue: String
    let currentText: String
    let correctedText: String
    let location: String
    
    init(priority: String, issue: String, currentText: String, correctedText: String, location: String) {
        self.id = UUID()
        self.priority = priority
        self.issue = issue
        self.currentText = currentText
        self.correctedText = correctedText
        self.location = location
    }
}

// MARK: - Quality Report

struct QualityReport: Codable {
    let overallScore: QualityScore
    let justification: String
    let accuracyIssues: [AccuracyIssue]
    let missingItems: [MissingItem]
    let suspiciousContent: [SuspiciousContent]
    let recommendedCorrections: [RecommendedCorrection]
    let recommendation: String
    let rawResponse: String
    
    var hasIssues: Bool {
        !accuracyIssues.isEmpty || !missingItems.isEmpty || !suspiciousContent.isEmpty
    }
    
    var highPriorityIssueCount: Int {
        accuracyIssues.filter { $0.severity == "High" }.count +
        missingItems.filter { $0.importance == "High" }.count +
        suspiciousContent.count
    }
    
    var highPriorityCorrections: [RecommendedCorrection] {
        recommendedCorrections.filter { $0.priority == "High" }
    }
    
    // Empty report for initial state
    static let empty = QualityReport(
        overallScore: .good,
        justification: "",
        accuracyIssues: [],
        missingItems: [],
        suspiciousContent: [],
        recommendedCorrections: [],
        recommendation: "",
        rawResponse: ""
    )
}
```

### File: `Sources/LookMaNoHands/Services/QualityChecker.swift`

```swift
import Foundation

class QualityChecker: ObservableObject {
    @Published var isChecking = false
    @Published var lastReport: QualityReport?
    @Published var error: String?
    
    private let promptManager: PromptManager
    
    init(promptManager: PromptManager = .shared) {
        self.promptManager = promptManager
    }
    
    // MARK: - Main Check Function
    
    func checkQuality(
        transcript: String,
        notes: String,
        using ollamaModel: String,
        ollamaHost: String = "http://localhost:11434"
    ) async throws -> QualityReport {
        
        await MainActor.run {
            isChecking = true
            error = nil
        }
        
        defer {
            Task { @MainActor in
                isChecking = false
            }
        }
        
        let prompt = buildQualityCheckPrompt(transcript: transcript, notes: notes)
        
        // Call Ollama API
        let response = try await callOllama(
            prompt: prompt,
            model: ollamaModel,
            host: ollamaHost
        )
        
        // Parse response into structured report
        let report = parseQualityResponse(response)
        
        await MainActor.run {
            lastReport = report
        }
        
        return report
    }
    
    // MARK: - Prompt Building
    
    private func buildQualityCheckPrompt(transcript: String, notes: String) -> String {
        let basePrompt = promptManager.getQualityCheckPrompt()
        
        return """
        \(basePrompt)
        
        ---
        
        ## Documents to Review
        
        ### Original Transcript
        
        \(transcript)
        
        ### Processed Meeting Notes
        
        \(notes)
        
        ---
        
        Now produce the quality review report following the format specified above.
        """
    }
    
    // MARK: - Ollama API Call
    
    private func callOllama(prompt: String, model: String, host: String) async throws -> String {
        let url = URL(string: "\(host)/api/generate")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw QualityCheckError.ollamaError("Failed to get response from Ollama")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw QualityCheckError.parseError("Failed to parse Ollama response")
        }
        
        return responseText
    }
    
    // MARK: - Response Parsing
    
    private func parseQualityResponse(_ response: String) -> QualityReport {
        let score = extractQualityScore(from: response)
        let justification = extractSection(from: response, after: "**Justification**:", before: "---") ?? "Unable to extract justification"
        let recommendation = extractSection(from: response, after: "## Final Recommendation", before: nil) ?? "Review manually"
        
        return QualityReport(
            overallScore: score,
            justification: justification.trimmingCharacters(in: .whitespacesAndNewlines),
            accuracyIssues: parseAccuracyIssues(from: response),
            missingItems: parseMissingItems(from: response),
            suspiciousContent: parseSuspiciousContent(from: response),
            recommendedCorrections: parseCorrections(from: response),
            recommendation: recommendation.trimmingCharacters(in: .whitespacesAndNewlines),
            rawResponse: response
        )
    }
    
    private func extractQualityScore(from response: String) -> QualityScore {
        let lowercased = response.lowercased()
        
        // Look for explicit rating
        if lowercased.contains("rating") || lowercased.contains("score") {
            if lowercased.contains("excellent") { return .excellent }
            if lowercased.contains("good") && !lowercased.contains("not good") { return .good }
            if lowercased.contains("needs revision") || lowercased.contains("needs work") { return .needsRevision }
            if lowercased.contains("poor") { return .poor }
        }
        
        // Fallback: count issue indicators
        let issueIndicators = ["issue", "error", "incorrect", "missing", "hallucination", "inaccurate"]
        let issueCount = issueIndicators.reduce(0) { count, indicator in
            count + (lowercased.components(separatedBy: indicator).count - 1)
        }
        
        switch issueCount {
        case 0: return .excellent
        case 1...2: return .good
        case 3...5: return .needsRevision
        default: return .poor
        }
    }
    
    private func extractSection(from text: String, after startMarker: String, before endMarker: String?) -> String? {
        guard let startRange = text.range(of: startMarker, options: .caseInsensitive) else {
            return nil
        }
        
        let afterStart = text[startRange.upperBound...]
        
        if let endMarker = endMarker,
           let endRange = afterStart.range(of: endMarker, options: .caseInsensitive) {
            return String(afterStart[..<endRange.lowerBound])
        }
        
        // Take next 500 characters or until end
        let endIndex = afterStart.index(afterStart.startIndex, offsetBy: min(500, afterStart.count))
        return String(afterStart[..<endIndex])
    }
    
    // Simplified parsers - expand as needed
    private func parseAccuracyIssues(from response: String) -> [AccuracyIssue] {
        // TODO: Implement detailed parsing based on response format
        return []
    }
    
    private func parseMissingItems(from response: String) -> [MissingItem] {
        // TODO: Implement detailed parsing based on response format
        return []
    }
    
    private func parseSuspiciousContent(from response: String) -> [SuspiciousContent] {
        // TODO: Implement detailed parsing based on response format
        return []
    }
    
    private func parseCorrections(from response: String) -> [RecommendedCorrection] {
        // TODO: Implement detailed parsing based on response format
        return []
    }
}

// MARK: - Errors

enum QualityCheckError: LocalizedError {
    case ollamaError(String)
    case parseError(String)
    
    var errorDescription: String? {
        switch self {
        case .ollamaError(let message): return "Ollama error: \(message)"
        case .parseError(let message): return "Parse error: \(message)"
        }
    }
}
```

### File: `Sources/LookMaNoHands/Views/QualityReportView.swift`

```swift
import SwiftUI

struct QualityReportView: View {
    let report: QualityReport
    var onApplyCorrections: (([RecommendedCorrection]) -> Void)?
    var onDismiss: (() -> Void)?
    
    @State private var showRawResponse = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Quality Report")
                    .font(.headline)
                
                Spacer()
                
                if let onDismiss = onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Score Card
            ScoreCardView(score: report.overallScore, justification: report.justification)
            
            // Issues Summary
            if report.hasIssues {
                IssuesSummaryView(report: report)
            }
            
            // Recommendations
            if !report.recommendedCorrections.isEmpty {
                CorrectionsView(
                    corrections: report.recommendedCorrections,
                    onApply: onApplyCorrections
                )
            }
            
            // Final Recommendation
            if !report.recommendation.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommendation")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(report.recommendation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            // Debug: Raw Response
            DisclosureGroup("Raw Response", isExpanded: $showRawResponse) {
                ScrollView {
                    Text(report.rawResponse)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Score Card

struct ScoreCardView: View {
    let score: QualityScore
    let justification: String
    
    var scoreColor: Color {
        switch score {
        case .excellent: return .green
        case .good: return .blue
        case .needsRevision: return .orange
        case .poor: return .red
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Score badge
            VStack {
                Text(score.rawValue)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(scoreColor)
            .cornerRadius(8)
            
            // Justification
            VStack(alignment: .leading, spacing: 2) {
                Text(score.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if !justification.isEmpty {
                    Text(justification)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(scoreColor.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Issues Summary

struct IssuesSummaryView: View {
    let report: QualityReport
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Issues Found")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack(spacing: 16) {
                IssueBadge(
                    count: report.accuracyIssues.count,
                    label: "Accuracy",
                    color: .red
                )
                
                IssueBadge(
                    count: report.missingItems.count,
                    label: "Missing",
                    color: .orange
                )
                
                IssueBadge(
                    count: report.suspiciousContent.count,
                    label: "Suspicious",
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct IssueBadge: View {
    let count: Int
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(count > 0 ? color : .secondary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Corrections View

struct CorrectionsView: View {
    let corrections: [RecommendedCorrection]
    var onApply: (([RecommendedCorrection]) -> Void)?
    
    var highPriority: [RecommendedCorrection] {
        corrections.filter { $0.priority == "High" }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recommended Corrections")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if let onApply = onApply, !highPriority.isEmpty {
                    Button("Apply High Priority") {
                        onApply(highPriority)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            
            ForEach(corrections) { correction in
                CorrectionRowView(correction: correction)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct CorrectionRowView: View {
    let correction: RecommendedCorrection
    
    var priorityColor: Color {
        switch correction.priority {
        case "High": return .red
        case "Medium": return .orange
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(correction.priority)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(priorityColor)
                    .cornerRadius(4)
                
                Text(correction.issue)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            if !correction.currentText.isEmpty {
                Text("Current: \(correction.currentText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            if !correction.correctedText.isEmpty {
                Text("Suggested: \(correction.correctedText)")
                    .font(.caption)
                    .foregroundColor(.green)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }
}
```

### Deliverables for Phase 4

- [ ] `QualityReport.swift` created and compiles
- [ ] `QualityChecker.swift` created and compiles
- [ ] `QualityReportView.swift` created and compiles
- [ ] Quality check can be triggered from MeetingView
- [ ] Report displays score with appropriate color
- [ ] Issues are summarized correctly
- [ ] Raw response can be viewed for debugging

---

## Phase 5: Integration & Polish

### Objective
Complete integration, add settings, and ensure everything works together.

### Changes to MeetingView.swift

```swift
// Complete integration example - add these to MeetingView

// MARK: - Additional State
@StateObject private var qualityChecker = QualityChecker()
@State private var showQualityReport = false

// MARK: - Quality Check Button (add after notes are generated)
if !generatedNotes.isEmpty {
    Button(action: runQualityCheck) {
        HStack {
            if qualityChecker.isChecking {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Image(systemName: "checkmark.shield")
            }
            Text("Run Quality Check")
        }
    }
    .disabled(qualityChecker.isChecking)
}

// MARK: - Quality Report Sheet
.sheet(isPresented: $showQualityReport) {
    if let report = qualityChecker.lastReport {
        QualityReportView(
            report: report,
            onApplyCorrections: applyCorrections,
            onDismiss: { showQualityReport = false }
        )
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Functions
private func runQualityCheck() {
    Task {
        do {
            _ = try await qualityChecker.checkQuality(
                transcript: transcriptionText,
                notes: generatedNotes,
                using: settings.ollamaModel
            )
            showQualityReport = true
        } catch {
            // Handle error
            print("Quality check failed: \(error)")
        }
    }
}

private func applyCorrections(_ corrections: [RecommendedCorrection]) {
    // Apply corrections to generatedNotes
    var updatedNotes = generatedNotes
    for correction in corrections {
        updatedNotes = updatedNotes.replacingOccurrences(
            of: correction.currentText,
            with: correction.correctedText
        )
    }
    generatedNotes = updatedNotes
    showQualityReport = false
}
```

### Settings Integration

Add to SettingsView.swift:

```swift
// MARK: - Meeting Types Tab Content

struct MeetingTypesSettingsView: View {
    @StateObject private var promptManager = PromptManager.shared
    @State private var selectedType: MeetingType = .general
    @State private var editedPrompt: String = ""
    @State private var hasChanges = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Type selector
            Picker("Meeting Type", selection: $selectedType) {
                ForEach(MeetingType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .onChange(of: selectedType) { newType in
                editedPrompt = promptManager.getPrompt(for: newType)
                hasChanges = false
            }
            
            // Prompt editor
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Prompt Template")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if promptManager.hasCustomPrompt(for: selectedType) {
                        Button("Reset to Default") {
                            promptManager.resetToDefault(for: selectedType)
                            editedPrompt = promptManager.getPrompt(for: selectedType)
                            hasChanges = false
                        }
                        .controlSize(.small)
                    }
                }
                
                TextEditor(text: $editedPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)
                    .border(Color.gray.opacity(0.3))
                    .onChange(of: editedPrompt) { _ in
                        hasChanges = editedPrompt != promptManager.getPrompt(for: selectedType)
                    }
            }
            
            // Save button
            HStack {
                Spacer()
                Button("Save Changes") {
                    promptManager.setCustomPrompt(editedPrompt, for: selectedType)
                    hasChanges = false
                }
                .disabled(!hasChanges)
            }
        }
        .padding()
        .onAppear {
            editedPrompt = promptManager.getPrompt(for: selectedType)
        }
    }
}
```

### Keyboard Shortcuts

Add to AppDelegate or relevant view:

```swift
// Keyboard shortcuts
.keyboardShortcut("d", modifiers: [.command]) // Auto-detect type
.keyboardShortcut("q", modifiers: [.command, .shift]) // Quality check
```

### Deliverables for Phase 5

- [ ] Quality check integrated into MeetingView
- [ ] Quality report displays in sheet
- [ ] Apply corrections works
- [ ] Settings tab for prompt customization
- [ ] Keyboard shortcuts added
- [ ] README updated with new features
- [ ] CLAUDE.md updated with new architecture
- [ ] End-to-end test passes

---

## Prompt Templates

Create these files in `Resources/Prompts/`:

### `general-meeting-prompt.txt`

See the full optimized prompt from our earlier conversation. Key sections:
- Role definition
- Processing rules (Filter noise, Group by theme, Capture technical specifics, etc.)
- Required output format (Meeting Notes header, Executive Summary, Key Discussion Points, Decisions, Action Items, Open Questions, Notable Quotes, Follow-up Meeting)
- Quality standards

### `standup-prompt.txt`

Key sections:
- Role: Scrum Master assistant
- Processing rules (Extract per person, Focus on three questions, Flag blockers)
- Required output format (Standup Notes, Team Status per person, Blockers Summary, Dependencies, Follow-up Items)

### `one-to-one-prompt.txt`

Key sections:
- Role: Executive assistant for 1:1s
- Processing rules (Privacy awareness, Track recurring themes, Capture both perspectives)
- Required output format (Quick Summary, Topics Discussed, Feedback Exchanged, Career & Development, Concerns, Action Items)

### `kickoff-prompt.txt`

Key sections:
- Role: Project Manager assistant
- Processing rules (Capture the "Why", Document stakeholders, Extract success criteria)
- Required output format (Project Overview, Stakeholders & Roles, Success Criteria, Timeline & Milestones, Risks, Assumptions, Action Items)

### `brainstorming-prompt.txt`

Key sections:
- Role: Creative facilitator
- Processing rules (Capture everything, Preserve attribution, Track idea evolution)
- Required output format (Session Objective, Ideas by Theme, Top Ideas, Idea Combinations, Concerns, Next Steps, Raw Idea List)

### `quality-check-prompt.txt`

Key sections:
- Role: Quality Assurance Reviewer
- Review tasks (Accuracy, Completeness, Attribution, Hallucination checks)
- Required output format (Overall Score, Accuracy Issues table, Missing Information, Suspicious Content, Recommended Corrections, Final Recommendation)

---

## Testing Checklist

### Unit Tests

```swift
// MeetingTypeDetectorTests.swift

func testDetectsStandup() {
    let transcript = """
    John: Yesterday I finished the API integration.
    Sarah: Great! Today I'll work on the frontend. No blockers for me.
    John: I'm blocked by the design specs.
    """
    
    let result = detector.detect(transcript: transcript)
    XCTAssertEqual(result.detectedType, .standup)
    XCTAssertEqual(result.confidence, .high)
}

func testDetectsOneToOne() {
    let transcript = """
    Manager: How are you feeling about your career development?
    Employee: I'd like to get some feedback on my recent project.
    Manager: Let's talk about your goals for next quarter.
    """
    
    let result = detector.detect(transcript: transcript)
    XCTAssertEqual(result.detectedType, .oneToOne)
}

func testDetectsKickoff() {
    let transcript = """
    PM: Welcome to the project kickoff for Project Atlas.
    Lead: Let's define the scope and identify our stakeholders.
    PM: We need to set milestones and success criteria.
    """
    
    let result = detector.detect(transcript: transcript)
    XCTAssertEqual(result.detectedType, .projectKickoff)
}

func testDetectsBrainstorming() {
    let transcript = """
    Alice: What if we tried a different approach?
    Bob: I have an idea - building on that, we could...
    Carol: Let's brainstorm some more options.
    """
    
    let result = detector.detect(transcript: transcript)
    XCTAssertEqual(result.detectedType, .brainstorming)
}

func testDefaultsToGeneral() {
    let transcript = """
    Let's discuss the quarterly results.
    The numbers look good this month.
    Any questions?
    """
    
    let result = detector.detect(transcript: transcript)
    XCTAssertEqual(result.detectedType, .general)
    XCTAssertEqual(result.confidence, .defaultType)
}
```

### Integration Tests

- [ ] Record standup → auto-detect → generate notes → quality check
- [ ] Record 1:1 → auto-detect → generate notes → quality check
- [ ] Manual type selection overrides auto-detection
- [ ] Custom prompt saves and loads correctly
- [ ] Quality check identifies intentional errors in notes

---

## Summary

This plan provides a complete roadmap for implementing meeting type selection and quality checking in Look Ma No Hands. Follow the phases in order, using the code templates as starting points.

**Key Files to Reference:**
- `MeetingType.swift` - Enum and metadata
- `PromptManager.swift` - Prompt loading/saving
- `MeetingTypeDetector.swift` - Auto-detection logic
- `QualityChecker.swift` - Verification service
- `MeetingTypePickerView.swift` - Selection UI
- `QualityReportView.swift` - Report display

**Session Prompts:**
Start each Claude Code session by referencing this document and specifying which phase you're working on.
