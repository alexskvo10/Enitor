// Только для веб-сборки (условный импорт в web_bits.dart).
import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Скачивание файла: в браузере нет диалога «Сохранить как» с путём.
void downloadText(String name, String text, String mime) {
  final blob = web.Blob([text.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  (web.document.createElement('a') as web.HTMLAnchorElement)
    ..href = url
    ..download = name
    ..click();
  // Safari обрывает скачивание, если ссылку отозвать сразу.
  Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
}

/// true — Enitor уже открыт в другой вкладке этого браузера. Две вкладки
/// писали бы одно хранилище поверх друг друга (как два exe на Windows).
Future<bool> anotherTabOpen() async {
  final ch = web.BroadcastChannel('enitor');
  var other = false;
  ch.onmessage = (web.MessageEvent e) {
    final d = e.data?.dartify();
    if (d == 'ping') ch.postMessage('here'.toJS);
    if (d == 'here') other = true;
  }.toJS;
  ch.postMessage('ping'.toJS);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  // Заблокированная вкладка молчит: иначе после закрытия первой новая
  // вкладка увидела бы её и тоже заблокировалась.
  if (other) ch.close();
  return other;
}

/// Просим браузер не чистить хранилище сам (Safari иначе стирает данные
/// сайта через 7 дней без визитов). Браузер может и отказать.
void requestPersistentStorage() {
  try {
    web.window.navigator.storage.persist();
  } catch (_) {}
}

/// Открыто как установленное приложение (с экрана «Домой» / PWA).
bool get isInstalledApp =>
    web.window.matchMedia('(display-mode: standalone)').matches;
