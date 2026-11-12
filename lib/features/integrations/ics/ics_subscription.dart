import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;

import '../../../data/repositories/schedule_repository.dart';
import '../../../data/sources/local/local_storage.dart';
import '../import/import_plan.dart';
import 'ics_parser.dart';

/// Ссылка на календарь, из которого импортировали (ключ «устройство»).
const kIcsSubscriptionKey = 'device.ics.subscription';

class IcsSubscription {
  const IcsSubscription({required this.url, this.auto = false, this.lastAt});

  final String url;

  /// «Обновлять раз в день при открытии» — по умолчанию выключено: каждый
  /// запрос виден серверу календаря (адрес, время), поэтому — только по
  /// явному решению.
  final bool auto;
  final DateTime? lastAt;

  IcsSubscription copyWith({bool? auto, DateTime? lastAt}) => IcsSubscription(
        url: url,
        auto: auto ?? this.auto,
        lastAt: lastAt ?? this.lastAt,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'auto': auto,
        if (lastAt != null) 'lastAt': lastAt!.toIso8601String(),
      };

  static IcsSubscription? fromJson(Map<String, dynamic>? j) {
    final url = j?['url'];
    if (url is! String) return null;
    return IcsSubscription(
      url: url,
      auto: j!['auto'] as bool? ?? false,
      lastAt: DateTime.tryParse(j['lastAt'] as String? ?? ''),
    );
  }
}

class IcsSubscriptionController extends Notifier<IcsSubscription?> {
  @override
  IcsSubscription? build() => IcsSubscription.fromJson(
        ref.read(localStorageProvider).readMap(kIcsSubscriptionKey),
      );

  Future<void> set(IcsSubscription? s) async {
    state = s;
    final storage = ref.read(localStorageProvider);
    if (s == null) {
      await storage.remove(kIcsSubscriptionKey);
    } else {
      await storage.writeMap(kIcsSubscriptionKey, s.toJson());
    }
  }
}

final icsSubscriptionProvider =
    NotifierProvider<IcsSubscriptionController, IcsSubscription?>(
  IcsSubscriptionController.new,
);

/// Один запрос на адрес, который ввёл пользователь. Только https/http;
/// ответ больше 5 МБ не читаем — календарь столько не весит.
Future<String> fetchIcs(String url, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c
        .get(Uri.parse(url), headers: {'Accept': 'text/calendar'})
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw http.ClientException('HTTP ${r.statusCode}', Uri.parse(url));
    }
    if (r.bodyBytes.length > 5 * 1024 * 1024) {
      throw http.ClientException('too large', Uri.parse(url));
    }
    // Без charset в ответе http читал бы latin1 — календарь же всегда UTF-8.
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  } finally {
    if (client == null) c.close();
  }
}

/// Обновление по ссылке при открытии приложения — только если включено и
/// прошли сутки. Новые и изменённые пункты записываются без предпросмотра:
/// человек сам включил «обновлять».
Future<void> refreshIcsSubscription(
  ProviderContainer container, {
  DateTime Function()? clock,
  http.Client? client,
}) async {
  final sub = container.read(icsSubscriptionProvider);
  final now = (clock ?? DateTime.now)();
  if (sub == null || !sub.auto) return;
  if (sub.lastAt != null && now.difference(sub.lastAt!) < const Duration(days: 1)) {
    return;
  }
  try {
    final text = await fetchIcs(sub.url, client: client);
    final plan = planIcsImport(
      parseIcs(text, local: tz.local),
      schedule: container.read(scheduleRepositoryProvider),
      now: now,
    );
    for (final e in plan) {
      await e.apply?.call();
    }
    await container
        .read(icsSubscriptionProvider.notifier)
        .set(sub.copyWith(lastAt: now));
  } catch (e) {
    // Нет сети — попробуем при следующем открытии.
    debugPrint('refreshIcsSubscription: $e');
  }
}
