package com.uditverma.zen

import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FocusRulesTest {
    private val tz = TimeZone.getTimeZone("Asia/Kolkata")

    /** 2026-10-05 is a Monday. */
    private fun time(day: Int, hour: Int, minute: Int): Calendar =
        Calendar.getInstance(tz).apply {
            clear()
            set(2026, Calendar.OCTOBER, day, hour, minute)
        }

    private val weekdayMornings = Schedule(days = setOf(1, 2, 3, 4, 5), start = 9 * 60, end = 11 * 60)
    private val nights = Schedule(days = setOf(5), start = 23 * 60, end = 7 * 60) // starts Friday night

    @Test
    fun isoDayMapsMondayToOneAndSundayToSeven() {
        assertEquals(1, FocusRules.isoDay(time(5, 12, 0)))
        assertEquals(7, FocusRules.isoDay(time(11, 12, 0)))
    }

    @Test
    fun sameDayScheduleIsActiveOnlyInsideItsHours() {
        assertNull(FocusRules.scheduleWindow(weekdayMornings, time(5, 8, 59)))
        val w = FocusRules.scheduleWindow(weekdayMornings, time(5, 9, 0))!!
        assertEquals(time(5, 9, 0).timeInMillis, w.since)
        assertEquals(time(5, 11, 0).timeInMillis, w.until)
        assertTrue(FocusRules.scheduleWindow(weekdayMornings, time(5, 10, 59)) != null)
        assertNull(FocusRules.scheduleWindow(weekdayMornings, time(5, 11, 0)))
    }

    @Test
    fun sameDayScheduleSkipsDaysNotChosen() {
        assertNull(FocusRules.scheduleWindow(weekdayMornings, time(10, 10, 0))) // Saturday
    }

    @Test
    fun overnightScheduleRunsPastMidnightIntoTheNextDay() {
        assertNull(FocusRules.scheduleWindow(nights, time(9, 22, 59))) // Friday before start
        val friday = FocusRules.scheduleWindow(nights, time(9, 23, 30))!!
        assertEquals(time(10, 7, 0).timeInMillis, friday.until)
        val saturdayMorning = FocusRules.scheduleWindow(nights, time(10, 6, 0))!!
        assertEquals(time(9, 23, 0).timeInMillis, saturdayMorning.since)
        assertNull(FocusRules.scheduleWindow(nights, time(10, 7, 0)))
        assertNull(FocusRules.scheduleWindow(nights, time(10, 23, 30))) // Saturday night not chosen
        assertNull(FocusRules.scheduleWindow(nights, time(9, 6, 0))) // Friday early: Thursday not chosen
    }

    @Test
    fun disabledEmptyOrZeroLengthSchedulesNeverRun() {
        assertNull(FocusRules.scheduleWindow(weekdayMornings.copy(enabled = false), time(5, 10, 0)))
        assertNull(FocusRules.scheduleWindow(weekdayMornings.copy(days = emptySet()), time(5, 10, 0)))
        assertNull(FocusRules.scheduleWindow(weekdayMornings.copy(end = 9 * 60), time(5, 9, 0)))
    }

    @Test
    fun manualSessionAndLatestEndingWindowWin() {
        val now = time(5, 10, 0)
        val manualEnd = time(5, 12, 0).timeInMillis
        val w = FocusRules.activeWindow(listOf(weekdayMornings), now.timeInMillis, manualEnd, now)!!
        assertEquals(manualEnd, w.until)
        assertNull(FocusRules.activeWindow(emptyList(), 0, now.timeInMillis, now)) // manual just ended
        assertNull(FocusRules.activeWindow(emptyList(), 0, 0, now))
    }

    @Test
    fun blocksEverythingExceptAllowedApps() {
        val always = setOf("com.uditverma.zen", "com.android.systemui")
        val allowed = setOf("com.whatsapp")
        assertTrue(FocusRules.shouldBlock("com.instagram.android", always, allowed))
        assertFalse(FocusRules.shouldBlock("com.whatsapp", always, allowed))
        assertFalse(FocusRules.shouldBlock("com.android.systemui", always, allowed))
    }
}
