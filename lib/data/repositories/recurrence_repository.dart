import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recurrence_rule.dart';
import '../sources/local/local_storage.dart';

const _kRulesKey = 'recurrence_rules';

/// Хранилище правил повторения. Сами экземпляры задач генерируются на лету
/// в [TaskRepository.ensureRecurrencesForDay] при открытии любого дня.
class RecurrenceRepository {
  RecurrenceRepository(this._storage) {
    _reload();
  }

  final LocalStorage _storage;
  final _controller = StreamController<List<RecurrenceRule>>.broadcast();
  List<RecurrenceRule> _cache = [];

  void _reload() {
    _cache =
        _storage.readList(_kRulesKey).map(RecurrenceRule.fromJson).toList();
    _controller.add(_cache);
  }

  Future<void> _save() async {
    await _storage.writeList(
      _kRulesKey,
      _cache.map((r) => r.toJson()).toList(),
    );
    _controller.add(List.unmodifiable(_cache));
  }

  List<RecurrenceRule> get all => List.unmodifiable(_cache);

  RecurrenceRule? byId(String id) {
    for (final r in _cache) {
      if (r.id == id) return r;
    }
    return null;
  }

  Stream<List<RecurrenceRule>> watchAll() async* {
    yield List.unmodifiable(_cache);
    await for (final v in _controller.stream) {
      yield v;
    }
  }

  Future<void> add(RecurrenceRule rule) async {
    _cache.add(rule);
    await _save();
  }

  Future<void> update(RecurrenceRule rule) async {
    final idx = _cache.indexWhere((r) => r.id == rule.id);
    if (idx == -1) return;
    _cache[idx] = rule;
    await _save();
  }

  /// Удаляет правило. Сами экземпляры задач (с recurrenceRuleId == id)
  /// чистит вызывающая сторона через TaskRepository.
  Future<void> delete(String id) async {
    _cache.removeWhere((r) => r.id == id);
    await _save();
  }

  void dispose() => _controller.close();
}

final recurrenceRepositoryProvider = Provider<RecurrenceRepository>((ref) {
  final repo = RecurrenceRepository(ref.watch(localStorageProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final recurrenceRulesProvider = StreamProvider<List<RecurrenceRule>>((ref) {
  return ref.watch(recurrenceRepositoryProvider).watchAll();
});
