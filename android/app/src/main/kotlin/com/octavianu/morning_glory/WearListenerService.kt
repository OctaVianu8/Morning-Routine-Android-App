package com.octavianu.morning_glory

import android.content.Context
import android.util.Log
import com.gdelataillade.alarm.services.AlarmScheduler
import com.gdelataillade.alarm.services.AlarmStorage
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject
import java.util.Date

/**
 * Receives the watch's messages while the app may not be running.
 *
 * `/morningglory/wake` pulls the alarm forward by re-arming the alarm plugin's
 * own stored alarm to fire in a few seconds through AlarmManager, so the
 * plugin's receiver / foreground service start the legitimate way.
 */
class WearListenerService : WearableListenerService() {

    override fun onMessageReceived(event: MessageEvent) {
        when (event.path) {
            WearBridge.PATH_PONG -> WearBridge.pendingPong?.complete(true)
            WearBridge.PATH_WAKE -> try {
                handleWake(applicationContext, String(event.data, Charsets.UTF_8))
            } catch (t: Throwable) {
                Log.w(TAG, "wake handling failed", t)
            }
        }
    }

    companion object {
        private const val TAG = "WearListener"
        private const val REARM_DELAY_MS = 6000L

        @Synchronized
        fun handleWake(context: Context, payload: String) {
            val json = JSONObject(payload)
            val alarmId = json.getInt("alarmId")
            val reason = json.optString("reason", "movement")
            val prefs = context.getSharedPreferences(WearBridge.PREFS, Context.MODE_PRIVATE)
            val planId = prefs.getInt(WearBridge.K_PLAN_ID, 0)
            val planTime = prefs.getLong(WearBridge.K_PLAN_TIME, 0L)
            val window = prefs.getInt(WearBridge.K_PLAN_WINDOW, 0)
            val now = System.currentTimeMillis()

            if (planId != alarmId || window <= 0) {
                Log.i(TAG, "ignored wake: no matching plan (plan=$planId window=$window msg=$alarmId)")
                return
            }
            val earliest = planTime - window * 60_000L - 60_000L
            val latest = planTime - 30_000L
            if (now < earliest || now > latest) {
                Log.i(TAG, "ignored wake: outside window (now=$now, $earliest..$latest)")
                return
            }
            // Idempotent: one early wake per plan.
            if (prefs.getInt(WearBridge.K_WAKE_ALARM, 0) == alarmId &&
                prefs.getLong(WearBridge.K_WAKE_AT, 0L) > planTime - window * 60_000L - 120_000L &&
                prefs.getLong(WearBridge.K_WAKE_AT, 0L) <= planTime
            ) {
                Log.i(TAG, "ignored wake: already handled for this plan")
                return
            }

            val alarm = AlarmStorage(context).getSavedAlarms().firstOrNull { it.id == alarmId }
            if (alarm == null || alarm.dateTime.time <= now) {
                Log.i(TAG, "ignored wake: stored alarm missing or not in the future")
                return
            }
            // Only ever pull forward: skip if the alarm already fires within the re-arm delay.
            if (alarm.dateTime.time <= now + REARM_DELAY_MS + 1000) {
                Log.i(TAG, "ignored wake: alarm already imminent")
                return
            }

            val armed = AlarmScheduler.schedule(
                context,
                alarm.copy(dateTime = Date(now + REARM_DELAY_MS)),
                requireDurable = true,
            )
            if (!armed) {
                Log.w(TAG, "re-arm refused; alarm keeps its original time")
                return
            }
            prefs.edit()
                .putLong(WearBridge.K_WAKE_AT, now)
                .putString(WearBridge.K_WAKE_REASON, reason)
                .putInt(WearBridge.K_WAKE_ALARM, alarmId)
                .putLong(WearBridge.K_WAKE_PLANNED, planTime)
                .apply()
            Log.i(TAG, "alarm $alarmId pulled forward by watch ($reason)")
        }
    }
}
