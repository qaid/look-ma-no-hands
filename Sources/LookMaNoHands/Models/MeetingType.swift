import Foundation

/// Meeting type that shapes LLM analysis prompts
enum MeetingType: String, CaseIterable, Codable, Identifiable {
    case standup = "standup"
    case oneOnOne = "oneOnOne"
    case allHands = "allHands"
    case customerCall = "customerCall"
    case videoEssay = "videoEssay"
    case general = "general"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standup: return "Standup"
        case .oneOnOne: return "1:1"
        case .allHands: return "All-Hands"
        case .customerCall: return "Customer Call"
        case .videoEssay: return "Video Essay"
        case .general: return "General"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .standup: return "figure.stand"
        case .oneOnOne: return "person.2"
        case .allHands: return "person.3"
        case .customerCall: return "phone"
        case .videoEssay: return "play.rectangle"
        case .general: return "doc.text"
        case .custom: return "slider.horizontal.3"
        }
    }

    var defaultPrompt: String {
        switch self {
        case .standup:
            return """
/no_think

You are summarizing a daily standup meeting. Focus on:

## Done
- What was completed since last standup

## In Progress / Next
- What is being worked on now and what comes next

## Blockers
- Any impediments or things needing help

Keep it brief and actionable. One bullet per person where identifiable.

## Transcript
[TRANSCRIPTION_PLACEHOLDER]
"""
        case .oneOnOne:
            return """
/no_think

You are summarizing a 1:1 meeting. Focus on:

## Feedback & Recognition
- Positive feedback and areas for growth

## Goals & Progress
- Career or project goal updates

## Action Items
| Owner | Action | Deadline |
|-------|--------|----------|

## Open Topics
- Any unresolved questions or items to revisit

## Transcript
[TRANSCRIPTION_PLACEHOLDER]
"""
        case .allHands:
            return """
/no_think

You are summarizing an all-hands meeting. Focus on:

## Key Announcements
- Company updates, decisions, or direction changes

## Highlights
- Notable achievements or milestones shared

## Q&A Summary
- Questions raised and responses given

## Next Steps
- Action items or follow-ups for the broader team

## Transcript
[TRANSCRIPTION_PLACEHOLDER]
"""
        case .customerCall:
            return """
/no_think

You are summarizing a customer call. Focus on:

## Customer Pain Points
- Problems or frustrations the customer expressed

## Commitments Made
- Promises or follow-ups your team committed to

## Next Steps
| Owner | Action | Deadline |
|-------|--------|----------|

## Notable Quotes
> Key things the customer said verbatim

## Transcript
[TRANSCRIPTION_PLACEHOLDER]
"""
        case .videoEssay:
            return """
/no_think

You are summarizing a video essay or lecture — a single-speaker, long-form presentation that develops an argument or explores a topic in depth. Focus on:

## Thesis / Central Argument
- The main claim or question the speaker is exploring

## Key Arguments & Evidence
- Major points made, in the order presented
- Supporting evidence, examples, or data cited for each

## Referenced Works & Sources
- Books, papers, people, videos, or other sources the speaker mentions or quotes

## Notable Quotes
> Memorable or particularly well-stated lines from the speaker

## Conclusions & Takeaways
- What the speaker concludes or wants the audience to take away

Keep the structure clean and concise. Preserve the logical flow of the speaker's argument rather than imposing chronological timestamps. Use bullet points, not paragraphs.

## Transcript
[TRANSCRIPTION_PLACEHOLDER]
"""
        case .general:
            return Settings.defaultMeetingPrompt
        case .custom:
            return ""
        }
    }
}
