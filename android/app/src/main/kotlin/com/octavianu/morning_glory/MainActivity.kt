package com.octavianu.morning_glory

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        WearBridge.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}
