package health.lifetrack.lifetrack

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FragmentActivity: the system fingerprint/PIN prompt (local_auth) needs it.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Screen privacy: FLAG_SECURE blanks screenshots, screen recordings
        // and the Recent apps preview while LifeTrack is on screen.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lifetrack/screen_privacy")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "set" -> {
                        if (call.arguments == true) {
                            window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
