package com.octavianu.morning_glory.wear

import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService

class PhoneListenerService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        for (event in events) {
            if (event.dataItem.uri.path != Protocol.PATH_PLAN) continue
            Store.touchPhone(this)
            if (event.type == DataEvent.TYPE_DELETED) {
                PlanManager.apply(this, null)
            } else {
                PlanManager.apply(this, PlanManager.parse(event.dataItem))
            }
        }
    }

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != Protocol.PATH_PING) return
        Store.touchPhone(this)
        Status.vibrate(this, longArrayOf(0, 150, 100, 150))
        val node = event.sourceNodeId
        val app = applicationContext
        Thread {
            try {
                Tasks.await(Wearable.getMessageClient(app).sendMessage(node, Protocol.PATH_PONG, ByteArray(0)))
            } catch (_: Throwable) {
            }
        }.start()
    }
}
