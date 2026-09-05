# Dayvera architecture

## Existing application

The original application is a native iPhone app built with SwiftUI, SwiftData and Swift Charts. `AppModel` coordinates HealthKit, EventKit, AlarmKit, recovery calculations and deterministic workout planning. `RootView` owns navigation; `DesignSystem.swift` supplies the adaptive colors, cards and typography. Workout templates and completed sessions use SwiftData, while private preferences and active state use protected Application Support files. There is no account, authentication service, backend or app-managed cloud sync to extend.

The rebrand keeps those boundaries. `DayveraApp` injects `AppModel` and the new `NutritionModel` into the same view hierarchy. Nutrition adds the fifth tab, a Today summary and a Progress destination. Existing recovery data and completed working sets provide context without becoming calorie multipliers.

## Nutrition data flow

1. A confirmed adult profile enters `NutritionEngine`, which returns deterministic, versioned calorie and macro estimates.
2. A food photo enters the available Apple on-device model, which returns food candidates and rough portions. The user matches candidates to the bundled USDA catalog, reviews amounts and adds missing ingredients. The model supplies no nutrient totals.
3. Reviewed meals, manual daily totals or one selected Health dietary source provide a day's intake. The user explicitly marks a day complete. Sources are not combined automatically.
4. Immutable target snapshots, complete intake days and consistent weight observations feed `NutritionAdaptationEngine`. Eligible changes become reviewable proposals and take effect the next day only after acceptance.
5. SwiftUI charts display observations, source/completeness status and historical targets. What-if calculations use the same engine and constraints as applied targets.

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
| Protected photo directory | Normalized, metadata-stripped meal images excluded from backup; removed when the associated meal is deleted |
| Bundled `FoodCatalog.json` | 7,793 USDA SR Legacy foods with per-100 g nutrients, source IDs, dataset version and available household portions |

Nutrition uses a separate `ModelContext` on the existing container, with explicit save/rollback, so a failed nutrition transaction does not roll back an active workout. Dietary Health samples are refreshed into memory over a bounded 35-day window; they are not exported or represented as permanent historical snapshots. Meal and target snapshots remain independent of future catalog/profile edits.

The original-module database fixture in `DayveraTests/Fixtures` verifies the additive schema and module rename together. See [REBRAND.md](REBRAND.md) for identifiers intentionally preserved across updates.

## Implementation file map

| File | Responsibility |
| --- | --- |
| `Dayvera/App/AppBrand.swift`, `LegacyCompatibility.swift` | Current identity and explicitly retained persistence/ownership identifiers |
| `Dayvera/App/DayveraApp.swift`, `NutritionModel.swift` | Dependency injection, additive container, transactions, source selection, profile/history and proposal orchestration |
| `Dayvera/Domain/NutritionModels.swift` | Profiles, goals, nutrients, catalog/food provenance, targets and evidence values |
| `Dayvera/Domain/NutritionRecords.swift` | Five additive SwiftData record types |
| `Dayvera/Services/NutritionEngine.swift` | Initial estimates, macro allocation, cycling and safety boundaries |
| `Dayvera/Services/NutritionAdaptationEngine.swift` | Robust weight slope, evidence gates and bounded calorie proposals |
| `Dayvera/Services/NutritionStore.swift` | Day grouping and protected image persistence |
| `Dayvera/Services/NutritionHealthService.swift` | Optional read-only dietary imports, UUID deduplication and bounded queries |
| `Dayvera/Services/FoodCatalogStore.swift` | Catalog decoding, search and trusted nutrient scaling |
| `Dayvera/Services/AppleFoodRecognitionService.swift` | Availability/capability checks, structured local image inference and output validation |
| `Dayvera/Views/NutritionSetupView.swift` | Profile, units, goals, activity, muscle priorities and eligibility |
| `Dayvera/Views/NutritionView.swift` | Dashboard, intake source/completeness, meals, recovery and adjustment review |
| `Dayvera/Views/FoodCaptureView.swift`, `MealEditorView.swift` | Camera/Photos selection, candidate matching, portion/label editing and explicit review |
| `Dayvera/Views/NutritionProgressView.swift` | Weight/intake/adherence charts, measurements, daily totals, source settings and target history |
| `Dayvera/Views/NutritionWhatIfView.swift` | Calorie/protein/cycling scenarios and next-day application |
| `Dayvera/Views/RootView.swift`, `DashboardView.swift`, `ProgressView.swift`, `SettingsView.swift` | Native navigation and existing-screen integration |
| `Dayvera/Info.plist`, `Dayvera.xcodeproj`, app assets | Camera purpose text, iOS 27 target, renamed scheme/module and new icon |
| `Scripts/import_food_catalog.py` | Reproducible normalization of the official USDA source archive |
| `DayveraTests/NutritionTests.swift` | Calculation/safety, migration, transactional logging, provenance and history regressions |

## Dependencies and boundaries

No third-party package, API key or server is added. System frameworks are SwiftUI, SwiftData, Charts, HealthKit, Foundation Models, PhotosUI, AVFoundation and UIKit, alongside existing EventKit and AlarmKit integration. Xcode 27 and iOS 27 are required for the selected image-capable Foundation Models API. Manual food entry remains available when Apple Intelligence or a suitable model is unavailable.

The import script uses only Python's standard library. All nutritional calculations, validation rules, uncertainty language and supporting sources are documented in [NUTRITION.md](NUTRITION.md). Device-controlled permissions, real meal recognition and provisioning remain separate acceptance checks recorded in [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md).
