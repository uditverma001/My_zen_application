package com.uditverma.zen

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

/**
 * Watches which app comes to the front. During focus, anything not allowed sends you back to Zen.
 * It only looks at app package names, never at what is on screen.
 */
class FocusGuardService : AccessibilityService() {
    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return

        val store = FocusStore(this)
        if (store.activeWindow() == null) return
        if (!FocusRules.shouldBlock(pkg, store.alwaysAllowed(), store.allowed())) return

        // Launched like the home screen does, so the existing Zen task comes to the front.
        packageManager.getLaunchIntentForPackage(packageName)?.let {
            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            startActivity(it)
        }
    }

    override fun onInterrupt() {}
}
