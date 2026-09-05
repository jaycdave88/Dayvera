# Codex Master Brief — Design Dayvera End-to-End in Penpot

You are acting as the senior iOS product designer, UX architect, design-system designer, and Penpot implementation agent for **Dayvera**.

Your job is to build the complete, editable Dayvera product design in the currently connected Penpot file using the Penpot MCP. Do not stop at wireframes, notes, screenshots, or a written specification. Create the actual Penpot pages, components, design tokens, screen designs, flows, and prototype-ready states.

Dayvera is an iOS health, recovery, training, planning, and nutrition application. The design should take inspiration from the usability principles behind Apple Health and Apple Fitness—clarity, strong hierarchy, progressive disclosure, calm use of data, native-feeling interactions, large readable type, whitespace, glanceable summaries, and accessibility—without copying Apple's screens, layouts, branding, icons, or proprietary visual assets.

Use the existing Dayvera SwiftUI repository as the behavioral source of truth. Preserve important product logic. The goal is to redesign presentation and interaction hierarchy, not to silently change validated product rules.

---

## 1. First verify the environment

Before designing anything:

1. Confirm the Penpot MCP server is connected and exposes design read/write tools.
2. Confirm the active Penpot file is the file that should contain the Dayvera design.
3. Inspect the current Penpot document structure before creating anything.
4. Inspect the Dayvera repository and current screenshots/flows.
5. Read these project files if present:
   - `QA/README.md`
   - `UX_REDESIGN_HANDOFF.md`
   - `ARCHITECTURE.md`
   - `NUTRITION.md`
   - `IMPLEMENTATION_STATUS.md`
   - `Dayvera/Views/RootView.swift`
   - `Dayvera/Views/DashboardView.swift`
   - `Dayvera/Views/NutritionView.swift`
   - `Dayvera/Views/FoodCaptureView.swift`
   - `Dayvera/Views/NutritionProgressView.swift`
   - `Dayvera/Views/NutritionWhatIfView.swift`
   - `Dayvera/Views/WorkoutsView.swift`
   - `Dayvera/Views/ProgressView.swift`
   - `Dayvera/Views/SettingsView.swift`
   - `Dayvera/Views/DataSourcesView.swift`
6. Review the QA screenshots in the repository and use them to understand current flows and existing behavior.
7. Do not modify the production SwiftUI implementation during the design phase unless explicitly asked. Penpot should first become the visual design source of truth.

If the Penpot MCP is not writable, report that as the blocker instead of pretending the design was created.

---

# 2. Canonical Dayvera information architecture

The final top-level tab bar should contain:

**Today · Plan · Train · Nutrition · Progress**

Settings remains below the main navigation and should not be a sixth tab.

Each tab owns a different recurring user job.

| Tab | User question | Primary action |
|---|---|---|
| Today | What matters most for me today? | Start today's recommended workout |
| Plan | When should I sleep, wake, and train tomorrow? | Apply tomorrow's plan |
| Train | What workout should I start or resume? | Resume or start workout |
| Nutrition | What should I eat/log today and what remains? | Log food |
| Progress | How are recovery, training, and nutrition changing? | Explore trends |

Do not force every tab into the same screen template. They share a design system, but each tab should have its own action hierarchy.

---

# 3. Product-wide design principles

The Dayvera experience should feel:

- calm;
- premium;
- native to iOS;
- easy to scan;
- private and trustworthy;
- data-rich without becoming dense;
- personal without becoming playful or childish;
- highly accessible;
- consistent across light and dark modes;
- usable one-handed;
- explicit about estimated versus measured or confirmed data.

Use the principle:

**Decision first → evidence second → technical detail third.**

Use cards only when grouping or visual priority actually requires them. Avoid a wall of identical rounded cards.

Avoid:
- Apple Fitness-style activity rings;
- decorative gradients everywhere;
- glowing AI treatments;
- excessive shadows;
- duplicated primary actions;
- color-only status;
- medical-dashboard aesthetics;
- raw diagnostic content on normal user screens.

---

# 4. Shared interaction system

All tabs use the same reusable Dayvera components, but action layouts differ by task.

## Primary action

One visually dominant action in a local decision context.

Examples:
- Start Workout
- Apply Plan
- Resume Workout
- Log Food
- Save Meal
- Apply Tomorrow

Minimum comfortable target: 44 pt.

## Secondary action

Examples:
- Adjust
- Alternatives
- Weigh In
- Change Match
- Edit Portion
- Keep Current Target

## Tertiary/detail action

Examples:
- Review Workout
- View Recovery Progress
- View Nutrition
- How This Was Calculated
- Technical Details

## Destructive action

Examples:
- Discard Workout
- Delete Template
- Remove Food
- Undo Applied Plan

Never style destructive actions as the primary brand CTA.

---

# 5. Today screen

The Today tab should answer within a few seconds:

- How am I doing?
- What should I do today?
- Why?
- Is anything important missing or wrong?
- How is nutrition tracking?
- What is coming tomorrow?

Create the standard Today screen with this hierarchy:

## A. Today's Workout — dominant surface

Example:

**TODAY'S WORKOUT**

**Lower Body Strength**

42 min · 6 exercises · Moderate

Recovery
72 · Moderate

Sleep
7h 18m

Training
3 / 4 this week

One concise explanation sentence.

Primary:
**Start Workout**

Secondary:
`Adjust` and `Alternatives`

Tertiary:
`Review Workout →`

Preserve the existing deterministic planner, recovery constraints, candidate rules, and active-workout protection.

On-device AI must never be presented as the authority for workout validity. It may rank valid candidates or improve explanation copy only where the existing implementation allows it.

## B. Recovery Snapshot

One grouped section containing:
- Sleep
- HRV
- Resting Heart Rate

Each metric should show:
- current value;
- comparison to target/baseline;
- status text + symbol;
- secondary source/freshness metadata.

Footer:
`View Recovery Progress →`

Do not make three giant separate cards.

## C. Fuel Today

Compact Nutrition summary only:

**Fuel Today**

820 kcal remaining

1,680 / 2,500 kcal

Protein
142 / 180 g

`View Nutrition →`

Do not duplicate the full Nutrition experience on Today.

## D. Next Up

Compact tomorrow summary:

Wake
6:45 AM

Train
7:15 AM

First commitment
9:00 AM

`Review Plan →`

---

# 6. Plan screen

Plan is outcome-first.

Show:

**Tomorrow**

Built around your first commitment.

Create a schedule timeline:

Bed
10:45 PM

Wake
6:45 AM

Train
7:15–8:00 AM

Ready
8:45 AM

First commitment
9:00 AM

Include a small note:

`Schedule-based planning, not sleep-cycle detection.`

Primary:
**Apply Plan**

Before applying, show exactly what will happen:
- wake alarm;
- detailed workout event if configured;
- privacy-safe Busy events where configured.

Use compact integration rows for Calendar and Alarm permission/configuration state.

After application, replace the CTA surface with:

**Plan Applied**

Then:
- exact scheduled items;
- status;
- `View Scheduled Items`;
- `Undo`.

Partial application or verification uncertainty must not be styled as full success.

Preserve current exact confirmation, receipt verification, calendar-destination rules, and app-owned-only Undo behavior.

---

# 7. Train screen

## Active workout state

If a draft is active:

**Workout in Progress**

Upper Body Strength

8 / 18 sets complete

Primary:
**Resume**

Secondary:
`Discard`

Saved workouts remain visible but cannot start until the draft is finished or discarded.

## No active workout state

Show:
- optional recent-workout fast start;
- Saved Workouts list.

Each saved workout should be a compact row rather than a large card with its own full-width CTA.

Row contents:
- workout name;
- exercise count;
- set count;
- last completion;
- trailing 44 pt Play control.

Tap row → Workout Preview.

Context menu:
- Edit
- Delete

Toolbar:
- New Template
- Exercise Library

---

# 8. Workout Preview

Create a lightweight preview screen:

Workout name

Estimated duration

Today's recovery-related adjustment

Exercise list

Example:

Bench Press
3 × 8

Row
3 × 10

Shoulder Press
3 × 8

Primary:
**Start Workout**

Secondary:
Edit Template

The Play control on Train can remain a fast path that skips preview.

---

# 9. Active Workout

Use a focused full-screen design.

Header:
- Close
- workout title
- Finish

Session status:
- elapsed time
- completed sets / total sets

Exercise section:
- exercise name;
- position, e.g. 2 of 6;
- Technique & Instructions;
- optional progression recommendation.

Set table at standard sizes:
- Set
- Previous
- lb/kg
- Reps
- Complete

At accessibility sizes, convert each set into a vertically labeled editor.

Progression should be compact:

`Suggested: Increase to 140 lb`

`Apply` · `Why`

Rest timer is a sticky bottom accessory:

Rest
1:12

`Skip`

Preserve:
- autosave;
- active draft recovery;
- previous performance;
- lb/kg conversion;
- rest timer behavior;
- set completion;
- notes;
- technique navigation;
- workout finish validation.

---

# 10. Nutrition tab

Nutrition is a first-class daily product area.

It should answer immediately:

- What is my target?
- What have I logged?
- What remains?
- How much protein remains?
- What should I log next?

The Nutrition tab owns:
- daily calories/macros;
- meal logging;
- camera capture;
- food review;
- intake source;
- weigh-in;
- nutrition target changes;
- What-If scenarios.

Historical nutrition analysis belongs in Progress.

---

# 11. Nutrition daily dashboard

Navigation title:

**Nutrition**

Include a clear date selector.

## A. Daily Nutrition Summary — dominant area

Example:

**TRAINING DAY · ESTIMATED TARGET**

**820 kcal remaining**

1,680 of 2,500 logged

Protein
142 / 180 g
38 g remaining

Primary:
**Log Food**

Secondary:
`Weigh In`

Calories and protein receive the highest visual priority.

## B. Macro Progress

Use linear progress, not rings.

Protein
142 / 180 g
79%
38 g remaining

Carbs
175 / 260 g
67%
85 g remaining

Fat
61 / 75 g
81%
14 g remaining

Never rely on color alone.

## C. Meals

Section:
**Meals**

Each row:
- optional image thumbnail;
- meal name;
- time;
- calories;
- protein;
- disclosure.

Repeat/favorite should live in row menus or details, not as large always-visible buttons.

## D. Day Status

Show compactly:
- authoritative intake source;
- training/rest day;
- logging completeness;
- target revision/effective date where relevant.

Primary contextual action:
**Mark Day Complete**

Explain that complete days can become evidence for target adjustment.

## E. Pending adjustment

If an adjustment proposal exists, show it below daily logging because it requires a decision.

## F. Recovery Context

Small informational row only.

Example:
`Recovery: Moderate · 7h 18m sleep`

Do not imply recovery automatically changes calories unless existing product logic actually does so.

---

# 12. Log Food launcher

Tapping **Log Food** should open one native-feeling sheet.

Organize actions by intent.

Capture:
- Take Photo
- Choose Photo

Find or Enter:
- Search Foods
- Enter Nutrition Label

Reuse:
- Recent & Favorite Meals

Advanced:
- Enter Daily Totals

Do not place all these actions directly on the Nutrition dashboard.

---

# 13. Camera flow

The photo flow must be one of the easiest workflows in Dayvera.

Canonical flow:

**Nutrition → Log Food → Take Photo → Camera → Use Photo → Recognition → Review Foods → Meal Editor → Save Meal**

Critical product rule:

**A photo never directly saves calories or macros.**

The recognition model may suggest food candidates and rough portions only.

Nutrient values should come from the trusted matched catalog, nutrition label, manual value, or selected Health source.

---

# 14. Camera screen

Prefer native iOS camera behavior.

Include:
- Cancel
- camera preview
- shutter
- camera switch where appropriate
- Retake
- Use Photo

Do not design an over-custom camera unless required.

Camera denied:
- return to Log Food;
- show inline issue;
- provide Open Settings;
- preserve manual logging alternatives.

---

# 15. Recognition loading

After a photo is accepted:

show the meal image.

Headline:
**Looking for foods…**

Supporting copy:
`Dayvera will suggest foods and rough portions. You'll review everything before anything is saved.`

Use an indeterminate progress indicator.

No fake progress percentage.

---

# 16. Review Foods

This is a critical trust screen.

Title:
**Review Foods**

Show the meal photo.

For each candidate:

**Grilled Chicken**

Suggested from photo

Estimated portion
~140 g

Matched to:
Chicken Breast, Cooked · USDA

231 kcal · 43 g protein

Actions:
`Change Match`
`Edit Portion`
`Remove`

For an unresolved result:

**Sauce**

Food match needed

Primary inline action:
**Find Food**

Provide:
`+ Add Missing Food`

Include visible information text:

`Photos can miss ingredients, oils, sauces, and exact portions.`

Sticky primary:
**Continue to Meal**

Do not show raw AI confidence as if it were nutrient accuracy.

---

# 17. Food Match Search

Native searchable list.

Example results:

White Rice, Cooked · USDA
Brown Rice, Cooked · USDA
Basmati Rice, Cooked · USDA

Rows should remain scannable.

Do not show a full macro table for every search result.

Tap result → Portion Editor.

---

# 18. Portion Editor

Show:

Food name

Amount

Unit

Supported household portion options when available.

Always support grams where the model/catalog supports it.

Live trusted nutrient preview:

Calories

Protein

Carbs

Fat

Source:
USDA / label / manual.

Explicitly indicate:
- `Estimated portion`
or
- `Edited by you`

Primary:
**Done**

---

# 19. Meal Editor

All food-entry methods should converge on one Meal Editor.

Fields:
- meal name;
- date/time;
- optional photo;
- foods.

Each food row:
- name;
- quantity;
- calories;
- protein;
- edit.

Meal total:
- calories;
- protein;
- carbs;
- fat.

Primary:
**Save Meal**

Secondary:
`Add Food`

If saving fails:
- show local error;
- preserve all entered data.

---

# 20. Nutrition label entry

If current implementation is manual label entry, design only that.

Fields:
- food name;
- serving size;
- servings consumed;
- calories;
- protein;
- carbs;
- fat.

Provenance:
**From package label**

Primary:
**Add to Meal**

Do not invent barcode or OCR functionality unless it already exists or is explicitly approved.

---

# 21. Recent & Favorite Meals

Create:
- Recent section
- Favorites section

Each row:
- meal;
- last logged date;
- calories;
- protein.

Tap → review → save.

A faster one-tap Repeat may be offered only if immediate Undo is available and behavior remains clear.

---

# 22. Intake Source

A day must have one authoritative intake source.

Create a single-select screen:

○ Logged Meals

● Apple Health · Source Name

○ Another Health Source

○ Manual Daily Totals

Explain:

`Dayvera uses one authoritative source for a day so nutrition totals are not double-counted.`

If calories exist but protein is missing:

Calories
1,900 kcal

Protein
Unknown

Never show missing macros as 0.

---

# 23. Day Completion

State:

**Day Open**

Primary:
**Mark Day Complete**

Supporting:
`Complete days can be used as evidence when Dayvera evaluates whether your nutrition target needs adjustment.`

After completion:

**Day Complete**

Allow `Reopen Day` only if current product rules support it.

---

# 24. Weigh In

Simple sheet.

Fields:
- date;
- weight;
- optional waist;
- optional hips;
- optional arm;
- optional thigh.

Use configured units.

Do not color body weight as good or bad.

Primary:
**Save**

---

# 25. Nutrition adjustment proposal

Do not silently change calorie targets.

Create a dedicated review surface.

Example:

**Target Adjustment**

Dayvera suggests:

**+150 kcal/day**

Current
2,500 kcal

Proposed
2,650 kcal

Starts
Tomorrow

Evidence:
- weight trend;
- complete intake days;
- recent weights;
- evaluation window.

Primary:
**Apply Tomorrow**

Secondary:
`Keep Current Target`

Tertiary:
`How This Was Calculated`

After acceptance:

**New Target Scheduled**

2,650 kcal

Starts tomorrow.

Preserve current safety behavior preventing inappropriate calorie reductions.

---

# 26. What-If

The What-If screen must look hypothetical.

Persistent label:

**SCENARIO · NOT APPLIED**

Controls:
- average calories;
- protein;
- calorie cycling.

Outputs:
- average calories;
- training-day calories;
- rest-day calories;
- protein;
- carbs;
- fat.

Primary:
**Apply Tomorrow**

Secondary:
`Reset`

Do not style scenario values as if they are already active.

---

# 27. Progress

Progress should ultimately contain:

**Recovery · Training · Nutrition**

Use the simplest understandable selector.

## Recovery

Show a plain-language takeaway first.

Then:
- Sleep Duration
- HRV
- Resting Heart Rate
- body measurements where appropriate.

Charts must:
- show missing dates as gaps;
- include units;
- show source;
- show range;
- have accessible summaries;
- not rely on color alone.

## Training

Top summary:
- sessions;
- working sets;
- training days.

Then:
- Estimated Strength Trend;
- exercise picker;
- chart;
- recent exercise history;
- workout history.

Always label estimated 1RM as estimated.

## Nutrition

Top takeaway:

Example:
`Weight trend is stable while complete-day intake is close to the current target.`

Then:
- Weight Trend
- Calories vs Target
- Protein Adherence
- Measurements
- Target History
- Adjustment History

Incomplete intake days must remain explicit.

Historical target revisions should not be overwritten.

---

# 28. Settings

Keep Settings below Today.

Use native iOS Form-style hierarchy.

Sections:

Connections:
- Apple Health
- Calendar
- Wake Alarms

Personalization:
- Workout Preferences
- Nutrition Profile
- On-Device Personalization

Data:
- Health Data & Sources
- Nutrition Sources
- Calendar Setup

Privacy & Safety:
- local/private summary;
- wellness/fitness—not medical diagnosis;
- privacy policy.

About:
- Dayvera version;
- exercise data attribution;
- USDA attribution;
- licenses.

---

# 29. Health Data & Sources

Separate normal configuration from diagnostics.

Main user layer:
- Apple Health status;
- guidance confidence;
- recovery signals;
- source choice;
- show on Today;
- use in recommendation where allowed;
- freshness;
- coverage.

Move advanced content into:

**Data Diagnostics**

Data Diagnostics may contain:
- query failures;
- technical identifiers;
- data coverage;
- raw sources;
- provider observations;
- safety-only check details;
- confidence definitions.

---

# 30. Calendar Setup

Do not put three different selection models into one huge form.

Create a landing screen:

Planning Calendars
All visible calendars
`Change`

Workout Details
Personal
`Change`

Busy Sharing
Work
`Change`

Then build separate focused selection screens:

Planning Calendars:
- multi-select;
- option to use all visible calendars.

Workout Details:
- single-select writable calendar.

Busy Sharing:
- multi-select;
- disable the details calendar with explanation if it already receives detailed workout data.

Preserve current privacy-safe Busy behavior and no-silent-redirection rules.

---

# 31. Dayvera visual system

Name the design direction:

**Quiet Vitality**

Use:
- SF Pro;
- strong typographic hierarchy;
- large readable values;
- semantic system-like surfaces;
- clear whitespace;
- restrained brand accent;
- minimal borders;
- no default shadows;
- no decorative glass content cards;
- native-feeling navigation and sheets.

Brand accent reference:

Light:
`#4655CC`

Dark:
`#8293FF`

Positive:

Light:
`#0B7A5A`

Dark:
`#65E4BC`

Caution:

Light:
`#8A5600`

Dark:
`#FFC04A`

Negative:

Light:
`#B32645`

Dark:
`#FF718B`

Use semantic background/text tokens rather than hard-coded screen colors.

---

# 32. Typography

Use SF Pro.

Define Penpot text styles approximately corresponding to:

- Large Title
- Title
- Title 2
- Title 3
- Headline
- Body
- Secondary Body
- Caption
- Caption Small
- Stat Large
- Stat Medium
- Stat Small

Engineering mapping should remain SwiftUI semantic fonts with Dynamic Type rather than fixed typography.

Use tabular/monospaced digits for times and changing numeric values where appropriate.

---

# 33. Spacing and geometry

Create shared tokens:

Spacing:
2, 4, 8, 12, 16, 20, 24, 32, 40, 48

Screen horizontal inset:
20 pt standard
16 pt compact

Corner radii:
- Control 12
- Card 18
- Hero 22
- Pill fully rounded

Minimum touch target:
44 × 44 pt.

No fixed-height text containers.

---

# 34. Penpot file structure

Build the Penpot file with these pages:

**00 — Cover**

**01 — Foundations**

**02 — Components**

**03 — Patterns**

**04 — Main Screens**

**05 — Nutrition & Camera Flow**

**06 — User Flows**

**07 — Prototype**

**08 — Engineering Handoff**

**09 — QA & States**

If Penpot supports sub-pages/boards differently, preserve the same conceptual organization.

---

# 35. Components to create

Create reusable components rather than one-off screen fragments.

Core:
- Primary Button
- Secondary Button
- Tertiary Action
- Destructive Action
- Status Label
- Inline Issue
- Section Header
- Empty State
- Loading State
- Success State

Today:
- Decision Card
- Recovery Snapshot
- Fuel Summary
- Next Up Row

Plan:
- Schedule Timeline
- Integration Row
- Applied Plan State
- Scheduled Item Row

Train:
- Active Workout Hero
- Template Row
- Workout Set Row
- Progression Row
- Rest Timer

Nutrition:
- Daily Nutrition Summary
- Macro Progress Row
- Compact Macro Strip
- Log Food Launcher Row
- Recognition Candidate
- Food Match Row
- Portion Row
- Provenance Label
- Meal Row
- Day Status
- Intake Source Row
- Adjustment Proposal
- Scenario Banner
- Body Measurement Row

Progress:
- Trend Section
- Chart Header
- Metric Summary
- Date Range Control
- History Row

Settings:
- Settings Row
- Connection Status Row
- Diagnostics Row

Create Light/Dark variants where necessary.

Create accessibility-size layout examples for important components.

---

# 36. Patterns to document

Create pattern examples for:

**Decision First**
Used by Today.

**Outcome → Action → Status**
Used by Plan.

**Resume / Start**
Used by Train.

**Target → Logged → Remaining**
Used by Nutrition.

**Capture → Review → Confirm**
Used by food camera.

**Insight → Chart → Detail**
Used by Progress.

**Configuration → Diagnostics**
Used by Health/Data settings.

---

# 37. Main screen set

Design these production-quality screens.

Onboarding:
- First Run
- Nutrition Setup
- Target Review

Today:
- Normal
- Health unavailable
- Limited recovery
- Active workout already exists

Plan:
- Ready
- Calendar disconnected
- Destination needs repair
- Applied
- Partial application / needs review

Train:
- Empty
- Saved workouts
- Active workout draft
- Workout Preview
- Active Workout

Nutrition:
- Setup
- Target Review
- Daily Dashboard
- Empty intake
- Day complete
- Log Food Sheet
- Camera permission state
- Camera capture
- Recognition Loading
- Photo Review
- Unresolved Food
- Food Search
- Portion Editor
- Meal Editor
- Nutrition Label Entry
- Recent/Favorite Meals
- Intake Source
- Manual Daily Totals
- Weigh In
- Adjustment Proposal
- Adjustment Scheduled
- What-If

Progress:
- Recovery
- Training
- Nutrition

Settings:
- Settings
- Health Data & Sources
- Signal Detail
- Data Diagnostics
- Calendar Setup
- Planning Calendar Selection
- Details Calendar Selection
- Busy Calendar Selection

---

# 38. Required screen variants

For important screens create:

- Light Mode
- Dark Mode
- standard Dynamic Type
- Accessibility Extra Large
- Increase Contrast

For motion/media states document Reduce Motion behavior.

Nutrition must also include:
- camera unavailable;
- recognition unavailable;
- recognition failed;
- unresolved ingredient;
- missing macros;
- no target;
- no intake;
- Health dietary source selected;
- adjustment pending.

---

# 39. Prototype flows

Build clickable interactions where Penpot supports them.

## Flow 1 — Daily workout

Today
→ Review Workout
→ Start Workout
→ Active Workout
→ Complete Set
→ Rest Timer
→ Finish
→ Workout Saved
→ Progress Training

## Flow 2 — Nutrition camera

Nutrition
→ Log Food
→ Take Photo
→ Camera
→ Use Photo
→ Recognition
→ Review Foods
→ Change Match
→ Edit Portion
→ Add Missing Sauce
→ Meal Editor
→ Save Meal
→ Daily macros update
→ Mark Day Complete
→ Nutrition Progress

## Flow 3 — Tomorrow plan

Today
→ Review Plan
→ Plan
→ Apply
→ Confirmation
→ Applied
→ Scheduled Items
→ Undo

## Flow 4 — Nutrition adjustment

Nutrition
→ Adjustment Proposal
→ Review Evidence
→ Apply Tomorrow
→ Scheduled Target
→ Target History

---

# 40. Accessibility requirements

Design for:

- Dynamic Type;
- Accessibility Extra Large;
- VoiceOver;
- Increase Contrast;
- Reduce Motion;
- Dark Mode;
- sufficient contrast;
- at least 44 pt touch targets;
- no color-only status;
- meaningful chart summaries;
- text wrapping rather than truncation;
- explicit units;
- keyboard-safe input layouts.

VoiceOver examples:

`Protein. 142 of 180 grams. 79 percent. 38 grams remaining.`

Recognition candidate:

`Grilled chicken. Suggested from photo. Estimated portion 140 grams. Matched to USDA chicken breast. 231 calories, 43 grams protein.`

---

# 41. Data visualization system

Daily:
- direct values;
- progress;
- tiny trend only when useful.

Weekly:
- sleep bars;
- HRV/RHR line + points;
- calories vs target;
- protein adherence;
- strength points.

Monthly/longer:
- reduce label density;
- preserve raw underlying data;
- label any aggregation explicitly.

Goal completion:
- linear progress;
- value + target text.

Comparisons:
- current vs baseline;
- direct delta text;
- reference lines.

Never use activity-ring imitation.

---

# 42. Engineering handoff annotations

On the Engineering Handoff page, annotate how designs map to SwiftUI:

Root navigation:
`TabView` + `NavigationStack`

Today:
`ScrollView` + `LazyVStack`

Plan:
`ScrollView` + `LazyVStack`

Train:
`List` / `ScrollView`

Active Workout:
`List` + `Grid` + `safeAreaInset`

Nutrition:
`ScrollView` + `LazyVStack`

Log Food:
`.sheet`

Camera:
existing AVFoundation/UIKit bridge or native implementation

Photo library:
`PhotosPicker`

Meal Editor:
`Form`

Food Search:
`List` + `.searchable`

Progress:
Swift Charts

Settings:
`Form`

Confirmations:
`confirmationDialog`

Icons:
SF Symbols where appropriate.

---

# 43. Product logic that must not be redesigned away

Do not change these rules:

1. The deterministic workout planner remains authoritative.
2. On-device AI cannot invent unsafe workout prescriptions.
3. Exercise/movement exclusions remain hard rules.
4. Active workout drafts cannot be overwritten.
5. Health data provenance must remain explicit.
6. Missing dates remain gaps.
7. Confidence, completeness, freshness, and sensor accuracy remain distinct concepts.
8. Calendar/Alarm changes require confirmation.
9. Undo only removes Dayvera-owned scheduled items.
10. Photo recognition suggests food candidates and rough portions only.
11. Recognition does not directly provide trusted nutrient totals.
12. Foods and portions must be reviewed before meal save.
13. Nutrients come from matched USDA/catalog, label, manual values, or the selected supported source.
14. One authoritative nutrition intake source is used per day.
15. Missing macros remain unknown, not zero.
16. Complete-day state affects adaptation evidence.
17. Nutrition target revisions remain versioned/historical.
18. Target adjustments require explicit acceptance.
19. Accepted target changes start on their intended future effective date.
20. Safety rules that block inappropriate calorie reductions remain intact.
21. Manual food logging remains available if Apple Intelligence/local recognition is unavailable.
22. No new backend/account/cloud dependency is introduced just for the redesign.

---

# 44. Penpot execution workflow

Work incrementally.

Phase 1:
Inspect code + existing Penpot file.

Phase 2:
Create foundations/tokens.

Phase 3:
Create reusable components.

Phase 4:
Create Today, Plan, Train.

Phase 5:
Create Nutrition core.

Phase 6:
Create Camera / Review / Meal flows.

Phase 7:
Create Progress.

Phase 8:
Create Settings and diagnostics.

Phase 9:
Create prototype links.

Phase 10:
QA all required states.

After each phase:
- verify editable Penpot structure;
- inspect visual output;
- fix obvious hierarchy/layout issues;
- record what is complete;
- continue.

Do not create everything as flattened SVG/image assets. The Penpot output should remain editable and component-based.

---

# 45. Final deliverables

The Penpot file is complete only when it contains:

- semantic Dayvera design tokens;
- typography styles;
- spacing/radius system;
- reusable component library;
- complete five-tab UI;
- onboarding;
- settings;
- camera flow;
- food recognition review;
- meal editor;
- macro tracking;
- nutrition setup;
- target review;
- target adjustment;
- What-If;
- active workout;
- recovery/training/nutrition progress;
- error/empty/loading/success states;
- light/dark examples;
- accessibility examples;
- clickable prototype flows;
- engineering annotations.

Also create a repository handoff document named:

`PENPOT_DESIGN_HANDOFF.md`

It should contain:
- Penpot file/project reference;
- page list;
- design token names;
- reusable component names;
- screen inventory;
- prototype flow inventory;
- known limitations;
- final decisions;
- implementation order for SwiftUI.

Do not start a large production-code rewrite until the Penpot design is coherent and the major screens have been visually reviewed.

---

# 46. Definition of done

The design is done only when:

- each tab clearly answers its own primary user question;
- there is only one dominant action per decision context;
- Nutrition makes camera logging obvious but does not overstate AI accuracy;
- Today remains glanceable;
- Plan clearly shows what will happen before Apply;
- Train clearly protects and resumes active drafts;
- Progress tells a story before showing charts;
- Settings separates normal configuration from diagnostics;
- all important states have Light/Dark designs;
- accessibility-sized layouts do not truncate or overlap;
- all major screens are built from shared Penpot components/tokens;
- the Penpot file can serve as the visual source of truth for Codex implementing SwiftUI.

Start now by inspecting the connected Penpot file and the Dayvera repository, then build the design in the phased order above.
