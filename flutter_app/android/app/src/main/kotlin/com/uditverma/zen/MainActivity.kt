package com.uditverma.zen

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Hosts the Flutter UI and exposes Focus mode's phone controls on the "zen/focus" channel:
 * the app blocker (accessibility service), app pinning, Do Not Disturb and launching allowed apps.
 */
class MainActivity : FlutterActivity() {
    private var filterBeforeFocus: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val store = FocusStore(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zen/focus").setMethodCallHandler { call, result ->
            when (call.method) {
                // App blocker
                "guardEnabled" -> result.success(guardEnabled())
                "openGuardSettings" -> result.success(open(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)))
                "openAppInfo" -> result.success(
                    open(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))),
                )
                "setConfig" -> result.success(store.setConfig(call.arguments as String))
                "startManual" -> result.success(store.startManual((call.arguments as Number).toLong()))
                "state" -> {
                    val w = store.activeWindow()
                    result.success(
                        mapOf("active" to (w != null), "since" to (w?.since ?: 0L), "until" to (w?.until ?: 0L)),
                    )
                }
                "listApps" -> Thread {
                    val apps = runCatching { listApps() }.getOrDefault(emptyList())
                    runOnUiThread { result.success(apps) }
                }.start()
                "launchApp" -> result.success(launchApp(call.arguments as String))
                "openDialer" -> result.success(open(Intent(Intent.ACTION_DIAL)))
                // App pinning (used when the blocker is off)
                "startLock" -> result.success(runCatching { startLockTask() }.isSuccess)
                "stopLock" -> result.success(runCatching { stopLockTask() }.isSuccess)
                "isLocked" -> result.success(isLocked())
                // Do Not Disturb
                "hasDndAccess" -> result.success(notifications().isNotificationPolicyAccessGranted)
                "openDndSettings" -> result.success(open(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)))
                "setDnd" -> result.success(setDnd(call.arguments == true))
                else -> result.notImplemented()
            }
        }
    }

    private fun guardEnabled(): Boolean {
        val am = getSystemService(AccessibilityManager::class.java) ?: return false
        return am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK).any {
            val info = it.resolveInfo.serviceInfo
            info.packageName == packageName && info.name == FocusGuardService::class.java.name
        }
    }

    /** Launchable apps with name and icon, for choosing which apps focus allows. */
    private fun listApps(): List<Map<String, Any>> {
        val pm = packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(launcher, 0)
            .distinctBy { it.activityInfo.packageName }
            .filter { it.activityInfo.packageName != packageName }
            .map { info ->
                mapOf(
                    "package" to info.activityInfo.packageName,
                    "label" to info.loadLabel(pm).toString(),
                    "icon" to iconPng(info.loadIcon(pm)),
                )
            }
            .sortedBy { (it["label"] as String).lowercase() }
    }

    private fun iconPng(drawable: android.graphics.drawable.Drawable, size: Int = 96): ByteArray {
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(Canvas(bitmap))
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    private fun launchApp(pkg: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
        return open(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun isLocked(): Boolean {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
    }

    private fun notifications() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun open(intent: Intent): Boolean = runCatching { startActivity(intent) }.isSuccess

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
