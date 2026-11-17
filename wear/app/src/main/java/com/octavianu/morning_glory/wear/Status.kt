package com.octavianu.morning_glory.wear

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable

object Status {
    fun battery(c: Context): Int {
        val i = c.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return -1
        val level = i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = i.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        return if (level < 0 || scale <= 0) -1 else level * 100 / scale
    }

    /** Publishes the current state from [Store] as the status DataItem (fire and forget). */
    fun publish(c: Context) {
        try {
            val app = c.applicationContext
            val req = PutDataMapRequest.create(Protocol.PATH_STATUS)
            req.dataMap.apply {
                putString("state", Store.state(app))
                putInt("alarmId", Store.loadPlan(app)?.alarmId ?: 0)
                putLong("updatedAt", System.currentTimeMillis())
                putInt("battery", battery(app))
                putBoolean("hrAvailable", Store.hrAvailable(app))
                putInt("epochs", Store.epochs(app))
                putLong("wokeAt", Store.wokeAt(app))
                putString("reason", Store.reason(app))
                val plan = Store.loadPlan(app)
                putBoolean("dryRun", plan?.dryRun ?: false)
                putLong("alarmTimeMillis", plan?.alarmTimeMillis ?: 0L)
                putInt("windowMinutes", plan?.windowMinutes ?: 0)
                putString("trace", Store.trace(app))
            }
            Wearable.getDataClient(app).putDataItem(req.asPutDataRequest().setUrgent())
        } catch (_: Throwable) {
        }
    }

    fun vibrate(c: Context, pattern: LongArray = longArrayOf(0, 200, 150, 200)) {
        try {
            val v = c.getSystemService(Vibrator::class.java) ?: return
            v.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } catch (_: Throwable) {
        }
    }

    /** Sends the wake message to all connected nodes; blocking, call off the main thread. */
    fun sendWake(c: Context, alarmId: Int, reason: String, at: Long): Boolean {
        val payload = """{"alarmId":$alarmId,"reason":"$reason","at":$at}""".toByteArray(Charsets.UTF_8)
        val app = c.applicationContext
        repeat(3) { attempt ->
            try {
                val nodes = Tasks.await(Wearable.getNodeClient(app).connectedNodes)
                if (nodes.isNotEmpty()) {
                    val client = Wearable.getMessageClient(app)
                    nodes.forEach { Tasks.await(client.sendMessage(it.id, Protocol.PATH_WAKE, payload)) }
                    return true
                }
            } catch (_: Throwable) {
            }
            if (attempt < 2) try { Thread.sleep(4_000) } catch (_: InterruptedException) { return false }
        }
        return false
    }

    fun mainHandler() = Handler(Looper.getMainLooper())
}
