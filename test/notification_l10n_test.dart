import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:enitor/l10n/app_localizations.dart';

// Уведомления живут вне дерева виджетов и берут строки через
// lookupAppLocalizations(Locale(Intl.defaultLocale)) — тот же путь, что и
// здесь. Если он сломается, узнать об этом иначе можно только по уведомлению
// не на том языке, которое придёт завтра в 8:30.

Map<String, dynamic> _arb(String locale) => jsonDecode(
      File('lib/l10n/app_$locale.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

void main() {
  final ru = lookupAppLocalizations(const Locale('ru'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('тексты уведомлений приходят на выбранном языке', () {
    expect(ru.notifTaskBacklogBody(5), contains('бэклоге'));
    expect(en.notifTaskBacklogBody(5), contains('backlog'));

    expect(ru.notifGoalBacklogBody(3), contains('новый месяц'));
    expect(en.notifGoalBacklogBody(3), contains('new month'));

    expect(ru.notifGeneral1(3), contains('задачи'));
    expect(en.notifGeneral1(3), contains('tasks'));

    expect(ru.notifRetroTitle, isNot(en.notifRetroTitle));
    expect(ru.notifMorningTitle, isNot(en.notifMorningTitle));
  });

  test('русские склонения по числу — не «5 задача»', () {
    expect(ru.notifTaskBacklogBody(1), contains('1 задача, пора её выполнить'));
    expect(ru.notifTaskBacklogBody(3), contains('3 задачи, пора их выполнить'));
    expect(ru.notifTaskBacklogBody(5), contains('5 задач, пора их выполнить'));

    expect(ru.notifGoalBacklogBody(1), startsWith('В бэклоге 1 цель'));
    expect(ru.notifGoalBacklogBody(3), startsWith('В бэклоге 3 цели'));
    expect(ru.notifGoalBacklogBody(5), startsWith('В бэклоге 5 целей'));
  });

  test('английские формы единственного и множественного числа', () {
    expect(en.notifTaskBacklogBody(1), contains('1 task is'));
    expect(en.notifTaskBacklogBody(2), contains('2 tasks are'));
    expect(en.notifGoalBacklogBody(1), startsWith('1 goal in'));
    expect(en.notifGoalBacklogBody(2), startsWith('2 goals in'));
  });

  test('ни одно уведомление не осталось непереведённым', () {
    final a = _arb('en');
    final b = _arb('ru');
    final untranslated = <String>[];
    for (final k in a.keys) {
      if (k.startsWith('@') || !k.startsWith('notif')) continue;
      final va = a[k];
      final vb = b[k];
      if (va is! String || vb is! String) continue;
      // Совпадение допустимо только у строк без букв (эмодзи, цифры).
      if (va == vb && RegExp('[A-Za-z]').hasMatch(va)) untranslated.add(k);
    }
    expect(untranslated, isEmpty, reason: 'одинаковый текст в en и ru');
  });

  test('наборы ключей en и ru совпадают', () {
    keys(Map<String, dynamic> m) =>
        m.keys.where((k) => !k.startsWith('@')).toSet();
    expect(keys(_arb('en')), keys(_arb('ru')));
  });
}
