import 'dart:io';

import 'package:enitor/data/sources/local/local_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// Инвентаризация ключей хранилища.
//
// Как ищем. Ключи SharedPreferences в проекте попадают в код тремя путями:
//   1. Аргумент-литерал или константа в вызовах LocalStorage / prefs:
//      readList / writeList / readMap / writeMap / remove и get*/set* у
//      SharedPreferences (`_storage.writeMap(_kGoalsKey, ...)`,
//      `_prefs.getString('tasks')`). Аргумент-переменную разрешаем через
//      таблицу констант.
//   2. Константы по соглашению имён: `const _kXxx = 'xxx'` и
//      `const kXxxKey = '...'`. Нужны, потому что ключ часто передаётся
//      в помощник параметром (`_readIntMap(key)`) и в вызове его не видно.
//   3. Литералы `'device.…'` где угодно: состояние устройства.
// Ищем регулярками, а не анализатором: в проекте нет зависимости от analyzer,
// а все ключи написаны по одному и тому же соглашению. Минус: ключ, который
// не назван по соглашению и не передан в вызов напрямую, сканер не увидит.
// Самопроверка внизу проверяет каждый путь на строке-исходнике.
//
// Таблица [keyCategories] — ручная: новый ключ в lib без строки в таблице
// роняет тест. Категории:
//   data    — данные пользователя; идут в бэкап;
//   derived — производное, пересчитывается и не должно быть источником правды;
//   device  — состояние этого устройства; начинается с `device.`, в бэкап не
//             попадает (см. local_storage.dart).

const _data = 'data';
const _derived = 'derived';
const _device = 'device';

const keyCategories = <String, String>{
  // Данные пользователя.
  'app_locale': _data,
  'appearance': _data,
  'unlocked_achievements': _data,
  'task_backlog': _data,
  'goal_backlog': _data,
  'goals': _data,
  'user_profile': _data,
  'day_ratings': _data,
  'period_ratings': _data,
  'recurrence_rules': _data,
  'schedule_items': _data,
  'tasks': _data,
  'day_templates': _data,
  'battery_hint': _data,
  'notif_prefs': _data,
  'pomodoro_prefs': _data,
  'pomodoro_state': _data,
  // Производное: кэши и отметки обработанных границ.
  'goal_ring_snapshots': _derived,
  'day_stats': _derived,
  'transfer_check': _derived,
  'weekly_retro_check': _derived,
  'update_check_state': _derived,
  // Состояние устройства.
  'device.integrations': _device,
  'device.integrations.idempotency': _device,
  'device.integrations.mcp_log': _device,
  'device.widget.today': _device,
  'device.ics.subscription': _device,
  'device.webhooks.endpoints': _device,
  'device.webhooks.queue': _device,
  'device.webhooks.settings': _device,
  'device.sync.base': _device,
  'device.sync.cursor': _device,
  'device.sync.pendingDays': _device,
  'device.sync.settings': _device,
  'device.sync.log': _device,
  'device.sync.tablet': _device,
  'device.sync.push': _device,
  'device.lan.group': _device,
  'device.lan.peers': _device,
  'device.lan.base': _device,
  'device.lan.cursor': _device,
  'device.lan.storeReset': _device,
  'device.ui.todayCalendar': _device,
  'device.tour': _device,
};

// Любая строковая константа: `const _prefsKey = 'update_check_state';`.
// Значение — только строчные буквы, цифры, `_` и `.`: так отсекаем
// не-ключи (имена Windows-уведомлений, GUID). Префикс `device.` без имени
// (`kDeviceKeyPrefix`) отсекаем позже — он заканчивается точкой.
final _constRe = RegExp(
  r"(?:const|final)\s+(_?\w+)\s*=\s*'([a-z][a-z0-9_.]*)';",
);

// Имена по соглашению репозиториев: `_kTasksKey`, `kMcpLogKey`. Значения
// таких констант считаем ключами безусловно (ключ мог уйти в помощник).
final _keyNameRe = RegExp(r'^_?k[A-Z]');

// Вызов чтения/записи с аргументом-ключом. Аргумент: литерал в '' или ""
// либо имя переменной. Получатель — хранилище, prefs или `)` от
// `ref.read(localStorageProvider)`; так `args.remove('v')` не попадает.
final _callRe = RegExp(
  r'(?:[Ss]torage|[Pp]refs|\))\s*\.\s*'
  r'(?:readList|writeList|readMap|writeMap|remove|'
  r'get(?:String|Bool|Int|Double|StringList)|'
  r'set(?:String|Bool|Int|Double|StringList))'
  r"""\(\s*(?:'([^']+)'|"([^"]+)"|(\w+))""",
);

// Литерал `'device.…'` где угодно в исходнике.
final _deviceLiteralRe = RegExp(r"""['"](device\.[^'"]*)['"]""");

/// Все ключи хранилища, найденные в наборе исходников: {путь: текст}.
/// Работает со строками, а не с файлами, — поэтому её видно из самопроверки.
Set<String> findStorageKeys(Map<String, String> sources) {
  // Таблица констант по всем файлам: имя → значение.
  final consts = <String, String>{};
  for (final src in sources.values) {
    for (final m in _constRe.allMatches(src)) {
      consts[m[1]!] = m[2]!;
    }
  }

  final keys = <String>{};
  void add(String? k) {
    // Пустые и префиксные значения (`device.`) ключами не считаем.
    if (k == null || k.isEmpty || k.endsWith('.')) return;
    keys.add(k);
  }

  for (final src in sources.values) {
    for (final m in _callRe.allMatches(src)) {
      add(m[1] ?? m[2] ?? consts[m[3]]);
    }
    for (final m in _deviceLiteralRe.allMatches(src)) {
      add(m[1]);
    }
  }
  consts.forEach((name, value) {
    if (_keyNameRe.hasMatch(name)) add(value);
  });
  return keys;
}

void main() {
  final sources = <String, String>{
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart')))
      f.path: f.readAsStringSync(),
  };
  final found = findStorageKeys(sources);

  test('в lib найдены ключи хранилища', () {
    expect(found, isNotEmpty);
  });

  test('каждый найденный ключ есть в таблице категорий', () {
    for (final k in found) {
      expect(
        keyCategories.containsKey(k),
        isTrue,
        reason: 'новый ключ $k без категории — добавь в таблицу',
      );
    }
  });

  test('каждый ключ таблицы встречается в lib (таблица не устарела)', () {
    expect(
      keyCategories.keys.where((k) => !found.contains(k)),
      isEmpty,
    );
  });

  test('категория device: префикс device., у остальных префикса нет', () {
    keyCategories.forEach((k, category) {
      final isDevicePrefixed = k.startsWith(kDeviceKeyPrefix);
      if (category == _device) {
        expect(
          isDevicePrefixed,
          isTrue,
          reason: 'ключ $k категории device должен начинаться с device.',
        );
      } else {
        expect(
          isDevicePrefixed,
          isFalse,
          reason: 'ключ $k категории $category не может начинаться с device.',
        );
      }
    });
  });

  test('самопроверка сканера: строка-исходник с ключами всех видов', () {
    const src = '''
      const _kProbeKey = 'probe_const';
      const kProbeOther = 'probe_other';
      static const _prefsKey = 'probe_name';
      _storage.readMap(_prefsKey);
      _storage.writeMap('probe_literal', {});
      _storage.readList(_kProbeKey);
      _storage
          .remove(kProbeOther);
      _prefs.getString("probe_prefs");
      const x = 'device.probe_device';
      args.remove('not_a_key');
    ''';
    final keys = findStorageKeys({'probe.dart': src});
    expect(
      keys,
      containsAll([
        'probe_const',
        'probe_other',
        'probe_name',
        'probe_literal',
        'probe_prefs',
        'device.probe_device',
      ]),
    );
    expect(keys, isNot(contains('not_a_key')));
    expect(keys, isNot(contains('device.')));
  });
}
