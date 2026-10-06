package com.uditverma.zen

import java.util.Calendar

/**
 * A repeating focus block. [days] are ISO weekdays (1 = Monday … 7 = Sunday) on which the block
 * starts; [start] and [end] are minutes after midnight. An [end] before [start] runs past midnight.
 */
data class Schedule(val days: Set<Int>, val start: Int, val end: Int, val enabled: Boolean = true)

/** A focus period, as epoch milliseconds. */
data class Window(val since: Long, val until: Long)

/** Pure focus logic, kept free of Android APIs so it can be unit tested. */
object FocusRules {
    /** The focus period in effect at [now], or null when the phone is free. */
    fun activeWindow(schedules: List<Schedule>, manualStart: Long, manualEnd: Long, now: Calendar): Window? {
        val candidates = mutableListOf<Window>()
        if (manualEnd > now.timeInMillis) candidates += Window(manualStart, manualEnd)
        schedules.mapNotNullTo(candidates) { scheduleWindow(it, now) }
        return candidates.maxByOrNull { it.until }
    }

    fun scheduleWindow(s: Schedule, now: Calendar): Window? {
        if (!s.enabled || s.start == s.end || s.days.isEmpty()) return null
        val minute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val today = isoDay(now)
        val yesterday = if (today == 1) 7 else today - 1
        if (s.start < s.end) {
            if (today in s.days && minute >= s.start && minute < s.end) {
                return Window(at(now, 0, s.start), at(now, 0, s.end))
            }
        } else {
            if (today in s.days && minute >= s.start) return Window(at(now, 0, s.start), at(now, 1, s.end))
            if (yesterday in s.days && minute < s.end) return Window(at(now, -1, s.start), at(now, 0, s.end))
        }
        return null
    }

    fun shouldBlock(pkg: String, alwaysAllowed: Set<String>, allowed: Set<String>): Boolean =
        pkg !in alwaysAllowed && pkg !in allowed

    /** Calendar's Sunday = 1 … Saturday = 7, converted to ISO Monday = 1 … Sunday = 7. */
    fun isoDay(c: Calendar): Int = (c.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1

    private fun at(now: Calendar, dayOffset: Int, minuteOfDay: Int): Long {
        val c = now.clone() as Calendar
        c.add(Calendar.DAY_OF_MONTH, dayOffset)
        c.set(Calendar.HOUR_OF_DAY, minuteOfDay / 60)
        c.set(Calendar.MINUTE, minuteOfDay % 60)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        return c.timeInMillis
    }
}
