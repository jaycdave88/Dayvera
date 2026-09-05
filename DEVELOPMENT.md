# Dayvera developer guide

The root [README](README.md) is the short product tour. This guide keeps the
repeatable build, test, and simulator routes used for engineering and QA.

## Requirements

- Xcode 27 or newer
- iOS 27 platform support
- An iOS 27 simulator, or an iOS 27 iPhone with an Apple development team

Simulator identifiers are machine-specific and intentionally not stored in the
repository. Find yours with:

```sh
xcrun simctl list devices available
```

## Run in Xcode

1. Open `Dayvera.xcodeproj`.
2. Choose an iOS 27 simulator and run the `Dayvera` scheme.
3. For a physical iPhone, select the `Dayvera` target and choose your team
   under Signing & Capabilities before running.

## Run the tests

```sh
xcodebuild test \
  -project Dayvera.xcodeproj \
  -scheme Dayvera \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=<SIMULATOR-UDID>' \
  -derivedDataPath /private/tmp/DayveraSignedTests \
  SDKROOT=iphonesimulator
```

## Deterministic simulator states

Debug builds support `--demo-data`, which replaces Health, Calendar, and alarm
services with deterministic fixtures and seeds workout templates and history.

After installing a Debug build:

```sh
xcrun simctl launch --terminate-running-process \
  <SIMULATOR-UDID> \
  com.momoai.personalassistant.sleepcoach \
  --demo-data --skip-onboarding --tab=today
```

Choose a primary tab with `--tab=today`, `plan`, `train`, `nutrition`, or `progress`.
The legacy `exercises` and `settings` values remain shortcuts to those nested
destinations for deterministic QA.

Focused routes are also available:

- `--demo-health-partial` simulates an HRV query failure.
- `--demo-applied-plan` shows the persistent applied-plan state.
- `--show-data-sources` opens Data & Sources.
- `--show-calendar-setup` opens the source-grouped planning, Workout details, and Busy destination controls.
- `--show-signal-source=<sleep|heartRateVariability|restingHeartRate>` opens one signal's source controls.
- `--show-exercise=<repdb-id>` opens a matching catalog exercise.
- `--show-template-editor` opens a new template.
- `--show-template-library` opens exercise selection for a new template.
- `--show-active-workout` starts the first seeded template.
- `--show-workout-builder` opens the guided workout questionnaire.
- `--show-workout-adjustment` opens Today’s adjustment sheet.
- `--show-workout-options` opens all three validated workout choices.
- `--show-workout-detail` opens the recommended workout detail.
- `--show-generated-workout` opens the generated workout logger unless another workout is already in progress.
- `--show-plan-editor` opens the manual and optional on-device-assisted Plan draft editor.
- `--show-meal-history` opens the all-days Meal History.
- `--show-progress` opens Training History.
- `--show-recovery-progress` opens Recovery Trends.

Every `--show-…` route selects its required tab automatically. Pair the routes
with `--demo-data` for repeatable health sources, templates, and history.

## Appearance and accessibility checks

```sh
xcrun simctl ui <SIMULATOR-UDID> appearance dark
xcrun simctl ui <SIMULATOR-UDID> appearance light
xcrun simctl ui <SIMULATOR-UDID> content_size accessibility-extra-large
xcrun simctl ui <SIMULATOR-UDID> content_size large
```

Build a compact-width fixture with:

```sh
xcodebuild \
  -project Dayvera.xcodeproj \
  -scheme Dayvera \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=<COMPACT-SIMULATOR-UDID>' \
  -derivedDataPath /private/tmp/DayveraCompactSimulatorDerived \
  CODE_SIGNING_ALLOWED=NO SDKROOT=iphonesimulator build
```

## Compile without Simulator services

```sh
xcodebuild -project Dayvera.xcodeproj -target Dayvera \
  -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build

xcodebuild -project Dayvera.xcodeproj -target DayveraTests \
  -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

See the [QA gallery](QA/README.md) for the current visual fixtures and validation notes.

## Dayvera nutrition QA

Use `--demo-data --skip-onboarding --tab=nutrition` for synthetic meals, weight history and targets. Add `--show-nutrition-scan`, `--show-nutrition-whatif`, `--show-nutrition-progress`, or `--show-nutrition-profile` for focused routes.

Xcode 27 is required. When it is not the selected default, prefix commands with `DEVELOPER_DIR=/path/to/Xcode-beta.app/Contents/Developer`; do not change global Xcode selection for this project. Real-device photo inference requires an available Apple Intelligence vision model and cannot be certified by simulator fixtures.
