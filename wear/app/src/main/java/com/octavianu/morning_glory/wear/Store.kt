package com.octavianu.morning_glory.wear

import android.content.Context
import android.content.SharedPreferences

data class Plan(val alarmId: Int, val alarmTimeMillis: Long, val windowMinutes: Int, val dryRun: Boolean = false) {
    val windowStartMillis: Long get() = alarmTimeMillis - windowMinutes * 60_000L
    val monitorStartMillis: Long get() = alarmTimeMillis - 60 * 60_000L
}

/** Persisted plan and state, shared between the service, receivers and the activity. */
object Store {
    private const val FILE = "morning_glory_wear"

    fun prefs(c: Context): SharedPreferences =
        c.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun loadPlan(c: Context): Plan? {
        val p = prefs(c)
        val w = p.getInt("windowMinutes", 0)
        val t = p.getLong("alarmTime", 0L)
        if (w <= 0 || t <= 0L) return null
        return Plan(p.getInt("alarmId", 0), t, w, p.getBoolean("dryRun", false))
    }

    fun savePlan(c: Context, plan: Plan?) {
        val e = prefs(c).edit()
        if (plan == null) {
            e.remove("windowMinutes").remove("alarmTime").remove("alarmId").remove("dryRun")
        } else {
            e.putInt("alarmId", plan.alarmId).putLong("alarmTime", plan.alarmTimeMillis)
                .putInt("windowMinutes", plan.windowMinutes).putBoolean("dryRun", plan.dryRun)
        }
        e.apply()
    }

    fun wakeSent(c: Context) = prefs(c).getBoolean("wakeSent", false)
    fun setWakeSent(c: Context, v: Boolean) = prefs(c).edit().putBoolean("wakeSent", v).apply()

    fun state(c: Context) = prefs(c).getString("state", "idle") ?: "idle"
    fun reason(c: Context) = prefs(c).getString("reason", "") ?: ""
    fun epochs(c: Context) = prefs(c).getInt("epochs", 0)
    fun wokeAt(c: Context) = prefs(c).getLong("wokeAt", 0L)
    /** Whether the most recent monitoring session was a dry run (survives plan clearing). */
    fun sessionDry(c: Context) = prefs(c).getBoolean("sessionDry", false)
    fun setSessionDry(c: Context, v: Boolean) = prefs(c).edit().putBoolean("sessionDry", v).apply()
    fun trace(c: Context) = prefs(c).getString("trace", "") ?: ""
    fun setTrace(c: Context, v: String) = prefs(c).edit().putString("trace", v).apply()
    fun hrAvailable(c: Context) = prefs(c).getBoolean("hrAvailable", false)
    fun lastPhoneContact(c: Context) = prefs(c).getLong("lastPhoneContact", 0L)

    fun touchPhone(c: Context) =
        prefs(c).edit().putLong("lastPhoneContact", System.currentTimeMillis()).apply()

    /** Writes state fields; the activity listens to prefs changes to refresh. */
    fun setState(
        c: Context, state: String, reason: String = "", epochs: Int? = null,
        wokeAt: Long? = null, hrAvailable: Boolean? = null,
    ) {
        val e = prefs(c).edit().putString("state", state).putString("reason", reason)
        epochs?.let { e.putInt("epochs", it) }
        wokeAt?.let { e.putLong("wokeAt", it) }
        hrAvailable?.let { e.putBoolean("hrAvailable", it) }
        e.apply()
    }
}
