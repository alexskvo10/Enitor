import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/schedule_template.dart';
import '../sources/local/local_storage.dart';

const _kKey = 'schedule_templates';
const _uuid = Uuid();

/// Шаблоны расписания — как шаблоны дня у задач, но из пунктов расписания.
class ScheduleTemplateRepository {
  ScheduleTemplateRepository(this._storage) {
    reload();
  }

  final LocalStorage _storage;
  final _controller = StreamController<List<ScheduleTemplate>>.broadcast();
  List<ScheduleTemplate> _cache = [];

  /// Перечитать из хранилища: синхронизация записала туда чужие правки.
  void reload() {
    _cache = _storage.readList(_kKey).map(ScheduleTemplate.fromJson).toList();
    _controller.add(List.unmodifiable(_cache));
  }

  Future<void> _save() async {
    await _storage.writeList(_kKey, _cache.map((t) => t.toJson()).toList());
    _controller.add(List.unmodifiable(_cache));
  }

  Stream<List<ScheduleTemplate>> watchTemplates() async* {
    yield List.unmodifiable(_cache);
    yield* _controller.stream;
  }

  Future<void> add(String name, List<ScheduleTemplateItem> items) async {
    _cache.add(
      ScheduleTemplate(
        id: _uuid.v4(),
        name: name,
        createdAt: DateTime.now(),
        items: items,
      ),
    );
    await _save();
  }

  Future<void> rename(String id, String name) async {
    final idx = _cache.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final t = _cache[idx];
    _cache[idx] = ScheduleTemplate(
      id: t.id,
      name: name,
      createdAt: t.createdAt,
      items: t.items,
    );
    await _save();
  }

  Future<void> remove(String id) async {
    _cache.removeWhere((t) => t.id == id);
    await _save();
  }

  void dispose() => _controller.close();
}

final scheduleTemplateRepositoryProvider =
    Provider<ScheduleTemplateRepository>((ref) {
  final repo = ScheduleTemplateRepository(ref.watch(localStorageProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final scheduleTemplatesProvider = StreamProvider<List<ScheduleTemplate>>(
  (ref) => ref.watch(scheduleTemplateRepositoryProvider).watchTemplates(),
);
