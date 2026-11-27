package uk.me.amugofjava.anytime_podcast_player

import android.content.Context
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "uk.me.amugofjava.anytime_podcast_player/power"
        ).setMethodCallHandler { call, result ->
            if (call.method == "isPowerSaveMode") {
                val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                result.success(powerManager?.isPowerSaveMode ?: false)
            } else {
                result.notImplemented()
            }
        }
    }
}
