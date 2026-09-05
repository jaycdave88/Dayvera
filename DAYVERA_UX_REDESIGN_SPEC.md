# Dayvera — Quiet Vitality

Product design specification · 2026-09-05

This document follows the requested audit → architecture → flows → visual system → screen design → component architecture → prototype → engineering order. The editable design is in the connected Penpot file. The same structure is suitable for a Figma reconstruction; a separate Figma file has not been created.

Behavior is grounded in the local repository and [QA gallery](QA/README.md). The supplied GitHub page could not be retrieved in this session; the local gallery and source were available. See [the code audit](PENPOT_CODE_AUDIT.md) for verified behavior, design corrections and limitations. The gallery's current nutrition screenshots and historical recovery/training screenshots are explicitly different baselines.

## 1. Existing-product UX audit

These are expert-review findings, not measured usability-study results. The existing implementation already contains important safety, privacy and accessibility behavior; the redesign should preserve it.

| Existing area / purpose | What works | Friction or risk | Redesign and reason |
|---|---|---|---|
| Today / choose today's useful action | Recovery-aware deterministic recommendation, contextual evidence and protected active drafts | Recommendation, health evidence and secondary destinations can compete for attention as features accumulate | One dominant workout surface; one grouped recovery section; compact fuel and tomorrow summaries. The next action becomes apparent without removing evidence. |
| Tomorrow plan / fit sleep and training around commitments | Exact confirmation, destination rules, receipt verification and owned-item Undo | Scheduling configuration can interrupt understanding of the proposed outcome | Timeline first, compact connection rows, exact confirmation, then itemized status. Users understand the change before granting it. |
| Train / start or resume | Saved templates, active draft recovery, exercise library and previous history | Repeated large start actions dilute scanability; a draft requires visibly different precedence | Resume hero only when active; otherwise compact template rows with a 44 pt Play control. Keep preview on row tap. |
| Workout preview / check before starting | Existing templates and recovery adjustment can explain the session | Full editing detail is unnecessary for a start decision | Duration, adjustment and exercise prescriptions, then one Start action. Editing remains secondary. |
| Active workout / record performance | Autosave, previous performance, units, progression, rest timer, notes and validation | Dense set columns and competing details create reading/input load, especially at large type | Focus on the current exercise and set editor. Stack labeled fields at AX sizes. Technique and progression rationale are drill-downs. |
| Nutrition / decide what to log and what remains | Personalized targets, macro estimates, meals, source selection, completion and adaptive history | Daily actions, setup, source control, capture and analysis can form a long undifferentiated surface | Calories and protein first; Log Food sheet; linear macro rows; meals; completeness/source; pending decision. Move historical analysis to Progress. |
| Photo capture / reduce typing | Camera and PhotosPicker exist; explicit on-device recognition; manual fallback | A camera icon alone can imply automatic nutrient measurement; the first screenshot does not establish inference quality | Make capture discoverable, then clearly separate Identify, Match, Review and Save. Each stage states what is known. |
| Food review / trust meal values | Candidate matching, grams, provenance and final review gate | Showing matched nutrients too early would imply AI nutrient accuracy; ingredient omissions are easy to miss | Initially unmatched candidates, explicit match/portion actions, missing-ingredient affordance and final confirmation. Preserve all save gates. |
| Nutrition profile / personalize estimates | Eligibility, activity, goals, training, protein/cycling and optional body measurements | Long forms and unsupported precision can obscure why questions matter | Group eligibility, body/activity, then training/macros. Target review distinguishes equation estimates from tracked evidence. Do not hide required confirmation. |
| What-If / explore safely | Bounded controls, goal-specific protein range, tomorrow scheduling | Results can be mistaken for active targets or body-composition predictions | Persistent SCENARIO · NOT APPLIED label, average/day outputs and future effective date after acceptance. |
| Nutrition progress / judge adaptation | Historical targets and complete-day evidence are retained | Incomplete logging can resemble under-eating; weight fluctuation can dominate interpretation | Takeaway first, gaps and incomplete days explicit, weight trend plus intake context, then versioned histories. |
| Recovery/training progress / learn over time | Separate domains, source data and estimated strength | Multiple metrics can lack a clear question or comparable window | Recovery / Training / Nutrition selector, one takeaway, shared date control, direct units/source and meaningful chart summaries. |
| Settings / configure product | Connections, personalization and source controls already exist | Technical observations can overwhelm normal configuration | Native grouped Form: Connections, Personalization, Data, Privacy & Safety, About. Diagnostics one level deeper. |
| Health Data & Sources / understand evidence | Source preference, availability and signal-specific controls | Confidence, freshness and sensor quality can be conflated | Current signal, selected source, coverage/freshness and allowed usage controls; definitions and query failures in Diagnostics. |
| Calendar setup / select destinations | Separate planning/details/Busy semantics and privacy behavior | Three selection models in one form require too much context switching | Landing rows leading to one focused selection task each. Disable conflicting Busy destinations with explanation. |

Highest priority across the product: the next useful action; its current status; enough evidence to understand it; configuration and technical detail only when relevant. Do not remove useful capability merely to make a screenshot look sparse.

## 2. Recommended information architecture

Five tabs match the implemented recurring jobs. Settings remains below Today. Each tab retains its own navigation stack.

| Tab | Primary job and action | Owned secondary destinations |
|---|---|---|
| Today | Decide what matters now → Start/Resume Workout | Workout preview, recovery detail, Nutrition shortcut, tomorrow plan, Settings |
| Plan | Review tomorrow → Apply Plan | Exact confirmation, scheduled items, partial receipts, Undo, calendar/alarm configuration |
| Train | Resume or start a workout | Preview, active logger, template edit/create, exercise library, technique |
| Nutrition | Know target/logged/remaining → Log Food | Capture, search, portion and meal editing, recent/favorites, source, manual totals, weigh-in, profile, target review, adjustment, What-If |
| Progress | Understand change over time | Recovery / Training / Nutrition; chart details, exercise history, measurements, target and adjustment history |

**Modal rules:** Log Food is a single sheet; capture uses the existing native camera bridge, and photo selection uses PhotosPicker. Search/portion/meal editors keep a focused navigation stack inside the entry task. Weigh-in is a short sheet. Active Workout is a full-screen task. Scheduling confirmation and destructive actions use native confirmation dialogs. Settings and historical details push within their owning navigation stack. Dismissal preserves the existing active-workout draft and never acts as an implicit Save. Unsaved meals currently use local view state and are discarded by Cancel; general meal-draft persistence is not part of this redesign.

## 3. Simplified user-flow map

| Journey | Entry → action → next screen → completion | Why |
|---|---|---|
| Daily workout | Today → Review Workout → Preview → Start → Active Workout → complete set/rest → Finish confirmation → Saved → Training Progress | A fast start remains available; users who need evidence get a lightweight preview. |
| Resume | Today or Train → Resume → existing draft → Finish → Saved | No duplicate draft or overwritten work. |
| Tomorrow | Today Review Plan or Plan tab → schedule → Apply → exact confirmation → receipt verification → Applied / Partial → Scheduled Items | The outcome is understood before system writes; partial work stays inspectable. |
| Undo plan | Applied → Scheduled Items → Undo confirmation → owned items removed | Reversibility has a clear and limited scope. |
| Food photo | Nutrition → Log Food → Take Photo → Camera → Use Photo → Identify on Device → candidates → catalog match/portion → Meal Editor → review confirmation → Save | Reduces typing while retaining the code's trust boundary. |
| Photo fallback | Capture/recognition unavailable → Enter Manually → same Meal Editor → review → Save | Capability or permission failure does not block logging. |
| Catalog/manual meal | Log Food → Search or Nutrition Label → portion/whole-portion values → Meal Editor → review → Save | Every entry method converges instead of requiring separate meal models. |
| Recent meal | Log Food → Recent/Favorites → copied meal review → Save new meal | The user verifies today's portion before creating a new record. This is a deliberate change to current immediate Repeat. |
| Completion | Nutrition → confirm selected source → Mark Day Complete → completed day → Nutrition Progress | Makes adaptation evidence an explicit user assertion. |
| Weigh-in | Nutrition → Weigh In → date/weight/optional measurements → Save | Short, neutral and one-handed; no moral coloring of weight. |
| Adjustment | Pending proposal → evidence → Apply Tomorrow → Scheduled Target → Target History | Acceptance and effective date are unambiguous. |
| Scenario | Nutrition options → What-If → bounded changes → Apply Tomorrow → scenario target scheduled | Hypothesis and active plan stay distinct. |
| Data setup | Today → Settings → Health Data & Sources → signal/source detail | Technical diagnostics no longer interrupt daily decisions. |

## 4. Visual/design direction

**Quiet Vitality:** warm, composed, information-led. Original layouts use a restrained indigo accent, readable values, generous vertical rhythm and semantic status labels. Cards group a decision or coherent evidence; ordinary settings and templates use rows. No activity rings, decorative glow, imitation Apple layouts or persistent glass content cards.

The design uses clarity, reversibility and accessible hierarchy consistent with [Apple's design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles). Native controls should adopt their platform appearance; content surfaces retain Dayvera's own visual hierarchy.

## 5. Design-system specification

### Typography

Engineering uses SF Pro through SwiftUI semantic fonts and Dynamic Type. Penpot uses editable Inter because SF Pro is unavailable in the connected font library. The fallback is a design-tool limitation, not a recommendation to ship Inter.

| Token/style | Standard specimen | Intended use |
|---|---|---|
| largeTitle | 34, bold | Main screen title |
| title / title2 / title3 | 28 / 22 / 20 | Section emphasis and task headings |
| headline | 17, semibold | Row names, actions |
| body | 17, regular | Explanations and form content |
| secondaryBody | 15 | Supporting context |
| caption / captionSmall | 13 / 11 | Metadata; do not use for primary decisions |
| statLarge / statMedium / statSmall | 40 / 30 / 22 | Dominant numeric values |
| axTitle / axBody / axHeadline / axCaption / axStat | 44 / 40 / 40 / 28 / 56 specimens | Accessibility layout examples; runtime follows system scaling |

Use tabular digits for live timers and numeric comparisons. Text grows vertically. Reflow multi-column structures into labeled stacks at accessibility sizes, following [Apple typography guidance](https://developer.apple.com/design/human-interface-guidelines/typography).

### Semantic color palette

| Role | Light | Dark |
|---|---|---|
| background | #F5F6FA | #11131B |
| surface | #FFFFFF | #1C1F2C |
| subtle | #ECEEF5 | #272B3B |
| text | #191C2D | #F4F5FB |
| secondary | #5B6075 | #AFB5CB |
| border | #D9DDE8 | #3E455C |
| accent | #4655CC | #8293FF |
| accentSoft | #E9ECFF | #2A3158 |
| onAccent | #FFFFFF | #101527 |
| positive | #0B7A5A | #65E4BC |
| caution | #8A5600 | #FFC04A |
| negative | #B32645 | #FF718B |

Protein maps to accent, carbs to positive, fat to caution for chart differentiation only; these colors do not judge a nutrient as good or bad. Status always includes words and a symbol. Soft semantic backgrounds accompany status foregrounds. Tokens use `color.<mode>.<role>` in Penpot; Figma can use mode values on a shared semantic variable collection.

### Spacing, geometry and controls

Spacing: 2, 4, 8, 12, 16, 20, 24, 32, 40, 48. Horizontal inset: 20 standard / 16 compact. Control radius 12; card 18; hero 22; pill fully rounded. No default shadow. Dividers are thin semantic borders; controls needing a visible boundary must remain clear in Increase Contrast.

Minimum comfortable interaction area: 44 × 44 pt. A small icon may sit inside a larger target. Primary buttons use accent/onAccent; secondary use restrained accent; destructive actions use negative and never the primary brand fill. Disabled states require explanatory context where the reason is not obvious. Loading actions retain their label and avoid implying success before persistence.

### Reusable chart system

| Pattern | Representation and rules |
|---|---|
| Daily | Direct values, target/remaining text and linear progress; no rings. |
| Weekly sleep | Duration bars with units and target reference; missing dates have gaps. |
| Weekly HRV/RHR | Line segments plus points, baseline reference and direct delta; do not bridge missing dates. |
| Calories / protein | Intake vs historical effective target; distinguish incomplete days by label/mark treatment, not just color. |
| Strength | Estimated 1RM points, exercise picker and history; label the estimate. |
| Monthly/longer | Reduce label density; state any aggregation and retain raw values in detail. |
| Measurements | Neutral line/point chart with configured units; no red/green body-weight judgment. |
| Goal completion | Linear value + target + remaining; text conveys meaning without color. |

Chart anatomy: takeaway → metric and date range → chart → source/coverage → accessible summary → details. Provide a table/list alternative and VoiceOver labels including date, value and units. Native chart accessibility should support audio graphs where appropriate; see [Apple chart guidance](https://developer.apple.com/design/human-interface-guidelines/charts).

## 6. Screen-by-screen redesign

### Shared layout contract

Standard artboards are 393 pt wide and represent full scroll content, not a fixed device-height requirement. Use native top and bottom safe areas. Title sits below navigation chrome; content uses 20 pt insets, 24–32 pt section gaps and 16–20 pt group padding. Long content scrolls. Tab bars and action accessories belong to native safe-area layout, not the content's arbitrary full-artboard height.

Use back navigation for drill-down and Cancel for a dismissible task. Active-workout dismissal preserves the autosaved draft; meal-editor cancellation retains its existing discard behavior. Decimal pads apply to appropriate numeric fields, units remain visible, and the focused field/action must stay above the keyboard. Confirmations announce outcome or error; haptics may reinforce successful set completion/save, but must never be the only feedback. No custom swipe gesture should be required to discover an essential action.

| Screen / IDs | Precise hierarchy and actions | States, interaction and accessibility |
|---|---|---|
| First Run / O01 | Dayvera introduction; three concise benefits; Get Started; connection/setup actions remain contextual | Missing permissions do not block browsing. Large type stacks content; no forced account creation. |
| Nutrition Safety / O02 | Why checks matter → adult appropriateness confirmation → supervision/symptom questions → Continue | Eligibility must be explicit. Ineligible profile retains journal capability and explains unavailable targets. |
| Today / T01–T04 | Large Today title + Settings; workout hero with name, duration/exercises/intensity, recovery/sleep/training context, one explanation; Start/Resume; Adjust/Alternatives; Review. Grouped Sleep/HRV/RHR. Compact Fuel Today. Compact Next Up. | Health unavailable uses unknown values and connection action; limited evidence says so. Active draft replaces Start with Resume. Never show three giant recovery cards. |
| Plan / P01–P09 | Tomorrow heading; commitment context; bed/wake/train/ready/first-commitment timeline; schedule-based note; Calendar/Alarm rows; exact effects summary; Apply Plan | Disconnected/destination-repair states offer focused repair. Confirmation lists exact writes. Applied replaces the CTA surface with receipt status; partial needs review. Scheduled Items and Undo remain available. |
| Train / R01–R03 | Saved Workouts title/list; toolbar New Template and Exercise Library. Each row: name, exercise/set counts, last completed and trailing Play. Active state adds Resume hero above rows. | Empty state offers template creation. Tap row previews; Play fast-starts. Context menu Edit/Delete. Active draft disables other starts with reason. |
| Preview / W01 | Workout title, duration, today's adjustment, compact exercise prescriptions, Start Workout; Edit Template secondary | Preserve hard exclusions and planner validity. Explanation may expand. Exercise names wrap. |
| Active Workout / W02–W06 | Close/title/Finish; elapsed time and set progress; exercise name/position; Technique; compact progression Apply/Why; set table Set/Previous/Weight/Reps/Complete; notes; bottom rest accessory | Complete set opens rest state; Skip ends rest. Finish validates entries and confirms saved completed sets. Error stays near invalid set. At AX sizes each set is a labeled vertical editor. Closing preserves autosave. |
| Nutrition / N01, N04, N05, N23, N24, N26, N28–N32 | Date selector; training/rest and estimated-target label; remaining calories large; logged/target; protein remaining; Log Food; Weigh In. Linear macro rows. Meal rows. Source/completeness/effective date. Pending adjustment below daily task. Small recovery context. | No target → Setup. No intake → Not logged, unknown macros, completion unavailable. Health missing macros → Unknown. Completed state offers supported reopen. Post-save totals reflect actual selected source. Pending/scheduled targets show dates. |
| Nutrition Setup / N02, N02B, N02C | Group body/units/activity/goal, optional composition, then training frequency/duration/experience and goal-valid protein/calorie/cycling controls | Show supported options only; bounded sliders use code ranges. Muscle group emphasis explains training stimulus, never selective nutrition. Validation inline; preserve entered data. |
| Target Review / N03, N03C | Estimated maintenance + uncertainty band; proposed daily target; macro grams/percent/ranges; formula explanation; eligibility/context; confirm initial target or edit current profile | Distinguish initial creation from current target history. Do not label estimates as measured. Display formatting follows existing model. |
| Log Food / N06 | Sheet title. Capture: Take Photo, Choose Photo. Find/Enter: Search Foods, Enter Nutrition Label. Reuse: Recent & Favorites. Advanced: Daily Totals. | Large full-row targets, no nested menu to discover camera. Cancel returns unchanged. |
| Camera / N07, N07U, N08, N08R | Native camera framing with Cancel/shutter; captured review Retake/Use Photo | Denied → Open Settings plus manual alternatives. Unavailable → manual/library. Do not invent a real camera feed in prototype. |
| Photo Ready / N08P | Accepted image; explicit Identify Food on Device; manual entry with photo alternative | Accepting image does not start inference. Explain local processing and review requirements. |
| Recognition / N09, N09U, N09F | Meal image; Looking for foods…; indeterminate spinner; concise explanation of suggestions and required review | No fake percentage. Unavailable/failed results offer manual entry and retain image. Reduce Motion keeps status clear without decorative animation. |
| Review Foods / N10I, N10A, N10, N11 | Photo; candidate rows with name, Suggested from photo, estimated grams; unmatched rows use Find/Match Food; matched rows show catalog name/source and nutrients; Change Match/Edit Portion/Remove; Add Missing Food; omissions note; Continue | Never show raw AI confidence as nutrient accuracy. Clarifying questions remain visible. Unresolved candidates continue to block final saving. Candidate VO reads name, provenance, portion and trusted nutrients only when available. |
| Food Search / N12, N12C | Native searchable list; food name + catalog source; compact result rows | Empty/error state retains query and manual fallback. Selection opens portion editor. No macro table on every result. |
| Portion / N13, N13R, N13E | Food name; grams/available household unit; live catalog preview; source and Estimated portion/Edited by you; Done | Existing entry edits scale confirmed nutrients when grams change; nutrient edits become manual. Decimal keyboard and explicit units. |
| Meal Editor / N14, N14R, N14E | Meal name/date/time/photo; food rows with quantities/calories/protein and edit; Add Food; total macro strip; final checked-foods/portions/preparation confirmation; Save Meal | Unchecked/unmatched/empty → Save disabled. Food add/edit/delete and changed photo results reset review; name/date and unresolved-candidate removal do not. Save error retains fields while open; Cancel discards unsaved editing. Future meal date is not permitted by current editor. |
| Label / N15, N15S | Food name, portion amount, whole-portion calories/protein/carbs/fat; label/manual provenance context; all four known confirmation; Add to Meal | No invented OCR, barcode or per-serving calculation. Unknown values must not be entered as zero. |
| Recent/Favorites / N16 | Two list sections, name/date/calories/protein; tap to review copied entries | Preserve original record, create a new draft. No unconfirmed one-tap Repeat without Undo. |
| Intake Source / N17 | Single-select rows: Logged Meals, each supported Health source, Manual Totals; concise anti-double-counting explanation | Missing Health macros remain Unknown. A source change resets completeness; meals remain saved. |
| Manual Totals / N18 | Entire-day values, explicit units; explanation that this source replaces meal/Health totals; all-four-known confirmation; Save | All four values required by current model; zero asserts none. Save failure retains input. |
| Weigh In / N19 | Date, weight and optional waist/hips/arm/thigh in configured units; Save | Neutral styling; accessible labels include units; no inferred health judgment. |
| Adjustment / N20, N20E, N21, N31 | +100 kcal example; current/proposed/effective date; evidence summary; Apply Tomorrow; Keep Current; How Calculated; scheduled receipt | Reject stale/unsafe proposal in model. Acceptance never silently changes today's target. |
| What-If / N22, N21S, N31S | Persistent scenario banner; calorie-delta slider, goal-valid protein g/kg slider, cycling toggle; average/training/rest calories and macros; Apply Tomorrow; Reset | No predicted pounds of muscle or fat. Show safety constraints. Scheduled state uses this scenario's actual values. |
| Nutrition options / N27 | Compact destinations for profile/current target, What-If, sources and history | Keeps daily logging focused without hiding advanced capabilities. |
| Recovery Progress / G01 | Recovery selector; takeaway; date range; sleep, HRV and RHR trends; source/coverage and accessible summary; detail | Missing dates remain gaps, no interpolated certainty. Empty/loading/query failure states distinguish no evidence from zero. |
| Training Progress / G02 | Sessions/sets/training-days summary; estimated strength; exercise picker; chart; recent performance; workout history | Estimated 1RM stays labeled. Empty history guides first workout; no misleading trend from one point. |
| Nutrition Progress / G03–G06 | Takeaway; weight trend; calories vs effective target; protein adherence; measurements; target/adjustment history | Incomplete days explicit. Historical revisions retained. Scenario and adaptation receipts use distinct fixtures. |
| Settings / S01 | Form sections: Connections; Personalization; Data; Privacy & Safety; About | Settings is not a sixth tab. Rows support long labels and Dynamic Type. No raw diagnostics on landing. |
| Health Sources / S02–S04 | Status, guidance confidence, recovery signals, source selection, freshness/coverage and allowed display/use controls; signal detail; separate Diagnostics | Query failures are actionable; no read-permission certainty inferred from missing Health data. Technical IDs only in diagnostics. |
| Calendar Setup / S05–S08 | Landing summaries for Planning / Workout Details / Busy Sharing, each with Change; separate selection screens | Planning multi-select/all-visible; details single writable destination; Busy multi-select with conflict explanation. Never silently redirect writes. |

Important states have Light/Dark counterparts in the design. The QA page contains large-text layouts for Today, Plan, Train, Nutrition, active sets, recognition review, Progress and Settings. These demonstrate reflow intent; native VoiceOver and keyboard behavior require implementation testing.

## 7. Figma component architecture

Preserve the Penpot conceptual structure: 00 Cover, 01 Foundations, 02 Components, 03 Patterns, 04 Main Screens, 05 Nutrition & Camera Flow, 06 User Flows, 07 Prototype, 08 Engineering Handoff, 09 QA & States.

In Figma, use collections `Color` (Light/Dark/contrast modes), `Spacing`, `Radius`, and `Type`; semantic aliases reference base values. Build component sets with properties such as `emphasis`, `status`, `selected`, `disabled`, `loading`, `source`, and `sizeClass`. Avoid separate hand-edited screen palettes. Penpot currently uses linked library components and mode-specific tokens; this is not a claim that Figma variant/property objects already exist.

Core components: primary/secondary/tertiary/destructive actions, status, issue, section header, empty/loading/success, five tab-bar selections, date control, connection/settings rows. Domain components: decision/recovery/fuel/next-up, timeline/receipt rows, active/template/set/progression/rest, nutrition summary/macro/meal/provenance/candidate/match/portion/source/day/adjustment/scenario/measurement, chart headers/metric summaries/history.

Use vertical Auto Layout for content, nested horizontal layouts for rows, Fill container text and Hug content height. Only icons and touch targets need stable minimum dimensions. At accessibility sizes, swap set tables and metric columns for vertical components. Standard Penpot artboards use editable component composition; accessibility examples demonstrate flexible stacked layout. Native controls, not fixed screen coordinates, govern the eventual SwiftUI implementation.

## 8. Prototype specification

Page 07 contains four named starts and a Start Here board: Daily workout, Food photo, Tomorrow plan, Target adjustment. Tabs and progress-domain controls are linked. The static recognition demo advances after a short delay; it does not claim a real percentage or inference duration. Secondary setup/source/scenario routes extend the core journeys.

Transitions should be immediate or native push/sheet transitions. Reduce Motion removes travel effects. A prototype click is a navigation demonstration, not a persistence or safety test. Forms, sliders, permissions, camera, timers and charts use fixtures; no health values should be inferred from them.

Review criteria: can a new user find Start/Resume, Log Food and Apply; understand estimated vs confirmed values; recover from unavailable AI; identify what will be scheduled; and locate the future effective date of an accepted target? Validate these tasks with people before treating the design as usability-proven.

## 9. Engineering handoff recommendations

| Order / files | Implementation | Why / verification |
|---|---|---|
| 1 · `DesignSystem.swift`, `RootView.swift` | Semantic styles, common actions/status/rows; preserve five TabView destinations and separate NavigationStacks | Establish consistency before migrating screens. Check Dynamic Type, contrast and selected-tab semantics. |
| 2 · `DashboardView.swift`, `TodayWorkoutRecommendationView.swift` | Decision-first Today, grouped evidence, compact fuel/next-up | Keep deterministic candidate validity and existing draft protection. Verify Start vs Resume routing. |
| 3 · `NightPlanView.swift`, calendar settings in `SettingsView.swift` | Timeline, focused destinations, exact confirmation and receipt views | Exercise success, partial write, destination repair and owned-only Undo paths. |
| 4 · `WorkoutsView.swift`, `ExerciseLibraryView.swift` | Compact template rows, preview, focused logger and AX set editor | Verify previous data, unit conversion, autosave, discard, rest and finish validation. |
| 5 · `NutritionView.swift`, `NutritionSetupView.swift` | Daily hierarchy, launcher, source/completeness, setup grouping and review | No engine/schema rewrite. Verify no-intake/unknown and future revision states. |
| 6 · `FoodCaptureView.swift`, `MealEditorView.swift` | Explicit recognition, unmatched review, shared editor, final confirmation and copied-meal review | Add state-transition tests for edits resetting review and repeated meals creating a fresh record. Physical-device camera/recognition acceptance required. |
| 7 · `NutritionWhatIfView.swift`, `NutritionProgressView.swift`, `ProgressView.swift` | Scenario banner, native sliders, unified progress entry, accessible chart summaries and historical targets | Use engine outputs and formatters; validate missing data and target effective dates. |
| 8 · `SettingsView.swift`, `DataSourcesView.swift` | Normal configuration separated from diagnostics | Preserve privacy/source semantics and no-silent-redirection rules. |

Mappings: TabView/NavigationStack for roots; ScrollView/LazyVStack for Today, Plan and Nutrition; List for saved workouts/search; Grid and safeAreaInset for active sets/rest; Form for editors/settings; sheet for launchers and weigh-in; PhotosPicker/native camera bridge; Swift Charts for trends; confirmationDialog for exact confirmation and destructive actions; SF Symbols for functional runtime icons.

No database migration, backend, account system or third-party package is required for this presentation redesign. Keep `AppModel`, `NutritionModel`, the engines, catalog, stores and platform integration services authoritative. New reusable presentation views can be extracted as each existing screen migrates. Do not start a large rewrite until the major Penpot screens are visually reviewed.
