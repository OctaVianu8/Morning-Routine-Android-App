package com.octavianu.morning_glory

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingCalendarResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        WearBridge.register(applicationContext, messenger)

        // Read-only calendar permission. The calendar plugin's own permission
        // API insists on WRITE_CALENDAR as well; the app only ever reads, so it
        // asks for READ_CALENDAR itself and declares nothing more.
        MethodChannel(messenger, "morning_glory/calendar").setMethodCallHandler { call, result ->
            when (call.method) {
                "has" -> result.success(hasCalendarRead())
                "request" -> requestCalendarRead(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun hasCalendarRead() = ContextCompat.checkSelfPermission(
        this, Manifest.permission.READ_CALENDAR
    ) == PackageManager.PERMISSION_GRANTED

    private fun requestCalendarRead(result: MethodChannel.Result) {
        if (hasCalendarRead()) return result.success("granted")
        if (pendingCalendarResult != null) return result.success("denied")
        pendingCalendarResult = result
        ActivityCompat.requestPermissions(
            this, arrayOf(Manifest.permission.READ_CALENDAR), CALENDAR_REQUEST
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CALENDAR_REQUEST) return
        val result = pendingCalendarResult ?: return
        pendingCalendarResult = null
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        // After a refusal, "no rationale" means Android will not show the
        // dialog again: the user has to enable it in the system settings.
        val blocked = !granted && !ActivityCompat.shouldShowRequestPermissionRationale(
            this, Manifest.permission.READ_CALENDAR
        )
        result.success(if (granted) "granted" else if (blocked) "blocked" else "denied")
    }

    private companion object {
        const val CALENDAR_REQUEST = 4711
    }
}
