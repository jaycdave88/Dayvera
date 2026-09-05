# Dayvera — Penpot design handoff

Design direction: **Quiet Vitality**. Date: 2026-09-05.

## File and project reference

- Connected Penpot file: **New File 1**.
- File ID: `40e06342-8830-80d6-8008-97472f73601e`.
- Requested final name: **Dayvera — Quiet Vitality**.
- Requested new project: **Dayvera**. Project creation/move and file rename have not been completed: the connected MCP exposes editable file tools, but no project-creation or writable file-name API. The design was built in the verified connected file. Do not report a new project as created.
- Start review on **07 — Prototype → 0 · Start here**, or inspect **04 — Main Screens** and **05 — Nutrition & Camera Flow**.

The connected design is editable Penpot content: text, native shapes, vector icons/charts, linked components and tokens. It is not a set of flattened screen images. The meal photograph is a raster sample. A separate Figma file was not created; the accompanying specification describes the equivalent Figma architecture.

## Documents and source of truth

- [Master brief](PENPOT_CODEX_MASTER_BRIEF.md): original detailed requirements.
- [UX redesign specification](DAYVERA_UX_REDESIGN_SPEC.md): audit, information architecture, flows, visual system, screen-by-screen design, Figma architecture, prototype and implementation order.
- [Code-to-design audit](PENPOT_CODE_AUDIT.md): verified code behavior and corrections made to the designs.
- [Launch and motivation audit](DAYVERA_LAUNCH_MOTIVATION_AUDIT.md): launch behavior, weekly consistency, milestones, ethical return states, notifications and SwiftUI implications.
- [Machine-readable inventory](PENPOT_DESIGN_INVENTORY.json): file/page/shape references, tokens, components and prototype connections.
- [Contrast checks](PENPOT_CONTRAST_QA.json): calculated ratios for semantic text/surface pairs.
- [Launch/motivation inventory](PENPOT_LAUNCH_MOTIVATION_INVENTORY.json): restored file revision, page, component and QA references for the additional phase.
- [QA gallery](QA/README.md): current nutrition screenshots and explicitly historical recovery/training baseline.

The local SwiftUI source remains authoritative for calculations, eligibility, safety, scheduling, source provenance and persistence. No production SwiftUI implementation or schema was changed in this design phase.

## Page inventory

| Page | Content | Page ID |
|---|---|---|
| 00 — Cover | Dayvera / Quiet Vitality overview | `40e06342-8830-80d6-8008-97472f73601f` |
| 01 — Foundations | Semantic color, typography, spacing, radius and touch targets | `6bbd8af2-01de-803c-8008-9747cf5ce1a1` |
| 02 — Components | Shared editable Light/Dark library and accessibility examples | `6bbd8af2-01de-803c-8008-9747cf5e68eb` |
| 03 — Patterns | Seven reusable decision/interaction patterns | `6bbd8af2-01de-803c-8008-9747cf5ef5c8` |
| 04 — Main Screens | Onboarding, Today, Plan, Train, workout, Progress, Settings | `6bbd8af2-01de-803c-8008-9747cf5f2aef` |
| 05 — Nutrition & Camera Flow | Daily nutrition, capture/review/edit, source, setup, targets and scenarios | `6bbd8af2-01de-803c-8008-9747cf5fa411` |
| 06 — User Flows | Four annotated end-to-end flow maps | `6bbd8af2-01de-803c-8008-9747cf602c73` |
| 07 — Prototype | Linked screen instances and named flow starts | `6bbd8af2-01de-803c-8008-9747cf609063` |
| 08 — Engineering Handoff | SwiftUI mapping, camera contract, audit, safety, accessibility and limitations | `6bbd8af2-01de-803c-8008-9747cf6138a5` |
| 09 — QA & States | Accessibility layouts and Increase Contrast examples | `6bbd8af2-01de-803c-8008-9747cf61b171` |
| 10 — Launch & Motivation | Launch continuity, first/returning launch, Weekly Rhythm, summaries, milestones, motion/accessibility and rejected mechanics | `9832c0ce-d707-80ef-8008-9763d13d3484` |

## Tokens and reusable components

Color tokens: `color.light.*`, `color.dark.*`, `color.contrastLight.*`, `color.contrastDark.*`. Roles: `background`, `surface`, `subtle`, `text`, `secondary`, `border`, `accent`, `accentSoft`, `onAccent`, `positive`, `positiveSoft`, `caution`, `cautionSoft`, `negative`, `negativeSoft`, `protein`, `carbs`, `fat`.

Core tokens: `space.2`, `.4`, `.8`, `.12`, `.16`, `.20`, `.24`, `.32`, `.40`, `.48`; radius control/card/hero/pill; minimum touch size; semantic font-size tokens. Typography styles: `largeTitle`, `title`, `title2`, `title3`, `headline`, `body`, `secondaryBody`, `caption`, `captionSmall`, `statLarge`, `statMedium`, `statSmall`, plus AX title/body/headline/caption/stat. Slider Control, Toggle Control, Search Field and Picker Row complement the domain components below.

The Penpot font is **Inter** because SF Pro is not available in the connected font library. Engineering should use **SwiftUI semantic SF Pro fonts with Dynamic Type**. Do not hardcode the specimen's pixel sizes into production.

| Family | Components |
|---|---|
| Core | Primary Button, Secondary Button, Tertiary Action, Destructive Action, Status Label, Inline Issue, Section Header, Empty State, Loading State, Success State |
| Navigation | Today / Plan / Train / Nutrition / Progress Tab Bar; Date Range Control |
| Today | Decision Card, Recovery Snapshot, Fuel Summary, Next Up Row |
| Plan | Schedule Timeline, Integration Row, Applied Plan State, Scheduled Item Row |
| Train | Active Workout Hero, Template Row, Workout Set Row, Progression Row, Rest Timer |
| Nutrition | Daily Nutrition Summary, Macro Progress Row, Compact Macro Strip, Log Food Button, Log Food Launcher Row, Recognition Candidate, Unmatched Food Candidate, Food Match Row, Portion Row, Provenance Label, Meal Row, Day Status, Intake Source Row, Adjustment Proposal, Scenario Banner, Body Measurement Row |
| Progress | Trend Section, Chart Header, Metric Summary, History Row |
| Settings | Settings Row, Connection Status Row, Diagnostics Row |
| Motivation | Weekly Rhythm Card, Micro Success Banner, Returning User Banner, Milestone Card, Notification Preference Row; Light/Dark variants |
| Accessibility | AX Field, AX Set Editor, AX Macro Progress, AX Recognition Candidate, AX Metric, AX Settings Row |

Library paths separate Light/Dark components, navigation selections and reusable screen assemblies. Auxiliary navigation masters alongside screen pages are component source artifacts, not extra product screens. Do not delete them without replacing their linked instances.

## Screen inventory

| Prefix | Screens/states |
|---|---|
| O | First Run, Nutrition Safety |
| T | Today normal, Health unavailable, limited recovery, active draft |
| P | Plan ready, Calendar disconnected, destination repair, verified applied, partial application, exact confirmation, scheduled items, Undo confirmation, undone |
| R | Saved workouts, active draft, empty Train |
| W | Preview, active workout, completed set/rest, skipped rest, finish confirmation, saved, invalid-set error |
| G | Recovery, Training, Nutrition progress, target history, scenario target history, adjustment history, measurements |
| S | Settings, Health Data & Sources, signal detail, Diagnostics, Calendar Setup and three focused selection screens |
| N | Daily dashboard and no-intake/no-target/complete/Health-source/pending/scheduled/post-save states; setup/training/goals/target review; Log Food; camera denied/unavailable/capture/review; explicit recognition initiation/loading/unavailable/failed; unmatched/partly matched/matched food review; food search; catalog/existing portion editors; unchecked/confirmed/failed meal editor; manual label; recent/favorites; authoritative source; manual totals; weigh-in; adjustment/evidence/scheduled; What-If; underfueling and eligibility states |
| A01–A08 | Today, Nutrition, Workout, Plan, Food Review, Recovery Progress, Settings and Train at accessibility text sizes, in Light/Dark |
| IC | Today, Plan, Train, Nutrition, Recovery Progress and Food Review with strengthened Light/Dark contrast |

Numeric values are illustrative fixtures. Production reads actual model output and the target effective on the displayed date. A screenshot's rounded macro grams need not algebraically reproduce a rounded calorie target exactly.

## Prototype flow inventory

1. **Daily workout:** Today → Preview → Active Workout → completed set/rest → Finish → Saved → Training Progress. Resume and invalid-set states are also designed.
2. **Food photo:** Nutrition → Log Food → Camera → Use Photo → explicit Identify Food on Device → recognition → unmatched foods → catalog matches/portions → optional missing food → final meal review → Save → daily totals → Mark Day Complete → Nutrition Progress.
3. **Tomorrow plan:** Today → Plan → exact confirmation → verified Applied → Scheduled Items → Undo confirmation → owned items removed.
4. **Target adjustment:** Pending → proposal → evidence → Apply Tomorrow → Scheduled Target → Target History. What-If has a separate scenario-scheduling branch.

Navigation and progress-domain selectors provide additional drill-down. The final prototype has 113 explicitly authored route entries and 227 navigation interactions including tab/domain links. The two-food branch preserves two selected foods when the user continues without adding another ingredient.

## Final design verification

- 11 populated pages. The original handoff contains 216 screen/mode examples; **10 — Launch & Motivation** adds 21 editable launch, decision, Light/Dark and accessibility boards.
- 208 library components, including 10 new Light/Dark motivation components; 99 tokens; 17 typography styles.
- 80 prototype boards, including the start selector; four journey starts plus Start Here.
- Penpot file validation returned no errors. Structural checks found no visible text outside the 216 screen artboards, no missing prototype destinations and no prototype click targets below 44 × 44 pt.
- Checked 88 opaque semantic foreground/background token pairs. All reached at least 4.5:1; minimum measured ratio was 4.59:1. This is a token-pair check, not a claim that every rendered pixel or native control has been audited.
- Visually reviewed representative Today, Plan, Train, Nutrition, food review, meal editor, What-If, active workout, Progress and Settings renders, including dark, AX and increased-contrast examples. Corrected an AX Plan action extending past its artboard, crowded What-If controls, overlapping text frames and six inherited light-mode button labels in dark examples.
- A separate reviewer checked the written handoff against code. Corrections distinguish weight-source consistency, exact review-reset triggers, meal Cancel behavior and the wider “Use both estimates” maintenance range.
- Saved Penpot checkpoints: **Dayvera · final design QA** and **Dayvera · launch and light motivation**. The launch/motivation page has no visible descendant outside its artboards, and final Penpot file validation returned zero errors. Final file/project naming remains the limitation described above.

## Final decisions

- Five tabs: Today, Plan, Train, Nutrition, Progress; Settings below Today.
- Decision first, evidence second, detail third. Each tab keeps its own action hierarchy.
- Photo acceptance does not automatically run recognition. Recognition never directly provides saved nutrient totals. The user matches and reviews foods, and a final confirmation gates Save.
- A day has one authoritative nutrition source; unknown nutrients remain unknown. Complete days are evidence, not merely a cosmetic checkmark.
- The brief's illustrative +150 adjustment was corrected to +100 to follow the existing adaptation cap. Accepted changes start on their future effective date and remain historical.
- What-If stays visibly hypothetical and uses the existing bounded delta, g/kg protein and cycling controls.
- Recovery context does not introduce new calorie-changing logic. Muscle-group emphasis is a training preference, not a spot-growth nutrition claim.
- No new backend/account/cloud dependency, database migration or third-party library is required.
- Use **Light Motivation**: domain-specific Weekly Rhythm, sparse milestones, personal records, weekly summaries and restrained completion feedback. Do not add daily streaks, points, levels, leaderboards, an achievement tab or a badge collection at launch.
- Keep the native launch screen visually continuous with Today and immediately usable. Do not add a mandatory post-launch logo sequence or simulated progress.
- Returning users retain history and see current guidance first. After a meaningful absence, use neutral “Welcome back” copy and disclose when recent data is insufficient for a confident trend.
- Engagement notifications remain limited, optional and utility-based. The current code has no general notification service, so this is a future implementation item rather than part of the visual redesign release.

## Implementation order

1. Shared presentation tokens/components in `DesignSystem.swift`; navigation in `RootView.swift`.
2. Today in `DashboardView.swift` / `TodayWorkoutRecommendationView.swift`.
3. Outcome-first Plan in `NightPlanView.swift` and focused calendar setup in settings.
4. Train, preview and accessible active logger in `WorkoutsView.swift`; preserve exercise library and technique routes.
5. Daily Nutrition and setup in `NutritionView.swift` / `NutritionSetupView.swift`.
6. Capture, food matching, shared editor and explicit review in `FoodCaptureView.swift` / `MealEditorView.swift`.
7. What-If and history in `NutritionWhatIfView.swift`, `NutritionProgressView.swift`, `ProgressView.swift`.
8. Settings and source/diagnostics hierarchy in `SettingsView.swift` / `DataSourcesView.swift`.
9. Launch continuity and Light Motivation: configure the generated launch screen to match the Today background, persist `lastMeaningfulForegroundAt`, derive Weekly Rhythm from existing workout/nutrition/recovery records, and add contextual milestones and weekly summaries. Add notification infrastructure only if the opt-in feature is separately scheduled.

Keep model/engine/store/platform services authoritative. Only the recent/favorite review-before-save change needs an intentional new draft transition; it must create a fresh meal identity. See the UX specification's file-by-file validation guidance.

## Known limitations and acceptance boundary

- Project creation and file rename remain unavailable through this MCP.
- Penpot uses Inter; SF Pro and native OS typography need implementation review.
- Standard screens are full-content artboards. They are not proof of device safe-area, sticky accessory or keyboard behavior. AX examples demonstrate reflow; not every state has an individual AX specimen.
- Prototype values and interactions are static demonstrations, not live camera, model, database, Health, Calendar, Alarm, timer or calculator execution. Secondary manual/recent routes may reuse representative editor fixtures; implementation must preserve actual entries.
- Recognition accuracy, physical permissions, VoiceOver focus, input keyboards and actual Dynamic Type require physical-device acceptance. The QA README explicitly does not claim these from simulator screenshots.
- The sample meal image is for design review only: [Poltino rice, chicken and broccoli](https://www.poltino.pl/pl/ris/ryz-z-kurczakiem-i-brokulami). It was not added to production assets; choose licensed production imagery separately if needed.
- No new app build or unit-test run was performed for these documentation/design-only changes. This handoff does not replace implementation tests or user research.
