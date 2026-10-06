package com.uditverma.zen

import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and exposes Focus mode's phone controls on the "zen/focus" channel:
 * app pinning (keeps the phone on Zen) and Do Not Disturb.
 */
class MainActivity : FlutterActivity() {
    private var filterBeforeFocus: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zen/focus").setMethodCallHandler { call, result ->
            when (call.method) {
                // Asks Android to pin Zen; the system shows its own confirmation first.
                "startLock" -> result.success(runCatching { startLockTask() }.isSuccess)
                "stopLock" -> result.success(runCatching { stopLockTask() }.isSuccess)
                "isLocked" -> result.success(isLocked())
                "hasDndAccess" -> result.success(notifications().isNotificationPolicyAccessGranted)
                "openDndSettings" -> result.success(open(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                "setDnd" -> result.success(setDnd(call.arguments == true))
                else -> result.notImplemented()
            }
        }
    }

    private fun isLocked(): Boolean {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
    }

    private fun notifications() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun open(action: String): Boolean =
        runCatching { startActivity(Intent(action)) }.isSuccess

    /** Turns Do Not Disturb (priority only) on, or restores what was set before. */
    private fun setDnd(on: Boolean): Boolean {
        val nm = notifications()
        if (!nm.isNotificationPolicyAccessGranted) return false
        return runCatching {
            if (on) {
                if (filterBeforeFocus == null) filterBeforeFocus = nm.currentInterruptionFilter
                nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
            } else {
                nm.setInterruptionFilter(filterBeforeFocus ?: NotificationManager.INTERRUPTION_FILTER_ALL)
                filterBeforeFocus = null
            }
        }.isSuccess
    }
}
