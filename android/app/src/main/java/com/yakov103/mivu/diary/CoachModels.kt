@file:UseSerializers(SwiftDate::class, SwiftUUID::class)
@file:Suppress("EnumEntryName") // entry names are the iOS raw values

package com.yakov103.mivu.diary

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

// Ports of the Codable types in ios/Mivu/Coach/CoachModels.swift and CoachTools.swift (CoachClarification).

enum class CoachTurnState { captured, analyzing, waitingForConnection, waitingForNetwork, needsRetry, needsClarification, completed }
enum class CoachDestination { settings, profiles, connection, nutritionSource, backup }
enum class CoachClarification { portion, food, day, meal, workout, confirm }

@Serializable
data class CoachReceipt(
    val operationKey: String,
    val turnID: UUID,
    val dayID: UUID? = null,
    val mealID: UUID? = null,
    val itemID: UUID? = null,
    val weightID: UUID? = null,
    val workoutID: UUID? = null,
    val goalID: UUID? = null,
    val destination: CoachDestination? = null,
    val committedRevision: Int,
    val resultJSON: String,
    val commandFingerprint: String? = null,
)

@Serializable
data class CoachTurn(
    val id: UUID,
    val capturedAt: Instant,
    val text: String,
    val photos: List<MealPhoto>,
    val state: CoachTurnState,
    val assistantText: String? = null,
    val receipts: List<CoachReceipt>,
    val captureTimeZoneID: String,
    val activeDayID: UUID? = null,
    val photoIDs: List<UUID>,
    val needsDayChoice: Boolean? = null,
    val resolvedDayID: UUID? = null,
    val pendingMealID: UUID? = null,
    val pendingMealRevision: Int? = null,
    val submissionManifest: CoachSubmissionManifest? = null,
    val captureSegmentID: UUID? = null,
    val question: CoachQuestion? = null,
    val incomplete: Boolean? = null,
    /** Error case from the last failed run; never user or model text. */
    val failureReason: String? = null,
)

@Serializable
data class CoachCaptureContext(
    val capturedAt: Instant,
    val timeZoneID: String,
    val activeDayID: UUID? = null,
    val previousDayConfirmedAt: Instant? = null,
    val activeConversationSegmentID: UUID? = null,
)

@Serializable
data class CoachSubmissionManifest(
    val submissionID: UUID,
    val context: CoachCaptureContext,
    val textFingerprint: String,
    val attachments: List<Attachment>,
    val pendingMealID: UUID? = null,
    val pendingMealRevision: Int? = null,
    val reply: CoachReply? = null,
) {
    @Serializable
    data class Attachment(val id: UUID, val role: PhotoRole, val createdAt: Instant, val contentFingerprint: String)
}

/** What a turn replies to: an earlier message or a Diary record. */
@Serializable
data class CoachReply(val target: Target, val excerpt: String) {
    @Serializable(with = Target.Serializer::class)
    sealed interface Target {
        @Serializable @SerialName("message") data class Message(val turnID: UUID, val fromPip: Boolean) : Target
        @Serializable @SerialName("meal") data class Meal(val mealID: UUID) : Target
        @Serializable @SerialName("item") data class Item(val mealID: UUID, val itemID: UUID) : Target
        @Serializable @SerialName("day") data class Day(val dayID: UUID) : Target
        @Serializable @SerialName("weight") data class Weight(val weightID: UUID) : Target
        @Serializable @SerialName("workout") data class Workout(val workoutID: UUID) : Target

        object Serializer : SwiftEnumSerializer<Target>(
            Message::class to Message.serializer(),
            Meal::class to Meal.serializer(),
            Item::class to Item.serializer(),
            Day::class to Day.serializer(),
            Weight::class to Weight.serializer(),
            Workout::class to Workout.serializer(),
        )
    }
}

/** A dated meal search result (CoachModels.swift:56); edits still require get_meal. */
@Serializable
data class CoachMealCandidate(
    val id: UUID,
    val dayID: UUID,
    val localDate: String,
    val timeZoneID: String,
    val revision: Int,
    val eatenAt: Instant,
    val timePrecision: MealTimePrecision? = null,
    val items: List<Item>,
    val omittedItemCount: Int,
    val capturedDescription: String,
    val descriptionTruncated: Boolean,
) {
    @Serializable data class Item(val id: UUID, val name: String, val quantity: Double, val unit: String)
}

/** An unanswered Coach question; the next reply is resolved against it. */
@Serializable
data class CoachQuestion(val kind: CoachClarification, val candidates: List<CoachReply.Target>, val originalText: String)
