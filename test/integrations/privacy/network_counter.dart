import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Счётчик сетевых запросов для сквозных тестов.
//
// Все запросы через package:http внутри [body] уходят в MockClient: он
// запоминает url и отвечает 599, так что реальной сети нет. После [body]
// вызывается [check] с числом запросов и их адресами.
//
// Как пользоваться в сквозных тестах: отключить интеграции, прогнать обычный
// сценарий (создать задачу, цель, восстановить бэкап) и проверить, что
// запросов не было:
//
//   await withNetworkCounter(
//     () => runFlowWithIntegrationsOff(),
//     (count, urls) => expect(count, 0, reason: 'лишние запросы: $urls'),
//   );
//
// Ограничение: считаются только запросы через http.* и клиент из
// http.runWithClient. Dart HttpClient напрямую (dart:io) сюда не попадёт.

Future<T> withNetworkCounter<T>(
  Future<T> Function() body,
  void Function(int count, List<Uri> urls) check,
) async {
  final urls = <Uri>[];
  final client = MockClient((request) async {
    urls.add(request.url);
    return http.Response('', 599);
  });
  final result = await http.runWithClient(body, () => client);
  check(urls.length, List.unmodifiable(urls));
  return result;
}
