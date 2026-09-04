# Sleep Coach UX flow contract

Last updated: 2026-09-04

This document is the product and engineering handoff for the simulator-validated navigation redesign. Preserve these ownership rules unless a later usability study establishes a better model.

## Canonical information architecture

| Destination | The question it owns | Primary action |
| --- | --- | --- |
| Today | How should I train today, and why? | Start the validated recommendation |
| Plan | When should I sleep, wake, and train tomorrow? | Apply plan |
| Train | Which saved workout should I start or resume? | Resume active workout or start a template |
| Progress | How are recovery and training changing? | Compare Recovery or Training over 7D/28D |

- Today owns the daily recommendation, its explanation, immediate recovery signals, and the route to Settings.
- Plan owns sleep need, gym duration, travel/buffer assumptions, selected planning calendars, detailed/Busy write destinations, wake-alarm application, persistent applied status, and undo.
- Train owns templates, active-workout state, and the exercise library. Reusing the library selector while building a template is a contextual workflow, not duplicate navigation.
- Progress owns Recovery and Training trends under one native segmented control.
- Settings is one level below Today and owns Apple Health, Data & Sources, workout preferences, and privacy. Calendar and alarm rows report status and direct the user to Plan, where those permissions have context.

## Critical flows

### First run

1. Explain the value of Apple Health and that Calendar/alarm access is deferred.
2. Let the user adjust their initial sleep target.
3. Offer one primary `Connect Apple Health` action and a clear `Continue without health data` alternative.
4. If the user skips, Today still offers a deterministic training-only recommendation and clearly marks recovery guidance as unavailable.

### Daily decision

1. Today presents one validated workout with duration, exercise count, recovery, sleep, and rolling seven-day training count.
2. `Adjust` changes time, equipment, focus, or effort; `Options` always shows exactly three valid plans.
3. `Review Workout` reveals prescriptions, technique links, provenance, and the concise explanation.
4. `Start Workout` opens the active logger directly. If another draft exists, Today cannot overwrite it and routes the user to Train.
5. The deterministic planner owns every constraint. Optional on-device AI may rank valid plans or rewrite the explanation only.
6. Recovery signals and detailed trends remain lower in the hierarchy.

At Accessibility Dynamic Type sizes, text remains fully scalable, controls remain at least 44 points tall, and the complete card stays scrollable.

### Tomorrow plan

1. Show the schedule outcome first and label it as schedule-based—not sleep-cycle detection.
2. Put `Apply plan` immediately after the outcome; pin it above the tab bar at Accessibility sizes.
3. Capture an immutable plan snapshot before confirmation so edits cannot change an in-flight request.
4. Confirm the exact alarm, one optional detailed workout event, and any privacy-safe Busy copies before writing.
5. Keep applied times and destinations visible, reconcile each app-owned receipt, and provide independent Undo.
6. Put timeline, commitment, timing assumptions, and the optional energy heuristic behind progressive disclosure.

### Workout

1. Resume an active draft, start one saved template, or start Today’s generated workout.
2. While a draft is active, explain why other templates cannot start and prevent editing/deleting the active template underneath it.
3. Build templates from the exercise catalog, with local editable sets, reps, load, RPE, rest, and order.
4. In the active logger, keep previous performance, the visible lb/kg unit, repetitions, completion, rest controls, and exercise options scannable without a chatbot interaction.
5. Keep lb/kg attached to each stored load and convert before comparisons.
6. Finish into Training History and per-exercise progress.

## Data-display rules

- Lead with the decision or actionable status, then comparison, then provenance and technical detail.
- Never use color as the only signal; pair it with text and a symbol.
- Distinguish recommendation confidence, data completeness, source freshness, and sensor accuracy. They are not synonyms.
- Attribute each metric to the Apple Health source actually used and explain automatic/manual fallback.
- Preserve missing dates as gaps. Do not invent continuity.
- Charts need a concise takeaway before the plot, direct units, 7D/28D scope, and meaningful accessibility summaries.
- Keep raw query identifiers and diagnostic errors under Technical details; put recovery instructions beside the affected source.

## Implemented acceptance checks

- iOS 26 simulator compile and a simulator-verified 195-test suite with zero failures or skips; unsigned Release device-SDK and signed physical-device builds also pass.
- Dark-mode iPhone 17 Pro review of all top-level screens, both trend destinations, Data & Sources, Calendar Setup, active workout, and first run.
- Compact-width light-mode review of Today, Plan, Calendar Setup, and active workout.
- Accessibility Extra Large review with reachable primary actions.
- Deterministic demo routes for repeatable visual review without personal Health data.
- The signed release candidate is installed and remained running on the development iPhone without a new crash diagnostic.

Hands-on physical-device acceptance remains required for real Eight Sleep/Hume/Apple Watch sample attribution, permission revocation/restoration, vendor sync timing, a finished workout write, Calendar behavior across timezone/DST changes, and a real AlarmKit wake alert.

## Follow-up backlog

1. Replace scattered debug-route parsing with a typed debug router.
2. Introduce a workout-flow coordinator if future features add more entry points than Today and Train; the current draft guard prevents destructive overlap.
3. Replace remaining generic global notices with local success/failure feedback near the affected content.
4. Add VoiceOver traversal tests and chart descriptors in addition to Dynamic Type screenshots.
5. Add favorites/recent exercises only after observing real catalog-search behavior; do not add more navigation until evidence shows it is needed.

## Design references

- [Apple Human Interface Guidelines: Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- [Apple Human Interface Guidelines: Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
- [Apple Human Interface Guidelines: HealthKit](https://developer.apple.com/design/human-interface-guidelines/healthkit)
- [Apple Human Interface Guidelines: Charts](https://developer.apple.com/design/human-interface-guidelines/charts)
- [Apple Human Interface Guidelines: Charting data](https://developer.apple.com/design/human-interface-guidelines/charting-data)
