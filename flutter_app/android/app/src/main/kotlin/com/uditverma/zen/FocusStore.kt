package com.uditverma.zen

import android.content.Context
import android.telecom.TelecomManager
import android.view.inputmethod.InputMethodManager
import java.util.Calendar
import org.json.JSONArray
import org.json.JSONObject

/**
 * Focus settings the blocker needs even when the Flutter UI isn't running:
 * allowed apps, schedules and any manual session. Written by the app, read by [FocusGuardService].
 */
class FocusStore(private val context: Context) {
    private val prefs = context.getSharedPreferences("zen_focus", Context.MODE_PRIVATE)

    private fun config(): JSONObject =
        runCatching { JSONObject(prefs.getString(KEY_CONFIG, null) ?: "{}") }.getOrDefault(JSONObject())

    fun allowed(): Set<String> = config().optJSONArray("allowed").strings().toSet()

    fun schedules(): List<Schedule> {
        val list = config().optJSONArray("schedules") ?: return emptyList()
        return (0 until list.length()).mapNotNull { i ->
            val s = list.optJSONObject(i) ?: return@mapNotNull null
            Schedule(
                days = s.optJSONArray("days").ints().toSet(),
                start = s.optInt("start"),
                end = s.optInt("end"),
                enabled = s.optBoolean("enabled", true),
            )
        }
    }

    fun activeWindow(now: Calendar = Calendar.getInstance()): Window? =
        FocusRules.activeWindow(schedules(), prefs.getLong(KEY_MANUAL_START, 0), prefs.getLong(KEY_MANUAL_END, 0), now)

    /** Saves new settings. Refused during focus, so a session can't be loosened from inside it. */
    fun setConfig(json: String): Boolean {
        if (activeWindow() != null) return false
        if (runCatching { JSONObject(json) }.isFailure) return false
        return prefs.edit().putString(KEY_CONFIG, json).commit()
    }

    /** Starts (or extends, never shortens) a manual session ending at [endMillis]. */
    fun startManual(endMillis: Long): Boolean {
        val now = System.currentTimeMillis()
        if (endMillis <= now) return false
        val currentEnd = prefs.getLong(KEY_MANUAL_END, 0)
        val edit = prefs.edit()
        if (currentEnd > now) {
            edit.putLong(KEY_MANUAL_END, maxOf(currentEnd, endMillis))
        } else {
            edit.putLong(KEY_MANUAL_START, now).putLong(KEY_MANUAL_END, endMillis)
        }
        return edit.commit()
    }

    /** Apps that are never blocked: Zen, system UI, calls and keyboards. */
    fun alwaysAllowed(): Set<String> {
        val set = mutableSetOf(context.packageName, *SYSTEM_ALLOWED)
        runCatching { context.getSystemService(TelecomManager::class.java)?.defaultDialerPackage }
            .getOrNull()?.let(set::add)
        runCatching { context.getSystemService(InputMethodManager::class.java)?.enabledInputMethodList }
            .getOrNull()?.forEach { set.add(it.packageName) }
        return set
    }

    private fun JSONArray?.strings(): List<String> =
        if (this == null) emptyList() else (0 until length()).mapNotNull { optString(it).takeIf(String::isNotEmpty) }

    private fun JSONArray?.ints(): List<Int> =
        if (this == null) emptyList() else (0 until length()).map { optInt(it) }

    companion object {
        private const val KEY_CONFIG = "config"
        private const val KEY_MANUAL_START = "manualStart"
        private const val KEY_MANUAL_END = "manualEnd"

        private val SYSTEM_ALLOWED = arrayOf(
            "android",
            "com.android.systemui",
            "com.android.phone",
            "com.android.server.telecom",
            "com.android.incallui",
            "com.samsung.android.incallui",
            "com.android.emergency",
            "com.google.android.permissioncontroller",
            "com.android.permissioncontroller",
        )
    }
}
