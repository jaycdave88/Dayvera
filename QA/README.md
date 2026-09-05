# Dayvera simulator QA gallery

These captures use deterministic demo data. They do not contain personal Health, Calendar, device, or account data. Real HealthKit, Calendar, and AlarmKit permission/system handoffs still require a physical iPhone.

## Nutrition release · iOS 27 · iPhone 17 Pro

- [Nutrition dashboard · dark](Screenshots/dayvera-nutrition-dark.png)
- [What-if calculator · dark](Screenshots/dayvera-whatif-dark.png)
- [Weight and intake progress · dark](Screenshots/dayvera-nutrition-progress-dark.png)
- [Photo capture entry · dark](Screenshots/dayvera-food-capture-dark.png)
- [Nutrition · Accessibility Extra Large · light](Screenshots/dayvera-nutrition-accessibility-light.png)

These captures cover the five-tab Dayvera interface. Camera hardware, real food inference and dietary Health handoffs require physical-device acceptance; the capture-entry screenshot does not establish recognition accuracy.

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

The historical baseline validated four-tab ownership (Today, Plan, Train, Progress), one primary action per decision screen, scrollability, compact-width reflow, inline titles at Accessibility sizes, non-color status labels, source/failure recovery copy, separate planning, workout-details, and Busy-copy calendar controls, protected active-workout drafts, and separated recovery/training trends. Settings and the exercise library are one level below the tabs. The fixtures include Eight Sleep, Hume, and Apple Watch observations so automatic preference and manual-source choices can be reviewed without real HealthKit data.
