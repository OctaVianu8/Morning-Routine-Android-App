package com.octavianu.morning_glory.wear

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.sqrt

class SleepMonitorService : Service(), SensorEventListener {
    private val handler = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var sensors: SensorManager? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var plan: Plan? = null
    private var detector: LightSleepDetector? = null
    private var running = false
    private var finishing = false
    private var dryWokeAt = 0L
    private var dryReason = ""

    // epoch accumulation
    private var epochEnd = 0L
    private var sumDev = 0.0
    private var maxDev = 0.0
    private var accCount = 0
    private var hrSum = 0.0
    private var hrCount = 0
    private var epochs = 0
    private var anyHr = false
    private var lastStatusAt = 0L

    private val tick = object : Runnable {
        override fun run() {
            val p = plan ?: return
            val now = System.currentTimeMillis()
            if (now >= p.alarmTimeMillis) {
                val reason = when {
                    dryReason.isNotEmpty() -> dryReason
                    detector?.notWorn == true -> "not_worn"
                    else -> ""
                }
                finish("finished", reason)
                return
            }
            flushIfDue(now)
            if (now - lastStatusAt >= STATUS_EVERY_MS) publish()
            handler.postDelayed(this, 5_000L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat()
        if (running) return START_NOT_STICKY
        val p = Store.loadPlan(this)
        val now = System.currentTimeMillis()
        if (p == null || p.alarmTimeMillis <= now || Store.wakeSent(this)) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        running = true
        plan = p
        detector = LightSleepDetector(p.windowStartMillis, p.alarmTimeMillis)

        val pm = getSystemService(PowerManager::class.java)
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "morningglory:monitor").apply {
            setReferenceCounted(false)
            acquire(p.alarmTimeMillis - now + 2 * 60_000L)
        }

        val sm = getSystemService(SensorManager::class.java)
        sensors = sm
        val acc = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (acc == null) {
            finish("finished", "no_accelerometer")
            return START_NOT_STICKY
        }
        sm.registerListener(this, acc, 100_000, 10_000_000)
        val hr = sm.getDefaultSensor(Sensor.TYPE_HEART_RATE)
        val hrPerm = hasHrPermission()
        if (hr != null && hrPerm) {
            try { sm.registerListener(this, hr, SensorManager.SENSOR_DELAY_NORMAL) } catch (_: Throwable) {}
        }
        val missing = hr != null && !hrPerm
        Store.setState(
            this, if (missing) "no_permission" else "monitoring",
            if (missing) "no_hr_permission" else "", epochs = 0, wokeAt = 0L, hrAvailable = false,
        )
        Store.setTrace(this, "")
        Store.setSessionDry(this, p.dryRun)
        publish()
        handler.postDelayed(tick, 5_000L)
        return START_NOT_STICKY
    }

    private fun hasHrPermission(): Boolean {
        val perm = if (Build.VERSION.SDK_INT >= 36) "android.permission.health.READ_HEART_RATE"
        else Manifest.permission.BODY_SENSORS
        return checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED
    }

    private fun startForegroundCompat() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Smart wake-up", NotificationManager.IMPORTANCE_LOW),
        )
        val n = Notification.Builder(this, CHANNEL)
            .setContentTitle("MorningGlory")
            .setContentText("MorningGlory is watching for light sleep")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }

    private fun publish() {
        lastStatusAt = System.currentTimeMillis()
        Status.publish(this)
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (finishing) return
        val now = System.currentTimeMillis()
        // Batched events arrive late: convert the sensor timestamp to wall clock.
        val t = now - (SystemClock.elapsedRealtimeNanos() - event.timestamp) / 1_000_000L
        flushIfDue(t)
        if (finishing) return
        if (epochEnd == 0L) epochEnd = t + EPOCH_MS
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                val x = event.values[0]; val y = event.values[1]; val z = event.values[2]
                val dev = abs(sqrt((x * x + y * y + z * z).toDouble()) - 9.81)
                sumDev += dev
                if (dev > maxDev) maxDev = dev
                accCount++
            }
            Sensor.TYPE_HEART_RATE -> {
                val bpm = event.values[0].toDouble()
                if (bpm > 30 && event.accuracy >= SensorManager.SENSOR_STATUS_ACCURACY_LOW) {
                    hrSum += bpm; hrCount++
                }
            }
        }
    }

    private fun flushIfDue(t: Long) {
        if (epochEnd == 0L || t < epochEnd || finishing) return
        if (accCount > 0) {
            val hr = if (hrCount > 0) hrSum / hrCount else null
            epochs++
            val d = detector?.onEpoch(
                LightSleepDetector.Epoch(epochEnd, sumDev / accCount, maxDev, hr),
            )
            val e = Store.prefs(this).edit().putInt("epochs", epochs)
            if (hr != null && !anyHr) {
                anyHr = true
                e.putBoolean("hrAvailable", true)
                if (Store.state(this) == "no_permission") e.putString("state", "monitoring")
            }
            e.putString("trace", detector?.trace ?: "")
            e.apply()
            if (d != null) {
                if (onDecision(d.reason)) return
            }
        }
        sumDev = 0.0; maxDev = 0.0; accCount = 0; hrSum = 0.0; hrCount = 0
        epochEnd = t + EPOCH_MS
    }

    /** Returns true when the session is ending (real wake), false in dry-run (keep monitoring). */
    private fun onDecision(reason: String): Boolean {
        val p = plan ?: return true
        val at = System.currentTimeMillis()
        val dry = Store.loadPlan(this)?.dryRun == true
        Store.setSessionDry(this, dry)
        if (dry) {
            // Dry run: remember what would have happened, send nothing, do not vibrate.
            dryWokeAt = at
            dryReason = reason
            Store.setState(this, Store.state(this), reason, wokeAt = at)
            publish()
            return false
        }
        finishing = true
        stopSensors()
        Status.vibrate(this)
        io.execute {
            val ok = Status.sendWake(this, p.alarmId, reason, at)
            handler.post {
                if (ok) {
                    Store.setWakeSent(this, true)
                    Store.setState(this, "woke", reason, wokeAt = at)
                } else {
                    Store.setState(this, "finished", "send_failed")
                }
                Status.publish(this)
                shutDown()
            }
        }
        return true
    }

    private fun finish(state: String, reason: String) {
        if (finishing) return
        finishing = true
        stopSensors()
        Store.setState(this, state, reason)
        Status.publish(this)
        shutDown()
    }

    private fun stopSensors() {
        handler.removeCallbacks(tick)
        try { sensors?.unregisterListener(this) } catch (_: Throwable) {}
    }

    private fun shutDown() {
        try { wakeLock?.takeIf { it.isHeld }?.release() } catch (_: Throwable) {}
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onDestroy() {
        stopSensors()
        try { wakeLock?.takeIf { it.isHeld }?.release() } catch (_: Throwable) {}
        io.shutdown()
        running = false
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "smart_wake"
        private const val NOTIF_ID = 42
        private const val EPOCH_MS = 30_000L
        private const val STATUS_EVERY_MS = 10 * 60_000L
    }
}
