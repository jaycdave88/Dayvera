# Dayvera — code-to-design audit

Audit date: 2026-09-05. Behavioral baseline: local Dayvera checkout at `c469c24`, branch `feat/dayvera-nutrition`. This is a design audit, not a new runtime or recognition-accuracy test. No production SwiftUI code was changed during this design phase.

The repository is authoritative when the master brief's illustrative copy differs from implemented behavior. The current QA gallery distinguishes the nutrition release from historical recovery/training screenshots. Those historical pixels must not be mistaken for the current five-tab implementation.

## Verified camera and AI flow

`FoodCaptureView.swift` already supports a camera and photo-library entry. A photo is retained and normalized, then the user explicitly selects **Identify food on device**. Recognition is not automatically started by accepting a photo. It produces candidate foods, rough grams and possible clarifying questions. The app retains manual entry when recognition is unavailable or fails.

`MealEditorView.swift` asks the user to match each candidate, review portions and preparation, and confirm the complete meal. Save is unavailable with unresolved candidates, no food entries, or an unchecked review confirmation. Food additions, edits and deletions, and changed photo results reset review; meal name/date changes and removal of unresolved candidates do not. Recognition does not directly save nutrient totals.

Designed sequence: Nutrition → Log Food → Take Photo → Camera → Use Photo → Identify Food on Device → Recognition → unmatched candidates → catalog match → portion review → optional missing food → Meal Editor → final review confirmation → Save Meal.

## Findings and design corrections

| Code evidence | Existing behavior | Design consequence |
|---|---|---|
| `Dayvera/Views/FoodCaptureView.swift:25` | Camera, PhotosPicker, explicit recognition and manual alternatives coexist. | N06 launcher exposes capture; N08P retains explicit recognition action. |
| `Dayvera/Views/FoodCaptureView.swift:56` | Preparing a photo does not analyze it. | Use Photo cannot skip into an already recognized or saved meal. |
| `Dayvera/Views/MealEditorView.swift:36` | Candidates initially require food matching. | N10I and N10A show unmatched states; initial candidates have no trusted calorie values. |
| `Dayvera/Views/MealEditorView.swift:68` | Final checked-foods/portions/preparation toggle gates Save. | N14 is unchecked, N14R checked, N14E preserves entries after failure. |
| `Dayvera/Views/MealEditorView.swift:107` | Food search selects from the bundled catalog and supports grams/available household portions. | N12/N12C lead to N13/N13R; no invented barcode, OCR or branded-food lookup. |
| `Dayvera/Views/MealEditorView.swift:169` | Manual values describe the entire portion. All four values must be confirmed; editing nutrients changes provenance to manual. | N15 uses whole-portion values, not a newly invented per-serving calculator. N13E distinguishes editing an existing entry. |
| `Dayvera/Domain/NutritionModels.swift:92` | Provenance distinguishes database, photo-estimated portion and entered label/manual values. | “From package label” is entry-context copy, not a new stored provenance type. |
| `Dayvera/App/NutritionModel.swift:93` | One authoritative source per day. Missing Health nutrients remain nil. No meals returns missing intake. | N04 reads Not logged/Unknown. N17/N26 never turn missing protein into zero. |
| `Dayvera/App/NutritionModel.swift:113` | Source/manual changes reset day completeness. | Source selection and manual totals must reopen evidence state, preserving saved meals. |
| `Dayvera/Views/NutritionView.swift:170` | Day completion requires known calories. | An empty day cannot be marked complete. |
| `Dayvera/Views/NutritionProgressView.swift:161` | Manual daily totals require all four known values and explicit confirmation; they replace the day's authoritative totals. | N18/N32 use known calories and macros. Missing-macro examples belong to Health-source states. |
| `Dayvera/Views/NutritionWhatIfView.swift:19` | Calorie delta −300…+300 in 50 kcal steps; protein control is g/kg; cycling is a toggle. | N22 labels protein in g/kg and keeps scenario outputs hypothetical. |
| `Dayvera/Domain/NutritionModels.swift:160` | Target displays round calories to 50 and grams to 5. | Scenario displays use 2,800/2,600 rather than falsely precise 2,786/2,586. |
| `Dayvera/Services/NutritionAdaptationEngine.swift:43` | At least 18 complete days in 21 days; additional weight coverage, adherence, consistent weight-source and trend checks. `NutritionModel.swift:224` adds target-age and consecutive-evaluation gates. | Proposal evidence is visible; a single low weigh-in never causes a change. |
| `Dayvera/Services/NutritionAdaptationEngine.swift:67` | Adjustment step is capped at min(100 kcal, 5% of current target). | Replaced brief's illustrative +150 with +100; 2,500 → 2,600 starts tomorrow. |
| `Dayvera/App/NutritionModel.swift:238` | Accept revalidates the proposal, target revision and safety. | Review and explicit acceptance remain separate from evidence gathering. |
| `Dayvera/App/NutritionModel.swift:261` | Scenario acceptance schedules its own calories, protein and cycling. | Scenario branch schedules 2,700; it does not incorrectly show the separate 2,600 adaptation result. |
| `Dayvera/App/NutritionModel.swift:274` | Muscle-gain underfueling flag uses at least five complete intake days in the last seven; mean intake below 90% of target. | N29 is an evidence-qualified review prompt, not an automatic calorie change. |
| `Dayvera/Views/NutritionSetupView.swift:72` | Adult/appropriateness confirmation and supervision flags gate estimates. | Eligibility must remain explicit in onboarding/profile implementation. |

## Calculation contract to preserve

These formulas describe the existing engine, not a newly prescribed nutrition protocol.

- RMR uses Mifflin–St Jeor: `10 × kg + 6.25 × cm − 5 × age + coefficient`; coefficients are +5, −161, or −78 for the app's selected estimation option.
- Maintenance is RMR multiplied by whole-day activity (1.2 / 1.375 / 1.55 / 1.725). Training calories are not added again.
- Initial gain offset is 5–10%; loss is −15…−10%; maintenance/recomposition use maintenance. Existing safety clamps still govern the result.
- Protein is weight × selected goal-valid g/kg. Fat minimum is the greater of 0.6 g/kg and 20% of energy; the working target is at least that minimum or 25% of energy. Carbohydrate receives the residual after protein and fat. Fat range's upper bound is 35% of energy.
- Cycling uses a 200 kcal training/rest gap for eligible schedules while preserving the average and respecting the rest-day floor.
- Body-fat input is retained when supplied but is not used by the current calorie equation. Muscle-group choices inform training priorities; nutrients cannot direct growth to a specific body part.
- For a single estimation coefficient, the maintenance band is a ±15% heuristic. “Use both estimates” widens it to `(RMR − 83) × activity × 0.85` through `(RMR + 83) × activity × 1.15`. Neither is a statistical confidence interval or measured metabolic result.
- Adult eligibility, supervision flags, finite/range validation, low-BMI loss protection and symptom-related reduction safeguards remain in the engine. Do not reproduce these checks solely in UI code.

## Cross-product invariants

The deterministic workout planner, movement exclusions and recovery constraints remain authoritative. AI may only rank valid candidates or improve allowed explanation copy. Active drafts cannot be overwritten. Preserve autosave, previous performance, units, notes, rest timing and finish validation.

Plan must display exact alarm/calendar destinations before confirmation. Receipt verification controls the applied state. Partial/uncertain results must not appear as full success. Undo only removes Dayvera-owned items and does not silently redirect calendar writes.

Health provenance stays explicit. Missing dates remain gaps. Confidence, completeness, freshness and sensor accuracy are separate concepts. Recovery context must not imply automatic nutrition changes absent corresponding existing logic.

## Intentional presentation changes and explicit behavior gaps

- The five destinations are retained; their content hierarchy is simplified. Nutrition owns daily logging and target decisions; Progress owns historical nutrition analysis.
- Capture methods move into one Log Food sheet. Settings/data diagnostics move below normal task flows. Calendar selections receive focused screens.
- The master brief requests review before repeating a recent/favorite meal. The existing repeat path saves immediately without Undo. Implement review as a new meal draft with copied food entries and a new meal identity; do not silently change the original meal.
- Active workouts have persistent draft recovery. Unsaved meal editing uses local view state; Cancel dismisses it. Save failures retain fields while the editor stays open. Do not claim that unfinished meals survive dismissal or add persistence implicitly.
- Penpot controls and figures are illustrative static fixtures. They do not execute the engine, camera, Health queries or persistence. Secondary prototype branches may reuse a representative editor fixture; production must preserve the actual selected foods and never add ingredients automatically.

## Verification boundary

Read: QA/README, current and historical representative screenshots, architecture/nutrition/handoff documents, root/dashboard/nutrition/capture/editor/progress/what-if/workout/settings/source views, and relevant model/engine methods.

Design checks do not replace physical-device checks for camera, local recognition availability, Health privacy behavior, Calendar/Alarm permissions, VoiceOver order, keyboard avoidance, native sheet dismissal, Dynamic Type, or Increase Contrast. Recognition accuracy is not established by the QA capture-entry screenshot or this design.
