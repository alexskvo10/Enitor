package dev.enitor.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import org.json.JSONObject

/**
 * Галочка на виджете → команда `complete_task` через тот же обработчик, что у
 * всех входов (источник `widget`). Приёмник не экспортирован: прислать сюда
 * может только сам виджет.
 */
class WidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_COMPLETE) return
        val taskId = intent.getStringExtra(EXTRA_TASK_ID) ?: return
        val pendingResult = goAsync()
        var finished = false
        val finish = {
            if (!finished) {
                finished = true
                pendingResult.finish()
            }
        }
        Handler(Looper.getMainLooper()).postDelayed(finish, 9_000)
        EngineHolder.ensure(context)
        val command = JSONObject()
            .put("v", 1)
            .put("command", "complete_task")
            .put("args", JSONObject().put("id", taskId))
        CommandBridge.send(
            "command",
            mapOf("source" to "widget", "json" to command.toString()),
            finish,
        )
    }

    companion object {
        const val ACTION_COMPLETE = "dev.enitor.app.WIDGET_COMPLETE"
        const val EXTRA_TASK_ID = "task_id"
    }
}
