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

    private fun rejects(s: DiarySnapshot, reason: String, manifests: Boolean = false) {
        try {
            s.validate()
            if (manifests) validateArchiveManifests(s)
            fail("expected InvalidData($reason)")
        } catch (e: DiaryError.InvalidData) {
            assertEquals(reason, e.reason)
        }
    }

    private fun DiarySnapshot.profile(f: (DiaryProfile) -> DiaryProfile) = copy(profile = f(profile))
    private fun DiarySnapshot.firstMeal(f: (DiaryMeal) -> DiaryMeal) = copy(meals = listOf(f(meals[0])) + meals.drop(1))
    private fun DiarySnapshot.firstTurn(f: (CoachTurn) -> CoachTurn) = copy(coachTurns = listOf(f(coachTurns[0])) + coachTurns.drop(1))

    @Test fun boundariesAccepted() {
        val m = valid.coachTurns[0].submissionManifest!!
        val eight = (1..8).map { CoachSubmissionManifest.Attachment(UUID.randomUUID(), PhotoRole.unspecified, valid.coachTurns[0].capturedAt, "a".repeat(64)) }
        valid.firstTurn { it.copy(submissionManifest = m.copy(attachments = eight)) }.let { validateArchiveManifests(it) }
        valid.firstTurn { it.copy(submissionManifest = m.copy(reply = m.reply!!.copy(excerpt = "x".repeat(280)))) }.validate()
        valid.firstTurn { t -> t.copy(receipts = listOf(t.receipts[0].copy(committedRevision = valid.revision)) + t.receipts.drop(1)) }.validate()
        valid.firstMeal { mm -> mm.copy(items = listOf(mm.items[0].copy(quantity = 100_000.0)) + mm.items.drop(1)) }.validate()
    }

    @Test fun receiptResultJsonIsStrict() {
        fun withJson(j: String) = valid.firstTurn { t -> t.copy(receipts = listOf(t.receipts[0].copy(resultJSON = j)) + t.receipts.drop(1)) }
        for (bad in listOf("[abc]", "{\"a\":NaN}", "[1.2.3]", "{a:1}", "'x'", "[1,]", "", "5", "[01]"))
            rejects(withJson(bad), "receipt")
        for (good in listOf("{\"ok\":true}", "[1, -2.5e3, null, \"\\u00e9\"]", " {} "))
            withJson(good).validate()
    }

    @Test fun localDateYearZeroRejected() = rejects(valid.copy(days = listOf(valid.days[0].copy(localDate = "0000-01-01")) + valid.days.drop(1)), "day")

    @Test fun nameBlankUsesSwiftWhitespace() {
        rejects(valid.profile { it.copy(name = "\u0085\u2028\u00a0") }, "metadata")
        valid.profile { it.copy(name = "\u001c") }.validate()
    }

    @Test fun validFixturePasses() {
        valid.validate()
        validateArchiveManifests(valid)
    }

    @Test fun schemaVersionMustBe1() = rejects(valid.copy(schemaVersion = 2), "metadata")

    @Test fun revisionRange() {
        rejects(valid.copy(revision = -1), "metadata")
        rejects(valid.copy(revision = 10_000_000), "metadata")
    }

    @Test fun profileNameLength() {
        rejects(valid.profile { it.copy(name = "   ") }, "metadata")
        rejects(valid.profile { it.copy(name = "x".repeat(201)) }, "metadata")
        valid.profile { it.copy(name = "x".repeat(200)) }.validate()
        // 200 family emoji are 200 graphemes (many more code points) and must pass like Swift's String.count.
        valid.profile { it.copy(name = "👨‍👩‍👧".repeat(200)) }.validate()
    }

    @Test fun languageEnOrHe() {
        valid.profile { it.copy(language = "he") }.validate()
        rejects(valid.profile { it.copy(language = "fr") }, "metadata")
    }

    @Test fun timeZoneMustBeKnown() = rejects(valid.profile { it.copy(timeZoneID = "Mars/Base") }, "metadata")

    @Test fun liveIdsDisjointFromTombstones() {
        rejects(valid.copy(deletedMealIDs = valid.deletedMealIDs + valid.meals[0].id), "collections")
        rejects(valid.copy(deletedWeightIDs = valid.deletedWeightIDs + valid.weights[0].id), "collections")
        rejects(valid.copy(deletedWorkoutIDs = valid.deletedWorkoutIDs + valid.workouts[0].id), "collections")
    }

    @Test fun oneWeightPerDay() {
        val linked = valid.weights.first { it.dayID != null }
        rejects(valid.copy(weights = valid.weights + linked.copy(id = UUID.randomUUID())), "collections")
    }

    @Test fun photoBytesRange() {
        rejects(valid.firstMeal { it.copy(photos = listOf(it.photos[0].copy(data = ByteArray(0))) + it.photos.drop(1)) }, "photo bytes")
        rejects(valid.firstMeal { it.copy(photos = listOf(it.photos[0].copy(data = ByteArray(10_000_001))) + it.photos.drop(1)) }, "photo bytes")
    }

    @Test fun itemQuantityRange() {
        fun withQuantity(q: Double) = valid.firstMeal { m -> m.copy(items = listOf(m.items[0].copy(quantity = q)) + m.items.drop(1)) }
        rejects(withQuantity(-1.0), "item")
        rejects(withQuantity(100_001.0), "item")
        rejects(withQuantity(Double.NaN), "item")
    }

    @Test fun awaitingReviewNeedsProposal() {
        val meal = valid.meals[0]
        val sub = meal.submissions.first { it.state == SubmissionState.awaitingReview }.copy(proposal = null)
        rejects(valid.firstMeal { it.copy(submissions = it.submissions.map { s -> if (s.id == sub.id) sub else s }) }, "submission")
    }

    @Test fun manualAcceptanceNeedsNewerRevision() {
        val meal = valid.meals.first { m -> m.submissions.any { it.manualAcceptance != null } }
        val sub = meal.submissions.first { it.manualAcceptance != null }
        val broken = meal.copy(revision = sub.baseRevision)
        rejects(valid.copy(meals = valid.meals.map { if (it.id == meal.id) broken else it }), "manual acceptance revision")
    }

    @Test fun receiptCommittedRevisionRange() {
        fun withRevision(r: Int) = valid.firstTurn { t -> t.copy(receipts = listOf(t.receipts[0].copy(committedRevision = r)) + t.receipts.drop(1)) }
        rejects(withRevision(0), "receipt")
        rejects(withRevision(valid.revision + 1), "receipt")
    }

    @Test fun replyExcerptLimit() {
        val t = valid.coachTurns[0]
        val manifest = t.submissionManifest!!
        rejects(valid.firstTurn { it.copy(submissionManifest = manifest.copy(reply = manifest.reply!!.copy(excerpt = "x".repeat(281)))) }, "coach turn")
    }

    @Test fun manifestTextFingerprint() {
        val manifest = valid.coachTurns[0].submissionManifest!!
        val bad = valid.firstTurn { it.copy(submissionManifest = manifest.copy(textFingerprint = "0".repeat(64))) }
        bad.validate()
        rejects(bad, "manifest", manifests = true)
    }

    @Test fun attachmentsAtMost8() {
        val manifest = valid.coachTurns[0].submissionManifest!!
        val extra = (1..9).map { CoachSubmissionManifest.Attachment(UUID.randomUUID(), PhotoRole.unspecified, valid.coachTurns[0].capturedAt, "a".repeat(64)) }
        rejects(valid.firstTurn { it.copy(submissionManifest = manifest.copy(attachments = extra)) }, "manifest", manifests = true)
    }
}
