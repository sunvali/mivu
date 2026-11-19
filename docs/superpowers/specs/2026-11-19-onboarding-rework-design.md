# Onboarding rework — design

Supersedes the flow and target rules in [the October onboarding design](2026-10-20-onboarding-design.md).
Its data model, Settings entry point and non-goals still apply. Research behind the changes:
`reports/Diet app onboarding patterns.md` in the owner's working copy. In short, the apps closest to Mivu
ask a few questions that change the number and then show the math. Long quizzes only serve paywalls.

## Why

Mivu is on the App Store, and success for setup is **targets saved**. Today, the ChatGPT
connect step sits before the targets screen, so a declined or failed sign-in blocks the one
outcome that matters. Everyone gets "light" activity. The flow uses plain text fields, and the
targets have no sex-aware floor, no pace cap and no pregnancy handling.

## Flow

Hello → Height → Weight → Birth year → Sex → Goal weight → Activity and pace → How you eat → Targets → Today.

1. **Hello.** As today, with copy that no longer promises ChatGPT up front.
2. **Height, Weight.** One question per screen. A large rounded number sits above a horizontal ruler.
   - Dragging the ruler snaps to 1 cm, 1 in, 0.1 kg or 0.1 lb, with a selection haptic on each step.
   - The number is a text field, so tapping it types an exact value.
   - A segmented control switches between cm and ft/in, and between kg and lb. Values are stored in metric.
   - Starting values: what is saved, otherwise 170 cm and 70 kg.
3. **Birth year.** A native wheel from 1900 to this year − 13. It starts at the saved year,
   otherwise 30 years ago. The existing 13+ rule stays.
4. **Sex.** Three large cards: Female, Male, Prefer not to say. On a first run nothing is preselected.
   Tapping a card selects it and moves on. Skip in the toolbar keeps "Prefer not to say".
5. **Goal weight.** The same ruler as Weight, starting at the saved goal or the current weight.
   - The caption under the number reads "7.4 kg to lose", "3 kg to gain" or "Keep my weight".
   - A target below BMI 18.5 shows the existing message, and Continue stays disabled.
6. **Activity and pace.**
   - Three activity cards: Mostly sitting (×1.2), On my feet some (×1.375, the default) and Very active (×1.55).
   - Pace rows (Gentle, Steady, Faster) show each pace's daily kcal and its goal month, for example
     "1,420 kcal a day · by March 2027". They update live and are hidden when keeping weight.
   - When a pace hits the calorie floor, the row says "Mivu won't go below 1,200 kcal a day."
7. **How you eat.**
   - A "Right now" row with a single *Pregnant or breastfeeding* chip sits above the existing diet and
     condition chips and the notes field.
   - Choosing it shows "Mivu will aim to keep your weight steady. Your doctor or midwife is the
     best guide for how much to eat right now."
8. **Targets.** The formula estimate shows immediately and every number stays editable.
   - **Save my targets** is the primary button.
   - **Tune with ChatGPT** is a glass secondary button, with the caption "Shares your answers with ChatGPT
     after you agree." It runs the existing consent and sign-in, then asks ChatGPT and replaces the numbers in place.
   - When ChatGPT is already connected, tuning starts automatically, as today.
   - The button is hidden when the plan can never connect.
   - The separate Connect step and its Apple Intelligence choice are removed. Apple Intelligence
     can't tune targets.
9. **Today.** Unchanged. Its empty-meals card ("Your first meal starts here") already points at
   Snap It and Chat with Pip on every empty day. A one-time "You're all set!" line would read
   wrong on later days, so no second nudge is added.

No permission prompts and no rating request anywhere in setup. Redo setup from Settings runs the
same flow, prefilled.

## Targets

- **Formula.**
  - Mifflin–St Jeor times the chosen activity factor. A profile without an activity uses ×1.375, as before.
  - Pace in kg a week is `min(pace, 1% of current weight)`. It moves energy by kg a week × 7700 / 7.
- **Floor.** 1,200 kcal for female, 1,500 for male and 1,350 for prefer not to say. It applies to the
  estimate and to ChatGPT's reply. A reply under the floor is rejected, so the estimate stays and
  Retry is offered. The prompt states the floor.
- **Pregnant or breastfeeding.** No deficit or surplus: targets keep weight. The prompt says so.
- **Goal month.**
  - The effective weekly change is the real energy gap (maintenance − kcal) × 7 / 7700, which the floor can shrink.
  - The goal date is today plus |current − goal| ÷ that change, in weeks. It shows as month and year.
- Macros are unchanged: protein 1.6 g/kg, fat 30 % of kcal, carbs the rest.

## Data

`ProfileAbout` gains `activity: Activity?` (`sitting`, `some`, `active`), and `nil` means the old default.
It must be optional because the synthesized decoder needs every non-optional key. Old profiles and
backups must keep decoding, and older apps ignore the extra key. The pregnancy answer is a diet tag
("Pregnant or breastfeeding") that already reaches Coach. No migrations.

## Shared control

`MeasureRuler` holds the large number field and the ruler, and is reused in this PR by:
- the morning weight editor;
- the weight correction editor;
- the goal editor's optional weight goal.

Each keeps its text field's accessibility identifier, so typing still works for people and tests.

Accessibility:
- The ruler is one adjustable element ("Weight, 72.4 kilograms") that steps by one whole unit.
- The number field types exact values.
- Text and the number scale with Dynamic Type. Touch targets are 44 pt or larger.
- Under Reduce Motion, the ruler snaps without animation.

## Constraints

English is the acceptance language. New strings are added to every bundled catalog language
(he, es, ru) so `languages.py` stays green. No new dependencies. Synthetic data in tests. Android
follows in a later PR.

## Non-goals

Health or notification prompts in setup, an 18+ gate, new Pip art, a first meal inside setup,
paywalls.
