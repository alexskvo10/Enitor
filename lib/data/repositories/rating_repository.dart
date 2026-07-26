import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sources/local/local_storage.dart';

const _kDayRatings = 'day_ratings';
const _kPeriodRatings = 'period_ratings';

/// Хранит субъективные оценки качества (рефлексия) — отдельно от статистики,
/// которую приложение считает само. Не влияет на продуктивность/своевременность.
///
/// • Оценки дней — карта dateKey → 1..10.
/// • Оценки периодов целей — карта periodKey → 1..10 (см. [GoalPeriodRef.key]).
class RatingRepository {
  RatingRepository(this._storage) {
    _reload();
  }

  final LocalStorage _storage;
  final _dayController = StreamController<Map<String, int>>.broadcast();
  final _periodController = StreamController<Map<String, int>>.broadcast();
  Map<String, int> _days = {};
  Map<String, int> _periods = {};

  void _reload() {
    _days = _readIntMap(_kDayRatings);
    _periods = _readIntMap(_kPeriodRatings);
  }

  Map<String, int> _readIntMap(String key) {
    final raw = _storage.readMap(key) ?? {};
    return raw.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  static String dayKey(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String();

  // ── Оценка дня ──────────────────────────────────────────────────────────────

  Stream<int?> watchDayRating(DateTime date) async* {
    final k = dayKey(date);
    yield _days[k];
    await for (final m in _dayController.stream) {
      yield m[k];
    }
  }

  Future<void> setDayRating(DateTime date, int value) async {
    _days[dayKey(date)] = value;
    await _storage.writeMap(_kDayRatings, _days);
    _dayController.add(Map.of(_days));
  }

  /// Все оценки дней (для достижений: «идеальные» дни 10/10 и т.п.).
  Stream<List<int>> watchAllDayRatings() async* {
    yield _days.values.toList();
    await for (final m in _dayController.stream) {
      yield m.values.toList();
    }
  }

  /// Карта dateKey → оценка (для ретроспективы: средняя оценка дней недели).
  Stream<Map<String, int>> watchDayRatingsMap() async* {
    yield Map.of(_days);
    await for (final m in _dayController.stream) {
      yield m;
    }
  }

  // ── Оценка периода цели ───────────────────────────────────────────────────────

  Stream<int?> watchPeriodRating(String periodKey) async* {
    yield _periods[periodKey];
    await for (final m in _periodController.stream) {
      yield m[periodKey];
    }
  }

  Future<void> setPeriodRating(String periodKey, int value) async {
    _periods[periodKey] = value;
    await _storage.writeMap(_kPeriodRatings, _periods);
    _periodController.add(Map.of(_periods));
  }

  void dispose() {
    _dayController.close();
    _periodController.close();
  }
}

final ratingRepositoryProvider = Provider<RatingRepository>((ref) {
  final repo = RatingRepository(ref.watch(localStorageProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final dayRatingProvider = StreamProvider.family<int?, DateTime>((ref, date) {
  return ref.watch(ratingRepositoryProvider).watchDayRating(date);
});

final allDayRatingsProvider = StreamProvider<List<int>>((ref) {
  return ref.watch(ratingRepositoryProvider).watchAllDayRatings();
});

final dayRatingsMapProvider = StreamProvider<Map<String, int>>((ref) {
  return ref.watch(ratingRepositoryProvider).watchDayRatingsMap();
});

final periodRatingProvider = StreamProvider.family<int?, String>((ref, key) {
  return ref.watch(ratingRepositoryProvider).watchPeriodRating(key);
});
