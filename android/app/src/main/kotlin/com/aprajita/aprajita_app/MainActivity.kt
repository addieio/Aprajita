package com.aprajita.aprajita_app

import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.aprajita.aprajita_app/volume_sos"
    private var methodChannel: MethodChannel? = null

    private var volumePressCount = 0
    private var lastPressTime = 0L
    private val resetHandler = Handler(Looper.getMainLooper())
    private val RESET_WINDOW_MS = 3500L
    private val TARGET_PRESSES = 4

    private val resetRunnable = Runnable {
        volumePressCount = 0
        runOnUiThread {
            methodChannel?.invokeMethod("onVolumePressCountChanged", mapOf("count" to 0, "target" to TARGET_PRESSES))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPressCount" -> result.success(volumePressCount)
                "resetCount" -> {
                    volumePressCount = 0
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                val now = System.currentTimeMillis()

                // If more than 3.5 seconds have elapsed since last press, start fresh count
                if (now - lastPressTime > RESET_WINDOW_MS) {
                    volumePressCount = 0
                }

                lastPressTime = now
                volumePressCount++

                resetHandler.removeCallbacks(resetRunnable)
                resetHandler.postDelayed(resetRunnable, RESET_WINDOW_MS)

                val currentCount = volumePressCount
                runOnUiThread {
                    methodChannel?.invokeMethod(
                        "onVolumePressCountChanged",
                        mapOf("count" to currentCount, "target" to TARGET_PRESSES)
                    )
                    if (currentCount >= TARGET_PRESSES) {
                        volumePressCount = 0
                        resetHandler.removeCallbacks(resetRunnable)
                        methodChannel?.invokeMethod("onVolumeSosTriggered", null)
                    }
                }

                // Consume the event during rapid emergency presses
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }
}
