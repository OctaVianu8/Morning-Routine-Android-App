package com.octavianu.morning_glory.wear

import com.octavianu.morning_glory.wear.LightSleepDetector.Epoch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class LightSleepDetectorTest {
    private val min = 60_000L
    private val t = 1_000_000_000L          // alarm time
    private val w = 30                      // window minutes
    private val windowStart = t - w * min
    private val monitorStart = t - 60 * min
    private val step = 30_000L

    private fun detector() = LightSleepDetector(windowStart, t)

    /** Epoch ending [offset] ms after the monitoring start. */
    private fun still(end: Long, hr: Double? = null) = Epoch(end, 0.02, 0.1, hr)
    private fun move(end: Long, hr: Double? = null) = Epoch(end, 0.5, 0.9, hr)

    private fun runStill(d: LightSleepDetector, fromEnd: Long, toEnd: Long, hr: Double? = null): LightSleepDetector.Decision? {
        var e = fromEnd
        while (e <= toEnd) {
            d.onEpoch(still(e, hr))?.let { return it }
            e += step
        }
        return null
    }

    @Test fun stillNight_noTrigger() {
        val d = detector()
        assertNull(runStill(d, monitorStart + step, t))
    }

    @Test fun movementBeforeWindowOnly_noTrigger() {
        val d = detector()
        var e = monitorStart + step
        while (e < windowStart) {
            val ep = if (e in (windowStart - 10 * min)..(windowStart - 8 * min)) move(e) else still(e)
            assertNull(d.onEpoch(ep))
            e += step
        }
        assertNull(runStill(d, windowStart + step, t))
    }

    @Test fun twoOfFourMovementInWindow_triggersMovement() {
        val d = detector()
        assertNull(runStill(d, monitorStart + step, windowStart + 5 * min))
        var e = windowStart + 5 * min + step
        assertNull(d.onEpoch(move(e))); e += step
        assertNull(d.onEpoch(still(e))); e += step
        val r = d.onEpoch(move(e))
        assertNotNull(r)
        assertEquals("movement", r!!.reason)
    }

    @Test fun singleMovementPlusBigHrRise_doesNotFire() {
        val d = detector()
        assertNull(runStill(d, monitorStart + step, windowStart + 5 * min, hr = 55.0))
        assertNull(d.onEpoch(move(windowStart + 5 * min + step, hr = 80.0)))
        assertEquals('M', d.lastEpochKind)
        assertNull(runStill(d, windowStart + 5 * min + 2 * step, windowStart + 5 * min + 4 * step, hr = 55.0))
    }

    @Test fun twoOfFourWithHrRise_movementHr() {
        val d = detector()
        assertNull(runStill(d, monitorStart + step, windowStart + 5 * min, hr = 55.0))
        var e = windowStart + 5 * min + step
        assertNull(d.onEpoch(move(e, hr = 55.0))); e += step
        assertNull(d.onEpoch(still(e, hr = 55.0))); e += step
        assertEquals("movement+hr", d.onEpoch(move(e, hr = 62.0))?.reason)
    }

    @Test fun twoOfFourWithoutHrRise_movement() {
        val d = detector()
        assertNull(runStill(d, monitorStart + step, windowStart + 5 * min, hr = 55.0))
        var e = windowStart + 5 * min + step
        assertNull(d.onEpoch(move(e, hr = 55.0))); e += step
        assertEquals("movement", d.onEpoch(move(e, hr = 56.0))?.reason)
    }

    @Test fun trace_charactersAndEmptyBeforeWindow() {
        val d = detector()
        assertNull(runStill(d, monitorStart + step, windowStart - step, hr = 55.0))
        assertEquals("", d.trace)
        var e = windowStart
        d.onEpoch(still(e, hr = 55.0)); e += step          // .
        d.onEpoch(still(e, hr = 70.0)); e += step          // h
        d.onEpoch(move(e, hr = 55.0))                      // m (fires? only 1 vote)
        e += step
        d.onEpoch(still(e, hr = 55.0)); e += step          // .
        val r = d.onEpoch(move(e, hr = 70.0))              // M, second vote -> fires
        assertEquals("movement+hr", r?.reason)
        assertEquals(".hm.M", d.trace)
    }

    @Test fun classificationContinuesAfterFiring() {
        val d = detector()
        assertNull(runStill(d, monitorStart + step, windowStart + 5 * min, hr = 55.0))
        var e = windowStart + 5 * min + step
        d.onEpoch(move(e, hr = 55.0)); e += step
        assertNotNull(d.onEpoch(move(e, hr = 55.0))); e += step
        assertNull(d.onEpoch(still(e, hr = 55.0))); e += step
        assertEquals('.', d.lastEpochKind)
        assertNull(d.onEpoch(move(e, hr = 70.0)))
        assertEquals('M', d.lastEpochKind)
        assertEquals("mm.M", d.trace.takeLast(4))
    }

    @Test fun traceStopsAtAlarmTime() {
        val d = detector()
        var e = monitorStart + step
        while (e <= t + 2 * step) { d.onEpoch(still(e)); e += step }
        assertEquals(w * 2, d.trace.length)
    }

    @Test fun singleIsolatedMovementWithoutHr_noTrigger() {
        val d = detector()
        assertNull(runStill(d, monitorStart + step, windowStart + 5 * min))
        assertNull(d.onEpoch(move(windowStart + 5 * min + step)))
        assertNull(runStill(d, windowStart + 5 * min + 2 * step, t))
    }

    @Test fun movementWithoutHrRise_noTriggerWhenIsolated() {
        val d = detector()
        assertNull(runStill(d, monitorStart + step, windowStart + 5 * min, hr = 55.0))
        assertNull(d.onEpoch(move(windowStart + 5 * min + step, hr = 56.0)))
    }

    @Test fun neverFiresTwice() {
        val d = detector()
        assertNull(runStill(d, monitorStart + step, windowStart + 5 * min))
        var e = windowStart + 5 * min + step
        var fires = 0
        repeat(10) {
            if (d.onEpoch(move(e)) != null) fires++
            e += step
        }
        assertEquals(1, fires)
    }

    @Test fun nothingInLastMinute() {
        val d = detector()
        assertNull(runStill(d, monitorStart + step, t - 3 * min))
        // alarmTime - 60 s and later must not fire even with violent movement
        assertNull(d.onEpoch(move(t - 60_000L)))
        assertNull(d.onEpoch(move(t - 30_000L)))
        assertNull(d.onEpoch(move(t)))
    }

    @Test fun worksWithoutHrThroughout() {
        val d = detector()
        assertNull(runStill(d, monitorStart + step, windowStart + 2 * min))
        var e = windowStart + 2 * min + step
        assertNull(d.onEpoch(move(e))); e += step
        val r = d.onEpoch(move(e))
        assertEquals("movement", r?.reason)
    }

    @Test fun noisyConstantBaseline_noTrigger() {
        val d = detector()
        var e = monitorStart + step
        while (e < t) {
            assertNull(d.onEpoch(Epoch(e, 0.05, 0.3, null)))
            e += step
        }
    }

    @Test fun watchOnTable_neverTriggers_andFlagsNotWorn() {
        val d = detector()
        var e = monitorStart + step
        while (e < windowStart) { d.onEpoch(Epoch(e, 0.002, 0.005, null)); e += step }
        assertNull(d.onEpoch(move(windowStart + step)))
        assertNull(d.onEpoch(move(windowStart + 2 * step)))
        assertEquals(true, d.notWorn)
    }

    @Test fun awakeAndMovingBeforeWindow_firesAtWindowStart() {
        val d = detector()
        var e = monitorStart + step
        while (e < windowStart) { assertNull(d.onEpoch(Epoch(e, 1.5, 2.0, null))); e += step }
        assertEquals("movement", d.onEpoch(Epoch(windowStart, 1.5, 2.0, null))?.reason)
    }

    @Test fun lateStart_usesAbsoluteThresholds() {
        val d = detector()
        // only 12 epochs of data, all inside the window
        var e = windowStart + step
        repeat(10) { assertNull(d.onEpoch(still(e))); e += step }
        assertNull(d.onEpoch(move(e))); e += step
        assertEquals("movement", d.onEpoch(move(e))?.reason)
    }
}
