package com.octavianu.morning_glory.wear

import android.Manifest
import android.app.Activity
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.TextView
import java.text.DateFormat
import java.util.Date

class MainActivity : Activity(), SharedPreferences.OnSharedPreferenceChangeListener {
    private lateinit var stateText: TextView
    private lateinit var detailText: TextView
    private lateinit var phoneText: TextView
    private lateinit var grant: Button
    private val handler = Status.mainHandler()
    private val ticker = object : Runnable {
        override fun run() { refresh(); handler.postDelayed(this, 2_000L) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        stateText = findViewById(R.id.stateText)
        detailText = findViewById(R.id.detailText)
        phoneText = findViewById(R.id.phoneText)
        grant = findViewById(R.id.grantButton)
        grant.setOnClickListener { requestPerms() }
        findViewById<Button>(R.id.vibrateButton).setOnClickListener { Status.vibrate(this) }
    }

    override fun onResume() {
        super.onResume()
        Store.prefs(this).registerOnSharedPreferenceChangeListener(this)
        handler.post(ticker)
        PlanManager.syncFromDataLayer(this)
    }

    override fun onPause() {
        handler.removeCallbacks(ticker)
        Store.prefs(this).unregisterOnSharedPreferenceChangeListener(this)
        super.onPause()
    }

    override fun onSharedPreferenceChanged(p: SharedPreferences?, key: String?) {
        handler.post { refresh() }
    }

    private fun missingPermissions(): List<String> {
        val list = ArrayList<String>()
        list += if (Build.VERSION.SDK_INT >= 36) "android.permission.health.READ_HEART_RATE"
        else Manifest.permission.BODY_SENSORS
        if (Build.VERSION.SDK_INT >= 33) list += Manifest.permission.POST_NOTIFICATIONS
        return list.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
    }

    private fun requestPerms() {
        val m = missingPermissions()
        if (m.isNotEmpty()) requestPermissions(m.toTypedArray(), 1)
    }

    override fun onRequestPermissionsResult(code: Int, perms: Array<out String>, res: IntArray) {
        super.onRequestPermissionsResult(code, perms, res)
        refresh()
    }

    private fun refresh() {
        val plan = Store.loadPlan(this)
        val state = Store.state(this)
        val tf = DateFormat.getTimeInstance(DateFormat.SHORT)
        stateText.text = when {
            plan == null && state != "woke" && state != "finished" -> "No smart alarm set on the phone"
            state == "monitoring" || state == "no_permission" ->
                "Monitoring… ${Store.epochs(this) / 2} min of data"
            state == "woke" -> "Woke you at ${tf.format(Date(Store.wokeAt(this)))} (${Store.reason(this)})"
            state == "finished" && Store.sessionDry(this) && Store.wokeAt(this) > 0L ->
                "Would have woken you at ${tf.format(Date(Store.wokeAt(this)))} (${Store.reason(this)})"
            state == "finished" && Store.reason(this).isEmpty() -> "No light sleep seen in the window"
            state == "finished" -> "Finished: ${Store.reason(this).replace('_', ' ')}"
            plan != null -> "Smart wake: ${tf.format(Date(plan.alarmTimeMillis))}, window ${plan.windowMinutes} min"
            else -> "No smart alarm set on the phone"
        }
        val dryNote = "Dry run: recording only, the alarm will ring at the normal time"
        detailText.text = when {
            plan?.dryRun == true && state == "monitoring" && Store.wokeAt(this) > 0L ->
                "$dryNote\nWould have woken you at ${tf.format(Date(Store.wokeAt(this)))} (${Store.reason(this)})"
            plan?.dryRun == true -> dryNote
            plan != null && (state == "monitoring" || state == "no_permission") ->
                "Smart wake ${tf.format(Date(plan.alarmTimeMillis))}, window ${plan.windowMinutes} min" +
                    if (Store.hrAvailable(this)) ", heart rate on" else ", movement only"
            else -> ""
        }
        val last = Store.lastPhoneContact(this)
        phoneText.text = if (last == 0L) "Phone: no plan received yet. Keep the watch connected by Bluetooth."
        else "Phone last heard at ${tf.format(Date(last))}"
        grant.visibility = if (missingPermissions().isEmpty()) View.GONE else View.VISIBLE
    }
}
