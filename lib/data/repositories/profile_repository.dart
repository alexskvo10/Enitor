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
