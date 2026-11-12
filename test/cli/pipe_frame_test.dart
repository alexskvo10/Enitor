import 'dart:convert';

import 'package:enitor/cli/pipe_frame.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _frameWithBody(int len) => [
  len & 0xFF,
  (len >> 8) & 0xFF,
  (len >> 16) & 0xFF,
  (len >> 24) & 0xFF,
  ...List<int>.filled(len, 0x61),
];

void main() {
  test('кадр: заголовок little-endian и тело в UTF-8', () {
    final bytes = encodeFrame('{"a":1}');
    expect(bytes.sublist(0, 4), [7, 0, 0, 0]);
    expect(utf8.decode(bytes.sublist(4)), '{"a":1}');
  });

  test('кадр: длина 300 байт пишется как 0x2C 0x01', () {
    final bytes = encodeFrame('x' * 300);
    expect(bytes.sublist(0, 4), [0x2C, 0x01, 0, 0]);
  });

  test('кадр: round-trip с кириллицей', () {
    const json = '{"v":1,"ok":false,"error":{"message":"Добавление выключено"}}';
    final decoded = decodeFrame(encodeFrame(json));
    expect(decoded.error, isNull);
    expect(decoded.json, json);
  });

  test('кадр: кириллица считается в байтах, а не в символах', () {
    final json = 'П' * 10; // 20 байт в UTF-8
    final bytes = encodeFrame(json);
    expect(bytes.sublist(0, 4), [20, 0, 0, 0]);
    expect(decodeFrame(bytes).json, json);
  });

  test('кадр: ровно 64 КБ проходит', () {
    final json = 'a' * 65536;
    final decoded = decodeFrame(encodeFrame(json));
    expect(decoded.error, isNull);
    expect(decoded.json!.length, 65536);
  });

  test('кадр: 64 КБ + 1 байт — ошибка «слишком большой»', () {
    final decoded = decodeFrame(_frameWithBody(65537));
    expect(decoded.json, isNull);
    expect(decoded.error, contains('too large'));
  });

  test('кадр: кодировать больше 64 КБ нельзя', () {
    expect(() => encodeFrame('a' * 65537), throwsArgumentError);
  });

  test('кадр: длина 0 — ошибка', () {
    final decoded = decodeFrame([0, 0, 0, 0]);
    expect(decoded.error, contains('empty'));
  });

  test('кадр: обрезанный заголовок — ошибка', () {
    expect(decodeFrame([5, 0, 0]).error, contains('truncated header'));
    expect(decodeFrame(<int>[]).error, contains('truncated header'));
  });

  test('кадр: обрезанное тело — ошибка', () {
    final decoded = decodeFrame([10, 0, 0, 0, 0x61, 0x61]);
    expect(decoded.json, isNull);
    expect(decoded.error, contains('truncated body'));
  });

  test('кадр: тело не UTF-8 — ошибка', () {
    final decoded = decodeFrame([2, 0, 0, 0, 0xFF, 0xFE]);
    expect(decoded.json, isNull);
    expect(decoded.error, contains('UTF-8'));
  });
}
