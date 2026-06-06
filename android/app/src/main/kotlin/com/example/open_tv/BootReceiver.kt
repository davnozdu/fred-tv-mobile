package dev.fredol.open_tv

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/// Launches the app when the device finishes booting, but only if the user
/// enabled autostart (mirrored into SharedPreferences from Flutter).
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }
        val prefs = context.getSharedPreferences("smotrim", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("autostart_enabled", false)) return
        val launch = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra("autostart", true)
        }
        try {
            context.startActivity(launch)
        } catch (_: Exception) {
        }
    }
}
