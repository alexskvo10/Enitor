import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/day_template.dart';
import '../sources/local/local_storage.dart';

const _kTemplatesKey = 'day_templates';
const _uuid = Uuid();

/// Хранит именованные шаблоны дня (наборы задач для применения одним нажатием).
class TemplateRepository {
  TemplateRepository(this._storage) {
    _reload();
  }

  final LocalStorage _storage;
  final _controller = StreamController<List<DayTemplate>>.broadcast();
  List<DayTemplate> _cache = [];

  void _reload() {
    _cache =
        _storage.readList(_kTemplatesKey).map(DayTemplate.fromJson).toList();
    _controller.add(_cache);
  }

  Future<void> _save() async {
    await _storage.writeList(
        _kTemplatesKey, _cache.map((t) => t.toJson()).toList());
    _controller.add(List.unmodifiable(_cache));
  }

  Stream<List<DayTemplate>> watchTemplates() async* {
    yield List.unmodifiable(_cache);
    await for (final all in _controller.stream) {
      yield all;
    }
  }

  Future<void> add(String name, List<TemplateItem> items) async {
    _cache.add(DayTemplate(
      id: _uuid.v4(),
      name: name,
      createdAt: DateTime.now(),
      items: items,
    ));
    await _save();
  }

  Future<void> rename(String id, String name) async {
    final idx = _cache.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final t = _cache[idx];
    _cache[idx] = DayTemplate(
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

final templateRepositoryProvider = Provider<TemplateRepository>((ref) {
  final repo = TemplateRepository(ref.watch(localStorageProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final templatesProvider = StreamProvider<List<DayTemplate>>((ref) {
  return ref.watch(templateRepositoryProvider).watchTemplates();
});
