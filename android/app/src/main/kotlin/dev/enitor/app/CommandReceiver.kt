package dev.enitor.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper

/**
 * Команды от Tasker, Automate и т.п.: явный broadcast в пакет dev.enitor.app
 * с действием `dev.enitor.app.COMMAND`. Приёмник, а не активити: Android 10+
 * не даёт запускать активити из фона, а автоматизация обычно работает в фоне.
 *
 * Ключ проверяет Dart (за постоянное время), он же решает, кому можно
 * ответить. Приложение на передний план не выходит.
 */
class CommandReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val pendingResult = goAsync()
        var finished = false
        val finish = {
            if (!finished) {
                finished = true
                pendingResult.finish()
            }
        }
        // У приёмника ~10 с; если Dart ещё поднимается и не успел — отпускаем
        // систему раньше, чем она сочтёт приложение зависшим.
        Handler(Looper.getMainLooper()).postDelayed(finish, 9_000)
        EngineHolder.ensure(context)
        CommandBridge.send(
            "command",
            mapOf(
                "source" to "tasker",
                "key" to intent.getStringExtra("key"),
                "json" to (intent.getStringExtra("command") ?: ""),
                "replyPackage" to intent.getStringExtra("reply_package"),
                "requestId" to intent.getStringExtra("request_id"),
            ),
            finish,
        )
    }

    companion object {
        const val ACTION = "dev.enitor.app.COMMAND"
    }
}
