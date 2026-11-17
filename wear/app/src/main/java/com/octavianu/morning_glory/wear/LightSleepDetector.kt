package com.octavianu.morning_glory.wear

/**
 * Actigraphy heuristic: deep sleep and REM keep the body still, light sleep and
 * brief arousals show movement. Pure Kotlin (no Android imports) so it can be
 * unit tested on the JVM. This is a movement based estimate, not sleep staging.
 */
class LightSleepDetector(
    private val windowStartMillis: Long,
    private val alarmTimeMillis: Long,
    private val config: Config = Config(),
) {
    data class Config(
        val absMoveThreshold: Double = 0.08,
        val moveFactor: Double = 4.0,
        val absSpikeThreshold: Double = 1.0,
        val hrRise: Double = 0.08,
        val minBaselineEpochs: Int = 10,
        /** Upper bound for the learned noise floor so a restless baseline cannot mute the detector. */
        val maxStillLevel: Double = 0.15,
        val notWornActivity: Double = 0.01,
        val lastEpochsForVote: Int = 4,
        val votesNeeded: Int = 2,
        val quietBeforeAlarmMillis: Long = 60_000L,
        val maxHistory: Int = 240,
    )

    data class Epoch(
        val endMillis: Long,
        val activity: Double,
        val maxActivity: Double,
        val hr: Double?,
    )

    data class Decision(val reason: String)

    private val activities = ArrayList<Double>()
    private val hrs = ArrayList<Double>()
    private val moveFlags = ArrayList<Boolean>()
    private var preWindowEpochs = 0
    private var preWindowMaxActivity = 0.0
    private var anyHr = false
    private var fired = false

    /** True when there was a full baseline with no heart rate and a perfectly flat accelerometer. */
    val notWorn: Boolean
        get() = preWindowEpochs >= config.minBaselineEpochs &&
            !anyHr && preWindowMaxActivity < config.notWornActivity

    val epochCount: Int get() = totalEpochs
    private var totalEpochs = 0

    private val traceBuf = StringBuilder()

    /**
     * One character per epoch inside the window, chronological: '.' still, 'm' movement,
     * 'h' still but heart rate risen, 'M' movement with heart rate risen.
     */
    val trace: String get() = traceBuf.toString()

    /** Kind of the most recent epoch ('.', 'm', 'h', 'M'), also after the detector has fired. */
    var lastEpochKind: Char = '.'
        private set

    fun onEpoch(e: Epoch): Decision? {
        val stillLevel = if (preWindowEpochs >= config.minBaselineEpochs) stillLevel() else 0.0
        val hrBase = hrBase()
        val moving = isMovement(e, stillLevel)
        val hrUp = e.hr != null && hrBase != null && e.hr >= hrBase * (1.0 + config.hrRise)
        lastEpochKind = when {
            moving && hrUp -> 'M'
            moving -> 'm'
            hrUp -> 'h'
            else -> '.'
        }
        if (e.endMillis >= windowStartMillis && e.endMillis < alarmTimeMillis) traceBuf.append(lastEpochKind)

        // Record after classifying against the previous baseline.
        totalEpochs++
        activities.add(e.activity)
        e.hr?.let { hrs.add(it); anyHr = true }
        moveFlags.add(moving)
        if (e.endMillis < windowStartMillis) {
            preWindowEpochs++
            if (e.activity > preWindowMaxActivity) preWindowMaxActivity = e.activity
            if (e.maxActivity > preWindowMaxActivity) preWindowMaxActivity = e.maxActivity
        }
        trim()

        if (fired) return null
        if (e.endMillis < windowStartMillis) return null
        if (e.endMillis >= alarmTimeMillis - config.quietBeforeAlarmMillis) return null
        if (totalEpochs < config.minBaselineEpochs) return null
        if (notWorn) return null

        val n = config.lastEpochsForVote
        val recent = moveFlags.takeLast(n)
        if (recent.count { it } >= config.votesNeeded) {
            fired = true
            return Decision(if (hrUp) "movement+hr" else "movement")
        }
        return null
    }

    private fun isMovement(e: Epoch, stillLevel: Double): Boolean {
        val threshold = maxOf(config.absMoveThreshold, stillLevel * config.moveFactor)
        return e.activity > threshold || e.maxActivity > config.absSpikeThreshold
    }

    private fun stillLevel(): Double {
        if (activities.isEmpty()) return 0.0
        val sorted = activities.sorted()
        val count = maxOf(1, (sorted.size * 0.6).toInt())
        return minOf(median(sorted.subList(0, count)), config.maxStillLevel)
    }

    private fun hrBase(): Double? =
        if (hrs.size >= 5) median(hrs.sorted()) else null

    private fun median(sorted: List<Double>): Double {
        val n = sorted.size
        return if (n % 2 == 1) sorted[n / 2] else (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    }

    private fun trim() {
        while (activities.size > config.maxHistory) activities.removeAt(0)
        while (hrs.size > config.maxHistory) hrs.removeAt(0)
        while (moveFlags.size > config.maxHistory) moveFlags.removeAt(0)
    }
}
