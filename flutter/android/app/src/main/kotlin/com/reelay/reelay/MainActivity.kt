package com.reelay.reelay

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val frameRate by lazy { FrameRateMatcher(this) }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "reelay/display").setMethodCallHandler { call, result ->
      when (call.method) {
        "matchFrameRate" -> frameRate.match(
          (call.argument<Double>("fps") ?: 0.0).toFloat(),
          call.argument<Int>("width") ?: 0,
          call.argument<Int>("height") ?: 0,
        ) { switched -> result.success(switched) }
        "clearFrameRate" -> {
          frameRate.clear()
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }
}
