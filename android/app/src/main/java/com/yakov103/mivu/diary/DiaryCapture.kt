package com.yakov103.mivu.diary

import java.util.UUID

// Port of CoachSubmissionPayload (ios/Mivu/Coach/CoachModels.swift) and captureCoachSubmission /
// reconcileCoachCapture (ios/Mivu/Diary/DiaryDatabaseMutations.swift): a capture is saved before analysis.

/** A validated Coach submission and the manifest that identifies its exact content for retries. */
data class CoachSubmissionPayload(
    val submissionID: UUID,
    val text: String,
    val attachments: List<MealPhoto>,
    val context: CoachCaptureContext,
    val pendingMealID: UUID? = null,
    val pendingMealRevision: Int? = null,
    val reply: CoachReply? = null,
) {
    val manifest: CoachSubmissionManifest

    init {
        if (attachments.size > 8 || attachments.map { it.id }.toSet().size != attachments.size || !text.atMost(20_000) ||
            !validZone(context.timeZoneID) || (pendingMealID == null) != (pendingMealRevision == null) ||
            (pendingMealRevision != null && pendingMealRevision < 0)
        ) throw DiaryError.InvalidData("coach submission")
        if (text.blankLikeSwift() && attachments.isEmpty()) throw DiaryError.EmptyCapture
        attachments.forEach(::validatePhoto)
        // Instants as a stored row reads them back, so a retry of a sub-second capture compares equal.
        manifest = CoachSubmissionManifest(submissionID,
            context.copy(capturedAt = context.capturedAt.stored, previousDayConfirmedAt = context.previousDayConfirmedAt?.stored),
            fingerprint(text),
            attachments.map { CoachSubmissionManifest.Attachment(it.id, it.role, it.createdAt.stored, fingerprint(it.data)) },
            pendingMealID, pendingMealRevision, reply)
    }
}

sealed interface Reconciliation {
    object Absent : Reconciliation
    data class Accepted(val turn: CoachTurn) : Reconciliation
    object ConflictingPayload : Reconciliation
}

/** Saves the capture in one transaction; a retry with the same manifest returns the stored turn unchanged. */
fun DiaryDatabase.captureCoachSubmission(payload: CoachSubmissionPayload, expectedRevision: Long): CoachTurn =
    transaction(expectedRevision) { tx ->
        tx.coachTurn(payload.submissionID)?.let { existing ->
            if (existing.submissionManifest != payload.manifest) throw DiaryError.StaleRevision
            return@transaction existing
        }
        val c = payload.manifest.context
        val head = tx.head
        // shortcut: iOS compares the segment with its derived "effective" ID (DiaryDatabaseMutations.swift:55); the
        // coach_segment index now exists but the raw head value is still compared. Upgrade with the empty-segment port.
        if (c.timeZoneID != head.profile.timeZoneID || c.activeDayID != head.activeDayID ||
            c.previousDayConfirmedAt != head.previousDayConfirmedAt ||
            c.activeConversationSegmentID != head.activeConversationSegmentID
        ) throw DiaryError.StaleRevision
        // Pending-meal captures compose their own meal/turn batch, as on iOS.
        if (payload.manifest.pendingMealID != null) throw DiaryError.InvalidData("pending meal capture")
        CoachTurn(id = payload.submissionID, capturedAt = c.capturedAt, text = payload.text,
            photos = payload.attachments.map { it.copy(createdAt = it.createdAt.stored) },
            state = CoachTurnState.captured, receipts = emptyList(), captureTimeZoneID = c.timeZoneID,
            activeDayID = c.activeDayID, photoIDs = payload.attachments.map { it.id },
            submissionManifest = payload.manifest, captureSegmentID = c.activeConversationSegmentID,
        ).also(tx::putCoachTurn)
    }

/** After an uncertain failure: whether the capture committed, and with this exact content. */
fun DiaryDatabase.reconcileCoachCapture(payload: CoachSubmissionPayload): Reconciliation = read { tx ->
    val turn = tx.coachTurn(payload.submissionID)
    when {
        turn == null -> Reconciliation.Absent
        turn.submissionManifest == payload.manifest -> Reconciliation.Accepted(turn)
        else -> Reconciliation.ConflictingPayload
    }
}

private val PENDING = setOf(CoachTurnState.captured, CoachTurnState.waitingForConnection, CoachTurnState.waitingForNetwork,
    CoachTurnState.analyzing, CoachTurnState.needsRetry)

/** Startup recovery scan: turns still awaiting analysis, oldest first. */
fun DiaryDatabase.pendingCoachTurns(): List<UUID> = coachTurnsWithoutPhotos()
    .filter { it.state in PENDING }
    .sortedWith(compareBy<CoachTurn> { it.capturedAt }.thenBy { it.id.toString().uppercase() })
    .map { it.id }

/** iOS `failCoachTurn` (`setCoachTurnState`): a completed turn keeps its reply; any other state clears it. */
fun DiaryDatabase.Tx.failCoachTurn(turnID: UUID, state: CoachTurnState, needsDayChoice: Boolean = false, failureReason: String? = null) {
    val kept = if (state == CoachTurnState.completed) coachTurnWithoutPhotos(turnID) else null
    updateCoachTurn(turnID, state, kept?.assistantText, kept?.question, kept?.incomplete, needsDayChoice, failureReason)
}

/** iOS `finishCoachTurn` (`completeCoachTurn`): the turn is completed with its reply; receipts are untouched. */
fun DiaryDatabase.Tx.finishCoachTurn(turnID: UUID, assistantText: String, question: CoachQuestion? = null, incomplete: Boolean? = null) =
    updateCoachTurn(turnID, CoachTurnState.completed, assistantText, question, incomplete)
