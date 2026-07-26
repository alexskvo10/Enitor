import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/motivational_quote.dart';

/// Источник мотивирующих цитат из JSON-ассета.
class QuoteService {
  QuoteService({required String locale}) : _locale = locale;

  final String _locale;
  List<MotivationalQuote>? _cache;
  final _random = math.Random();

  Future<List<MotivationalQuote>> _load() async {
    if (_cache != null) return _cache!;
    final raw =
        await rootBundle.loadString('assets/quotes/quotes_$_locale.json');
    final list = (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(MotivationalQuote.fromJson)
        .toList();
    _cache = list;
    return list;
  }

  Future<MotivationalQuote?> randomQuote() async {
    final all = await _load();
    if (all.isEmpty) return null;
    return all[_random.nextInt(all.length)];
  }
}

final quoteServiceProvider =
    Provider.family<QuoteService, String>((ref, locale) {
  return QuoteService(locale: locale);
});

final randomQuoteProvider =
    FutureProvider.family<MotivationalQuote?, String>((ref, locale) {
  return ref.watch(quoteServiceProvider(locale)).randomQuote();
});
