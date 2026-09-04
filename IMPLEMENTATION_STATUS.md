# Sleep Coach implementation status

Last updated: 2026-09-04

## Current state

The iOS 26 simulator scope is implemented and integrated. The project is a native, iPhone-only SwiftUI app with an iOS 26.0 deployment target.

- Primary navigation is exactly **Today, Plan, Train, Progress**. Settings is in Today’s toolbar; the exercise library is in Train.
- Recovery and training trends live under Progress with 7D/28D controls.
- Today leads with a concrete, validated workout selected from exactly three options: recommended, shorter, and alternate focus. The deterministic planner uses the user’s goal, weekly target, available time, equipment, exclusions, enabled recovery signals, and local training history. Low confidence, high recent load, a reached weekly target, and low recovery conservatively reduce the training envelope. Progression suggestions are optional and require confirmation; weights never change automatically.
- Optional Foundation Models personalization is explicitly opt-in and on device. It can rank only the three validated plans and write a short explanation; it cannot invent exercises or alter recovery, duration, equipment, exclusion, progression, or volume rules. The deterministic result remains available when the model, consent, power, or thermal state prevents personalization.
- Plan works backward from the first hard Calendar commitment, leads with a schedule-based outcome, keeps Apply immediately reachable, persists the applied alarm/event status with Undo, and requires confirmation before changing anything. Calendar read failures show the fallback reason, overlapping refreshes coalesce into a final pass, and foreground refresh reconciles the saved state with the actual app-owned alarm and event. The optional energy guide is labeled as a wake-relative heuristic.
- Train supports new/edit/delete templates, catalog multi-select, custom exercises, editable sets/reps/load/RPE/rest, reordering, readiness-adjusted starts, rest timing, autosaved active drafts, resume/save-and-close/discard/finish, and completed history. Today cannot overwrite an unfinished workout; it routes the user back to the current draft. Resuming a draft older than six hours keeps its sets and notes but restarts the timer so an accidental multi-day Health workout cannot be exported.
- A template with an active draft cannot be edited underneath that draft.
- Training progress reports period sessions/working sets and per-exercise top-set estimated 1RM/PBs. Load values retain their original lb/kg unit and are converted before cross-session comparison. Local history informs exercise familiarity, muscle recency, weekly load, and optional progression suggestions.

## Health and metrics implementation

- Apple Health is the boundary for Eight Sleep and Hume. The app does not depend on private vendor APIs or fabricate proprietary vendor scores.
- Source labels are retained. Fresh Eight Sleep is preferred for overnight sleep; stale Eight Sleep does not displace fresher data.
- Data & Sources exposes independent controls for Today visibility, recommendation inclusion, ordering, Automatic/manual source selection, and manual-source fallback. Existing saved preferences migrate to the previous defaults.
- Each signal reports the source used now, the selection or fallback reason, freshness, exact latest observed sample, 7/28-day coverage, and actual baseline depth. All observed source bundles remain inspectable.
- HealthKit initially reads only Sleep, HRV, and resting heart rate; completed strength workouts use write-only workout permission.
- Background-delivery observers cover all three read metrics. A setup failure is surfaced in Data & Sources and can be retried with Refresh instead of being silently ignored.
- Finished workouts save locally before export. Pending, failed, exported, and unverifiable legacy states persist in Training History; pending/failed exports can be retried with a stable HealthKit sync identifier and increasing version so retries replace rather than duplicate a workout.
- Connection labels distinguish Not requested, Access requested, Data received, Partial data, No readable samples, and Refresh failed. A successful empty read is not mislabeled as authorization denial because HealthKit intentionally withholds that distinction.
- Per-type HealthKit query failures are retained and surfaced. Partial data still produces a deliberately lower-coverage result; a total query failure clears the previous recommendation and diagnostics rather than leaving them looking current.
- Recommendation confidence is explicitly separated from source status and data coverage, and the UI states that it is not sensor accuracy or clinical certainty.
- Health queries are bounded, naps are not promoted to overnight sleep, and overlapping sleep-stage intervals are merged rather than double-counted.
- HRV and resting-heart-rate comparisons use a 21-day same-source median. Trends preserve missing calendar days as gaps and expose freshness, completeness, and insufficient-baseline states.
- Sleep status labels and supporting copy now share one threshold model, including a regression test for a 33-minute shortfall near target.
- Recovery progress includes sleep versus target, HRV/RHR deviation, and same-source sleep-timing variability.
- Health and Calendar refresh on foreground activation. Concurrent refresh requests queue one final pass instead of being dropped. First-run state does not claim Health is connected before authorization.
- A planning commitment must start inside the requested calendar day; an event that began the prior day but overlaps midnight no longer displaces that day’s first commitment.
- AlarmKit and EventKit writes are scoped to the app-owned wake alarm and gym event and require user confirmation. Persisted applied-plan status is checked against the actual system items after foregrounding and cannot remain a false green state after external deletion or a one-shot alarm firing.
- The bundled privacy manifest declares no tracking or developer-collected data and records the required-reason use of UserDefaults and file timestamps. Health-adjacent preferences and applied-plan state migrate from legacy UserDefaults into backup-excluded, protected Application Support files.

## Exercise catalog implementation and guardrails

- `SleepCoach/Domain/ExerciseCatalogModels.swift`, `SleepCoach/Services/ExerciseCatalogStore.swift`, `SleepCoach/Views/ExerciseLibraryView.swift`, and `SleepCoachTests/ExerciseCatalogTests.swift` are integrated into the Xcode project.
- The official RepDB free-tier JSON at `https://exercise-dataset.com/exercises.json` is decoded with schema/version, count, identifier, strength-category, and HTTPS media-host validation. The QA snapshot contained 491 strength exercises.
- Search covers names and descriptive metadata. Browse mode has A–Z sections plus equipment, muscle, and level filters; selection mode supports adding multiple entries to a template while preventing duplicate catalog IDs.
- Catalog exercises retain `catalogID` through templates, active drafts, completed sets, and exercise-specific progress while keeping an editable local prescription snapshot.
- Legacy active drafts with missing catalog IDs are backfilled from their template on restore, preserving exercise identity and progress continuity.
- Catalog metadata is fetched at runtime and cached atomically in Application Support. Illustrations use URLCache plus an in-memory image cache. Personal health/workout data are not sent with catalog requests.
- Required visible credit is present in the library, exercise detail, and Settings: `Exercise data by RepDB (repdb.co)`. `THIRD_PARTY_NOTICES.md` links the exact RepDB data license.
- The dataset is not committed or republished. RepDB media are not used as generative-AI inputs.
- The free tier supplies still illustrations. Start and Finish are labeled as positions. Two-position preview only alternates those two stills, explicitly says it is not full-motion video, and is unavailable with Reduce Motion. Do not add RepDB premium preview animations without a separate license.
- `yuhonas/free-exercise-db` media remain excluded pending provenance clarification. wger content remains excluded without per-entry license/attribution filtering. LongHaul Fitness remains a metadata-only fallback.

## QA evidence completed

- An iOS 26 Simulator build succeeded after catalog, navigation, metrics, and workout integration.
- The release-candidate suite ran **124 tests with zero failures or skips** on both an iPhone 17 Pro iOS 26 simulator and the connected development iPhone before it was unplugged.
- A fresh simulator build also succeeded after all functional and UI audit fixes. The current integrated Swift source is green.
- Final unsigned Debug and Release builds both succeeded against the physical iOS 26 device SDK with signing disabled, static analysis passed, and a current signed Debug device build succeeded.
- A clean Release archive succeeded, and its shipped app executable contained no machine-specific absolute source paths. Debug symbols remain in the separate dSYM rather than the app bundle.
- Visual inspection was completed on the iPhone 17 Pro iOS 26 simulator for first run, Today’s generated workout, adjustment, all three options, workout detail, Plan, applied Plan, Train, active workout, Exercises, exercise detail, template library selection, both Training and Recovery progress, Settings, Data & Sources, and per-signal source controls in dark mode.
- Compact-width inspection was completed on an iPhone SE (3rd generation) iOS 26 simulator in light mode for Plan, Train, and Exercises.
- Accessibility inspection was completed on the compact simulator for Today, Plan, active workout, Exercises, Training progress, and Data & Sources. An additional Increase Contrast pass was completed on Today. Screens remain scrollable, controls remain reachable, and major navigation titles switch inline at accessibility sizes.
- Layouts use Dynamic Type-aware stacking, 44-point interactive targets, semantic labels for charts and controls, explicit non-color status text/symbols, dark/light adaptive colors, and Reduce Motion behavior for exercise preview.
- The post-fix capture set is stored in `QA/Screenshots`; `QA/README.md` provides the current gallery index.
- The workspace root was refreshed with `zg index . --mode auto`; fresh zvec-grep audits covered health/planning, catalog/workout identity, navigation, accessibility, and licensing.

## Physical-device deployment state

- A development iPhone running iOS 26 was previously verified over USB with pairing, Developer Mode, and developer disk-image services available. Machine-specific device details are intentionally omitted from this public repository.
- Xcode's iOS 26.5 platform support (23F77, 8.52 GB) was downloaded and installed, resolving the prior device-platform mismatch.
- The app and test targets use automatic signing. The public project intentionally leaves `DEVELOPMENT_TEAM` blank; choose a local team in Xcode before the next phone deployment. The bundle identifiers are `com.momoai.personalassistant.sleepcoach` and `.tests`, and HealthKit capability metadata is declared alongside the entitlements.
- Automatic provisioning registered the development phone and generated a profile containing the HealthKit and HealthKit background-delivery entitlements. Provisioning profiles and certificates are excluded from version control.
- Signed physical-device builds use the local development identity without writing its team or device identifiers into the public project. The latest release-candidate suite completed 124 tests with zero failures or skips on the connected phone before it was unplugged. Installation and hands-on permission/source acceptance resume when the phone is reconnected and unlocked.
- A clean simulator compile also succeeded after the project-signing changes.

## Current simulator fixtures

QA uses iPhone 17 Pro and compact-width iPhone simulators on iOS 26. Their machine-specific UUIDs are intentionally omitted; use `xcrun simctl list devices available` and the portable commands in `DEVELOPMENT.md`.

Debug builds support deterministic `--demo-data`, `--demo-health-partial`, `--demo-applied-plan`, `--tab=<today|plan|train|progress>`, `--show-data-sources`, `--show-signal-source=<metric>`, `--show-exercise=<repdb-id>`, `--show-template-editor`, `--show-template-library`, `--show-active-workout`, `--show-workout-adjustment`, `--show-workout-options`, `--show-workout-detail`, `--show-generated-workout`, `--show-progress`, and `--show-recovery-progress` routes. Legacy `--tab=exercises` and `--tab=settings` remain QA shortcuts to the nested destinations. See `DEVELOPMENT.md` for commands and prerequisites.

All `--show-…` routes self-select their required tab. A paired `--tab` argument is optional.

## Final audit fixes completed

- Sleep status/copy thresholds are consistent and regression-tested.
- Prior-day overlapping Calendar events are filtered out of the requested day’s commitment candidates.
- Compact-width and Accessibility Dynamic Type rows now stack where needed instead of crowding values or controls.
- Secondary and status text use stronger contrast against tinted surfaces.
- The Plan navigation title is shorter and consistent with the tab label.
- Debug detail routes self-select their tabs.
- Legacy active-draft catalog IDs are restored from their template and covered by an end-to-end identity regression test.
- Health source and recommendation trust are now user-controlled and separately explained instead of being collapsed into a generic Connected/High-confidence state.
- Initial Health authorization is read-only; workout write permission is requested contextually at completion. A setup error remains retryable instead of dismissing onboarding.
- Workout number pads have a Done control, set completion uses 44-point targets, and stale drafts cannot create multi-day workout durations.
- Workout loads retain their unit at the exercise, active-set, and completed-set boundaries. Legacy untagged loads are interpreted as pounds and converted before comparison, preventing a unit preference change from relabeling 100 lb as 100 kg.
- Recommendation consent is enforced before the normalized state is built; disabled sleep, HRV, or resting-heart-rate values cannot reach the planner, evidence list, or optional model.
- A generated workout cannot replace an autosaved workout already in progress.
- Calendar read failures, queued refreshes, applied-plan drift, background Health delivery, and idempotent workout-export retries have dedicated regression coverage.

## Reproducible simulator validation

The green simulator suite is run with:

```sh
xcodebuild test \
  -project SleepCoach.xcodeproj \
  -scheme SleepCoach \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=<SIMULATOR-UDID>' \
  -derivedDataPath /private/tmp/SleepCoachSignedTests \
  SDKROOT=iphonesimulator
```

## Remaining acceptance work

On the development iPhone, complete runtime acceptance for real Eight Sleep/Hume/Apple Watch samples and exact source attribution; first-run, limited-history, revoked, and restored HealthKit access; stale and mixed-source fallback; saving a finished workout to Health; Calendar authorization/event creation across timezone and DST changes; and an approved AlarmKit wake alarm firing.

Simulator QA validates layout, navigation, persistence, algorithms, catalog networking/cache behavior, and deterministic lifecycle flows. The next phone session still needs runtime acceptance for real vendor sync timing, HealthKit permission sheets and data provenance, and an AlarmKit alert firing on hardware.
