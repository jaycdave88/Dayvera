# Dayvera implementation status

Last updated: 2026-09-05

## Dayvera nutrition release

The current project is a native iPhone SwiftUI app targeting **iOS 27**. Its five tabs are **Today, Plan, Train, Nutrition, Progress**. The project, module, shared scheme, app name, icon, documentation, and GitHub remote use Dayvera. Installed-app identifiers and persisted ownership keys remain compatible with existing installations; see [REBRAND.md](REBRAND.md).

- Nutrition includes adult profile setup, four goals, calorie and macro ranges, uncertainty explanations, muscle priorities, current intake, recovery context, 7/28-day weight/intake/protein-adherence charts, measurements, reviewed adjustments, and what-if scenarios.
- Meals support camera/Photos import, on-device structured food candidates, explicit database matching and portion review, manual label values, favorites, repeat/edit/delete, and local photos. The bundled USDA SR Legacy catalog contains 7,793 complete nutrient records; model output never supplies authoritative nutrients.
- Dietary Health access is optional and independent of existing recovery reads. Exactly one intake source counts each day; missing macros remain unknown, failed imports clear stale totals, and completeness must be confirmed.
- SwiftData adds five record types. Existing workout entity schemas remain unchanged. A database produced by the original module verifies migration, workout identity and Health-export continuity.
- The nutrition-release simulator baseline passed **209 tests with zero failures**, including original-store migration, macro conservation, source separation, missing-data handling, and illness-related target safeguards. The later Penpot-aligned integrated suite is recorded below.
- The final unsigned Release build succeeded against the iOS 27 physical-device SDK. The Debug simulator app installs and launches successfully; dark and Accessibility Extra Large light layouts were inspected.
- Xcode 27 beta 6 and the iOS 27 simulator SDK compile the Apple Foundation Models image attachment and guided-generation APIs used here. Runtime model availability remains device-dependent.
- Current nutrition captures are in [QA/README.md](QA/README.md). All captured data are synthetic.

## Launch, navigation and light motivation update

The current source implements the Penpot-approved launch and retention direction without introducing rigid streaks or a reward economy:

- A static adaptive `UILaunchScreen` background resolves directly into the app. There is no post-launch logo animation, fake progress or artificial delay.
- First launch retains the concise guided setup. Health, Calendar, alarm and camera requests remain contextual to the feature that needs them.
- Returning users reach Today immediately. After seven days, a dismissible welcome message offers a simple path back; after 30 days, it also explains that recent trends may need more data.
- Today includes Weekly Rhythm: completed sessions against the user's weekly session target, explicitly completed nutrition days, neutral recovery-data coverage, and four-week training momentum when available.
- Meeting the weekly training plan can show one contextual milestone per week. Acknowledgement is local and protected. The app has no daily streak, points, levels, badge collection, leaderboard or loss-framed reminder.
- Routine nutrition completion uses restrained native success feedback. Essential confirmation remains visible and does not depend on motion, haptics or color.

Targeted tests cover return classification, session-based weekly summaries, unique recovery-day coverage, prior-week momentum and motivation-state persistence. The complete simulator suite passed **213 tests with zero failures or skips** on an iPhone 17 Pro running iOS 27.0. The integrated interface build installed and launched successfully, and the current five-tab, active-workout, Log Food, recovery-progress, and Settings surfaces were visually inspected.

### Device acceptance remaining for this release

A connected iOS 27 phone was discovered, but its device identifier did not match any existing locally provisioned build. The machine has multiple development signing teams, so this release has not been installed onto that phone. Select the appropriate team in Xcode for a device build. Camera permission, real meal recognition/portion review, Apple Intelligence availability/download, dietary Health permissions/imports, and upgrading an existing installation still need hands-on acceptance. Simulator tests do not certify those system interactions or food-recognition accuracy.

The inspected Penpot-aligned captures are indexed in [QA/README.md](QA/README.md). They cover all five tabs plus Log Food, Active Workout, Recovery Progress, and Settings. Light Mode, Accessibility Extra Large, Increase Contrast, return-after-absence, and real recognition-result captures remain follow-up acceptance evidence.

The installed Xcode 26.6 toolchain supplies the iOS 26.5 SDK, which does not expose the iOS 27 Foundation Models vision symbols used by `AppleFoodRecognitionService`. For local simulator integration only, the service was temporarily replaced with an unavailable-capability fallback; the checked-in production source was restored immediately afterward and has no compatibility-stub diff. This validated the surrounding UI, persistence, and fallback paths. A clean production build and real photo-recognition run still require Xcode 27 and a supported physical device.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the integration and file map, and [NUTRITION.md](NUTRITION.md) for formulas, evidence requirements and safety constraints.

## Historical recovery and training baseline

The following sections record the pre-nutrition iOS 26 release. Their test counts, device installs and screenshots are historical evidence, not validation of the iOS 27 nutrition release.

- Primary navigation is exactly **Today, Plan, Train, Progress**. Settings is in Today’s toolbar; the exercise library is in Train.
- Recovery and training trends live under Progress with 7D/28D controls.
- Today leads with a concrete, validated workout selected from exactly three options: recommended, shorter, and alternate focus. The deterministic planner uses the user’s goal, weekly target, available time, equipment, exclusions, enabled recovery signals, and local training history. Low confidence, high recent load, a reached weekly target, and low recovery conservatively reduce the training envelope. Progression suggestions are optional and require confirmation; weights never change automatically.
- Optional Foundation Models personalization is explicitly opt-in and on device. It can rank only the three validated plans and write a short explanation; it cannot invent exercises or alter recovery, duration, equipment, exclusion, progression, or volume rules. The deterministic result remains available when the model, consent, power, or thermal state prevents personalization.
- Plan works backward from the first hard commitment across the user’s selected calendars. One writable destination can receive the detailed workout; any number of other writable destinations can receive a neutral `Busy` copy with no health or workout content. Apply stays immediately reachable, persists destination-specific receipts, supports independent Undo, and requires an exact confirmation before changing anything. Calendar read failures show the fallback reason, overlapping refreshes coalesce into a final pass, and foreground refresh reconciles every app-owned item. The optional energy guide is labeled as a wake-relative heuristic.
- Train supports new/edit/delete templates, catalog multi-select, custom exercises, editable sets/reps/load/RPE/rest, reordering, readiness-adjusted starts, rest timing, autosaved active drafts, resume/save-and-close/discard/finish, and completed history. The active logger uses previous/load-unit/reps/completion columns, copy-previous controls, protected exercise removal, and a persistent rest bar. Today cannot overwrite an unfinished workout; it routes the user back to the current draft. Resuming a draft older than six hours keeps its sets and notes but restarts the timer so an accidental multi-day Health workout cannot be exported.
- A template with an active draft cannot be edited underneath that draft.
- Training progress reports period sessions/working sets and per-exercise top-set estimated 1RM/PBs. Load values retain their original lb/kg unit and are converted before cross-session comparison. Local history informs exercise familiarity, muscle recency, weekly load, and optional progression suggestions.

## Health and metrics implementation

- Apple Health is the boundary for Eight Sleep and Hume. The app does not depend on private vendor APIs or fabricate proprietary vendor scores.
- Source labels are retained. Fresh Eight Sleep is preferred for overnight sleep; stale Eight Sleep does not displace fresher data.
- Data & Sources exposes independent controls for Today visibility, recommendation inclusion, ordering, Automatic/manual source selection, and manual-source fallback. Existing saved preferences migrate to the previous defaults.
- Each signal reports the source used now, the selection or fallback reason, freshness, exact latest observed sample, 7/28-day coverage, and actual baseline depth. All observed source bundles remain inspectable.
- HealthKit’s versioned read registry contains 16 types. Sleep, HRV, and resting heart rate can influence readiness; respiratory rate, oxygen saturation, sleeping wrist temperature, body temperature, and raw heart rate are conservative safety-only checks; workouts, active energy, exercise time, steps, body mass, body-fat percentage, lean body mass, and BMI are training or progress context. Completed strength workouts use a separately requested write permission.
- Immediate background delivery intentionally observes only the three low-frequency decision signals: sleep, HRV, and resting heart rate. Any of those updates triggers the full bounded 16-type refresh; foreground and explicit refreshes do the same. This avoids wake storms from raw heart-rate, step, energy, workout, and body-measurement updates.
- Automatic launch, foreground, and observer failures remain non-modal and are surfaced in Health status and Data & Sources. Explicit Connect, Review Health Access, and manual refresh actions may surface an actionable error. Observer callbacks never recursively re-register themselves.
- Provider observations list the exact metric types actually received from Eight Sleep, Hume/FitTrack, and Apple Watch provenance. A missing row never claims that a device lacks support or that read access was denied.
- Body measurements are progress context only and never change readiness, safety gates, or today’s workout. Apple Health workout imports can affect seven-day session frequency only; they never invent muscle-group recency, working-set volume, or progression history.
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
- AlarmKit and EventKit writes are scoped to the app-owned wake alarm and destination-specific detailed/Busy calendar items and require user confirmation. Persisted applied-plan receipts are checked against the actual system items after foregrounding and cannot remain a false green state after external deletion, destination changes, or a one-shot alarm firing.
- The bundled privacy manifest declares no tracking or developer-collected data and records the required-reason use of UserDefaults and file timestamps. Health-adjacent preferences and applied-plan state migrate from legacy UserDefaults into backup-excluded, protected Application Support files.

## Exercise catalog implementation and guardrails

- `Dayvera/Domain/ExerciseCatalogModels.swift`, `Dayvera/Services/ExerciseCatalogStore.swift`, `Dayvera/Views/ExerciseLibraryView.swift`, and `DayveraTests/ExerciseCatalogTests.swift` are integrated into the Xcode project.
- The official RepDB free-tier JSON at `https://exercise-dataset.com/exercises.json` is decoded with schema/version, count, identifier, strength-category, and HTTPS media-host validation. The QA snapshot contained 491 strength exercises.
- Search covers names and descriptive metadata. Browse mode has A–Z sections plus equipment, muscle, and level filters; selection mode supports adding multiple entries to a template while preventing duplicate catalog IDs.
- Catalog exercises retain `catalogID` through templates, active drafts, completed sets, and exercise-specific progress while keeping an editable local prescription snapshot.
- Legacy active drafts with missing catalog IDs are backfilled from their template on restore, preserving exercise identity and progress continuity.
- Catalog metadata is fetched at runtime and cached atomically in Application Support. Illustrations use URLCache plus an in-memory image cache. Personal health/workout data are not sent with catalog requests.
- Required visible credit is present in the library, exercise detail, and Settings: `Exercise data by RepDB (repdb.co)`. `THIRD_PARTY_NOTICES.md` links the exact RepDB data license.
- The dataset is not committed or republished. RepDB media are not used as generative-AI inputs.
- The free tier supplies still illustrations. Start and Finish are labeled as positions. Two-position preview only alternates those two stills, explicitly says it is not full-motion video, and is unavailable with Reduce Motion. Do not add RepDB premium preview animations without a separate license.
- `yuhonas/free-exercise-db` media remain excluded pending provenance clarification. wger content remains excluded without per-entry license/attribution filtering. LongHaul Fitness remains a metadata-only fallback.

## Historical baseline QA evidence

- An iOS 26 Simulator build succeeded after catalog, navigation, metrics, and workout integration.
- The final release-candidate suite ran **195 tests with zero failures or skips**. The result bundle identifies an iPhone 17 Pro simulator on iOS 26.0.1, confirming that the final run did not target the connected phone. A preceding integrated build also passed 185 tests on the development iPhone before the last launch-hardening and Calendar edge-case tests were added.
- Focused final suites passed 24/24 HealthKit lifecycle tests, 29/29 Calendar tests, and 4/4 independent Calendar-review regressions. A fresh simulator build succeeded after the functional and UI audit fixes; the current integrated Swift source is green.
- Final unsigned Debug and Release builds both succeeded against the physical iOS 26 device SDK with signing disabled, static analysis passed, and a current signed Debug device build succeeded.
- A clean Release archive succeeded, and its shipped app executable contained no machine-specific absolute source paths. Debug symbols remain in the separate dSYM rather than the app bundle.
- Visual inspection was completed on the iPhone 17 Pro iOS 26 simulator for first run, Today’s generated workout, adjustment, all three options, workout detail, Plan, applied Plan, multi-calendar setup, Train, active workout, Exercises, exercise detail, template library selection, both Training and Recovery progress, Settings, Data & Sources, and per-signal source controls in dark mode.
- Compact-width inspection was completed on an iPhone SE (3rd generation) iOS 26 simulator in light mode for Plan, multi-calendar setup, Train, and Exercises.
- Accessibility inspection was completed on the compact simulator for Today, Plan, active workout, Exercises, Training progress, and Data & Sources. An additional Increase Contrast pass was completed on Today. Screens remain scrollable, controls remain reachable, and major navigation titles switch inline at accessibility sizes.
- Layouts use Dynamic Type-aware stacking, 44-point interactive targets, semantic labels for charts and controls, explicit non-color status text/symbols, dark/light adaptive colors, and Reduce Motion behavior for exercise preview.
- The post-fix capture set is stored in `QA/Screenshots`; `QA/README.md` provides the current gallery index.
- The workspace root was refreshed with `zg index . --mode auto`; fresh zvec-grep audits covered health/planning, catalog/workout identity, navigation, accessibility, and licensing.

## Historical baseline physical-device deployment

- A development iPhone running iOS 26 was previously verified over USB with pairing, Developer Mode, and developer disk-image services available. Machine-specific device details are intentionally omitted from this public repository.
- Xcode's iOS 26.5 platform support (23F77, 8.52 GB) was downloaded and installed, resolving the prior device-platform mismatch.
- The app and test targets use automatic signing. The public project intentionally leaves `DEVELOPMENT_TEAM` blank; choose a local team in Xcode before the next phone deployment. The bundle identifiers are `com.momoai.personalassistant.sleepcoach` and `.tests`, and HealthKit capability metadata is declared alongside the entitlements.
- Automatic provisioning registered the development phone and generated a profile containing the HealthKit and HealthKit background-delivery entitlements. Provisioning profiles and certificates are excluded from version control.
- Signed physical-device builds use the local development identity without writing its team or device identifiers into the public project. The final release candidate was signed, installed, launched exactly once, and remained alive after the startup observation window. No new Dayvera crash diagnostic was produced; the earlier repeated open/close behavior was XCTest repeatedly launching and terminating its host, not an application crash loop.
- Clean simulator and unsigned Release device-SDK builds also succeeded after the project-signing changes.

## Simulator fixtures

Current nutrition QA uses an iPhone 17 Pro simulator on iOS 27. The historical baseline used iOS 26 and compact-width fixtures. Their machine-specific UUIDs are intentionally omitted; use `xcrun simctl list devices available` and the portable commands in `DEVELOPMENT.md`.

Debug builds support deterministic `--demo-data`, `--demo-health-partial`, `--demo-applied-plan`, `--tab=<today|plan|train|nutrition|progress>`, `--show-data-sources`, `--show-calendar-setup`, `--show-signal-source=<metric>`, `--show-exercise=<repdb-id>`, `--show-template-editor`, `--show-template-library`, `--show-active-workout`, `--show-workout-adjustment`, `--show-workout-options`, `--show-workout-detail`, `--show-generated-workout`, `--show-progress`, and `--show-recovery-progress` routes. Legacy `--tab=exercises` and `--tab=settings` remain QA shortcuts to the nested destinations. See `DEVELOPMENT.md` for commands and prerequisites.

All `--show-…` routes self-select their required tab. A paired `--tab` argument is optional.

## Historical baseline audit fixes

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
- Multiple Calendar roles are explicit: selected calendars inform planning, one receives workout details, and optional destinations receive only a neutral Busy event. Ambiguous EventKit identities and missing detailed replacements fail closed.
- Active workout logging now keeps the load unit visible, formats long resumed timers as hours, and uses a non-action-like “Keep” progression state.

## Reproducible simulator validation

The green simulator suite is run with:

```sh
xcodebuild test \
  -project Dayvera.xcodeproj \
  -scheme Dayvera \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=<SIMULATOR-UDID>' \
  -derivedDataPath /private/tmp/DayveraSignedTests \
  SDKROOT=iphonesimulator
```

## Recovery and training acceptance still remaining

On the development iPhone, complete hands-on runtime acceptance for real Eight Sleep/Hume/Apple Watch samples and exact source attribution; first-run, limited-history, revoked, and restored HealthKit access; stale and mixed-source fallback; saving a finished workout to Health; Calendar authorization/event creation across timezone and DST changes; and an approved AlarmKit wake alarm firing.

Automated simulator and physical-device QA validate layout fixtures, navigation, persistence, algorithms, catalog networking/cache behavior, deterministic lifecycle flows, signing, installation, and launch. Manual acceptance is still required for real vendor sync timing, Apple-controlled HealthKit permission sheets and data provenance, and an AlarmKit alert firing on hardware.
