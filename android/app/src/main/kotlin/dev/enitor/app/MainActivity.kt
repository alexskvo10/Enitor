package dev.enitor.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Окно приложения подключается к общему движку ([EngineHolder]) и не
 * уничтожает его при закрытии: фоновые входы (Tasker, виджет) продолжают
 * работать с тем же Dart-изолятом и тем же кэшем данных.
 */
class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        EngineHolder.ensure(context)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // После поворота или восстановления процесса тот же intent пришёл бы
        // второй раз — анкета открылась бы дважды.
        // Из «недавних» Android отдаёт исходный intent ещё раз — он уже
        // обработан.
        val fromHistory =
            (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        if (savedInstanceState == null && !fromHistory) handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    /** Ссылка `enitor://…` и «Поделиться → Enitor». Оба — только анкета. */
    private fun handleIntent(intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_VIEW -> {
                val data = intent.data ?: return
                if (data.scheme.equals("enitor", ignoreCase = true)) {
                    CommandBridge.send("link", mapOf("url" to data.toString()))
                }
            }
            Intent.ACTION_SEND -> {
                if (intent.type?.startsWith("text/") != true) return
                // Браузеры кладут заголовок страницы в SUBJECT, а адрес — в
                // TEXT: заголовок становится названием, адрес — описанием.
                val text = listOfNotNull(
                    intent.getStringExtra(Intent.EXTRA_SUBJECT),
                    intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString(),
                ).filter { it.isNotBlank() }.distinct().joinToString("\n")
                CommandBridge.send("share", mapOf("text" to text))
            }
        }
    }
}
