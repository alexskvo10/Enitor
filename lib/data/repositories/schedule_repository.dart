import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/date_utils.dart';
import '../models/recurrence_rule.dart';
import '../models/schedule_item.dart';
import '../sources/local/local_storage.dart';
import 'task_repository.dart';

const _kScheduleKey = 'schedule_items';
const _uuid = Uuid();

/// Хранилище пунктов расписания. Бэкап снимает все ключи хранилища целиком,
/// так что расписание попадает в него без правок в BackupService.
class ScheduleRepository {
  ScheduleRepository(this._storage) {
    _cache =
        _storage.readList(_kScheduleKey).map(ScheduleItem.fromJson).toList();
  }

  final LocalStorage _storage;
  final _controller = StreamController<List<ScheduleItem>>.broadcast();
  List<ScheduleItem> _cache = [];

  List<ScheduleItem> get all => List.unmodifiable(_cache);

  /// Перечитать из хранилища: синхронизация записала туда чужие правки.
  void reload() {
    _cache =
        _storage.readList(_kScheduleKey).map(ScheduleItem.fromJson).toList();
    _controller.add(all);
  }

  List<ScheduleItem> forDay(DateTime day) => scheduleForDay(_cache, day);

  Stream<List<ScheduleItem>> watchAll() async* {
    yield all;
    yield* _controller.stream;
  }

  Future<void> _save() async {
    await _storage.writeList(
      _kScheduleKey,
      _cache.map((i) => i.toJson()).toList(),
    );
    _controller.add(all);
  }

  Future<ScheduleItem> create({
    required String title,
    required DateTime date,
    required int startMinutes,
    int? endMinutes,
    String? note,
    String? location,
    int? colorIndex,
    RecurrenceKind? repeat,
    List<int> weekdays = const [],
    int weekInterval = 1,
    List<int> monthDays = const [],
    int intervalDays = 1,
    DateTime? endDate,
    int? reminderMinutes,
  }) async {
    final now = DateTime.now();
    final item = ScheduleItem(
      id: _uuid.v4(),
      title: title,
      date: dateOnly(date),
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      note: note,
      location: location,
      colorIndex: colorIndex,
      // Дни недели без явного вида — серия по дням недели.
      repeat: repeat ?? (weekdays.isEmpty ? null : RecurrenceKind.weekly),
      weekdays: weekdays,
      weekInterval: weekInterval,
      monthDays: monthDays,
      intervalDays: intervalDays,
      endDate: endDate == null ? null : dateOnly(endDate),
      reminderMinutes: reminderMinutes,
      createdAt: now,
      updatedAt: now,
    );
    _cache.add(item);
    await _save();
    return item;
  }

  Future<void> update(ScheduleItem item) async {
    final idx = _cache.indexWhere((i) => i.id == item.id);
    if (idx == -1) return;
    _cache[idx] = item.copyWith(updatedAt: DateTime.now());
    await _save();
  }

  ScheduleItem? byId(String id) => _cache.where((i) => i.id == id).firstOrNull;

  /// Импорт: пункт с тем же id обновляется, иначе добавляется. Так повторный
  /// импорт того же календаря не дублирует. Цвет и напоминание — настройки
  /// самого человека, а не календаря: у существующего пункта сохраняются.
  Future<void> upsert(ScheduleItem item) async {
    final idx = _cache.indexWhere((i) => i.id == item.id);
    if (idx == -1) {
      _cache.add(item);
    } else {
      final old = _cache[idx];
      _cache[idx] = ScheduleItem(
        id: item.id,
        title: item.title,
        date: item.date,
        startMinutes: item.startMinutes,
        endMinutes: item.endMinutes,
        note: item.note,
        location: item.location,
        colorIndex: old.colorIndex,
        repeat: item.repeat,
        weekdays: item.weekdays,
        weekInterval: item.weekInterval,
        monthDays: item.monthDays,
        intervalDays: item.intervalDays,
        endDate: item.endDate,
        exceptDates: item.exceptDates,
        reminderMinutes: old.reminderMinutes,
        createdAt: old.createdAt,
        updatedAt: DateTime.now(),
      );
    }
    await _save();
  }

  Future<void> delete(String id) async {
    _cache.removeWhere((i) => i.id == id);
    await _save();
  }

  /// Убирает из серии один день; у разового пункта — удаляет его целиком.
  Future<void> deleteOccurrence(ScheduleItem item, DateTime day) async {
    if (!item.isSeries) return delete(item.id);
    await update(
      item.copyWith(exceptDates: [...item.exceptDates, dateOnly(day)]),
    );
  }

  void dispose() => _controller.close();
}

/// «Сделать задачей»: пункт остаётся в расписании, а задача получает его
/// название, время и заметку (с местом) как описание. [series] —
/// повторяющаяся задача по тому же правилу с [day] до конца серии; иначе —
/// одна задача на [day]. «Через неделю» у задач нет — такая серия
/// становится задачей каждую неделю.
///
/// Оценку длительности не ставим: бюджет дня уже вычитает этот слот как
/// занятый расписанием, и оценка посчитала бы его второй раз.
Future<void> addScheduleAsTask(
  TaskRepository tasks,
  ScheduleItem item,
  DateTime day, {
  required bool series,
}) async {
  final description = [
    if (item.location != null) item.location!,
    if (item.note != null) item.note!,
  ].join('\n');
  if (series && item.isSeries) {
    // [day] — день серии, так что «каждые N дней» от него идут в той же фазе.
    await tasks.createRecurrence(
      title: item.title,
      description: description.isEmpty ? null : description,
      kind: item.repeat!,
      startDate: day,
      weekdays: item.weekdays,
      monthDays: item.monthDays,
      intervalDays: item.intervalDays,
      startMinutes: item.startMinutes,
      endMinutes: item.endMinutes,
      endDate: item.endDate,
    );
  } else {
    await tasks.createAndAdd(
      title: item.title,
      description: description.isEmpty ? null : description,
      date: day,
      startMinutes: item.startMinutes,
      endMinutes: item.endMinutes,
    );
  }
}

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  final repo = ScheduleRepository(ref.watch(localStorageProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final scheduleItemsProvider = StreamProvider<List<ScheduleItem>>((ref) {
  return ref.watch(scheduleRepositoryProvider).watchAll();
});
