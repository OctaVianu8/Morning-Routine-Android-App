package com.octavianu.morning_glory.wear

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.ContextCompat
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable

object PlanManager {
    private const val REQ = 4711

    /** Applies a plan from the phone (null or windowMinutes 0 cancels). */
    fun apply(c: Context, incoming: Plan?) {
        val ctx = c.applicationContext
        val old = Store.loadPlan(ctx)
        val now = System.currentTimeMillis()
        val valid = incoming != null && incoming.windowMinutes > 0 && incoming.alarmTimeMillis > now
        if (!valid) {
            cancelAll(ctx)
            Store.savePlan(ctx, null)
            Store.setWakeSent(ctx, false)
            Store.setState(ctx, "idle", epochs = 0, wokeAt = 0L)
            Store.setTrace(ctx, "")
            Status.publish(ctx)
            return
        }
        val plan = incoming!!
        val same = old != null && old.alarmId == plan.alarmId && old.alarmTimeMillis == plan.alarmTimeMillis
        if (same && old != plan && old != null && old.windowMinutes == plan.windowMinutes &&
            old.dryRun != plan.dryRun
        ) {
            // Only the dry-run flag changed: update in place, keep a running session going.
            Store.savePlan(ctx, plan)
            if (Store.state(ctx) == "scheduled") arm(ctx, plan)
            else if (Store.state(ctx) == "monitoring" || Store.state(ctx) == "no_permission") {
                try {
                    ContextCompat.startForegroundService(ctx, Intent(ctx, SleepMonitorService::class.java)
                        .putExtra("dryRunChanged", true))
                } catch (_: Throwable) {}
            }
            Status.publish(ctx)
            return
        }
        if (same && old == plan) {
            // Nothing changed; make sure the alarm exists but do not disturb a running service.
            if (Store.state(ctx) == "scheduled") arm(ctx, plan)
            return
        }
        cancelAll(ctx)
        if (!same) Store.setWakeSent(ctx, false)
        Store.savePlan(ctx, plan)
        Store.setState(ctx, "scheduled", epochs = 0, wokeAt = 0L)
        Store.setTrace(ctx, "")
        arm(ctx, plan)
        Status.publish(ctx)
    }

    /** Schedules the exact alarm at T-60 min, or starts monitoring right away if that has passed. */
    fun arm(c: Context, plan: Plan) {
        val now = System.currentTimeMillis()
        if (plan.alarmTimeMillis <= now) return
        if (plan.monitorStartMillis <= now) {
            try {
                ContextCompat.startForegroundService(c, Intent(c, SleepMonitorService::class.java))
                return
            } catch (_: Throwable) {
                scheduleAt(c, now + 5_000L)
                return
            }
        }
        scheduleAt(c, plan.monitorStartMillis)
    }

    fun rearm(c: Context) {
        val plan = Store.loadPlan(c) ?: return
        if (plan.alarmTimeMillis <= System.currentTimeMillis()) {
            Store.savePlan(c, null)
            Store.setState(c, "idle")
            return
        }
        if (Store.state(c) == "woke" || Store.state(c) == "finished") return
        arm(c, plan)
    }

    private fun pending(c: Context): PendingIntent =
        PendingIntent.getBroadcast(
            c, REQ, Intent(c, MonitorAlarmReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun scheduleAt(c: Context, at: Long) {
        val am = c.getSystemService(AlarmManager::class.java) ?: return
        val pi = pending(c)
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
        try {
            if (exact) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        } catch (_: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }

    fun cancelAll(c: Context) {
        try { c.getSystemService(AlarmManager::class.java)?.cancel(pending(c)) } catch (_: Throwable) {}
        try { c.stopService(Intent(c, SleepMonitorService::class.java)) } catch (_: Throwable) {}
    }

    fun parse(item: com.google.android.gms.wearable.DataItem): Plan {
        val m = DataMapItem.fromDataItem(item).dataMap
        return Plan(m.getInt("alarmId"), m.getLong("alarmTimeMillis"), m.getInt("windowMinutes"),
            if (m.containsKey("dryRun")) m.getBoolean("dryRun") else false)
    }

    /** Reads the current plan DataItem (events can be missed). Runs on a background thread. */
    fun syncFromDataLayer(c: Context, done: (() -> Unit)? = null) {
        val app = c.applicationContext
        Thread {
            try {
                val uri = Uri.Builder().scheme("wear").path(Protocol.PATH_PLAN).build()
                val buf = Tasks.await(Wearable.getDataClient(app).getDataItems(uri))
                try {
                    var plan: Plan? = null
                    for (item in buf) {
                        if (item.uri.path == Protocol.PATH_PLAN) plan = parse(item)
                    }
                    apply(app, plan)
                } finally {
                    buf.release()
                }
            } catch (_: Throwable) {
            } finally {
                done?.invoke()
            }
        }.start()
    }
}

class MonitorAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val plan = Store.loadPlan(context) ?: return
        if (plan.alarmTimeMillis <= System.currentTimeMillis()) return
        try {
            ContextCompat.startForegroundService(context, Intent(context, SleepMonitorService::class.java))
        } catch (_: Throwable) {
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pr = goAsync()
        PlanManager.rearm(context)
        PlanManager.syncFromDataLayer(context) { pr.finish() }
    }
}
