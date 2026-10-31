package com.yakov103.mivu.onboarding

import com.yakov103.mivu.coach.CoachInferenceInput
import com.yakov103.mivu.diary.NutritionValues
import com.yakov103.mivu.diary.ProfileAbout
import com.yakov103.mivu.diary.ProfileAbout.Pace
import com.yakov103.mivu.diary.ProfileAbout.Sex
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of ios/MivuTests/OnboardingTargetsTests.swift: the same synthetic answers and expected values. */
class OnboardingTargetsTest {
    private fun answers(sex: Sex, heightCm: Double, weightKg: Double, targetKg: Double, birthYear: Int, pace: Pace = Pace.steady) =
        OnboardingAnswers(ProfileAbout(heightCm, birthYear, sex, pace, emptyList(), ""), weightKg, targetKg)

    @Test fun estimateLosesAtTheChosenPace() {
        val targets = answers(Sex.female, 165.0, 70.0, 62.0, 1990).estimate(year = 2026)
        assertEquals(NutritionValues(kcal = 1360.0, carbs = 127.0, protein = 112.0, fat = 45.0), targets)
    }

    @Test fun estimateKeepsWeightWithTheMidpointWhenSexIsSkipped() {
        assertEquals(2330.0, answers(Sex.unspecified, 180.0, 80.0, 80.0, 1996).estimate(year = 2026).kcal)
    }

    @Test fun estimateNeverGoesBelowTheFloor() {
        assertEquals(1200.0, answers(Sex.female, 150.0, 45.0, 40.0, 1950, Pace.faster).estimate(year = 2026).kcal)
    }

    @Test fun losingBelowAHealthyWeightIsNotATarget() {
        assertTrue(answers(Sex.female, 165.0, 70.0, 62.0, 1990).targetIsHealthy)
        assertFalse(answers(Sex.female, 165.0, 55.0, 48.0, 1990).targetIsHealthy)
        assertTrue(answers(Sex.female, 165.0, 45.0, 48.0, 1990).targetIsHealthy)
        assertTrue(answers(Sex.female, 165.0, 48.0, 48.0, 1990).targetIsHealthy)
    }

    @Test fun replyIsAcceptedOnlyWhenTheNumbersHoldTogether() {
        val good = """```json {"kcal":1800,"protein":120,"carbs":200,"fat":60,"explanation":"A steady deficit."} ```"""
        assertEquals(NutritionValues(kcal = 1800.0, carbs = 200.0, protein = 120.0, fat = 60.0), OnboardingTargets.parse(good)?.targets)
        assertEquals("A steady deficit.", OnboardingTargets.parse(good)?.explanation)
        assertNull(OnboardingTargets.parse("""{"kcal":900,"protein":60,"carbs":90,"fat":30,"explanation":"Low."}"""))
        assertNull(OnboardingTargets.parse("""{"kcal":1800,"protein":50,"carbs":50,"fat":20,"explanation":"Off."}"""))
        assertNull(OnboardingTargets.parse("Sorry, I can't help with that."))
    }

    @Test fun inputSendsTheAnswersAsSortedJsonAfterTheDeveloperRules() {
        val a = answers(Sex.female, 165.0, 70.0, 62.0, 1990)
        val input = OnboardingTargets.input(a, a.estimate(2026), 2026)
        assertEquals(CoachInferenceInput.Role.developer, (input[0] as CoachInferenceInput.Message).role)
        assertTrue((input[0] as CoachInferenceInput.Message).text.endsWith("""{"kcal": number, "protein": grams, "carbs": grams, "fat": grams, "explanation": "two or three short, friendly sentences"}"""))
        assertEquals("""{"activity":"unknown, assume light","age":36,"diet":[],"formula_estimate":{"carbs_g":127,"fat_g":45,"kcal":1360,"protein_g":112},""" +
            """"goal":"lose about 0.5 kg a week","height_cm":165,"notes":"","sex":"female","target_weight_kg":62,"weight_kg":70}""",
            (input[1] as CoachInferenceInput.Message).text)
    }
}
