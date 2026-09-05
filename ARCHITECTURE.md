# Dayvera architecture

## Existing application

The original application is a native iPhone app built with SwiftUI, SwiftData and Swift Charts. `AppModel` coordinates HealthKit, EventKit, AlarmKit, recovery calculations and deterministic workout planning. `RootView` owns navigation; `DesignSystem.swift` supplies the adaptive colors, cards and typography. Workout templates and completed sessions use SwiftData, while private preferences and active state use protected Application Support files. There is no account, authentication service, backend or app-managed cloud sync to extend.

The rebrand keeps those boundaries. `DayveraApp` injects `AppModel` and the new `NutritionModel` into the same view hierarchy. `RootView` presents five top-level jobs—Today, Plan, Train, Nutrition and Progress—while Settings remains below Today. Nutrition adds a Today summary and a Progress destination. Existing recovery data and completed working sets provide context without becoming calorie multipliers.

## Product and navigation boundaries

Each tab owns a distinct decision. Today prioritizes the current workout and recovery context; Plan previews tomorrow's schedule before system writes; Train protects the active draft and owns templates; Nutrition owns today's target, intake and food capture; Progress owns historical recovery, training and nutrition analysis. Native `NavigationStack`, `TabView`, sheets, forms and Swift Charts preserve platform behavior and accessibility.

The launch screen is a static semantic background configured by `UILaunchScreen` and the adaptive `LaunchBackground` color asset. It contains no logo sequence, fake progress or intentional delay. First launch uses the existing guided setup; later permissions remain contextual. Returning users go directly to Today, where a locally derived welcome message appears only after a meaningful absence.

## Editable Plan flow

The calculated `DailyPlan` remains the starting point. `PlanDraft` copies its bedtime, wake time, training start, and training end into an ephemeral editing layer. Manual edits and optional on-device suggestions pass through `PlanDraftValidator`, which requires a future wake time, a 7–12 hour sleep opportunity, training after waking, a 20–180 minute workout, and completion by the deterministic ready deadline.

Plan assistance is request-scoped and off by default. `FoundationModelPlanAssistant` can propose only ±120-minute shifts in five-minute increments plus a bounded workout duration. Structured model output is treated as untrusted, validated by `PlanProposalEngine`, and shown as a before/after proposal. The user must first copy it into the draft and save the draft. No edit or suggestion calls EventKit or AlarmKit. Only the existing Apply confirmation creates or replaces app-owned system items using a frozen `PlanApplicationRequest`.

## Training modalities

`WorkoutBuildIntent` captures one session's modality, available time, focus, effort, equipment, and experience level. The supported modalities are cardio, strength/resistance, balance, and flexibility/mobility; levels are beginner, intermediate, and advanced. Bodyweight is always available, and users can select from barbells, dumbbells, kettlebells, benches, racks, cable or strength machines, pull-up bars, bands, suspension trainers, medicine balls, and cardio machines.

Strength continues through the validated planner, RepDB-backed reviewed catalog, hard movement/exercise exclusions, and optional ranking of already-valid candidates. `GuidedWorkoutPlanner` builds cardio, balance, and mobility sessions from a small reviewed local catalog with transparent duration and intensity cues. It does not ask a language model to invent movements or prescriptions. All modalities use the existing preview, active-draft protection, completion, history, and weekly-session accounting paths.

## Nutrition data flow

1. A confirmed adult profile enters `NutritionEngine`, which returns deterministic, versioned calorie and macro estimates.
2. A food photo enters the available Apple on-device model, which returns food candidates and rough portions. The user matches candidates to the bundled USDA catalog, reviews amounts and adds missing ingredients. The model supplies no nutrient totals.
3. Reviewed meals, manual daily totals or one selected Health dietary source provide a day's intake. The user explicitly marks a day complete. Sources are not combined automatically.
4. Immutable target snapshots, complete intake days and consistent weight observations feed `NutritionAdaptationEngine`. Eligible changes become reviewable proposals and take effect the next day only after acceptance.
5. SwiftUI charts display observations, source/completeness status and historical targets. What-if calculations use the same engine and constraints as applied targets.

Photo recognition is deliberately separated from nutrient authority. `AppleFoodRecognitionService` validates structured, on-device suggestions for candidate names and rough gram amounts. `FoodCatalogStore`, a package label, manual values or the selected supported Health source supplies nutrients only after review. Recognition failure returns the user to searchable/manual entry with their work preserved.

Each `FoodEntry` preserves the user's amount, unit, count, and grams-per-unit alongside canonical grams. Quantity changes rescale the saved nutrient snapshot, while decoding older entries defaults safely to their previous gram amount. The Nutrition dashboard shows the selected day's reviewed meals; Meal History groups every saved meal by local day with day totals and returns the user to that date.

## Unified Progress

`ProgressView` owns a single segmented Recovery, Training, and Nutrition destination. Recovery and Training reuse the same 7/28-day shell; Nutrition embeds its provenance-aware weight, intake, adherence, measurement, and target history. Focused links from Today and Train open the relevant section without creating duplicate top-level destinations.

## Motivation and return flow

`WeeklyRhythmEngine` derives a current-week summary from completed sessions, explicitly completed nutrition days and unique nights with recovery observations. Training and nutrition can show progress bars; recovery coverage is descriptive because more sensor data is not itself a health achievement. Momentum describes how often the session target was met across the previous four completed weeks rather than enforcing a consecutive-day streak.

`AppModel` stores the last meaningful-use date and acknowledged milestone identifiers in the existing protected private-state store. `RootView` classifies a return of at least seven days and passes that state to Today. A return of at least 30 days also explains that recent trends may need more observations. A weekly training milestone appears contextually and can be acknowledged; there is no point balance, level, badge collection or notification-driven loss mechanic.

## Storage and schema

| Storage | Contents |
| --- | --- |
| Existing `WorkoutTemplateRecord`, `WorkoutSessionRecord` | Unchanged workout entity schemas and identities |
| `MealRecord` | Date, captured timezone, meal name, favorite flag, local photo filename and atomic JSON food-entry snapshots |
| `NutritionDayRecord` | Unique local day key, selected authoritative intake source, optional manual totals, completeness and training-day flag |
| `BodyMeasurementRecord` | Dated optional weight, waist, hips, arm and thigh measurements |
| `NutritionTargetRevision` | Versioned calculation and profile snapshots, effective/created dates and reason |
| `NutritionAdjustmentRecord` | Proposed calories, observed trend, source target revision, evaluation date and review status |
| Protected private-state files | Nutrition profile and dietary-import preference, following existing persistence conventions |
| Protected motivation state | Last meaningful use and acknowledged weekly milestone identifiers; no engagement profile or cloud history |
| Protected photo directory | Normalized, metadata-stripped meal images excluded from backup; removed when the associated meal is deleted |
| Bundled `FoodCatalog.json` | 7,793 USDA SR Legacy foods with per-100 g nutrients, source IDs, dataset version and available household portions |

Nutrition uses a separate `ModelContext` on the existing container, with explicit save/rollback, so a failed nutrition transaction does not roll back an active workout. Dietary Health samples are refreshed into memory over a bounded 35-day window; they are not exported or represented as permanent historical snapshots. Meal and target snapshots remain independent of future catalog/profile edits.

The original-module database fixture in `DayveraTests/Fixtures` verifies the additive schema and module rename together. See [REBRAND.md](REBRAND.md) for identifiers intentionally preserved across updates.

## Implementation file map

| File | Responsibility |
| --- | --- |
| `Dayvera/App/AppBrand.swift`, `LegacyCompatibility.swift` | Current identity and explicitly retained persistence/ownership identifiers |
| `Dayvera/App/DayveraApp.swift`, `NutritionModel.swift` | Dependency injection, additive container, transactions, source selection, profile/history and proposal orchestration |
| `Dayvera/Domain/TrainingProfile.swift` | Training preferences plus returning-user classification and Weekly Rhythm derivation |
| `Dayvera/Domain/PlanEditingModels.swift` | Ephemeral Plan draft, deterministic validation, bounded proposal application and application-request conversion |
| `Dayvera/Domain/NutritionModels.swift` | Profiles, goals, nutrients, catalog/food provenance, targets and evidence values |
| `Dayvera/Domain/NutritionRecords.swift` | Five additive SwiftData record types |
| `Dayvera/Services/NutritionEngine.swift` | Initial estimates, macro allocation, cycling and safety boundaries |
| `Dayvera/Services/NutritionAdaptationEngine.swift` | Robust weight slope, evidence gates and bounded calorie proposals |
| `Dayvera/Services/NutritionStore.swift` | Day grouping and protected image persistence |
| `Dayvera/Services/NutritionHealthService.swift` | Optional read-only dietary imports, UUID deduplication and bounded queries |
| `Dayvera/Services/FoodCatalogStore.swift` | Catalog decoding, search and trusted nutrient scaling |
| `Dayvera/Services/AppleFoodRecognitionService.swift` | Availability/capability checks, structured local image inference and output validation |
| `Dayvera/Services/FoundationModelPlanAssistant.swift` | Request-scoped structured timing proposal; no system writes or authority over validation |
| `Dayvera/Services/CuratedExerciseCatalog.swift` | Reviewed strength metadata plus deterministic cardio, balance and mobility session construction |
| `Dayvera/Views/NutritionSetupView.swift` | Profile, units, goals, activity, muscle priorities and eligibility |
| `Dayvera/Views/NutritionView.swift` | Dashboard, intake source/completeness, meals, recovery and adjustment review |
| `Dayvera/Views/FoodCaptureView.swift`, `MealEditorView.swift` | Camera/Photos selection, candidate matching, portion/label editing and explicit review |
| `Dayvera/Views/NutritionProgressView.swift` | Weight/intake/adherence charts, measurements, daily totals, source settings and target history |
| `Dayvera/Views/NutritionWhatIfView.swift` | Calorie/protein/cycling scenarios and next-day application |
| `Dayvera/Views/RootView.swift`, `DashboardView.swift`, `ProgressView.swift`, `SettingsView.swift` | Native navigation and existing-screen integration |
| `Dayvera/Resources/Assets.xcassets/LaunchBackground.colorset`, `Dayvera/Info.plist` | Static light/dark launch surface that resolves directly into the app |
| `Dayvera/Info.plist`, `Dayvera.xcodeproj`, app assets | Camera purpose text, iOS 27 target, renamed scheme/module and new icon |
| `Scripts/import_food_catalog.py` | Reproducible normalization of the official USDA source archive |
| `DayveraTests/NutritionTests.swift` | Calculation/safety, migration, transactional logging, provenance and history regressions |
| `DayveraTests/PlanEditingTests.swift` | Draft validation, bounded model-output rejection and preservation of application metadata/destinations |

## Dependencies and boundaries

No third-party package, API key or server is added. System frameworks are SwiftUI, SwiftData, Charts, HealthKit, Foundation Models, PhotosUI, AVFoundation and UIKit, alongside existing EventKit and AlarmKit integration. Xcode 27 and iOS 27 are required for the selected image-capable Foundation Models API. Manual food entry remains available when Apple Intelligence or a suitable model is unavailable. Motivation uses local dates, existing records, native progress views and restrained sensory feedback; it introduces no notification service, animation framework or reward economy.

The import script uses only Python's standard library. All nutritional calculations, validation rules, uncertainty language and supporting sources are documented in [NUTRITION.md](NUTRITION.md). Device-controlled permissions, real meal recognition and provisioning remain hands-on acceptance checks in the [TestFlight guide](TESTFLIGHT.md).
