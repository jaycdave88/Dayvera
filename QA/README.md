# iOS 26 simulator QA gallery

These captures use deterministic demo data. They do not contain personal Health, Calendar, device, or account data. Real HealthKit, Calendar, and AlarmKit permission/system handoffs still require a physical iPhone.

## Navigation redesign · iPhone 17 Pro · dark mode

- [Optional first run](Screenshots/sleepcoach-ux-first-run-dark.png)
- [Today decision](Screenshots/sleepcoach-ux-today-dark.png)
- [Tomorrow plan](Screenshots/sleepcoach-ux-plan-dark.png)
- [Train templates](Screenshots/sleepcoach-ux-train-dark.png)
- [Settings](Screenshots/sleepcoach-ux-settings-dark.png)
- [Data & Sources](Screenshots/sleepcoach-ux-data-sources-dark.png)
- [Recovery Trends](Screenshots/sleepcoach-ux-recovery-trends-dark.png)
- [Training History](Screenshots/sleepcoach-ux-training-history-dark.png)

## Compact-width and Accessibility Extra Large · light mode

- [Today · standard text](Screenshots/sleepcoach-ux-compact-today-light.png)
- [Plan · standard text](Screenshots/sleepcoach-ux-compact-plan-light.png)
- [Today · Accessibility Extra Large](Screenshots/sleepcoach-ux-compact-today-ax-light.png)
- [Plan · Accessibility Extra Large](Screenshots/sleepcoach-ux-compact-plan-ax-light.png)
- [Plan applied feedback · Accessibility Extra Large](Screenshots/sleepcoach-ux-compact-plan-applied-ax-light.png)

At Accessibility sizes, primary actions remain at least 44 points tall, content reflows vertically, and the complete explanation remains scrollable.

## Exercise and source-detail coverage

- [Exercise catalog](Screenshots/sleepcoach-final-exercises-dark.png)
- [Exercise detail and static position preview](Screenshots/sleepcoach-final-exercise-detail-dark.png)
- [Template exercise multi-select](Screenshots/sleepcoach-ux-template-library-dark.png)
- [Exercises · compact Accessibility size](Screenshots/sleepcoach-final-compact-exercises-ax-light.png)
- [Signal source controls](Screenshots/sleepcoach-final-sleep-source-dark.png)
- [Partial Health query failure](Screenshots/sleepcoach-final-hrv-query-failure-dark.png)
- [Data & Sources · compact Accessibility size](Screenshots/sleepcoach-ux-compact-data-sources-ax-light.png)
- [Today · Increase Contrast](Screenshots/sleepcoach-final-compact-today-increase-contrast.png)

Validated behavior includes four-tab ownership (Today, Plan, Train, Progress), one primary action per decision screen, scrollability, compact-width reflow, inline titles at Accessibility sizes, non-color status labels, source/failure recovery copy, protected active-workout drafts, and separated recovery/training trends. Settings and the exercise library are one level below the tabs. The fixtures include Eight Sleep, Hume, and Apple Watch observations so automatic preference and manual-source choices can be reviewed without real HealthKit data.
