package com.yakov103.mivu.diary

import java.util.UUID
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class DiaryValidationTest {
    private val valid: DiarySnapshot = SwiftJson.decodeFromJsonElement(
        DiarySnapshot.serializer(),
        SwiftJson.parseToJsonElement(javaClass.classLoader!!.getResource("archive/ios-v4-full.json")!!.readText())
            .jsonObject["snapshot"]!!,
    )

    private fun rejects(s: DiarySnapshot, manifests: Boolean = false) {
        try {
            s.validate()
            if (manifests) validateArchiveManifests(s)
            fail("expected InvalidData")
        } catch (e: DiaryError.InvalidData) {
            assertTrue(e.reason.isNotEmpty())
        }
    }

    private fun DiarySnapshot.profile(f: (DiaryProfile) -> DiaryProfile) = copy(profile = f(profile))
    private fun DiarySnapshot.firstMeal(f: (DiaryMeal) -> DiaryMeal) = copy(meals = listOf(f(meals[0])) + meals.drop(1))
    private fun DiarySnapshot.firstTurn(f: (CoachTurn) -> CoachTurn) = copy(coachTurns = listOf(f(coachTurns[0])) + coachTurns.drop(1))

    @Test fun validFixturePasses() {
        valid.validate()
        validateArchiveManifests(valid)
    }

    @Test fun schemaVersionMustBe1() = rejects(valid.copy(schemaVersion = 2))

    @Test fun revisionRange() {
        rejects(valid.copy(revision = -1))
        rejects(valid.copy(revision = 10_000_000))
    }

    @Test fun profileNameLength() {
        rejects(valid.profile { it.copy(name = "   ") })
        rejects(valid.profile { it.copy(name = "x".repeat(201)) })
        valid.profile { it.copy(name = "x".repeat(200)) }.validate()
        // 200 family emoji are 200 graphemes (many more code points) and must pass like Swift's String.count.
        valid.profile { it.copy(name = "👨‍👩‍👧".repeat(200)) }.validate()
    }

    @Test fun languageEnOrHe() {
        valid.profile { it.copy(language = "he") }.validate()
        rejects(valid.profile { it.copy(language = "fr") })
    }

    @Test fun timeZoneMustBeKnown() = rejects(valid.profile { it.copy(timeZoneID = "Mars/Base") })

    @Test fun liveIdsDisjointFromTombstones() {
        rejects(valid.copy(deletedMealIDs = valid.deletedMealIDs + valid.meals[0].id))
        rejects(valid.copy(deletedWeightIDs = valid.deletedWeightIDs + valid.weights[0].id))
        rejects(valid.copy(deletedWorkoutIDs = valid.deletedWorkoutIDs + valid.workouts[0].id))
    }

    @Test fun oneWeightPerDay() {
        val linked = valid.weights.first { it.dayID != null }
        rejects(valid.copy(weights = valid.weights + linked.copy(id = UUID.randomUUID())))
    }

    @Test fun photoBytesRange() {
        rejects(valid.firstMeal { it.copy(photos = listOf(it.photos[0].copy(data = ByteArray(0))) + it.photos.drop(1)) })
        rejects(valid.firstMeal { it.copy(photos = listOf(it.photos[0].copy(data = ByteArray(10_000_001))) + it.photos.drop(1)) })
    }

    @Test fun itemQuantityRange() {
        fun withQuantity(q: Double) = valid.firstMeal { m -> m.copy(items = listOf(m.items[0].copy(quantity = q)) + m.items.drop(1)) }
        rejects(withQuantity(-1.0))
        rejects(withQuantity(100_001.0))
        rejects(withQuantity(Double.NaN))
    }

    @Test fun awaitingReviewNeedsProposal() {
        val meal = valid.meals[0]
        val sub = meal.submissions.first { it.state == SubmissionState.awaitingReview }.copy(proposal = null)
        rejects(valid.firstMeal { it.copy(submissions = it.submissions.map { s -> if (s.id == sub.id) sub else s }) })
    }

    @Test fun manualAcceptanceNeedsNewerRevision() {
        val meal = valid.meals.first { m -> m.submissions.any { it.manualAcceptance != null } }
        val sub = meal.submissions.first { it.manualAcceptance != null }
        val broken = meal.copy(revision = sub.baseRevision)
        rejects(valid.copy(meals = valid.meals.map { if (it.id == meal.id) broken else it }))
    }

    @Test fun receiptCommittedRevisionRange() {
        fun withRevision(r: Int) = valid.firstTurn { t -> t.copy(receipts = listOf(t.receipts[0].copy(committedRevision = r)) + t.receipts.drop(1)) }
        rejects(withRevision(0))
        rejects(withRevision(valid.revision + 1))
    }

    @Test fun replyExcerptLimit() {
        val t = valid.coachTurns[0]
        val manifest = t.submissionManifest!!
        rejects(valid.firstTurn { it.copy(submissionManifest = manifest.copy(reply = manifest.reply!!.copy(excerpt = "x".repeat(281)))) })
    }

    @Test fun manifestTextFingerprint() {
        val manifest = valid.coachTurns[0].submissionManifest!!
        val bad = valid.firstTurn { it.copy(submissionManifest = manifest.copy(textFingerprint = "0".repeat(64))) }
        bad.validate()
        rejects(bad, manifests = true)
    }

    @Test fun attachmentsAtMost8() {
        val manifest = valid.coachTurns[0].submissionManifest!!
        val extra = (1..9).map { CoachSubmissionManifest.Attachment(UUID.randomUUID(), PhotoRole.unspecified, valid.coachTurns[0].capturedAt, "a".repeat(64)) }
        rejects(valid.firstTurn { it.copy(submissionManifest = manifest.copy(attachments = extra)) }, manifests = true)
        assertEquals(manifest.attachments.size <= 8, true)
    }
}
