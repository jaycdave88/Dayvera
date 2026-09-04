# Sleep Coach

Sleep Coach is a private, local-first SwiftUI app for iPhone that turns Apple Health sleep and recovery data into an explainable training recommendation and plan for tomorrow morning. The project intentionally targets iOS 26.0 only.

The app is wellness software. It does not diagnose, treat, or determine whether exercise is medically safe.

## Current product

The primary navigation has exactly five tabs:

- **Today** leads with the answer to “How should I train today?”, provides one direct path into Train, then shows readiness, a concrete volume/effort/progression prescription, the user-selected recovery signals, and the strongest available drivers.
- **Plan** works backward from the first hard Calendar commitment to suggest bedtime, wake time, and gym timing. AlarmKit and EventKit changes occur only after confirmation. The optional energy guide is explicitly labeled as a wake-relative heuristic.
- **Train** shows today’s readiness adjustment, any resumable workout draft, user-created templates, one-tap starts, and Training History. Exercises remains the single top-level catalog destination except when reused as a template selector.
- **Exercises** provides a searchable A–Z strength catalog with equipment, muscle, and level filters; licensed illustrations; instructions; tips; and safety notes.
- **Settings** owns Apple Health, a dedicated Data & Sources center, integration status, privacy explanations, and third-party attribution. Plan owns its timing assumptions and contextual Calendar connection.

Trends are intentionally nested, not a sixth tab. Today opens **Recovery Trends**; Train opens **Training History**. Both support 7-day and 28-day windows.

The workout flow is:

1. Create a template from one or more catalog exercises, or add a custom exercise.
2. Review and edit sets, reps, load, target RPE, rest time, and exercise order. Catalog exercises start with a neutral load of zero because a public catalog cannot infer a safe personal weight.
3. Start the template with the day’s readiness-adjusted working-set prescription.
4. Log sets, use the rest timer, and let the active draft autosave.
5. Resume, save and close, discard, or finish the workout. Finished sessions feed workout history and per-exercise estimated-1RM/PB trends and can be saved to Apple Health.

## Metrics and data behavior

Apple Health is the integration boundary for Eight Sleep and Hume. Sleep Coach does not call private vendor APIs or invent vendor-only scores.

- A fresh Eight Sleep source is preferred for overnight sleep when present; stale preferred data does not displace a fresher source.
- Hume can contribute HRV and resting-heart-rate samples through Apple Health.
- Source names remain visible so a value can be traced to the app that wrote it.
- Today defaults to Sleep, HRV, and Resting Heart Rate. Users can independently show/hide, reorder, or include/exclude each signal from the workout recommendation.
- Each signal can use Automatic source selection or a specific source bundle observed in Apple Health. Automatic selection prefers fresh Eight Sleep for sleep and fresh Hume for HRV/resting heart rate, then falls back to the freshest readable source. Manual fallback is separately controllable.
- Each signal shows its current value, target or 21-day same-source median, freshness/status, coverage, baseline depth, selected source, and the reason for automatic/manual/fallback selection.
- HealthKit authorization is described honestly as Not requested, Access requested, Data received, Partial data, No readable samples, or Refresh failed. Independent query failures remain visible instead of being discarded, and a total query failure clears the prior recommendation rather than presenting it as current.
- Initial HealthKit read permission is limited to the three surfaced recovery metrics. Completed strength workouts remain a separate write permission.
- Recommendation confidence describes enabled-input availability and history depth. It does not claim read permission, vendor sync health, wearable accuracy, or clinical certainty.
- Status labels and their explanatory copy use the same thresholds, so a meaningful sleep shortfall is not simultaneously described as “On target.”
- Missing calendar days remain gaps rather than being interpolated. Insufficient, missing, and stale data have explicit states.
- Recovery trends separate sleep duration, HRV deviation, resting-heart-rate deviation, and sleep-timing variability. Training trends use per-exercise top working sets and estimated 1RM; the app does not present mixed-template aggregate tonnage as strength progress.

This hierarchy follows the same broad principle used in operational dashboards and explanatory data design: lead with the decision, emphasize comparison and change, and move supporting detail behind drill-down.

## Privacy and exercise-catalog networking

Sleep Coach processes and stores health, plan, template, workout, and draft data locally in its iOS app container. It has no Sleep Coach account, application server, advertising, analytics SDK, or app-managed cloud health-data sync. System backup behavior and an explicit Data Protection policy remain production-hardening work documented in `SECURITY.md`.

The only unrelated network content is the public exercise catalog and its illustrations. Health or workout data are never included with those requests.

The catalog uses the official [RepDB free-tier distribution](https://exercise-dataset.com/exercises.json), filters it to strength exercises, and validates its schema and identifiers. The upstream snapshot used during QA contained 491 illustrated strength exercises, including dumbbell, barbell, and kettlebell movements. Metadata is cached atomically in Application Support; images use URLCache and an in-memory cache.

RepDB requires visible attribution: [Exercise data by RepDB (repdb.co)](https://repdb.co). Its [dataset license](https://github.com/RepDB/exercise-dataset/blob/main/LICENSE-DATA.md) permits in-app use with attribution but not republishing the dataset as a standalone dataset or API. Accordingly, the catalog and media are fetched at runtime and are not committed to this repository. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The free distribution provides still illustrations, not production animation files. `Two-position preview` simply alternates the two licensed Start and Finish stills, says that it is not full-motion video, and is disabled when Reduce Motion is enabled. Shipping real technique video or animation requires separately licensed media.

## Run on a physical iPhone

Requirements: Xcode 26 or newer, an iPhone running iOS 26, and an Apple development team.

1. Install the iOS 26 platform in Xcode > Settings > Components.
2. Open `SleepCoach.xcodeproj`.
3. Select the `SleepCoach` target and choose your team under Signing & Capabilities.
4. Connect the phone, enable Developer Mode if prompted, choose it as the run destination, and run.
5. Enable Apple Health sharing in Eight Sleep and Hume.
6. Connect Apple Health during the optional guided setup, or later from Settings > Data & Sources.
7. Open Data & Sources to verify received samples, select sources, and choose which signals appear or affect the recommendation.
8. Connect Calendar from Plan only if you want Sleep Coach to add the proposed gym event.

Real Eight Sleep/Hume samples, first-run HealthKit authorization, writing a completed workout to Health, Calendar permissions, and an AlarmKit alarm actually firing must be accepted on a physical device. Simulator data proves UI and app logic, not those operating-system/vendor handoffs.

## iOS 26 Simulator QA

Use `xcrun simctl list devices available` to find a local iOS 26 simulator UUID. Simulator identifiers are machine-specific and intentionally not stored in the repository; substitute yours for `<SIMULATOR-UDID>` below.

Run the full unit suite on the iPhone 17 Pro fixture:

```sh
xcodebuild test \
  -project SleepCoach.xcodeproj \
  -scheme SleepCoach \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=<SIMULATOR-UDID>' \
  -derivedDataPath /private/tmp/SleepCoachSignedTests \
  SDKROOT=iphonesimulator
```

Build specifically for compact-width review on the iPhone SE fixture:

```sh
xcodebuild \
  -project SleepCoach.xcodeproj \
  -scheme SleepCoach \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=<COMPACT-SIMULATOR-UDID>' \
  -derivedDataPath /private/tmp/SleepCoachCompactSimulatorDerived \
  CODE_SIGNING_ALLOWED=NO SDKROOT=iphonesimulator build
```

Useful appearance and Dynamic Type checks are:

```sh
xcrun simctl ui <SIMULATOR-UDID> appearance dark
xcrun simctl ui <COMPACT-SIMULATOR-UDID> appearance light
xcrun simctl ui <COMPACT-SIMULATOR-UDID> content_size accessibility-extra-large
xcrun simctl ui <COMPACT-SIMULATOR-UDID> content_size large
```

### Deterministic debug routes

Debug builds support `--demo-data`, which replaces Health/Calendar/Alarm services with deterministic fixtures and seeds workout templates/history. Select a tab with `--tab=today`, `plan`, `train`, `exercises`, or `settings`.

Examples after installing a Debug build:

```sh
xcrun simctl launch --terminate-running-process \
  <SIMULATOR-UDID> \
  com.momoai.personalassistant.sleepcoach \
  --demo-data --skip-onboarding --tab=today

xcrun simctl launch --terminate-running-process \
  <SIMULATOR-UDID> \
  com.momoai.personalassistant.sleepcoach \
  --demo-data --skip-onboarding --show-template-library
```

Additional Debug-only routes:

- `--demo-health-partial` pairs with `--demo-data` to simulate an HRV query failure while the other Health reads succeed.
- `--show-data-sources` opens the Data & Sources center.
- `--show-signal-source=<sleep|heartRateVariability|restingHeartRate>` opens one signal's source controls.
- `--show-exercise=<repdb-id>` selects Exercises and opens a matching loaded catalog entry.
- `--show-template-editor` opens a new template.
- `--show-template-library` opens the catalog multi-select inside a new template.
- `--show-active-workout` starts the first seeded template.
- `--show-progress` opens Training History from Train.
- `--show-recovery-progress` opens Recovery Trends from Today.
- `--demo-applied-plan` pairs with `--demo-data` to apply the deterministic alarm/event through demo services and show the persistent Plan completion state.

Every `--show-…` route selects its required tab automatically; no matching `--tab` argument is required. Use `--demo-data` for deterministic health sources, templates, and history.

If Simulator services are unavailable, compile both targets against the iOS 26 device SDK without signing:

```sh
xcodebuild -project SleepCoach.xcodeproj -target SleepCoach \
  -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build

xcodebuild -project SleepCoach.xcodeproj -target SleepCoachTests \
  -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

See the [simulator QA gallery](QA/README.md) for post-fix iPhone 17 Pro, compact-width, Dynamic Type, and Increase Contrast captures. [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) contains the complete validation record and remaining physical-device acceptance work.

The [UX flow contract](UX_REDESIGN_HANDOFF.md) records screen ownership, critical flows, acceptance criteria, and the prioritized follow-up backlog. [SECURITY.md](SECURITY.md) records repository hygiene and local-data hardening requirements.

## Architecture

- `SleepCoach/Domain`: source-labeled health, planning, exercise-catalog, and workout models.
- `SleepCoach/Services`: HealthKit, EventKit, AlarmKit, wellness scoring, exercise-catalog caching, draft persistence, and workout recording.
- `SleepCoach/App`: application state, dependency composition, and deterministic demo services.
- `SleepCoach/Views`: Today, Plan, Train, Exercises, nested Recovery Trends and Training History, Settings, and per-metric Data & Sources controls.
- `SleepCoachTests`: lifecycle, wellness-engine, catalog, persistence compatibility, and workout/progression coverage.
# SleepCoach
