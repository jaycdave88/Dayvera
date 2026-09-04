<div align="center">

# Sleep Coach

**Wake with a plan. Train with context.**

A private, local-first iOS app that turns Apple Health recovery signals into an
explainable workout recommendation and morning schedule.

<p>
  <img src="https://img.shields.io/badge/iOS-26%2B-000000?logo=apple&logoColor=white" alt="iOS 26 or newer" />
  <img src="https://img.shields.io/badge/UI-SwiftUI-F05138?logo=swift&logoColor=white" alt="SwiftUI" />
  <a href="https://github.com/jaycdave88/SleepCoach/actions/workflows/repository-hygiene.yml"><img src="https://github.com/jaycdave88/SleepCoach/actions/workflows/repository-hygiene.yml/badge.svg" alt="Repository hygiene" /></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="Apache 2.0 license" /></a>
</p>

<p>
  <a href="#-see-it-in-action"><strong>🎬 Tour</strong></a> ·
  <a href="#-how-it-works"><strong>✨ How it works</strong></a> ·
  <a href="#-run-it"><strong>🚀 Run it</strong></a> ·
  <a href="#-data--privacy"><strong>🔒 Data & privacy</strong></a> ·
  <a href="#-project-guides"><strong>📚 Guides</strong></a>
</p>

</div>

## 🎬 See it in action

<p align="center"><strong>Decide → plan → train</strong></p>

<p align="center">
  <a href="./QA/Screenshots/sleepcoach-ux-today-dark.png"><img src="./QA/Screenshots/sleepcoach-ux-today-dark.png" width="260" alt="Today screen showing a full-performance workout recommendation and readiness score" /></a>
  <a href="./QA/Screenshots/sleepcoach-ux-plan-dark.png"><img src="./QA/Screenshots/sleepcoach-ux-plan-dark.png" width="260" alt="Plan screen showing bedtime, wake time, workout time, and calendar commitment" /></a>
  <a href="./QA/Screenshots/sleepcoach-ux-train-dark.png"><img src="./QA/Screenshots/sleepcoach-ux-train-dark.png" width="260" alt="Train screen showing a readiness-adjusted workout template" /></a>
</p>

<p align="center"><sub>Know how hard to train, work backward from tomorrow, then start a prepared workout.</sub></p>

<p align="center"><strong>Learn → review → trust</strong></p>

<p align="center">
  <a href="./QA/Screenshots/sleepcoach-final-exercise-detail-dark.png"><img src="./QA/Screenshots/sleepcoach-final-exercise-detail-dark.png" width="260" alt="Illustrated kettlebell exercise detail and position preview" /></a>
  <a href="./QA/Screenshots/sleepcoach-ux-recovery-trends-dark.png"><img src="./QA/Screenshots/sleepcoach-ux-recovery-trends-dark.png" width="260" alt="Recovery trends with sleep duration chart" /></a>
  <a href="./QA/Screenshots/sleepcoach-ux-data-sources-dark.png"><img src="./QA/Screenshots/sleepcoach-ux-data-sources-dark.png" width="260" alt="Apple Health signal and source controls" /></a>
</p>

<p align="center"><sub>Simulator captures use deterministic demo data—not personal health information. <a href="./QA/README.md">Open the full QA gallery</a>.</sub></p>

## ✨ How it works

`Eight Sleep / Hume / Apple Watch → Apple Health → Sleep Coach`

- **Read:** sleep, HRV, and resting heart rate, with the contributing source kept visible.
- **Decide:** explain today's readiness, workout volume, effort, and progression.
- **Plan:** suggest bedtime, wake time, and gym time from the next hard Calendar commitment.
- **Train:** build templates from an illustrated exercise catalog, log sets, and review progress.

Sleep Coach reads what compatible apps write to Apple Health; it does not call
private Eight Sleep or Hume APIs. Alarms and Calendar events change only after
confirmation.

## 🚀 Run it

Requires **Xcode 26+** and an **iOS 26** simulator or iPhone.

1. Open `SleepCoach.xcodeproj`.
2. Choose an iOS 26 simulator and press **Run** (`⌘R`).
3. For a real iPhone, select your development team under **Signing & Capabilities**, then connect Apple Health inside the app.

For repeatable demo states, tests, and command-line builds, use the
[developer guide](DEVELOPMENT.md).

> [!NOTE]
> Simulator QA covers the interface and app logic. Real HealthKit sources,
> permission sheets, Calendar writes, and AlarmKit delivery require an iPhone.

## 🔒 Data & privacy

- Health, plan, template, and workout data stay in the app's local container.
- No Sleep Coach account, application server, ads, or analytics SDK.
- Health and workout data are never attached to exercise-catalog requests.
- Recommendation confidence describes available inputs—not medical certainty or wearable accuracy.

Sleep Coach is wellness software, not medical advice. See the
[security and privacy notes](SECURITY.md) for the release-hardening checklist.

## 📚 Project guides

| Guide | What it contains |
| :--- | :--- |
| [QA gallery](QA/README.md) | Dark, light, compact-width, and accessibility captures |
| [Developer guide](DEVELOPMENT.md) | Build, test, and deterministic demo commands |
| [Implementation status](IMPLEMENTATION_STATUS.md) | Verified behavior and remaining device acceptance |
| [UX flow contract](UX_REDESIGN_HANDOFF.md) | Screen ownership, flows, and acceptance criteria |
| [Security](SECURITY.md) | Repository hygiene and local-data hardening |

Exercise content and illustrations are fetched at runtime from
[RepDB](https://repdb.co) under its
[dataset terms](https://github.com/RepDB/exercise-dataset/blob/main/LICENSE-DATA.md)
and are not redistributed in this repository. See
[third-party notices](THIRD_PARTY_NOTICES.md).
