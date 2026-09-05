# Dayvera — launch, motivation, rewards, and retention audit

Audit date: 2026-09-05. Overall strategy: **LIGHT MOTIVATION**.

Dayvera benefits from restrained motivation because it already records meaningful outcomes: completed workouts, completed nutrition days, sleep coverage, body measurements, target revisions, and estimated strength bests. It does not benefit from a game economy, rigid daily streaks, or collectible badges. The product should make progress easier to understand and completion more satisfying while treating rest, illness, missing data, and return after absence as normal.

This is a product/design decision document. It does not modify production SwiftUI or add notification permissions. The current repository remains the behavioral source of truth.

## 1. Launch experience

### Native iOS launch screen

**Decision: modify the generated launch screen to match the first real surface; use no logo or wordmark.**

The project currently uses Xcode's generated launch screen (`INFOPLIST_KEY_UILaunchScreen_Generation = YES`) and has no custom launch image. The launch surface should use the same semantic background as Today in Light and Dark Mode. It may include system chrome placeholders only if they match the actual first frame closely. It should contain no progress indicator, text, app icon, illustration, or animation.

This follows [Apple's launch guidance](https://developer.apple.com/design/human-interface-guidelines/launching): launch immediately, make the launch screen nearly identical to the first screen, avoid text, and do not treat launch as advertising. The app icon already provided brand recognition before launch. Repeating it on a separate splash would add visual discontinuity without helping the user act.

### Dayvera-controlled transition

**Decision: no post-launch logo animation.**

Today should replace the system launch screen as soon as SwiftUI can draw it. A standard content appearance may use an opacity transition no longer than **120 ms** only when a real section becomes available after having shown a placeholder. This is state feedback, not an app-wide branded intro, and it must not block taps.

- Entry: Today is already present with cached/available content, meaningful unknown/loading states, or the first-run welcome.
- Exit: no overlay exists to dismiss. The first screen remains the interaction target throughout.
- Frequency: no branded transition on cold, warm, or returning launches.
- Reduce Motion: use immediate replacement; an opacity-only transition is also acceptable when the system prefers cross-fades.
- VoiceOver: focus begins on the actual navigation title or first-run heading. Never announce a decorative brand mark.
- Slow initialization: render Today and expose refresh/availability status. Do not keep a splash visible while Health or nutrition refreshes.
- Data already available: display it immediately without an animation gate.

The existing asynchronous `appModel.start()`, nutrition attachment, and foreground refresh behavior already supports a usable root while data refreshes. A branded overlay would make that behavior feel slower.

## 2. First launch and returning launch

### First launch

**Keep one concise welcome and use progressive onboarding.** The existing guided setup already explains the product, offers Apple Health connection, lets the user set a sleep target, and permits Set Up Later. Retain that foundation, update its icon/visual language to the Dayvera mark only within the welcome, and avoid adding an introductory carousel.

Recommended sequence:

1. Native launch background resolves directly into the Welcome screen.
2. One screen explains Dayvera's three jobs: plan, train/recover, and fuel progress.
3. Sleep target remains editable.
4. Connect Apple Health is the primary action; Set Up Later remains available.
5. Calendar and Alarm permission are requested only when the user applies a Plan.
6. Camera permission is requested only when Take Photo is selected.
7. Nutrition eligibility/profile is requested when the user asks for a personal target, not during the global welcome.
8. Optional reminders are offered after the user performs the relevant action and understands the benefit, never as a first-run gate.

This keeps required context brief and follows [Apple's onboarding guidance](https://developer.apple.com/design/human-interface-guidelines/onboarding) to explain features near where they are used.

### Returning launch

**Tap Dayvera → Today.** No repeated welcome and no splash. Current action and current evidence take priority. If an active workout draft exists, Resume remains the dominant action.

## 3. Motivation-system audit

| Mechanic | Product behavior reinforced | User benefit | Potential harm | Recommended? | Confidence |
|---|---|---|---|---|---|
| Daily streak | Opening/logging every day | Simple continuity signal | Guilt, low-value check-ins, pressure during rest/illness, return avoidance | **No — replace** | High |
| Weekly consistency | Completing planned training and evidence-quality nutrition days | Progress is visible without demanding perfection | A combined score could hide domain differences or punish missing sensor data | **Yes, domain-specific** | High |
| Personal milestones | First workout, first complete nutrition day, first target, sustained routine | Marks real progress and helps users recognize capability | Too many milestones can feel patronizing | **Yes, sparse** | High |
| Achievements | Structured accomplishments | Can create memory and recognition | Easily becomes arbitrary app-use gamification | **Limited to meaningful milestones** | Medium-high |
| Badges | Collectible visual rewards | Quick recognition | Collection pressure and childish tone do not fit the product | **No at launch** | High |
| Goal completion | Planned sessions, target evidence, applied plan | Clarifies whether the user's intended routine happened | Daily calorie perfection can encourage unhealthy interpretation | **Yes, carefully scoped** | High |
| Progress rings | Compact completion visualization | Glanceable | Resembles Apple activity rings and overstates unified completion | **No** | High |
| Progress bars | Weekly session/evidence progress | Direct, accessible, noncompetitive | Can imply failure if framed as a countdown | **Yes** | High |
| Personal records | Best exercise performance | Intrinsic evidence of training progress | Estimated 1RM can be mistaken for tested strength | **Yes; retain estimated label** | High |
| Improvement milestones | Same-source recovery/body/training trend | Connects behavior with visible progress | Sensor noise and causality overclaim | **Yes only with sufficient evidence** | Medium-high |
| Weekly summary | Training, nutrition evidence, recovery coverage and next step | Helps reflection without daily pressure | Dense scorecards or judgmental grades | **Yes** | High |
| Monthly summary | Longer trend context | Makes slow change visible | Aggregation can conceal gaps | **Progress insight, not a separate reward** | Medium |
| Encouragement messages | Completion and return | Makes the product warmer | Generic praise can feel hollow or manipulative | **Yes, factual and sparing** | High |
| Completion celebrations | Workout saved, plan verified, complete day | Confirms successful persistence and adds satisfaction | Repetition fatigue and false success before verification | **Yes, micro feedback** | High |
| Activity consistency | Planned workouts completed this week | Supports sustainable training | Encourages training through low recovery if framed rigidly | **Yes; rest-aware** | High |
| Check-in consistency | Repeated app check-ins | None unless a check-in has a defined outcome | Rewards screen time rather than health behavior | **No generic check-in streak** | High |
| Health-data milestones | More data coverage | Better interpretation quality | Rewards device availability rather than user effort | **No badges; show coverage neutrally** | High |
| Personalized insights | Meaningful changes and next step | Strong intrinsic reward | False causality or false precision | **Yes with source/uncertainty** | High |
| Achievement history | Browse earned rewards | Preserves accomplishment | Creates an unnecessary destination for a small mechanic | **No dedicated collection** | High |

## 4. Streak decision

**Do not implement daily streaks. Replace them with Weekly Rhythm and Momentum.**

Weekly Rhythm is a compact, domain-separated view:

- Training: `3 of 4 planned sessions`.
- Nutrition evidence: `5 complete days this week` when nutrition tracking is enabled.
- Recovery coverage: `6 nights recorded` as neutral data coverage, never an accomplishment badge.

The week is not labeled won, lost, perfect, or broken. Planned rest is already compatible because training is measured against the user's weekly target rather than seven consecutive days. Illness and lower recovery do not create a failure message. The calendar week resets the display, while a longer rolling trend supplies continuity.

Momentum is plain-language interpretation derived from several weeks, such as `Training has been consistent for 3 of the last 4 weeks.` It has no fragile streak counter and no midnight deadline. Returning users can continue from the current week without repairing a broken number.

Data support:

- Training sessions and dates: already available in `WorkoutSessionRecord`.
- Planned weekly training target: already available in the training profile.
- Complete nutrition days: already available in `NutritionDayRecord.isComplete`.
- Recovery coverage: already available in trend summaries, including missing calendar dates.
- Multi-week Momentum: derivable from these records; no new schema is required.

## 5. Milestones and achievements

**Use milestones; do not launch a badge collection.** A milestone is a contextual receipt of meaningful progress, shown once prominently and retained in the relevant history through the underlying record.

Approved initial milestone families:

- Getting started: first completed workout; first confirmed nutrition day; first personal nutrition target.
- Consistency: first week meeting the user's planned session target; first week with at least five confirmed nutrition days when nutrition tracking is enabled; four weeks with at least three weeks meeting the relevant plan.
- Training progress: a new estimated exercise best after sufficient comparable history.
- Reflection: first Weekly Summary viewed. This recognizes reflection only once; repeated screen visits are not achievements.
- Goal progress: reaching a user-defined training or nutrition evidence goal where that goal exists. Do not create a weight-loss or calorie-adherence trophy.

Do not award achievements for opening the app, visiting tabs, granting permissions, taking a photo, recording health samples, or maintaining uninterrupted daily use.

Historical accomplishment remains intact when current Momentum changes. For milestones that need a one-time “new” treatment, store a small local receipt containing stable milestone ID, earned date, underlying record/revision ID where relevant, and first-viewed date. Derived progress remains authoritative; the receipt prevents repeated celebration. The current code does not contain a milestone receipt model.

## 6. Celebration system

| Level | Use | Treatment | Constraints |
|---|---|---|---|
| Micro feedback | Meal saved, nutrition day completed, set completed, workout saved, verified Plan application | Checkmark/status change; optional `.success` sensory feedback; 120–180 ms semantic color/opacity change | Fire only after persistence or receipt verification. No confetti. Do not haptically celebrate imported sensor data. |
| Milestone | First workout, weekly plan met, new estimated best | Small inline milestone card or sheet; one restrained mark scales from 0.96 to 1 while fading in over at most 240 ms; one success haptic | Show once. Dismissible. Content remains readable without animation. Reduce Motion uses immediate/opacity appearance. |
| Major achievement | Sustained user-defined goal reached over a meaningful period | Reserved full-width Progress callout with concise evidence and Share only if later approved | No launch-time modal, forced share, confetti, sound, or repeated animation. Initial release does not need this tier. |

SwiftUI supports state-triggered [`sensoryFeedback`](https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(_:trigger:)) and exposes [`accessibilityReduceMotion`](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion). Haptic feedback supplements visible status and is never required to understand success.

## 7. Emotional design and copy

Copy reports truth first, then encouragement:

- `3 of 4 planned sessions complete this week.`
- `One session remains in your weekly plan.`
- `Your most consistent training month yet.`
- `New estimated best for Bench Press.`
- `Welcome back. Today's plan is ready.`
- `There isn't enough recent data for a trend yet.`

Avoid loss language, countdowns, shame, urgency, grades, mascots, and “perfect day” framing. Never call a planned rest day inactivity. Never praise a lower calorie intake or a lower body weight without the user's goal, evidence, and safety context.

## 8. Returning after absence

The return state is an inline Today treatment, not a modal.

| Absence | Returning experience |
|---|---|
| 2 days | No special welcome. Show current Today content; missing dates remain gaps. |
| 1 week | `Welcome back` with the current recommendation and one Resume/Review action. Do not enumerate missed days. |
| 1 month | Welcome back plus `Recent trends may need more data.` Offer Review goals/data sources only when stale or unavailable. |
| Several months | Welcome back; current safe recommendation; review goal/profile and reconnect sources only where verification shows a problem. Retain all historical records and estimated bests. |

Required data: `lastMeaningfulForegroundAt` stored locally after Today becomes usable, plus the current date and existing freshness/coverage. The code observes `scenePhase` but does not currently persist this timestamp. The value must stay on-device and must not count app opens as progress.

## 9. Reward architecture

- Immediate: verified status, checkmark, optional success haptic, macro/session progress update.
- Short term: Weekly Rhythm, one remaining action, weekly reflection.
- Long term: Momentum, estimated personal records, meaningful same-source improvement, user-defined goal completion.
- Intrinsic: clearer decisions, understanding trends, confidence that nutrition supports the training goal, and visible improvement. These remain the dominant reward.

No points, levels, coins, leaderboards, competitive comparisons, streak freezes, paid recovery of lost progress, or artificial scarcity.

## 10. Achievement-center decision

**No dedicated Achievement Center and no new tab.** Milestones appear contextually on Today after the primary task and in the relevant Progress history. Newly earned milestone detail may use a dismissible sheet. Earned state is represented by the historical evidence itself; there is no decorative locked grid.

If a future achievement collection is reconsidered, it must first demonstrate that browsing it improves reflection. Its minimum states would be earned, in progress, and unavailable/not applicable; “locked” must explain the meaningful behavior rather than tease a reward. Every item needs title, factual criteria, progress with units, earned date, and an accessibility label. That future concept is not approved for Penpot or SwiftUI now.

## 11. Today integration

Today keeps its existing decision-first structure:

1. Today's workout or active-workout Resume.
2. Recovery evidence.
3. Fuel Today.
4. Next Up.
5. Compact Weekly Rhythm.
6. A newly earned milestone only when one exists.

Weekly Rhythm must not displace the current recommendation. It uses linear progress and direct values. A milestone card appears below useful current information, never above Start/Resume, and disappears from Today after acknowledgement while remaining discoverable through the relevant Progress history.

## 12. Notification ethics

**Recommendation: limited and opt-in.** The current repository has AlarmKit for an explicitly applied wake alarm but no general notification service or `UNUserNotificationCenter` integration. Do not request notification permission during global onboarding.

Potential categories, each independently controlled:

- Plan reminder: only if the user chooses a recurring time and the next-day plan is not applied.
- Weekly Summary available: one user-selected day/time, generated from local data.
- Meaningful insight: off by default; only when a new evidence-qualified insight exists.
- Milestone earned: off by default and never time-sensitive.

No streak-loss, “we miss you,” midnight urgency, repeated prompts, or generic re-engagement. Tapping a notification deep-links to the relevant screen. Notifications disclose no sensitive health numbers on the lock screen unless the user explicitly chooses detailed previews and platform privacy allows it.

## 13. Accessibility and motion

- Motion is optional decoration; content and state exist before, during, and after it.
- Read `accessibilityReduceMotion`; replace scale/movement with immediate or opacity appearance. Honor the system's preferred cross-fade behavior where available.
- VoiceOver announces `Workout saved`, `Plan applied and verified`, or the milestone title only after the corresponding state is true. Move focus only when a new sheet is intentionally presented.
- Dynamic Type may turn Weekly Rhythm rows into vertical label/value/progress groups.
- Pair every color with text and a symbol. Use the existing semantic Light/Dark/Increase Contrast tokens.
- Do not repeat haptics for animated substeps. Provide a future in-app switch only if testing shows a need beyond system control.

## 14. Approved Penpot implications

Create only these approved components/patterns:

- Native Launch Continuity: Light/Dark static background resolving into Today; no logo animation.
- First-Launch Welcome refinement.
- Weekly Rhythm Card, domain-row and compact Today variant.
- Momentum/Weekly Summary card.
- Micro Success Banner.
- Milestone Card and Milestone Detail sheet.
- Returning User inline state for one week and one month+.
- Notification Preferences rows, clearly marked future/optional.
- Reduce Motion and accessibility-size variants for milestone and Weekly Rhythm.

Do not create Badge Grid, Locked Badge, Points, Level, Streak, Streak Freeze, Leaderboard, or reward-store components.

## 15. SwiftUI implications

| Experience | Simplest implementation | Data/persistence |
|---|---|---|
| Launch continuity | Configure `UILaunchScreen` background asset to match the Today background; let `RootView` render immediately | No new runtime state. Keep refresh asynchronous. |
| First launch | Refine existing `GuidedSetupView` and retain `@AppStorage("hasCompletedGuidedSetup")` | Existing state; permissions remain contextual. |
| Weekly Rhythm | Pure derived `WeeklyRhythm` value rendered by a reusable SwiftUI view | Existing sessions, training target, nutrition days and recovery summary. No schema. |
| Momentum | Derive domain-specific weekly completion across a bounded range | Existing records; define calendar/time-zone rules and unit tests. |
| Micro success | State-driven status plus `.sensoryFeedback(.success, trigger:)`; short `withAnimation` for color/opacity | Trigger only after model save/verified receipt. |
| Milestone evaluation | Small deterministic `MilestoneEngine` over existing records | Add protected local `MilestoneReceipt` only for earned/seen state. Do not duplicate source metrics. |
| Milestone presentation | Inline card or `.sheet`; standard transition or opacity; no animation framework | Stable milestone ID, earned date, evidence ID, first-viewed date. |
| Return state | Persist `lastMeaningfulForegroundAt`; derive absence band at launch/foreground | Protected local date. Update only after Today is usable. |
| Weekly summary | SwiftUI view in Progress, optionally linked from Today | Derived from existing data; optional last-viewed date. |
| Notifications | Future `UNUserNotificationCenter` service with per-category settings and deep links | New local preferences and scheduled-request receipts. Keep separate from AlarmKit plan behavior. |

`matchedGeometryEffect` is unnecessary. A launch logo has no destination in Today, and forcing one would make animation dictate information architecture. Use built-in transitions, `withAnimation`, `sensoryFeedback`, environment accessibility values, native sheets, and SF Symbols.

## 16. Required decisions

| Feature | Recommendation | Reason | Priority |
|---|---|---|---|
| Native launch branding | **Modify** | Match Today's semantic background; remove branding/progress rather than add a splash | P1 |
| Post-launch logo animation | **No** | Delays useful content and has no natural destination in Today | P1 |
| First-launch welcome | **Yes** | Product and Health-data context are useful once; current implementation is concise and skippable | P1 |
| Daily streaks | **Replace** | Weekly Rhythm/Momentum supports consistency without guilt or rest-day punishment | P1 |
| Weekly consistency | **Yes** | Existing behavior and data naturally support planned, domain-specific progress | P1 |
| Badges | **No** | Decorative collection adds pressure and does not improve decisions | P3 / omit |
| Milestones | **Yes** | Sparse milestones recognize real outcomes and records | P2 |
| Completion celebrations | **Yes** | Micro feedback confirms successful saves and verified changes | P1 |
| Achievement collection | **No** | Contextual Progress history is sufficient | P3 / omit |
| Weekly summaries | **Yes** | Reflection connects daily actions to useful trends | P2 |
| Personal records | **Yes** | Existing estimated strength bests are intrinsically meaningful | P1 / retain |
| Engagement notifications | **Limited** | Only user-selected reminders/summaries/insights provide utility; infrastructure is not present | P3 |
| Return-after-absence experience | **Required** | A neutral welcome lowers restart friction and protects wellness tone | P2 |

### Approved-mechanic implementation summary

| Mechanic | Encourages / user benefit | Pressure safeguards | IA location | Required data | Supported now? | Penpot | SwiftUI |
|---|---|---|---|---|---|---|---|
| Weekly Rhythm | Sustainable adherence; shows the next useful step | No consecutive-day count, no failure state, domains remain separate | Compact on Today; full in Progress summary | Sessions/weekly target, complete nutrition days, recovery coverage | Yes | Compact/full card + AX/Dark | Derived value and reusable view |
| Momentum | Continued participation across weeks | Allows imperfect weeks and planned rest | Progress; one-line Today insight only when useful | Several weeks of existing records | Yes | Trend summary state | Calendar-safe aggregation |
| Micro success | Confirms persistence/verification | Routine scale, no confetti, fires after success | Local to completed action | Save/receipt state | Yes | Success banner/state | State-driven animation + sensory feedback |
| Milestones | Recognizes firsts, plan consistency and estimated bests | Sparse criteria, dismissible, no locked grid | Contextual Today + relevant Progress history | Existing records plus earned/seen receipt | Partly; receipt absent | Card/detail/new state | Deterministic engine + local receipt |
| Weekly Summary | Reflection and understanding | No grade or unified score | Progress; optional Today link | Existing training/nutrition/recovery data | Yes | Summary card/detail | Derived snapshot; optional viewed date |
| Estimated personal best | Visible strength improvement | Always labeled estimated and exercise-specific | Training Progress + milestone when new | Completed sets/sessions | Yes | Existing trend + milestone treatment | Reuse current PB derivation |
| Return state | Makes resuming easy | No missed-day list or lost-streak language | Inline top of Today | Last meaningful foreground date | No | 1-week and 1-month+ variants | Protected local timestamp + state resolver |
| Limited notifications | User-chosen utility | Category controls, no urgency, off by default except explicit reminder | Settings → Notifications | Preferences, scheduling receipts, deep links | No general notification service | Settings rows and permission context | Future notification service |

The lowest useful level is **LIGHT MOTIVATION**: progress, weekly consistency, factual milestones, estimated personal records, restrained success feedback, and supportive return states. Moderate or heavy gamification would conflict with Dayvera's recovery-aware purpose and would reward engagement rather than better decisions.
