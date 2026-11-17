package com.octavianu.morning_glory

import android.content.Context
import android.util.Log
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.DataMap
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Phone side of the Wearable Data Layer protocol (see wear/README.md).
 * Every method resolves, never throws to Dart, and degrades to false / empty
 * when Google Play services or a watch are absent.
 */
object WearBridge {
    private const val TAG = "WearBridge"
    const val CHANNEL = "morning_glory/wear"
    const val CAPABILITY = "morning_glory_wear"
    const val PATH_PLAN = "/morningglory/plan"
    const val PATH_PING = "/morningglory/ping"
    const val PATH_PONG = "/morningglory/pong"
    const val PATH_WAKE = "/morningglory/wake"
    const val PATH_STATUS = "/morningglory/status"

    const val PREFS = "morning_glory_wear"
    const val K_PLAN_ID = "plan_alarmId"
    const val K_PLAN_TIME = "plan_alarmTimeMillis"
    const val K_PLAN_WINDOW = "plan_windowMinutes"
    const val K_PLAN_DRY = "plan_dryRun"
    const val K_HISTORY = "night_history"
    private const val HISTORY_MAX = 30
    const val K_WAKE_AT = "lastEarlyWakeAt"
    const val K_WAKE_REASON = "lastEarlyWakeReason"
    const val K_WAKE_ALARM = "lastEarlyWakeAlarmId"
    const val K_WAKE_PLANNED = "lastEarlyWakePlannedAt"

    private val executor = Executors.newCachedThreadPool()

    /** Completed by WearListenerService when a pong arrives. */
    @Volatile
    var pendingPong: CompletableFuture<Boolean>? = null

    fun register(context: Context, messenger: BinaryMessenger) {
        val ctx = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            // Blocking Task.await runs off the main thread; result is posted back by MethodChannel
            // (replies are allowed from any thread via the engine's platform-thread hop).
            executor.execute {
                val out: Any? = try {
                    handle(ctx, call)
                } catch (t: Throwable) {
                    Log.w(TAG, "${call.method} failed", t)
                    fallback(call.method)
                }
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    try {
                        result.success(out)
                    } catch (t: Throwable) {
                        Log.w(TAG, "reply failed", t)
                    }
                }
            }
        }
    }

    private fun fallback(method: String): Any? = when (method) {
        "ping" -> false
        "status" -> mapOf<String, Any?>("watchReachable" to false)
        "lastEarlyWake" -> emptyMap<String, Any?>()
        "syncPlan" -> false
        "history" -> "[]"
        else -> null
    }

    private fun handle(ctx: Context, call: MethodCall): Any? = when (call.method) {
        "syncPlan" -> syncPlan(
            ctx,
            (call.argument<Number>("alarmId") ?: 0).toInt(),
            (call.argument<Number>("alarmTimeMillis") ?: 0L).toLong(),
            (call.argument<Number>("windowMinutes") ?: 0).toInt(),
            call.argument<Boolean>("dryRun") ?: false,
        )
        "history" -> history(ctx)
        "clearHistory" -> {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(K_HISTORY).apply()
            null
        }
        "ping" -> ping(ctx)
        "status" -> status(ctx)
        "lastEarlyWake" -> lastEarlyWake(ctx)
        else -> null
    }

    private fun <T> await(task: Task<T>, seconds: Long = 4): T? = try {
        Tasks.await(task, seconds, TimeUnit.SECONDS)
    } catch (t: Throwable) {
        Log.w(TAG, "task failed: ${t.javaClass.simpleName}: ${t.message}")
        null
    }

    private fun syncPlan(ctx: Context, alarmId: Int, timeMillis: Long, windowMinutes: Int, dryRun: Boolean): Boolean {
        val window = windowMinutes.coerceIn(0, 60)
        // Persist first: the listener validates early-wake messages against this
        // even if the watch is offline now or the app process is dead later.
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putInt(K_PLAN_ID, alarmId)
            .putLong(K_PLAN_TIME, timeMillis)
            .putInt(K_PLAN_WINDOW, window)
            .putBoolean(K_PLAN_DRY, dryRun)
            .apply()
        val req = PutDataMapRequest.create(PATH_PLAN).apply {
            dataMap.putInt("alarmId", alarmId)
            dataMap.putLong("alarmTimeMillis", timeMillis)
            dataMap.putInt("windowMinutes", window)
            dataMap.putBoolean("dryRun", dryRun)
            dataMap.putLong("updatedAt", System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()
        return await(Wearable.getDataClient(ctx).putDataItem(req)) != null
    }

    private fun reachableNodes(ctx: Context) =
        await(
            Wearable.getCapabilityClient(ctx)
                .getCapability(CAPABILITY, CapabilityClient.FILTER_REACHABLE)
        )?.nodes ?: emptySet()

    private fun ping(ctx: Context): Boolean {
        val future = CompletableFuture<Boolean>()
        pendingPong = future
        try {
            val nodes = await(Wearable.getNodeClient(ctx).connectedNodes) ?: emptyList()
            if (nodes.isEmpty()) return false
            val client = Wearable.getMessageClient(ctx)
            for (n in nodes) {
                try {
                    client.sendMessage(n.id, PATH_PING, ByteArray(0))
                } catch (t: Throwable) {
                    Log.w(TAG, "ping send failed", t)
                }
            }
            return try {
                future.get(5, TimeUnit.SECONDS)
            } catch (t: Throwable) {
                false
            }
        } finally {
            if (pendingPong === future) pendingPong = null
        }
    }

    private fun status(ctx: Context): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        val nodes = reachableNodes(ctx)
        out["watchReachable"] = nodes.isNotEmpty()
        out["watchName"] = nodes.firstOrNull()?.displayName ?: ""
        try {
            val items = await(Wearable.getDataClient(ctx).dataItems)
            if (items != null) {
                try {
                    for (item in items) {
                        if (item.uri.path == PATH_STATUS) {
                            val m = DataMapItem.fromDataItem(item).dataMap
                            out["state"] = m.getString("state", "")
                            out["alarmId"] = m.getInt("alarmId")
                            out["updatedAt"] = m.getLong("updatedAt")
                            out["battery"] = m.getInt("battery")
                            out["hrAvailable"] = m.getBoolean("hrAvailable")
                            out["epochs"] = m.getInt("epochs")
                            out["wokeAt"] = m.getLong("wokeAt")
                            out["reason"] = m.getString("reason", "")
                        }
                    }
                } finally {
                    items.release()
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "status item read failed", t)
        }
        out.putAll(lastEarlyWake(ctx))
        return out
    }

    /** Cheap, prefs-only: safe to call from the alarm sync path. */
    private fun lastEarlyWake(ctx: Context): Map<String, Any?> {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return mapOf(
            "lastEarlyWakeAt" to prefs.getLong(K_WAKE_AT, 0L),
            "lastEarlyWakeReason" to (prefs.getString(K_WAKE_REASON, "") ?: ""),
            "lastEarlyWakeAlarmId" to prefs.getInt(K_WAKE_ALARM, 0),
            "lastEarlyWakePlannedAt" to prefs.getLong(K_WAKE_PLANNED, 0L),
        )
    }

    /** Newest-30 night records as a JSON array string ("[]" when none). */
    private fun history(ctx: Context): String =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(K_HISTORY, null) ?: "[]"

    /** Upserts one finished night (keyed by alarmTimeMillis) from a status DataMap. */
    @Synchronized
    fun recordNight(ctx: Context, m: DataMap) {
        val alarmTime = m.getLong("alarmTimeMillis")
        if (alarmTime <= 0L) return
        val night = JSONObject()
            .put("alarmTimeMillis", alarmTime)
            .put("windowMinutes", m.getInt("windowMinutes"))
            .put("dryRun", m.getBoolean("dryRun"))
            .put("wokeAt", m.getLong("wokeAt"))
            .put("reason", m.getString("reason", ""))
            .put("trace", m.getString("trace", ""))
            .put("epochs", m.getInt("epochs"))
            .put("hrAvailable", m.getBoolean("hrAvailable"))
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val items = ArrayList<JSONObject>()
        try {
            val old = JSONArray(prefs.getString(K_HISTORY, null) ?: "[]")
            for (i in 0 until old.length()) {
                val o = old.optJSONObject(i) ?: continue
                if (o.optLong("alarmTimeMillis") != alarmTime) items.add(o)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "history parse failed, starting over", t)
        }
        items.add(night)
        items.sortBy { it.optLong("alarmTimeMillis") }
        val kept = items.takeLast(HISTORY_MAX)
        val out = JSONArray()
        for (o in kept) out.put(o)
        prefs.edit().putString(K_HISTORY, out.toString()).apply()
    }
}
