# Onboarding with Pip — design

## Why

A new user opens Mivu with no targets, so Today and Coach have nothing to measure
against. Onboarding asks a few questions, and ChatGPT turns the answers into
daily calorie and macro targets. Diet, conditions and allergies are kept, so
Coach can give advice that fits the person. Pip hosts the flow so it feels like
meeting the companion, not filling in a form.

## Who sees it

- It runs on first launch only, for a new diary with no goal record.
- Existing profiles are never forced through it.
- Settings gets "Redo setup with Pip", which runs the same flow prefilled with
  the saved answers.

## Flow

1. **Hello.** Pip waves (`greeting`), with Start and "Set up later".
   "Set up later" goes straight to the app with no targets.
2. **Questions**, one card per screen. Pip stays above the card, `attentive`
   while you answer and nodding (`saved`) on Next.
   - Height. Required. Toggle cm / ft-in.
   - Current weight. Required. Toggle kg / lb. Saved as a normal weight entry.
   - Birth year. Required.
   - Sex: Female / Male / Prefer not to say. Optional.
   - Target weight. Required. Toggle kg / lb.
   - Pace: Gentle, Steady (the default) or Faster, about 0.25, 0.5 and
     0.75 kg a week. Hidden when the target equals the current weight
     (the goal is to keep it).
   - Diet and health: chips plus an "Anything else?" text field. Optional.
     - Chips: gluten-free, lactose-free, vegetarian, vegan, type 1 diabetes,
       type 2 diabetes, Crohn's, IBS, nut allergy.
     - The text field takes other allergies, intolerances and dislikes.
3. **Connect ChatGPT**, using the existing connection flow. If you are already
   connected, this step is skipped.
4. **Working.** Pip plays `thinking`. Formula targets show at once, marked
   "Estimate"; ChatGPT replaces them when it answers.
5. **Results.**
   - Shows: kcal, protein, carbs and fat, plus two or three sentences from
     ChatGPT on how it got them.
   - Every number can be edited before you accept.
   - Accept saves the targets as today's goal record and plays `saved`.
   - If ChatGPT failed, the screen keeps the estimate, shows Retry, and Pip
     plays `recovery`.

## Targets

- **Formula (the instant fallback):**
  - Calories at rest use Mifflin–St Jeor. "Prefer not to say" uses the
    midpoint of the female and male results.
  - Activity is not asked, to keep questions to a minimum: everyone gets
    light activity (×1.375) until Apple Health and sport apps supply it.
  - Pace adjusts by ±(kg a week × 7700 / 7) kcal a day.
  - The total never goes below 1200 kcal.
  - Macros: protein 1.6 g per kg of current weight, fat 30% of kcal, and
    carbs the rest.
- **ChatGPT:**
  - One request on the existing Responses client and the user's subscription.
  - Input: the answers (diet, conditions and allergies are context only).
  - Output: strict JSON with `kcal`, `protein`, `carbs`, `fat` and
    `explanation`.
  - The formula result is sent along as a reference.
  - Values are checked before they are shown: all present, kcal 1200–5000,
    and macro calories within 15% of kcal. If any check fails, the estimate
    is kept and Retry is offered.
- **Health conditions are context only.** Targets are computed the normal
  way. There is no special care note, and Mivu never suggests medication or
  insulin doses.

## Data

- `DiaryProfile` gains optional fields:
  - `heightCm`, `birthYear` and `sex` (female, male or unspecified);
  - `pace`;
  - `dietTags: [String]` and `healthNotes: String`.
- All new fields decode as absent in old diaries, so nothing migrates
  destructively. Backups and export carry them through the profile.
- Weight is stored as a `WeightEntry`, in kg.
- Targets and the goal weight are stored as a `GoalRecord`, with exercise
  credit kept at its current default.
- Settings can edit the diet and health fields. Coach and meal analysis
  requests include them next to the existing `preferences`, so advice and
  estimates respect them, for example gluten-free or carb awareness.
- Units are a display choice. Values are always stored metric.

## Constraints

- English only. Dynamic Type, VoiceOver labels on Pip and every control,
  reduced motion (Pip holds still), and 44-point targets.
- Synthetic inputs only in tests. Nothing is logged from the ChatGPT response
  beyond the existing diagnostics.
- Native SwiftUI, reusing `CompanionView`, the gesture library, the
  connection flow and `ResponsesClient`. No new dependencies.

## Non-goals

- Apple Health or sport-app integration.
- New Pip art or gestures.
- Medical guidance.
- Forcing existing users through onboarding.
- Hebrew.

## Left to the builder

- Card layout and copy tone, within the app's design system.
- The exact prompt wording.
- Where "Redo setup" sits in Settings.
