package dev.fredol.open_tv

import android.content.Context
import android.view.WindowManager
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
                    "isPackageInstalled" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        val installed = try {
                            packageManager.getPackageInfo(pkg, 0)
                            true
                        } catch (e: Exception) {
                            false
                        }
                        result.success(installed)
                    }
                    "setKeepScreenOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        runOnUiThread {
                            if (on) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
