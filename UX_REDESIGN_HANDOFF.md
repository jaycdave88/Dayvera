# Sleep Coach UX flow contract

Last updated: 2026-09-04

This document is the product and engineering handoff for the simulator-validated navigation redesign. Preserve these ownership rules unless a later usability study establishes a better model.

## Canonical information architecture

| Destination | The question it owns | Primary action |
| --- | --- | --- |
| Today | How should I train today? | Choose workout |
| Plan | When should I sleep, wake, and train tomorrow? | Apply plan |
| Train | Which saved workout should I start or resume? | Resume active workout or start a template |
| Exercises | How do I perform an exercise? | Browse/search the reference catalog |
| Settings | Which data and system integrations may the app use? | Context-specific connection or source management |

- Today owns the daily recommendation, its confidence, recovery signals, and Recovery Trends.
- Plan owns sleep need, gym duration, travel/buffer assumptions, Calendar connection, wake-alarm application, persistent applied status, and undo.
- Train owns templates, active-workout state, and Training History. It must not push another top-level copy of Exercises.
- Exercises is the top-level reference catalog. Reusing its selector while building a template is a contextual workflow, not duplicate navigation.
- Settings owns Apple Health and Data & Sources. Calendar and alarm rows report status and direct the user to Plan, where those permissions have context.

## Critical flows

### First run

1. Explain the value of Apple Health and that Calendar/alarm access is deferred.
2. Let the user adjust their initial sleep target.
3. Offer one primary `Connect Apple Health` action and a clear `Continue without health data` alternative.
4. If the user skips, Today shows a focused connection state instead of a fabricated or unavailable training recommendation.

### Daily decision

1. Today states the training recommendation and supporting detail first.
2. `Choose workout` switches to Train.
3. Volume, effort, progression, readiness, confidence, and two leading reasons provide supporting evidence.
4. Recovery signals and Recovery Trends are lower in the hierarchy.

At Accessibility Dynamic Type sizes, the primary action remains pinned above the tab bar. Text remains fully scalable and the rest of the card scrolls.

### Tomorrow plan

1. Show the schedule outcome first and label it as schedule-based—not sleep-cycle detection.
2. Put `Apply plan` immediately after the outcome; pin it above the tab bar at Accessibility sizes.
3. Capture an immutable plan snapshot before confirmation so edits cannot change an in-flight request.
4. Confirm the exact alarm and optional gym event before writing.
5. Keep applied times visible and provide Undo.
6. Put timeline, commitment, timing assumptions, and the optional energy heuristic behind progressive disclosure.

### Workout

1. Resume an active draft, or start one saved template.
2. While a draft is active, explain why other templates cannot start and prevent editing/deleting the active template underneath it.
3. Build templates from the exercise catalog, with local editable sets, reps, load, RPE, rest, and order.
4. Finish into Training History and per-exercise progress.

## Data-display rules

- Lead with the decision or actionable status, then comparison, then provenance and technical detail.
- Never use color as the only signal; pair it with text and a symbol.
- Distinguish recommendation confidence, data completeness, source freshness, and sensor accuracy. They are not synonyms.
- Attribute each metric to the Apple Health source actually used and explain automatic/manual fallback.
- Preserve missing dates as gaps. Do not invent continuity.
- Charts need a concise takeaway before the plot, direct units, 7D/28D scope, and meaningful accessibility summaries.
- Keep raw query identifiers and diagnostic errors under Technical details; put recovery instructions beside the affected source.

## Implemented acceptance checks

- iOS 26 simulator compile and unit suite.
- Dark-mode iPhone 17 Pro review of all top-level screens, both trend destinations, Data & Sources, and first run.
- Compact-width light-mode review of Today and Plan.
- Accessibility Extra Large review with reachable primary actions.
- Deterministic demo routes for repeatable visual review without personal Health data.

Physical-device acceptance remains required for HealthKit permission states and source attribution, Eight Sleep/Hume sync timing, workout writes, Calendar behavior across timezone/DST changes, and a real AlarmKit wake alert.

## Follow-up backlog

1. Replace scattered debug-route parsing with a typed debug router.
2. Introduce a workout-flow coordinator so template selection, editing, and an active session cannot stack conflicting modal states.
3. Replace remaining generic global notices with local success/failure feedback near the affected content.
4. Add VoiceOver traversal tests and chart descriptors in addition to Dynamic Type screenshots.
5. Move health-adjacent draft/status persistence to an explicitly selected iOS Data Protection and backup policy before production release.
6. Add favorites/recent exercises only after observing real catalog-search behavior; do not add more navigation until evidence shows it is needed.

## Design references

- [Apple Human Interface Guidelines: Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- [Apple Human Interface Guidelines: Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
- [Apple Human Interface Guidelines: HealthKit](https://developer.apple.com/design/human-interface-guidelines/healthkit)
- [Apple Human Interface Guidelines: Charts](https://developer.apple.com/design/human-interface-guidelines/charts)
- [Apple Human Interface Guidelines: Charting data](https://developer.apple.com/design/human-interface-guidelines/charting-data)
