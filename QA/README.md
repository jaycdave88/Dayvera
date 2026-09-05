# Dayvera simulator QA gallery

These captures use deterministic demo data. They do not contain personal Health, Calendar, device, or account data. Real HealthKit, Calendar, and AlarmKit permission/system handoffs still require a physical iPhone.

The gallery distinguishes current captures from historical baselines. Screenshots demonstrate layout and deterministic flows; they do not establish wearable accuracy, nutrition-estimate accuracy or food-recognition accuracy.

## Nutrition release · iOS 27 · iPhone 17 Pro

- [Nutrition dashboard · dark](Screenshots/dayvera-nutrition-dark.png)
- [What-if calculator · dark](Screenshots/dayvera-whatif-dark.png)
- [Weight and intake progress · dark](Screenshots/dayvera-nutrition-progress-dark.png)
- [Photo capture entry · dark](Screenshots/dayvera-food-capture-dark.png)
- [Nutrition · Accessibility Extra Large · light](Screenshots/dayvera-nutrition-accessibility-light.png)

These captures cover the five-tab Dayvera interface. Camera hardware, real food inference and dietary Health handoffs require physical-device acceptance; the capture-entry screenshot does not establish recognition accuracy.

### Nutrition camera flow represented by the product

`Nutrition → Log Food → Take Photo or Choose Photo → Recognition → Review Foods → Match and edit portions → Meal Editor → Save Meal`

The existing capture-entry image shows where the flow begins. No current gallery image is labeled as recognition review or a saved photo meal. A food photo supplies suggestions only; a reviewed catalog/label/manual match supplies nutrients, and the user must confirm the meal before it affects daily totals.

## Penpot-aligned redesign · iOS 27 · iPhone 17 Pro · dark mode

These captures were taken after the integrated redesign build and inspected at full simulator resolution. They use deterministic demo data.

- [Today decision, recovery, and Weekly Rhythm](Screenshots/dayvera-today-redesign.png)
- [Tomorrow schedule and Apply Plan hierarchy](Screenshots/dayvera-plan-redesign.png)
- [Train quick start and saved workouts](Screenshots/dayvera-train-redesign.png)
- [Active workout set logging](Screenshots/dayvera-active-workout-redesign.png)
- [Nutrition target and macro progress](Screenshots/dayvera-nutrition-redesign.png)
- [Log Food launcher](Screenshots/dayvera-nutrition-log-food-redesign.png)
- [Progress training takeaway and trend](Screenshots/dayvera-progress-redesign.png)
- [Recovery progress takeaway and chart](Screenshots/dayvera-recovery-progress-redesign.png)
- [Settings hierarchy](Screenshots/dayvera-settings-redesign.png)

The launch screen uses the same adaptive background as Today and introduces no timed logo sequence. Its continuity was verified during repeated simulator launches; a static launch frame is not included because it does not represent an independently interactive screen. Welcome-back timing and Weekly Rhythm calculations are covered by unit tests. Additional Light Mode, Increase Contrast, Accessibility Extra Large, return-after-absence, recognition-result, and failure-state captures remain useful follow-up acceptance evidence.

The Log Food capture verifies that camera, photo-library, search, label, recent/favorite meal, and manual-total paths are reachable. The local QA build used a temporary compatibility service because the installed Xcode 26.6 toolchain exposes the iOS 26.5 SDK while the checked-in recognition service uses iOS 27 Foundation Models vision APIs. That compatibility service was removed after testing and is not committed. The screenshot therefore verifies the review-first interface, not real food recognition.

## Historical recovery/training baseline · iOS 26

The images below were captured before the nutrition feature and rebrand. Their filenames have moved with the project; their pixels retain the earlier interface.

### Navigation redesign · iPhone 17 Pro · dark mode

- [Optional first run](Screenshots/dayvera-ux-first-run-dark.png)
- [Today decision](Screenshots/dayvera-ux-today-dark.png)
- [Tomorrow plan](Screenshots/dayvera-ux-plan-dark.png)
- [Train templates](Screenshots/dayvera-ux-train-dark.png)
- [Active workout logger](Screenshots/dayvera-final-active-workout-dark.png)
- [Settings](Screenshots/dayvera-ux-settings-dark.png)
- [Multi-calendar setup](Screenshots/dayvera-final-calendar-setup-dark.png)
- [Health Data & Sources](Screenshots/dayvera-ux-data-sources-dark.png)
- [Recovery Trends](Screenshots/dayvera-ux-recovery-trends-dark.png)
- [Training History](Screenshots/dayvera-ux-training-history-dark.png)

### Compact-width and Accessibility Extra Large · light mode

- [Today · standard text](Screenshots/dayvera-ux-compact-today-light.png)
- [Plan · standard text](Screenshots/dayvera-ux-compact-plan-light.png)
- [Today · Accessibility Extra Large](Screenshots/dayvera-ux-compact-today-ax-light.png)
- [Plan · Accessibility Extra Large](Screenshots/dayvera-ux-compact-plan-ax-light.png)
- [Plan applied feedback · Accessibility Extra Large](Screenshots/dayvera-ux-compact-plan-applied-ax-light.png)
- [Calendar Setup · Accessibility Extra Large](Screenshots/dayvera-final-calendar-setup-compact-ax-light.png)

At Accessibility sizes, primary actions remain at least 44 points tall, content reflows vertically, and the complete explanation remains scrollable.

### Exercise and source-detail coverage

- [Exercise catalog](Screenshots/dayvera-final-exercises-dark.png)
- [Exercise detail and static position preview](Screenshots/dayvera-final-exercise-detail-dark.png)
- [Template exercise multi-select](Screenshots/dayvera-ux-template-library-dark.png)
- [Exercises · compact Accessibility size](Screenshots/dayvera-final-compact-exercises-ax-light.png)
- [Signal source controls](Screenshots/dayvera-final-sleep-source-dark.png)
- [Partial Health query failure](Screenshots/dayvera-final-hrv-query-failure-dark.png)
- [Health Data & Sources · compact Accessibility size](Screenshots/dayvera-ux-compact-data-sources-ax-light.png)
- [Today · Increase Contrast](Screenshots/dayvera-final-compact-today-increase-contrast.png)

The historical baseline validated the earlier four-tab ownership (Today, Plan, Train, Progress), one primary action per decision screen, scrollability, compact-width reflow, inline titles at Accessibility sizes, non-color status labels, source/failure recovery copy, separate planning, workout-details, and Busy-copy calendar controls, protected active-workout drafts, and separated recovery/training trends. The current app adds Nutrition as the fifth tab. Settings and the exercise library remain one level below the tabs. The fixtures include Eight Sleep, Hume, and Apple Watch observations so automatic preference and manual-source choices can be reviewed without real HealthKit data.
