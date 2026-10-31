package com.yakov103.mivu.ui.coach

import com.yakov103.mivu.diary.DiaryError
import org.junit.Assert.assertEquals
import org.junit.Test

class CoachMessageTest {
    @Test fun anExpiredUndoIsNotReportedAsAChange() {
        assertEquals("Undo is no longer available.", coachMessage(DiaryError.UndoExpired))
        assertEquals("Something changed while I was working. Check it, then try again.", coachMessage(DiaryError.StaleRevision))
    }
}
