package dev.enitor.app

import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Один Flutter-движок на процесс. LocalStorage живёт поверх SharedPreferences,
 * а тот кэширует данные в Dart-изоляте: второй движок (например, для фоновой
 * команды от Tasker) видел бы устаревший кэш, и два изолята перезаписывали бы
 * данные друг друга. Поэтому и окно приложения, и фоновые входы подключаются к
 * одному кэшированному движку.
 */
object EngineHolder {
    private const val ENGINE_ID = "enitor_main"

    fun ensure(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }
        val app = context.applicationContext
        val engine = FlutterEngine(app)
        CommandBridge.attach(engine, app)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }
}

/**
 * Канал `dev.enitor.app/commands` — общий с Windows. Пока Dart не сказал
 * «ready», вызовы копятся в буфере: ссылка, по которой приложение только
 * запускается, не теряется.
 */
object CommandBridge {
    private const val CHANNEL = "dev.enitor.app/commands"
    private const val REPLY_ACTION = "dev.enitor.app.REPLY"

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var ready = false
    private val pending = mutableListOf<Triple<String, Map<String, Any?>, () -> Unit>>()

    fun attach(engine: FlutterEngine, context: Context) {
        appContext = context
        ready = false
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(::onDartCall)
        }
    }

    private fun onDartCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ready" -> {
                ready = true
                val queued = pending.toList()
                pending.clear()
                queued.forEach { (method, args, done) -> invoke(method, args, done) }
                result.success(null)
            }
            "multicastLock" -> {
                appContext?.let { MulticastHolder.set(it, call.argument<Boolean>("on") == true) }
                result.success(null)
            }
            "widgetChanged" -> {
                appContext?.let { TodayWidgetProvider.refreshAll(it) }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** [done] вызывается, когда Dart ответил (или отказал) — для goAsync. */
    fun send(method: String, args: Map<String, Any?>, done: () -> Unit = {}) {
        if (!ready) {
            pending.add(Triple(method, args, done))
            return
        }
        invoke(method, args, done)
    }

    private fun invoke(method: String, args: Map<String, Any?>, done: () -> Unit) {
        val ch = channel
        if (ch == null) {
            done()
            return
        }
        ch.invokeMethod(method, args, object : MethodChannel.Result {
            override fun success(value: Any?) {
                deliverReply(value, args["requestId"] as? String)
                done()
            }

            override fun error(code: String, message: String?, details: Any?) = done()

            override fun notImplemented() = done()
        })
    }

    /**
     * Ответ уходит адресным broadcast ровно в один пакет — тот, что Dart
     * разрешил (`replyTo` есть только у пакетов из списка в Интеграциях).
     * Общий broadcast, который видят все приложения, не отправляется никогда.
     */
    private fun deliverReply(value: Any?, requestId: String?) {
        val map = value as? Map<*, *> ?: return
        val replyTo = map["replyTo"] as? String ?: return
        val reply = map["reply"] as? String ?: return
        val context = appContext ?: return
        val intent = Intent(REPLY_ACTION)
            .setPackage(replyTo)
            .putExtra("reply", reply)
        requestId?.let { intent.putExtra("request_id", it) }
        context.sendBroadcast(intent)
    }
}

/**
 * Синхронизация по сети: без этой блокировки Android отбрасывает чужие
 * широковещательные пакеты Wi-Fi, и телефон не слышит соседей. Держим её,
 * только пока Enitor на экране и есть группа устройств.
 */
object MulticastHolder {
    private var lock: WifiManager.MulticastLock? = null

    fun set(context: Context, on: Boolean) {
        if (on) {
            if (lock?.isHeld == true) return
            val wifi = context.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
            lock = wifi.createMulticastLock("enitor-lan").apply {
                setReferenceCounted(false)
                acquire()
            }
        } else {
            lock?.let { if (it.isHeld) it.release() }
            lock = null
        }
    }
}
