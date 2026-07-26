import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart';
import '../models/user_profile.dart';
import '../sources/local/local_storage.dart';

const _kProfileKey = 'user_profile';

class ProfileRepository {
  ProfileRepository(this._storage) {
    _reload();
  }

  final LocalStorage _storage;
  final _controller = StreamController<UserProfile?>.broadcast();
  UserProfile? _cache;

  void _reload() {
    final raw = _storage.readMap(_kProfileKey);
    _cache = raw == null ? null : UserProfile.fromJson(raw);
    _controller.add(_cache);
  }

  Future<UserProfile> ensureProfile() async {
    if (_cache != null) return _cache!;
    final now = DateTime.now();
    final profile = UserProfile(startedAt: dateOnly(now), updatedAt: now);
    _cache = profile;
    await _storage.writeMap(_kProfileKey, profile.toJson());
    _controller.add(_cache);
    return profile;
  }

  Stream<UserProfile?> watchProfile() async* {
    yield _cache;
    await for (final profile in _controller.stream) {
      yield profile;
    }
  }

  /// Еженедельный сброс базы для недельной дельты.
  ///
  /// Если с момента последнего снимка началась новая неделя (или снимка ещё
  /// не было), фиксирует текущие средние как базу. Вызывается на старте
  /// приложения — в этот момент пользователь ещё не действовал на этой неделе,
  /// поэтому текущее значение равно значению конца прошлой недели.
  Future<void> maybeRollWeeklyDelta({
    required double? currentProductivity,
    required double? currentOnTime,
  }) async {
    final profile = await ensureProfile();
    final weekStart = startOfWeek(DateTime.now());
    final last = profile.lastWeekResetAt;
    final needRoll = last == null || dateOnly(last).isBefore(weekStart);
    if (!needRoll) return;

    // Конструируем напрямую: значения могут быть null (нет данных), а copyWith
    // с null сохранил бы старое значение.
    _cache = UserProfile(
      userId: profile.userId,
      email: profile.email,
      displayName: profile.displayName,
      startedAt: profile.startedAt,
      lastWeekAvgProductivity: currentProductivity,
      lastWeekOnTimeAverage: currentOnTime,
      lastWeekResetAt: weekStart,
      updatedAt: DateTime.now(),
    );
    await _storage.writeMap(_kProfileKey, _cache!.toJson());
    _controller.add(_cache);
  }

  void dispose() => _controller.close();
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final repo = ProfileRepository(ref.watch(localStorageProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final profileProvider = StreamProvider<UserProfile?>((ref) {
  return ref.watch(profileRepositoryProvider).watchProfile();
});
