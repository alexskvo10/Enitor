package dev.enitor.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Bundle
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StrikethroughSpan
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.util.Calendar

/**
 * Виджет «Сегодня». Данные — снимок, который пишет Dart (ключ
 * `device.widget.today` в SharedPreferences, тексты уже на языке
 * приложения): сегодняшний и завтрашний день. День выбирается здесь по
 * правилу приложения «до 4:00 — ещё вчера», поэтому утром виджет показывает
 * новый день, даже если Enitor не открывали (обновление — раз в 30 минут).
 */
class TodayWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { render(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        options: Bundle,
    ) = render(context, manager, id)

    companion object {
        private const val PREFS = "FlutterSharedPreferences"
        private const val KEY = "flutter.device.widget.today"
        private val ROWS = intArrayOf(
            R.id.row0, R.id.row1, R.id.row2, R.id.row3, R.id.row4, R.id.row5,
        )
        private val CHECKS = intArrayOf(
            R.id.check0, R.id.check1, R.id.check2, R.id.check3, R.id.check4, R.id.check5,
        )
        private val TIMES = intArrayOf(
            R.id.time0, R.id.time1, R.id.time2, R.id.time3, R.id.time4, R.id.time5,
        )
        private val TITLES = intArrayOf(
            R.id.title0, R.id.title1, R.id.title2, R.id.title3, R.id.title4, R.id.title5,
        )

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, TodayWidgetProvider::class.java))
            ids.forEach { render(context, manager, it) }
        }

        private enum class TimeState { NORMAL, URGENT, OVERDUE }

        /**
         * Те же правила, что у корешка задачи в приложении (_calcTimeState в
         * today_screen.dart): после конца — просрочена, за 30 минут до конца
         * и после 23:00 — требует внимания. Конец меньше начала — задача
         * «через полночь», её конец наступает на следующий день. Виджет
         * обновляется раз в 30 минут, так что цвет может запоздать на столько же.
         */
        private fun timeState(task: JSONObject): TimeState {
            val c = Calendar.getInstance()
            val nowMin = c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
            // До 4:00 показываем вчерашний день: с его начала прошли сутки.
            val daysSince = if (c.get(Calendar.HOUR_OF_DAY) < 4) 1 else 0
            val start = if (task.has("start")) task.optInt("start") else null
            val end = if (task.has("end")) task.optInt("end") else null
            val overnight = start != null && end != null && end < start
            if (daysSince >= 1 && !overnight) return TimeState.OVERDUE
            val endFromDay = end?.let { if (overnight) it + 1440 else it }
            val now = daysSince * 1440 + nowMin
            return when {
                endFromDay != null && now >= endFromDay -> TimeState.OVERDUE
                endFromDay != null && now >= endFromDay - 30 -> TimeState.URGENT
                daysSince == 0 && nowMin >= 23 * 60 -> TimeState.URGENT
                else -> TimeState.NORMAL
            }
        }

        /** «День приложения»: до 4:00 — ещё вчерашняя дата. */
        private fun effectiveDay(): String {
            val c = Calendar.getInstance()
            if (c.get(Calendar.HOUR_OF_DAY) < 4) c.add(Calendar.DAY_OF_MONTH, -1)
            return "%04d-%02d-%02d".format(
                c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH),
            )
        }

        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_today)
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
            val snapshot = raw?.let { runCatching { JSONObject(it) }.getOrNull() }
            val day = snapshot?.optJSONObject("days")?.optJSONObject(effectiveDay())

            views.setTextViewText(R.id.title, snapshot?.optString("title") ?: "Enitor")
            views.setTextViewText(R.id.date, day?.optString("date") ?: "")
            views.setOnClickPendingIntent(R.id.header, openLink(context, "enitor://open?screen=today", 0))
            views.setOnClickPendingIntent(R.id.add, openLink(context, "enitor://add", 1))
            views.setContentDescription(R.id.add, snapshot?.optString("addLabel") ?: "+")

            val tasks = day?.optJSONArray("tasks")
            val count = tasks?.length() ?: 0
            val total = day?.optInt("total", count) ?: 0
            val done = day?.optInt("done") ?: 0
            val allDone = total > 0 && done == total
            val counter = day?.optString("counter") ?: ""

            views.setViewVisibility(R.id.progressRow, if (total > 0 && !allDone) View.VISIBLE else View.GONE)
            views.setProgressBar(R.id.progress, total.coerceAtLeast(1), done, false)
            views.setTextViewText(R.id.counter, counter)

            // Нет снимка на этот день (Enitor давно не открывали) — просим
            // открыть; есть, но пустой — спокойное «на сегодня ничего».
            views.setViewVisibility(R.id.empty, if (count == 0) View.VISIBLE else View.GONE)
            if (count == 0) {
                views.setTextViewText(
                    R.id.empty,
                    snapshot?.optString(if (day == null) "openApp" else "empty") ?: "Enitor",
                )
            }
            views.setViewVisibility(R.id.allDone, if (allDone) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.allDoneText, snapshot?.optString("allDone") ?: "")
            views.setTextViewText(R.id.allDoneCounter, counter)

            // Сколько строк влезает. Высота в портрете — MAX_HEIGHT, в
            // альбомной — MIN_HEIGHT (так их отдаёт лаунчер); по одной
            // MIN_HEIGHT в портрете 2×2 вмещал бы одну строку вместо трёх.
            // 88 — отступы 2×14dp + шапка 44dp + прогресс 16dp; строка — 32dp,
            // «ещё N» — около 18dp.
            val options = manager.getAppWidgetOptions(id)
            val portrait = context.resources.configuration.orientation !=
                Configuration.ORIENTATION_LANDSCAPE
            val height = options.getInt(
                if (portrait) AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT
                else AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT,
                110,
            )
            val space = height - 88
            var capacity = (space / 32).coerceIn(1, ROWS.size)
            if (total > capacity && space - capacity * 32 < 18) capacity = (capacity - 1).coerceAtLeast(1)
            val shown = if (allDone) 0 else minOf(count, capacity)

            val hidden = total - shown
            views.setViewVisibility(R.id.more, if (shown > 0 && hidden > 0) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.more, (snapshot?.optString("more") ?: "+%d").replace("%d", "$hidden"))

            val ink = context.getColor(R.color.widget_ink)
            val muted = context.getColor(R.color.widget_ink_muted)
            for (i in ROWS.indices) {
                val task = if (i < shown) tasks?.optJSONObject(i) else null
                if (task == null) {
                    views.setViewVisibility(ROWS[i], View.GONE)
                    continue
                }
                val isDone = task.optBoolean("done")
                val title = task.optString("title")
                views.setViewVisibility(ROWS[i], View.VISIBLE)
                // Время — справа от названия: названия всегда стоят у флажка.
                val time = task.optString("time")
                views.setViewVisibility(TIMES[i], if (time.isEmpty()) View.GONE else View.VISIBLE)
                views.setTextViewText(TIMES[i], time)
                views.setTextColor(
                    TIMES[i],
                    when (if (isDone) TimeState.NORMAL else timeState(task)) {
                        TimeState.OVERDUE -> context.getColor(R.color.widget_high)
                        TimeState.URGENT -> context.getColor(R.color.widget_medium)
                        TimeState.NORMAL -> muted
                    },
                )
                // Выполненные — зачёркнуты и приглушены.
                views.setTextViewText(
                    TITLES[i],
                    if (isDone) SpannableString(title).apply {
                        setSpan(StrikethroughSpan(), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    } else title,
                )
                views.setTextColor(TITLES[i], if (isDone) muted else ink)
                views.setImageViewResource(
                    CHECKS[i],
                    when {
                        isDone -> R.drawable.widget_check_on
                        task.optString("priority") == "high" -> R.drawable.widget_check_high
                        task.optString("priority") == "medium" -> R.drawable.widget_check_medium
                        else -> R.drawable.widget_check_off
                    },
                )
                views.setContentDescription(CHECKS[i], title)
                if (!isDone) {
                    views.setOnClickPendingIntent(CHECKS[i], completeIntent(context, task.optString("id"), i))
                }
                views.setOnClickPendingIntent(
                    TITLES[i],
                    openLink(context, "enitor://open?screen=today", 10 + i),
                )
            }
            manager.updateAppWidget(id, views)
        }

        private fun openLink(context: Context, link: String, code: Int): PendingIntent {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(link), context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(
                context, code, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun completeIntent(context: Context, taskId: String, row: Int): PendingIntent {
            val intent = Intent(context, WidgetActionReceiver::class.java)
                .setAction(WidgetActionReceiver.ACTION_COMPLETE)
                .putExtra(WidgetActionReceiver.EXTRA_TASK_ID, taskId)
            return PendingIntent.getBroadcast(
                context, 100 + row, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
