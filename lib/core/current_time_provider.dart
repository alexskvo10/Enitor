import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Тикающее «сейчас» — раз в минуту, общее для экранов «Сегодня» и «Цели»:
/// оба пересчитывают срочность на каждый тик, пока их секция открыта (задачи —
/// вплоть до минуты, цели — по дню, но проверять чаще безопасно и дёшево).
final currentTimeProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  yield DateTime.now();
  await for (final _ in Stream<void>.periodic(const Duration(minutes: 1))) {
    yield DateTime.now();
  }
});
