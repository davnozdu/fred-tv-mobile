package dev.fredol.open_tv

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "cz.smotrim.player/launch"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchedFromBoot" -> {
                        val fromBoot = intent?.getBooleanExtra("autostart", false) ?: false
                        result.success(fromBoot)
                    }
                    "setAutostart" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        getSharedPreferences("smotrim", Context.MODE_PRIVATE)
                            .edit()
                            .putBoolean("autostart_enabled", enabled)
                            .apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
