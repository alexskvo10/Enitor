import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'network_counter.dart';

// Самопроверка помощника network_counter: он должен видеть запрос и без них
// показывать ноль.

void main() {
  test('запрос внутри body: счётчик 1 и url записан', () async {
    final target = Uri.parse('https://example.com');
    await withNetworkCounter(
      () => http.get(target),
      (count, urls) {
        expect(count, 1);
        expect(urls, [target]);
      },
    );
  });

  test('без запросов: счётчик 0', () async {
    await withNetworkCounter(
      () async => 42,
      (count, urls) {
        expect(count, 0);
        expect(urls, isEmpty);
      },
    );
  });
}
