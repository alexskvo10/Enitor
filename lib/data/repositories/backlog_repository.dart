import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/backlog_item.dart';
import '../sources/local/local_storage.dart';

const _kTaskBacklogKey = 'task_backlog';
const _kGoalBacklogKey = 'goal_backlog';

// ─── Бэклог задач ─────────────────────────────────────────────────────────────

class BacklogRepository {
  BacklogRepository(this._storage) {
    _reload();
  }

  final LocalStorage _storage;
  final _controller = StreamController<List<BacklogItem>>.broadcast();
  List<BacklogItem> _cache = [];

  void _reload() {
    _cache = _storage.readList(_kTaskBacklogKey).map(BacklogItem.fromJson).toList();
    _controller.add(_cache);
  }

  Future<void> _save() async {
    await _storage.writeList(
        _kTaskBacklogKey, _cache.map((i) => i.toJson()).toList());
    _controller.add(List.unmodifiable(_cache));
  }

  List<BacklogItem> get all => List.unmodifiable(_cache);

  Stream<List<BacklogItem>> watchItems() async* {
    yield List.unmodifiable(_cache);
    await for (final all in _controller.stream) {
      yield all;
    }
  }

  Future<void> add(BacklogItem item) async {
    // Не добавляем дубли по id
    if (_cache.any((i) => i.id == item.id)) return;
    _cache.add(item);
    await _save();
  }

  Future<void> remove(String id) async {
    _cache.removeWhere((i) => i.id == id);
    await _save();
  }

  void dispose() => _controller.close();
}

// ─── Бэклог целей ─────────────────────────────────────────────────────────────

class GoalBacklogRepository {
  GoalBacklogRepository(this._storage) {
    _reload();
  }

  final LocalStorage _storage;
  final _controller = StreamController<List<GoalBacklogItem>>.broadcast();
  List<GoalBacklogItem> _cache = [];

  void _reload() {
    _cache = _storage
        .readList(_kGoalBacklogKey)
        .map(GoalBacklogItem.fromJson)
        .toList();
    _controller.add(_cache);
  }

  Future<void> _save() async {
    await _storage.writeList(
        _kGoalBacklogKey, _cache.map((i) => i.toJson()).toList());
    _controller.add(List.unmodifiable(_cache));
  }

  List<GoalBacklogItem> get all => List.unmodifiable(_cache);

  Stream<List<GoalBacklogItem>> watchItems() async* {
    yield List.unmodifiable(_cache);
    await for (final all in _controller.stream) {
      yield all;
    }
  }

  Future<void> add(GoalBacklogItem item) async {
    if (_cache.any((i) => i.id == item.id)) return;
    _cache.add(item);
    await _save();
  }

  Future<void> remove(String id) async {
    _cache.removeWhere((i) => i.id == id);
    await _save();
  }

  void dispose() => _controller.close();
}

// ─── Провайдеры ───────────────────────────────────────────────────────────────

final backlogRepositoryProvider = Provider<BacklogRepository>((ref) {
  final repo = BacklogRepository(ref.watch(localStorageProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final backlogItemsProvider = StreamProvider<List<BacklogItem>>((ref) {
  return ref.watch(backlogRepositoryProvider).watchItems();
});

final goalBacklogRepositoryProvider = Provider<GoalBacklogRepository>((ref) {
  final repo = GoalBacklogRepository(ref.watch(localStorageProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final goalBacklogItemsProvider = StreamProvider<List<GoalBacklogItem>>((ref) {
  return ref.watch(goalBacklogRepositoryProvider).watchItems();
});
