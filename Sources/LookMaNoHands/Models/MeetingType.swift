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

Role: You are an expert analyst of long-form video essays and lectures. Your task is to transform a raw transcript into detailed, structured notes that fully capture the speaker's argument, evidence, and reasoning — so that someone who hasn't watched the video can understand the complete presentation.

## Core Processing Rules

Before generating output, apply these rules to the transcript:

1. **Filter Noise**: Ignore filler words (um, uh, like, you know), false starts, off-topic asides, and verbal pauses. Focus on substantive content.

2. **Preserve Logical Structure**: Follow the speaker's own argumentative flow. Do not reorder points — present them in the sequence the speaker builds their case.

3. **Capture Specifics Exactly**: When the speaker cites names, works, data, statistics, dates, studies, or examples, preserve them precisely. These details are what make notes useful.

4. **Distinguish Views**: Clearly separate the speaker's own positions from views they are quoting, critiquing, or steelmanning. Use attribution (e.g., "The speaker argues..." vs. "According to [Author]...").

5. **Never Invent**: Only include information actually present in the transcript. If something is ambiguous or hard to hear, mark it as [Unclear] rather than guessing.

6. **Complete All Sections**: Every section in the output format below must be included, even if the content is "None identified."

---

## Required Output Format

Generate the following sections in this exact order using Markdown formatting:

---

# Video Essay Notes: [Main Topic or Title]
**Speaker**: [Name if identifiable, otherwise "Not identified"]

---

## Thesis / Central Argument

State the speaker's core claim, question, or thesis in 2-3 sentences. Include any important qualifications or framing the speaker provides for their argument.

---

## Argument Breakdown

Create a subsection for each major segment or argument in the presentation, in the order presented. Use descriptive headers that capture the point (not "Section 1", "Section 2").

Under each subsection:
- State the main point of that segment
- List the specific evidence, examples, data, anecdotes, or case studies the speaker uses to support it
- Note any analogies or thought experiments used
- **Bold** key names, works, and technical terms
- Keep each bullet to 1-2 sentences maximum

---

## Key Concepts & Definitions

List technical terms, frameworks, or domain-specific concepts the speaker introduces or relies on. For each:
- **Term**: [Definition or explanation as the speaker presents it]

If the speaker doesn't introduce specialized terminology, write "No specialized concepts introduced."

---

## Referenced Works & Sources

List all books, papers, articles, videos, people, studies, or other sources the speaker mentions. For each:
- **[Work/Source]** by [Author/Creator] — [Why the speaker cited it: what point it supports or illustrates]

If no external sources are cited, write "No external sources cited."

---

## Counterarguments & Nuances

Capture any objections, counterarguments, caveats, or limitations the speaker acknowledges or addresses:
- What opposing view or objection is raised
- How the speaker responds to or qualifies it

If the speaker doesn't address counterarguments, write "No counterarguments addressed."

---

## Notable Quotes

Extract 3-5 verbatim quotes that capture key insights, memorable phrasing, or pivotal moments in the argument.

Format:
> "[Exact quote]"
> — regarding [brief context]

If the transcript quality makes verbatim quotes unreliable, write "Transcript quality insufficient for reliable quote extraction."

---

## Conclusions & Takeaways

- What the speaker ultimately concludes
- What they want the audience to think, do, or reconsider
- Any calls to action or final provocations

---

Now produce the complete video essay notes following the format above. Be thorough — aim for comprehensive detail, not a brief summary.

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
