# Dayvera nutrition methodology

Dayvera connects food logging, training, and recovery on the device. All numerical targets and adjustments are deterministic. Apple's on-device image model proposes visible foods and rough portions; it never supplies authoritative nutrient values or overrides the calculation engine.

## Data and food estimates

The bundled catalog contains USDA FoodData Central SR Legacy records with energy, protein, carbohydrate, fat, and available household portion weights. Only records containing all four nutrients are included. Nutrients are scaled from values per 100 g. The catalog is a historical reference, not a current branded-product database. Source IDs and dataset version are saved with each food entry. Photo-derived portion provenance remains visible after user confirmation. Unknown dishes require ingredient breakdown or manual/label values. Hidden oils and sauces cannot be reliably inferred from a photo.

Source: https://fdc.nal.usda.gov/download-datasets/

Regenerate from the official SR Legacy JSON zip:

```sh
python3 Scripts/import_food_catalog.py /path/to/FoodData_Central_sr_legacy_food_json_2018-04.zip Dayvera/Resources/FoodCatalog.json
```

A day's authoritative intake is Dayvera meals, a daily manual total, or one selected Apple Health source. These sources are not silently summed. Missing values remain unknown. Manual values require explicit confirmation; zero means none, not unavailable. Database calories may differ from 4/4/9 arithmetic because of fiber and food-specific energy factors.

## Energy and macros

Mifflin–St Jeor: RMR = 10 × kg + 6.25 × cm − 5 × age + coefficient. The original sex-based coefficients are +5 and −161. Choosing both uses their midpoint and widens the displayed estimate range. TDEE = RMR × whole-day activity factor (1.2, 1.375, 1.55, or 1.725). Occupation, movement and training are considered together; workout calories are not added a second time.

- Muscle gain: default 5% surplus; initial setting 5–10%.
- Maintenance/recomposition: maintenance.
- Fat loss: default 10% deficit; initial setting 10–15%.
- Protein: maintenance/gain 1.6–2.2 g/kg (default 1.8); loss/recomposition 1.8–2.2 (default 2.0).
- Fat: 25% energy by default; 20–35% and at least 0.6 g/kg within this planning model.
- Carbohydrate: remaining energy. Allocate protein/carbohydrate/fat at 4/4/9 kcal per gram.

The ±15% starting maintenance range is a heuristic uncertainty allowance, not a calibrated confidence interval. Display rounding to 50 kcal and 5 g deliberately avoids false precision; calculations retain unrounded values. Displayed rounded macros and percentages can have small rounding differences. Body composition is context, not grounds to trust a consumer scale's calorie estimate more than the initial equation.

Training/rest cycling has a 200-kcal difference and preserves the weekly average: training = base + 200 × (7 − trainingDays)/7; rest = base − 200 × trainingDays/7. Protein stays consistent. Infeasible macros or inadequate rest-day energy reject the scenario. A scenario never forecasts exact muscle/fat gain or weight-loss dates.

## Gradual adaptation

The 21-day evaluation needs 18 confirmed complete intake days, at least four weigh-in days each week, one consistent weight source and average absolute calorie deviation within 10% of the saved targets. Use daily weight medians and a median pairwise slope over real dates. Missing days are not filled.

Planning weight-change bands: gain +0.1–0.25%/week; maintenance ±0.1%; loss −0.25–0.5%. Recomposition does not adjust calories based on scale change alone. Two weekly windows must agree on the direction, and the current target must have been effective for at least 28 days. A suggestion is emitted at most once per seven days; accepted changes restart the observation period. Suggestions change the daily average by 100 kcal or 5%, whichever is smaller, within conservative bounds; suggestions require explicit review. Changes take effect the next local day. Prior targets and input snapshots remain immutable.

Food-log completeness and measurement consistency describe available evidence, not sensor accuracy or clinical certainty. Stable weight plus complete records can yield an observed maintenance estimate, which remains susceptible to reporting error. Consistently logged intake below a gain target prompts a possible under-fueling message, not a diagnosis.

## Boundaries

Automated targets require adult eligibility and are unavailable for pregnancy/breastfeeding or reported needs for professionally supervised nutrition. Automated fat-loss advice is unavailable for underweight users. Targets cannot fall below estimated RMR or the configured deficit guardrail. These are application limits, not proof that an intake is safe or adequate. Illness/concerning symptoms pause reductions, including initial fat-loss deficits and profile edits that would lower the existing target. Honest food logging remains available outside recommendation bounds.

Nutrition supports overall muscle growth; targeted resistance training provides the local stimulus. Muscle priorities show completed working sets and do not change macro allocation by body region. Sleep and recovery are displayed as context, not calorie multipliers or diagnoses of REDs.

## Evidence

- Mifflin et al., resting energy equation: https://pubmed.ncbi.nlm.nih.gov/2305711/
- Morton et al., protein and resistance training meta-analysis: https://pubmed.ncbi.nlm.nih.gov/28698222/
- Helms et al., small and large energy surpluses: https://link.springer.com/article/10.1186/s40798-023-00651-y
- IOC, limitations of energy-availability assessment: https://doi.org/10.1136/bjsports-2023-107359
- NIDDK, adult/pregnancy applicability: https://www.niddk.nih.gov/health-information/weight-management/body-weight-planner

The implementation's defaults are conservative product choices informed by this evidence; they are not validated personalized clinical prescriptions.
